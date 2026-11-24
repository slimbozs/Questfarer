"""Cross-zone quests: a post-pass over the shared chains (run after auto_chain.py and the race tracks).

Inserted lines carry {via=crosszone}; each run removes the previous run's lines first.
Order: auto_chain.py -> race tracks -> crosszone.py -> round_trips.py --write -> build_guides.py

    python crosszone.py            # both factions, writes the route files
    python crosszone.py --dry      # report only
"""
import os
import re
import sys

import build_guides as bg
import plan_zone as pz

ROUTES = bg.ROUTES
TAG = "{via=crosszone}"
SHARED = {"Alliance": "ORDER", "Horde": "ORDER.Horde"}
TRACKS = {"Alliance": ["ORDER", "ORDER.NightElf", "ORDER.Dwarf", "ORDER.SkyborneA"],
          "Horde": ["ORDER.Horde", "ORDER.Tauren", "ORDER.Undead", "ORDER.SkyborneH"]}
ACCEPT_YARDS = 400
TURNIN_YARDS = 400
OBJECTIVE_YARDS = 700
MAX_EXTRA_SECONDS = 15 * 60
MIN_SHARE = 0.6
UNLOCK_SHARE = 0.5
RUN_SPEED = 7.0
# QuestieDB zoneOrSort values for events, seasonal and raid/war-effort content
EVENT_SORTS = {-1, -22, -284, -344, -364, -365, -366, -367, -368, -369, -676}
MOUNT_LEVEL, MOUNT_SPEED = 40, 1.6


def speed(level):
    return RUN_SPEED * (MOUNT_SPEED if level >= MOUNT_LEVEL else 1.0)


def strip_tagged(files):
    n = 0
    for rf in files:
        p = os.path.join(ROUTES, rf)
        lines = open(p, encoding="utf-8").read().split("\n")
        keep = [ln for ln in lines if TAG not in ln]
        if len(keep) != len(lines):
            n += len(lines) - len(keep)
            open(p, "w", encoding="utf-8", newline="\n").write("\n".join(keep))
    return n


def insert_lines(inserts):
    """inserts: [(route file, after line (1-based), text)]"""
    by_file = {}
    for rf, after, text in inserts:
        by_file.setdefault(rf, []).append((after, text))
    for rf, items in by_file.items():
        p = os.path.join(ROUTES, rf)
        lines = open(p, encoding="utf-8").read().split("\n")
        # later lines first; same anchor keeps accept, complete, turnin order
        for k in sorted(range(len(items)), key=lambda k: (items[k][0], k), reverse=True):
            after, text = items[k]
            lines.insert(after, text)
        open(p, "w", encoding="utf-8", newline="\n").write("\n".join(lines))


def snapshot(files):
    return {rf: open(os.path.join(ROUTES, rf), encoding="utf-8").read() for rf in files}


def restore(snap):
    for rf, txt in snap.items():
        open(os.path.join(ROUTES, rf), "w", encoding="utf-8", newline="\n").write(txt)


class Replay(bg.Compiler):
    def __init__(self, data):
        super().__init__(data)
        self.trace = []  # dicts: gi, file, line, pos, level, log
        self.turn_at = {}  # quest -> trace index of its turn-in
        self.gi = -1
        self.cur_file = None

    def compile_step(self, st, guide, prev):
        res = super().compile_step(st, guide, prev)
        open_q = {q for q, c in self.accepted if c is None} - {q for q, c in self.turned if c is None}
        for r in res:
            if "turnin" in r and not r.get("class"):
                self.turn_at.setdefault(r["turnin"], len(self.trace))
            pos = (r.get("map") or guide["map"], r["x"], r["y"]) if "x" in r else None
            line = int(st["where"].rsplit(":", 1)[1])
            if st["verb"] == "fly":
                line -= 1  # insert before the flight
            self.trace.append({"gi": self.gi, "file": self.cur_file, "line": line,
                               "pos": pos, "level": self.est_level(), "log": len(open_q)})
        return res


def replay(data, order):
    comp = Replay(data)
    files = bg.read_order(order)
    comp.guides = []
    for gi, rf in enumerate(files):
        comp.gi, comp.cur_file = gi, rf
        h, steps = bg.parse_route(os.path.join(ROUTES, rf))
        comp.guides.append(comp.compile_guide(h, steps))
    comp.finish()
    comp.by_map = {}
    for i, t in enumerate(comp.trace):
        if t["pos"]:
            comp.by_map.setdefault(t["pos"][0], []).append(i)
    return comp, files


def check(data, faction):
    """Set of (order, message without line number) for all errors and warnings."""
    out = set()
    for order in TRACKS[faction]:
        c, _ = bg.compile_track(data, order)
        for m in c.errors + c.warnings:
            out.add((order, re.sub(r"^[^:]+:\d+: ", "", m)))
    return out


def all_routed(data, faction):
    routed = set()
    for order in TRACKS[faction]:
        c, _ = bg.compile_track(data, order)
        routed |= c.routed
    return routed


def points_of(data, field, q, faction=None):
    npcs, objs, items = data.givers(q.get(field))
    pts = []
    for n in npcs:
        fr = (data.npcs.get(str(n)) or {}).get("friendlyToFaction")
        if faction and fr and faction[0] not in fr:
            continue
        pts += data.points("npc", n)
    for o in objs:
        pts += data.points("object", o)
    return pts, items


def candidates(data, comp, faction, routed, planner):
    """Cross-zone quests plus their same-zone prerequisites (the planner skipped those)."""
    races = bg.ALLIANCE if faction == "Alliance" else bg.HORDE
    dyn = pz.dynamic_fix_ids()
    usable = {}
    for sid, q in data.quests.items():
        qid = int(sid)
        if qid in routed or qid in pz.NEVER_PLAN or qid in pz.SEASON_IDS or qid in dyn:
            continue
        rm = q.get("requiredRaces") or 0
        if rm and not any(rm & bg.race_bit(r, faction) for r in races):
            continue
        if (q.get("specialFlags") or 0) & 1 or q.get("requiredSkill") or q.get("requiredClasses"):
            continue
        if not (data.xp.get(qid) or (0, 0))[1]:
            continue
        if (q.get("requiredLevel") or 0) >= 60 or q.get("zoneOrSort") in EVENT_SORTS:
            continue
        otext = " ".join(str(t) for t in bg.as_list(q.get("objectivesText")))
        if pz.needs_reputation(q) or (qid not in pz.DUNGEON_TEXT_OK and pz.inside_dungeon(data, q, otext)):
            continue  # same rules as the planner
        # several givers incl. the turn-in NPC: take it there, the others are often event/phased copies
        s_npcs, s_objs, _ = data.givers(q.get("startedBy"))
        f_npcs, _, _ = data.givers(q.get("finishedBy"))
        same = set(s_npcs) & set(f_npcs)
        if same and len(s_npcs) > 1:
            q = dict(q, startedBy=[sorted(same), s_objs])
        start, items = points_of(data, "startedBy", q, faction)
        if not start:
            continue  # item starts, no giver place
        finish, _ = points_of(data, "finishedBy", q)
        if not finish:
            continue
        opts, _ = comp.objectives(q)
        opts = [p for p in opts if pz.world(tuple(p[:3])) is not None]
        has_obj = bool(bg.slots(q.get("objectives"))) or bool(q.get("triggerEnd"))
        text = " ".join(q.get("objectivesText") or [])
        if not has_obj:
            if pz.TEXT_TASK.search(text) or not pz.DELIVERY.search(text):
                continue
        elif not opts:
            continue
        maps = {p[0] for p in start} | {p[0] for p in finish} | {p[0] for p in opts}
        clusters = []
        for m in sorted({p[0] for p in opts}):
            bp = bg.best_point([tuple(p[:3]) for p in opts if p[0] == m], m, None)
            if bp:
                clusters.append((bp[0], bp[1], bp[2]))
        usable[qid] = {"id": qid, "q": q, "start": start, "finish": finish, "obj": clusters, "has_obj": has_obj,
                       "cross": len(maps) > 1, "unlocks": []}
    keep = {qid for qid, c in usable.items() if c["cross"]}
    todo = list(keep)
    while todo:  # prerequisites, any depth
        c = usable[todo.pop()]
        for p in bg.as_list(c["q"].get("preQuestSingle")) + bg.as_list(c["q"].get("preQuestGroup")):
            if p in usable:
                usable[p]["unlocks"].append(c["id"])
                if p not in keep:
                    keep.add(p)
                    todo.append(p)
    return [usable[q] for q in sorted(keep)]


def nearest(comp, lo, targets, cap, ok=lambda t: True):
    """(trace index, yards) of the closest step in the first guide that gets within cap, or None."""
    trace = comp.trace
    idx = sorted({i for p in targets for i in comp.by_map.get(p[0], ()) if i >= lo})
    best = None
    for i in idx:
        t = trace[i]
        if best and t["gi"] != trace[best[0]]["gi"]:
            break
        if not ok(t):
            continue
        for p in targets:
            if p[0] != t["pos"][0]:
                continue
            d = pz.yards(t["pos"], p)
            if d <= cap and (not best or d < best[1]):
                best = (i, d)
    return best


def place(data, c, comp, lo, planner):
    trace = comp.trace
    q = c["q"]
    req = q.get("requiredLevel") or max(1, (q.get("questLevel") or 1) - 5)
    ql = q.get("questLevel") or req
    solo = bg.solo_level(data, q)
    xp_lv, xp_val = data.xp.get(c["id"])
    # accept once allowed and before it goes gray
    a = nearest(comp, lo, c["start"], ACCEPT_YARDS,
                lambda t: t["level"] >= req and ql > bg.gray_level(int(t["level"])))
    if not a:
        return None
    ai = a[0]
    # objectives at a level that's fine solo
    o = None
    if c["has_obj"]:
        o = nearest(comp, ai, c["obj"], OBJECTIVE_YARDS, lambda t: t["level"] >= solo)
        if not o:
            return None
    oi = o[0] if o else ai
    # turn in while it still gives full XP
    f = nearest(comp, oi, c["finish"], TURNIN_YARDS, lambda t: int(t["level"]) - (xp_lv or ql) <= 5)
    if not f:
        return None
    fi = f[0]
    if any(trace[i]["log"] + 1 > pz.LOG_LIMIT for i in range(ai, fi + 1)):
        return None
    level = trace[oi]["level"]
    secs = 2 * pz.TALK_SECONDS + 2 * a[1] / speed(trace[ai]["level"]) + 2 * f[1] / speed(trace[fi]["level"])
    kill_xp = 0
    if o:
        secs += 2 * o[1] / speed(level) + planner.complete_seconds(q, level)
    if pz.ESCORT.search(" ".join(q.get("objectivesText") or [])):
        secs += pz.ESCORT_SECONDS  # escorts are slow and get ambushed
        kill_xp = sum(bg.mob_xp(int(level), ml) * n for ml, n in data.kill_estimate(q))
    xp = xp_val + kill_xp
    bonus = UNLOCK_SHARE * sum((data.xp.get(u) or (0, 0))[1] for u in c["unlocks"] if u not in comp.routed)
    rate = (xp + bonus) / max(secs, 1)
    need = (pz.QUEST_FIRST_FLOOR if pz.QUEST_FIRST else MIN_SHARE) * planner.grind_rate(level)
    if secs > MAX_EXTRA_SECONDS or rate < need:
        return None
    return {"a": ai, "o": oi if o else None, "f": fi, "secs": secs, "xp": xp, "rate": rate, "need": need}


def run_faction(data, faction, dry):
    order = SHARED[faction]
    files = bg.read_order(order)
    before = snapshot(files)  # for --dry
    removed = strip_tagged(files)
    # start where the last race track joins
    import simulate as sim
    join = 0
    for tr, (o, fac) in sim.TRACK_ORDERS.items():
        if fac != faction:
            continue
        tf, _ = sim.track_routes(tr)
        first = next(f for f in tf if f in files and not bg.parse_route(os.path.join(ROUTES, f))[0].get("races"))
        join = max(join, files.index(first))
    base = check(data, faction)
    routed = bg.compile_track(data, order)[0].routed  # race tracks may have one too: a done accept is skipped
    comp, _ = replay(data, order)
    planner = pz.Planner(data, comp, 0, 1, 60, bg.ALLIANCE if faction == "Alliance" else bg.HORDE, faction)
    cands = candidates(data, comp, faction, routed, planner)
    print("%s: shared chain from %s (guide %d of %d); %d cross-zone candidates; %d old lines removed"
          % (faction, files[join], join + 1, len(files), len(cands), removed))
    added, rejected = [], set()
    while True:
        comp, _ = replay(data, order)
        trace = comp.trace
        lo = next(i for i, t in enumerate(trace) if t["gi"] >= join)
        found = None
        for c in cands:
            if c["id"] in rejected or c["id"] in {a["id"] for a in added}:
                continue
            q = c["q"]
            # prereqs: any one of preQuestSingle, all of preQuestGroup
            pre_s = [comp.turn_at[p] for p in bg.as_list(q.get("preQuestSingle")) if p in comp.turn_at]
            pre_g = bg.as_list(q.get("preQuestGroup"))
            if bg.as_list(q.get("preQuestSingle")) and not pre_s or any(p not in comp.turn_at for p in pre_g):
                continue
            after = max(([min(pre_s)] if pre_s else []) + [comp.turn_at[p] for p in pre_g] + [-1])
            if set(bg.as_list(q.get("exclusiveTo"))) & ({qq for qq, cc in comp.accepted}):
                continue
            pl = place(data, c, comp, max(lo, after + 1), planner)
            if pl and (not found or pl["a"] < found[1]["a"]):
                found = (c, pl)
        if not found:
            break
        c, pl = found
        tagx = lambda v: "%-8s %d %s" % (v, c["id"], TAG)  # noqa: E731
        ins = [(trace[pl["a"]]["file"], trace[pl["a"]]["line"], tagx("accept"))]
        if pl["o"] is not None:
            ins.append((trace[pl["o"]]["file"], trace[pl["o"]]["line"], tagx("complete")))
        ins.append((trace[pl["f"]]["file"], trace[pl["f"]]["line"], tagx("turnin")))
        snap = snapshot({rf for rf, _, _ in ins})
        insert_lines(ins)
        now = check(data, faction)
        if now - base:
            restore(snap)
            rejected.add(c["id"])
            print("   rejected %6d %-40s %s" % (c["id"], c["q"].get("name")[:40], sorted(now - base)[0][1][:90]))
            continue
        added.append({"id": c["id"], "name": c["q"].get("name"), "xp": pl["xp"], "secs": pl["secs"],
                      "from": trace[pl["a"]]["file"], "to": trace[pl["f"]]["file"],
                      "lvl": trace[pl["a"]]["level"]})
        print("   + %6d %-40s %5d XP %4.1f min  %s -> %s" % (
            c["id"], c["q"].get("name")[:40], pl["xp"], pl["secs"] / 60,
            trace[pl["a"]]["file"].replace(".route", ""), trace[pl["f"]]["file"].replace(".route", "")))
    if dry:
        restore(before)
        print("   (dry run: route files restored)")
    total = sum(a["xp"] for a in added)
    print("%s: %d quests added, ~%d XP, ~%.1f h extra time" % (
        faction, len(added), total, sum(a["secs"] for a in added) / 3600))
    # level drift: the addon's resync skips outgrown guides
    comp, _ = replay(data, order)
    for g in comp.guides:
        if g["_endLevel"] >= g["maxLevel"] + 1:
            print("   level drift: %s ends at ~%.1f, its range is %d-%d" % (
                g["name"], g["_endLevel"], g["minLevel"], g["maxLevel"]))
    return added


def main():
    dry = "--dry" in sys.argv
    data = bg.Data()
    factions = [a for a in sys.argv[1:] if not a.startswith("--")] or ["Alliance", "Horde"]
    for fac in factions:
        run_faction(data, fac, dry)


if __name__ == "__main__":
    main()
