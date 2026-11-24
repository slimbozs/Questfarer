"""Calibrate the planner's time model from real play: a WoW combat log plus the addon's recorder.

Usage:  python analyze_play.py [WoWCombatLog.txt] [--player Name] [--sv path\\to\\Questfarer.lua]

Without arguments it takes the newest combat log in E:\\World of Warcraft\\_forever_\\Logs and the
account SavedVariables. Turn the log on in game with /combatlog (it writes while it's on).
"""
import csv
import glob
import io
import os
import re
import statistics as st
import sys
from collections import defaultdict
from datetime import datetime

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
import build_guides as bg  # noqa: E402
import plan_zone as pz  # noqa: E402
from check_recorded import LuaReader  # noqa: E402

LOG_GLOB = r"E:\World of Warcraft\_forever_\Logs\WoWCombatLog-*.txt"
SV_GLOB = r"E:\World of Warcraft\_forever_\WTF\Account\*\SavedVariables\Questfarer.lua"
GAP_CAP = 180      # seconds, longer gaps between kills are questing/travel/AFK
IDLE_GAP = 900     # seconds, longer gaps between recorder events are breaks
LOW_HP = 0.25      # health fraction that counts as a close call
MINE = 0x1         # COMBATLOG_OBJECT_AFFILIATION_MINE

DAMAGE = re.compile(r"^(SWING|SPELL|SPELL_PERIODIC|RANGE)_DAMAGE$|^(SWING|SPELL|RANGE|SPELL_PERIODIC)_MISSED$")
EAT = re.compile(r"^(Food|Drink|Refreshment)$")


def ts(date, clock):
    return datetime.strptime(date + " " + clock[:15], "%m/%d/%Y %H:%M:%S.%f").timestamp()


def adv_block(f):
    """(infoGUID, curHP, maxHP, level, x, y, map) of an advanced-logging block, or None."""
    for i in range(12, len(f) - 2):
        if re.fullmatch(r"\d{3,4}", f[i]) and "." in f[i - 1] and "." in f[i - 2] and "." in f[i + 1]:
            start = 9 if f[0].startswith("SWING") else 12
            try:
                return f[start], int(f[start + 2]), int(f[start + 3]), int(f[i + 2]), float(f[i - 2]), \
                    float(f[i - 1]), int(f[i])
            except (ValueError, IndexError):
                return None
    return None


def parse(path, player):
    me, pets = None, set()
    mobs = {}            # guid -> fight info
    hp = []              # (t, cur, max)
    eat = []             # (t, kind)
    deaths = []
    level_seen = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if "  " not in line:
                continue
            head, rest = line.rstrip("\n").split("  ", 1)
            date, clock = head.split(" ")
            try:
                f = next(csv.reader(io.StringIO(rest)))
            except StopIteration:
                continue
            ev = f[0]
            if len(f) < 9:
                continue
            t = ts(date, clock)
            sg, sn, sfl, dg, dn, dfl = f[1], f[2], f[3], f[5], f[6], f[7]
            if me is None and sn.split("-")[0] == player:
                me = sg
            if ev == "SPELL_SUMMON" and sg == me:
                pets.add(dg)
            for g, fl in ((sg, sfl), (dg, dfl)):
                try:
                    if g.startswith("Pet-") and int(fl, 16) & MINE:
                        pets.add(g)
                except ValueError:
                    pass
            ours = {me} | pets
            if DAMAGE.match(ev) or ev.endswith("_DAMAGE_LANDED"):
                for us, them, them_name in ((sg, dg, dn), (dg, sg, sn)):
                    if us in ours and them.startswith("Creature-"):
                        m = mobs.setdefault(them, {"first": t, "last": t, "died": None, "name": them_name,
                                                   "npc": int(them.split("-")[5]), "level": None,
                                                   "dealt": 0})
                        m["last"] = t
                        if us == sg and ev.endswith("_DAMAGE"):
                            m["dealt"] += 1
                a = adv_block(f)
                if a:
                    g, cur, mx, lvl = a[0], a[1], a[2], a[3]
                    if g == me and mx > 0:
                        hp.append((t, cur, mx))
                    elif g in mobs and 0 < lvl < 64:
                        mobs[g]["level"] = lvl
            elif ev == "UNIT_DIED":
                if dg in mobs and mobs[dg]["died"] is None:
                    mobs[dg]["died"] = t
                elif dg == me:
                    deaths.append(t)
            elif ev == "SPELL_AURA_APPLIED" and dg == me and EAT.match(f[10] if len(f) > 10 else ""):
                eat.append((t, f[10]))
    return me, mobs, hp, eat, deaths


def recorder(char):
    log = []
    for p in glob.glob(SV_GLOB):
        sv = LuaReader(open(p, encoding="utf-8", errors="replace").read()).assignments()
        rec = sv.get("QuestfarerRecorderDB") or {}
        for e in (rec.get("log") or {}).values() if isinstance(rec.get("log"), dict) else rec.get("log") or []:
            if isinstance(e, dict) and (not char or str(e.get("char", "")).startswith(char)):
                log.append(e)
    return sorted(log, key=lambda e: e.get("t", 0))


def fmt(t):
    return datetime.fromtimestamp(t).strftime("%H:%M")


def main():
    args = sys.argv[1:]
    player = "Lundgren"
    if "--player" in args:
        player = args[args.index("--player") + 1]
    logs = [a for a in args if a.lower().endswith(".txt")] or sorted(glob.glob(LOG_GLOB), key=os.path.getmtime)[-1:]
    data = bg.Data()
    out = []
    rec = recorder(player)
    lv_events = [e for e in rec if e.get("e") == "level"]

    def plevel(t):
        lv = None
        for e in rec:
            if e.get("t", 0) <= t and e.get("lvl"):
                lv = e["to"] if e.get("e") == "level" else e["lvl"]
        return lv

    for path in logs:
        me, mobs, hp, eat, deaths = parse(path, player)
        kills = sorted((m for m in mobs.values() if m["died"] and m["dealt"]), key=lambda m: m["died"])
        out.append("== %s  (player %s)" % (os.path.basename(path), me))
        if not kills:
            out.append("no kills found")
            continue
        t0, t1 = min(m["first"] for m in mobs.values()), max(m["last"] for m in mobs.values())
        out.append("session %s-%s, %.0f min, %d kills (%.0f per hour), deaths: %d"
                   % (fmt(t0), fmt(t1), (t1 - t0) / 60, len(kills), len(kills) / ((t1 - t0) / 3600), len(deaths)))
        rows, factor_rows = [], []
        for m in kills:
            dur = m["died"] - m["first"]
            pl = plevel(m["first"])
            ml = m["level"] or (data.npcs.get(str(m["npc"])) or {}).get("maxLevel")
            rows.append((m["name"], dur, ml, pl))
            if pl and ml:
                factor_rows.append((ml - pl, dur))
        by = defaultdict(list)
        for name, dur, ml, pl in rows:
            by[(name, ml)].append(dur)
        out.append("\n-- seconds per kill (first hit to death), by mob")
        for (name, ml), ds in sorted(by.items(), key=lambda kv: -len(kv[1])):
            out.append("  %-28s lvl %-3s x%-3d median %5.1f s   (min %.0f, max %.0f)"
                       % (name[:28], ml, len(ds), st.median(ds), min(ds), max(ds)))
        out.append("\n-- by level difference (mob - you): median fight seconds, and the model's factor")
        byd = defaultdict(list)
        for d, dur in factor_rows:
            byd[d].append(dur)
        base = st.median(byd[0]) if byd.get(0) else st.median([d for _, d in factor_rows])
        for d in sorted(byd):
            out.append("  %+d  x%-3d median %5.1f s   ratio to same level %.2f   model %.2f"
                       % (d, len(byd[d]), st.median(byd[d]), st.median(byd[d]) / base, pz.kill_factor(d)))
        overlaps = sum(1 for i, m in enumerate(kills)
                       if any(o is not m and o["first"] < m["died"] and o["died"] > m["first"] for o in kills))
        out.append("\nkills that overlapped another fight (adds / multi-pulls): %d of %d" % (overlaps, len(kills)))
        gaps = []
        for a, b in zip(kills, kills[1:]):
            g = b["first"] - a["died"]
            if 0 <= g <= GAP_CAP:
                gaps.append(g)
        fights = [m["died"] - m["first"] for m in kills]
        out.append("fight time: median %.1f s, mean %.1f s" % (st.median(fights), st.mean(fights)))
        if gaps:
            out.append("gap to the next pull (<= %d s): median %.1f s, mean %.1f s, n=%d"
                       % (GAP_CAP, st.median(gaps), st.mean(gaps), len(gaps)))
            per = st.mean(fights) + st.mean(gaps)
            out.append("=> one kill cycle (fight + gap) ~%.0f s; model: SEC_PER_KILL %d (quest mobs), "
                       "GRIND_SEC_PER_KILL %d" % (per, pz.SEC_PER_KILL, pz.GRIND_SEC_PER_KILL))
        out.append("food/drink buffs: %d (%s)" % (len(eat), ", ".join(sorted({k for _, k in eat})) or "-"))
        lows = []
        for t, cur, mx in hp:
            if cur / mx < LOW_HP and (not lows or t - lows[-1][0] > 30):
                lows.append((t, cur, mx))
        out.append("close calls (under %d%% health): %d" % (LOW_HP * 100, len(lows)))
        for t, cur, mx in lows:
            near = [m["name"] for m in mobs.values() if m["first"] <= t <= (m["died"] or m["last"]) + 1]
            out.append("  %s  %d/%d  vs %s" % (datetime.fromtimestamp(t).strftime("%H:%M:%S"), cur, mx,
                                               ", ".join(sorted(set(near))) or "?"))
    out.append("\n== Recorder (%d events)" % len(rec))
    qxp = [e for e in rec if e.get("e") == "turnin" and e.get("xp")]
    if rec:
        out.append("from %s to %s, %d turn-ins worth %d XP, %d accepts"
                   % (fmt(rec[0]["t"]), fmt(rec[-1]["t"]), len(qxp), sum(e["xp"] for e in qxp),
                      sum(1 for e in rec if e.get("e") == "accept")))
    times = sorted(e["t"] for e in rec)
    for a, b in zip(lv_events, lv_events[1:]):
        need = bg.XP_TO_LEVEL[a["to"]]
        # breaks over IDLE_GAP don't count as play
        ts_ = [a["t"]] + [t for t in times if a["t"] < t < b["t"]] + [b["t"]]
        secs = sum(min(y - x, IDLE_GAP) if y - x <= IDLE_GAP else 0 for x, y in zip(ts_, ts_[1:]))
        h = secs / 3600
        out.append("level %d -> %d: %d XP in at least ~%.0f min of play (gaps over %d min left out, so XP/h is at most ~%.0f)"
                   % (a["to"], b["to"], need, h * 60, IDLE_GAP // 60, need / h if h else 0))
    for e in lv_events:
        out.append("  level %d at %s" % (e["to"], datetime.fromtimestamp(e["t"]).strftime("%H:%M")))
    text = "\n".join(out)
    os.makedirs(os.path.join(ROOT, "reports"), exist_ok=True)
    open(os.path.join(ROOT, "reports", "play_analysis.txt"), "w", encoding="utf-8").write(text + "\n")
    print(text)


if __name__ == "__main__":
    main()
