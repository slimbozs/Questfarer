"""Simulate a 1-60 playthrough of every guide track, once per class.

Class numbers are ESTIMATES, not measured on Forever: compare routes with it, not real play times.

    python simulate.py                 # every track, every class it has trainers for
    python simulate.py main NightElf   # some tracks
    python simulate.py --class MAGE    # one class
"""
import collections
import math
import os
import re
import sys

import build_guides as bg
import plan_zone as pz
import compare_zones as cz
import auto_chain as ac

ADDON = os.path.join(os.path.dirname(bg.ROOT), "Questfarer")

# kill time vs an average class, lower = faster
CLASS_SPEED = {"HUNTER": 0.80, "WARLOCK": 0.85, "MAGE": 0.95, "DRUID": 0.95, "SHAMAN": 0.95, "ROGUE": 1.0,
               "PRIEST": 1.05, "PALADIN": 1.10, "WARRIOR": 1.10}
RANK_PENALTY = 0.025      # kill time +2.5% per level you are behind your trainer (after the first)
RANK_PENALTY_MAX = 0.35
MOUNT_LEVEL = 40          # vanilla rule, NOT confirmed for Forever
MOUNT_SPEED = 1.6
TRAINER_NEAR = 150        # yards: the route passes your trainer
LONG_GRIND = 45 * 60
LONG_TRIP = 6 * 60

TRACK_ORDERS = {"main": ("ORDER", "Alliance"), "NightElf": ("ORDER.NightElf", "Alliance"),
                "Dwarf": ("ORDER.Dwarf", "Alliance"), "SkyborneA": ("ORDER.SkyborneA", "Alliance"),
                "Horde": ("ORDER.Horde", "Horde"), "Tauren": ("ORDER.Tauren", "Horde"),
                "Undead": ("ORDER.Undead", "Horde"), "SkyborneH": ("ORDER.SkyborneH", "Horde")}
SHARED = {"Alliance": "ORDER", "Horde": "ORDER.Horde"}
# capital city -> uiMap: stops there are training chances
CITY_AREAS = {"Stormwind": 1453, "Ironforge": 1455, "Darnassus": 1457, "Orgrimmar": 1454, "ThunderBluff": 1456,
              "Undercity": 1458}
CITY_FP = {"Stormwind": "Stormwind", "Ironforge": "Ironforge", "Rut'theran Village": "Darnassus",
           "Orgrimmar": "Orgrimmar", "Thunder Bluff": "ThunderBluff", "Undercity": "Undercity"}


def load_trainers():
    src = open(os.path.join(ADDON, "Trainers.lua"), encoding="utf-8").read()
    consts = {k: int(v) for k, v in re.findall(r"local (\w+) = (\d+)", src)}
    out, cls = {}, None
    for line in src.splitlines():
        m = re.match(r"    ([A-Z]+) = \{", line)
        if m:
            cls = m.group(1)
            out[cls] = {}
            continue
        m = re.match(r'\s+(\w+)\s*=\s*\{ npc = "([^"]+)", map = (\w+), x = ([\d.]+), y = ([\d.]+)', line)
        if m and cls:
            mp = consts.get(m.group(3)) or int(m.group(3))
            out[cls][m.group(1)] = (mp, float(m.group(4)), float(m.group(5)), m.group(2))
    return out


def balanced(src, i):
    """Index after the brace block that starts at src[i] == '{'."""
    depth = 0
    for j in range(i, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                return j + 1
    return len(src)


def load_spells(cls, faction):
    """{level: (new spells, copper)}, no talent ranks, own faction only."""
    path = os.path.join(ADDON, "Data", "Spells", cls.capitalize() + ".lua")
    src = open(path, encoding="utf-8").read()
    start = src.index("{", src.index("SpellsByLevel"))
    body = src[start + 1:balanced(src, start) - 1]
    out, i = {}, 0
    for m in re.finditer(r"\[(\d+)\]\s*=\s*\{", body):
        if m.start() < i:
            continue
        b = m.end() - 1
        i = balanced(body, b)
        n = cost = 0
        for e in re.finditer(r"\{id = (\d+), cost = (\d+)((?:[^{}]|\{[^{}]*\})*)\}", body[b + 1:i - 1]):
            if "requiredTalentId" in e.group(3):
                continue
            fm = re.search(r'faction = "(\w+)"', e.group(3))
            if fm and fm.group(1) != faction:
                continue
            n += 1
            cost += int(e.group(2))
        out[int(m.group(1))] = (n, cost)
    return out


class SimCompiler(bg.Compiler):
    def __init__(self, data, races=None):
        super().__init__(data)
        self.events = []
        self.races = races  # steps whose {race=} leaves these out are skipped

    def compile_step(self, st, guide, prev):
        v = st["verb"]
        if self.races and "race" in st["opts"]:
            if not {r.strip() for r in st["opts"]["race"].split(",")} & set(self.races):
                return []
        if v in ("accept", "turnin", "complete"):
            ids = [int(s) for s in st["args"].split(",") if s.strip()]
            acc = {q for q, _ in self.accepted}
            done = {q for q, _ in self.turned}
            ids = [i for i in ids if i not in (acc if v == "accept" else done)]
            if not ids:
                return []
            st = dict(st, args=",".join(map(str, ids)))
        xp0, lvl0 = self.xp_total, self.est_level()
        res = super().compile_step(st, guide, prev)
        self.events.append({"verb": v, "res": res, "xp0": xp0, "xp1": self.xp_total, "lvl0": lvl0,
                            "guide": guide["name"], "where": st["where"]})
        return res


def track_routes(track):
    order, faction = TRACK_ORDERS[track]
    files = bg.read_order(order)
    if order == SHARED[faction]:
        return files, faction
    # A race track: follow the last guide's `next` into the shared chain.
    header, _ = bg.parse_route(os.path.join(bg.ROUTES, files[-1]))
    nxt = header.get("next")
    shared = bg.read_order(SHARED[faction])
    names = {}
    for rf in shared:
        h, _ = bg.parse_route(os.path.join(bg.ROUTES, rf))
        names[h.get("guide")] = rf
    if nxt in names:
        files = files + shared[shared.index(names[nxt]):]
    else:
        print("!! %s: next %r not found in %s" % (track, nxt, SHARED[faction]))
    return files, faction


def compile_playthrough(data, files):
    # races of the first guide (none: main track, all races)
    h0, _ = bg.parse_route(os.path.join(bg.ROUTES, files[0]))
    races = [r.strip() for r in h0.get("races", "").split(",") if r.strip()] or None
    comp = SimCompiler(data, races)
    guides = []
    for rf in files:
        header, steps = bg.parse_route(os.path.join(bg.ROUTES, rf))
        g = comp.compile_guide(header, steps)
        g["_route"] = rf
        guides.append(g)
    return comp, guides


def fp_points(data, faction):
    out = {}
    for nid, name in ac.FP_BY_FACTION[faction].items():
        pts = data.points("npc", nid)
        if pts:
            out[name] = pts[0]
    return out


def objective_seconds(data, q):
    ob = bg.slots(q.get("objectives"))
    counts = [int(n) for t in bg.as_list(q.get("objectivesText")) for n in re.findall(r"\b(\d+)\b", str(t))]
    n_obj = len(bg.as_list(ob.get(2)))
    for it in bg.as_list(ob.get(3)):
        item = data.items.get(str(it[0] if isinstance(it, list) else it)) or {}
        if item.get("objectDrops") and not item.get("npcDrops"):
            n_obj += 1
    secs = 0
    if n_obj:
        secs += pz.OBJECT_SECONDS * max(n_obj, min(sum(counts) or n_obj, 15))
    text = " ".join(map(str, bg.as_list(q.get("objectivesText"))))
    if not ob and not q.get("objectivesText"):
        return 0
    if not any(ob.get(k) for k in (1, 2, 3)) and pz.TEXT_TASK.search(text):
        secs += pz.ESCORT_SECONDS if pz.ESCORT.search(text) else pz.TEXT_OBJECTIVE_SECONDS
    return secs


def grind_rate(level):
    lvl = max(1, int(level))
    return max(bg.mob_xp(lvl, lvl + d) / (pz.GRIND_SEC_PER_KILL * pz.kill_factor(d)) for d in range(-3, 2))


def top_mob(data, q):
    lv = bg.mob_level(data, q)
    return lv or 0


class Run:
    def __init__(self, data, comp, guides, faction, cls, trainers, spells, fps):
        self.d, self.comp, self.guides, self.faction, self.cls = data, comp, guides, faction, cls
        self.trainers = trainers.get(cls, {})
        self.spells = spells
        self.fps = fps
        self.t = 0.0
        self.parts = collections.Counter()   # quest / grind / travel / flight seconds
        self.band = collections.Counter()    # seconds per 10-level band
        self.pos = None
        self.hearth = None
        self.hearth_uses = []                # self.t at every hearthstone use
        self.trained_at = 1
        self.train_visits = []               # (level, area)
        self.missed_train = []               # train steps without a trainer for this class
        self.gaps = []                       # (from level, to level, spells behind at worst)
        self.near = {}
        self.city = []                       # (level, city area, guide, has a trainer for this class)
        self.hard = []                       # (eff diff, level, guide, quest, mob level, levels behind)
        self.long_grinds = []
        self.long_trips = []
        self.done_kill = set()
        self.level_times = {}

    def level(self, xp):
        return bg.level_from_xp(xp)

    def behind(self, level):
        """(levels behind, spells behind) on training."""
        lv = int(level)
        missing = sum(n for l, (n, _) in self.spells.items() if self.trained_at < l <= lv)
        return (lv - self.trained_at if missing else 0), missing

    def speed(self, level):
        lag, _ = self.behind(level)
        pen = min(RANK_PENALTY_MAX, RANK_PENALTY * max(0, lag - 1))
        return CLASS_SPEED.get(self.cls, 1.0) * (1 + pen)

    def add(self, secs, kind, level):
        self.t += secs
        self.parts[kind] += secs
        self.band[min(5, int(level) // 10)] += secs
        lv = int(level)
        if lv not in self.level_times:
            self.level_times[lv] = self.t

    def travel(self, p, level, ev):
        if p is None:
            return
        p = (p[0], p[1], p[2])
        if self.pos is None:
            self.pos = p
            return
        secs = cz.travel_seconds(self.pos, p, [])
        if secs == float("inf") or secs > 3600:
            secs = 0  # boat/portal gap, don't count a broken path
        if level >= MOUNT_LEVEL:
            secs /= MOUNT_SPEED
        if secs > LONG_TRIP:
            self.long_trips.append((secs, level, ev["guide"], ev["where"]))
        self.add(secs, "travel", level)
        self.pos = p

    def fight_seconds(self, q, level):
        secs = 0.0
        for mlevel, kills in self.d.kill_estimate(q):
            secs += kills * pz.SEC_PER_KILL * pz.kill_factor(mlevel - level) * self.speed(level)
        return secs

    def check_hard(self, q, level, ev):
        mob = top_mob(self.d, q)
        if not mob:
            return
        lag, _ = self.behind(level)
        el = bg.elite_level(self.d, q)
        diff = (el + 1 if el else mob) - level
        self.hard.append((round(diff, 1), round(level, 1), ev["guide"], "%s %s%s" % (
            q.get("id", ""), q.get("name"), " (elite %d)" % el if el else ""), mob, lag))

    def city_pass(self, area, lvl, ev):
        if area and (not self.city or self.city[-1][1] != area or int(lvl) - self.city[-1][0] > 1):
            self.city.append((int(lvl), area, ev["guide"], area in self.trainers))

    def step(self, ev, out):
        lvl = self.level(ev["xp0"])
        mp = out.get("map")
        self.city_pass(next((a for a, m in CITY_AREAS.items() if m == mp), None), lvl, ev)
        if "fly" in out:
            self.city_pass(CITY_FP.get(out["fly"]), lvl, ev)
        cls = out.get("class")
        if cls and self.cls not in (cls if isinstance(cls, list) else [cls]):
            return
        if self.cls in (out.get("notclass") or []):
            return
        v = ev["verb"]
        p = (out["map"], out["x"], out["y"]) if "x" in out and out.get("map") else None
        if v == "fly":
            self.travel(p, lvl, ev)
            dest = self.fps.get(out["fly"])
            if dest and self.pos:
                secs = pz.yards(self.pos, dest) / cz.FLIGHT_SPEED + cz.FLIGHT_OVERHEAD
                if secs < 1e6:
                    self.add(secs, "flight", lvl)
                self.pos = dest
            return
        if v == "hearth":
            self.hearth_uses.append(self.t)
            self.add(20, "travel", lvl)
            if self.hearth:
                self.pos = self.hearth
            return
        self.travel(p, lvl, ev)
        if v == "sethearth":
            self.hearth = self.pos
            self.add(pz.TALK_SECONDS, "quest", lvl)
        elif v == "getfp":
            self.add(10, "travel", lvl)
        elif v == "train":
            area = out["train"]
            if area in self.trainers:
                lag, missing = self.behind(lvl)
                if lag:
                    self.gaps.append((self.trained_at, int(lvl), missing))
                self.trained_at = int(lvl)
                self.train_visits.append((int(lvl), area))
                self.add(30, "quest", lvl)
            else:
                self.missed_train.append((int(lvl), area, ev["guide"]))
        elif v == "accept":
            self.add(pz.TALK_SECONDS, "quest", lvl)
        elif v == "complete":
            qids = out["complete"] if isinstance(out["complete"], list) else [out["complete"]]
            secs = pz.AREA_SECONDS
            for qid in qids:
                q = dict(self.d.quest(qid) or {}, id=qid)
                secs += self.fight_seconds(q, lvl) + objective_seconds(self.d, q)
                self.done_kill.add(qid)
                self.check_hard(q, lvl, ev)
            self.add(secs, "quest", lvl)
        elif v == "turnin":
            qid = out["turnin"]
            q = dict(self.d.quest(qid) or {}, id=qid)
            if qid not in self.done_kill and self.d.kill_estimate(q):
                self.add(self.fight_seconds(q, lvl) + objective_seconds(self.d, q), "quest", lvl)
                self.check_hard(q, lvl, ev)
                self.done_kill.add(qid)
            self.add(pz.TALK_SECONDS, "quest", lvl)
        elif v == "level":
            xp, end, secs = ev["xp0"], ev["xp1"], 0.0
            while xp < end:  # level by level, the rate changes with level
                lv = int(self.level(xp))
                nxt = min(end, sum(bg.XP_TO_LEVEL[1:lv + 1]))
                if nxt <= xp:
                    break
                s = (nxt - xp) / (grind_rate(lv) / self.speed(lv))
                self.add(s, "grind", lv)
                secs += s
                xp = nxt
            if secs > LONG_GRIND:
                self.long_grinds.append((secs, lvl, out["level"], ev["guide"]))
        # passing your trainer while behind on spells: an easy stop the route doesn't make
        lag, missing = self.behind(lvl)
        if lag >= 4 and self.pos:
            for area, (mp, x, y, npc) in self.trainers.items():
                if mp == self.pos[0] and pz.yards(self.pos, (mp, x, y)) < TRAINER_NEAR:
                    self.near.setdefault((ev["guide"], area), (int(lvl), missing))

    def run(self):
        for ev in self.comp.events:
            for out in ev["res"]:
                self.step(ev, out)
        end = self.level(self.comp.xp_total)
        lag, missing = self.behind(end)
        if lag:
            self.gaps.append((self.trained_at, int(end), missing))
        self.end_level = end
        return self


def hours(s):
    return "%.1f h" % (s / 3600.0)


def track_classes(trainers, guides):
    areas = [s["train"] for s in guides[0]["steps"] if "train" in s and s["train"] not in CITY_AREAS]
    return [c for c in bg.FACTION_CLASSES["Alliance"] if any(a in trainers.get(c, {}) for a in areas)]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    only = sys.argv[sys.argv.index("--class") + 1].upper() if "--class" in sys.argv else None
    if only in args:
        args.remove(only)
    args = [a for a in args if a.upper() != only] if only else args
    tracks = args or list(TRACK_ORDERS)
    data = bg.Data()
    trainers = load_trainers()
    for track in tracks:
        files, faction = track_routes(track)
        cz.FACTION = faction
        comp, guides = compile_playthrough(data, files)
        fps = fp_points(data, faction)
        classes = [only] if only else track_classes(trainers, guides)
        print("=" * 100)
        print("TRACK %s (%s): %d guides, ends at level %.1f, %d warnings/errors in the replay"
              % (track, faction, len(guides), comp.est_level(), len(comp.warnings) + len(comp.errors)))
        tiny = [g["name"] for g in guides if len(g["steps"]) < 8]
        if tiny:
            print("  tiny guides (<8 steps): " + "; ".join(tiny))
        runs = []
        for cls in classes:
            r = Run(data, comp, guides, faction, cls, trainers, load_spells(cls, faction), fps).run()
            runs.append(r)
        print("  %-8s %7s  %6s %6s %6s %6s | %s" % ("class", "total", "quest", "grind", "travel", "flight",
                                                  "hours per band 1-9/10-19/20-29/30-39/40-49/50-60"))
        for r in runs:
            print("  %-8s %7s  %5.0f%% %5.0f%% %5.0f%% %5.0f%% | %s" % (
                r.cls, hours(r.t), *(100.0 * r.parts[k] / r.t for k in ("quest", "grind", "travel", "flight")),
                " / ".join("%.1f" % (r.band[b] / 3600) for b in range(6))))
        for r in runs:
            print("  -- %s: trained at %s" % (r.cls, ", ".join("%d %s" % v for v in r.train_visits) or "never"))
            big = [g for g in r.gaps if g[1] - g[0] >= 6]
            if big:
                print("     no trainer visit: " + "; ".join("levels %d->%d (%d spells/ranks waiting)" % g for g in big))
            if r.missed_train:
                print("     train steps with no %s trainer: %s" % (
                    r.cls, "; ".join("%d %s (%s)" % m for m in r.missed_train)))
            passes = [c for c in r.city if c[0] >= 14]
            if passes:
                print("     city stops from 14 on: " + "; ".join(
                    "%d %s%s" % (c[0], c[1], "" if c[3] else " (no trainer for you)") for c in passes))
            if r.near:
                print("     passes own trainer while behind: " + "; ".join(
                    "%s @%s lvl %d (%d waiting)" % (g, a, lv, n) for (g, a), (lv, n) in list(r.near.items())[:8]))
            hard = sorted(r.hard, reverse=True)[:5]
            print("     hardest fights (mob - your level): " + "; ".join(
                "%+.1f %s @%.0f [%s] %d lvls behind trainer" % (h[0], h[3], h[1], h[2], h[5]) for h in hard))
        r = runs[0] if runs else None
        if r:
            for s, lv, to, g in sorted(r.long_grinds, reverse=True)[:12]:
                print("  long grind (%s): %s %.1f -> %d in %s" % (r.cls, hours(s), lv, to, g))
            for s, lv, g, w in sorted(r.long_trips, reverse=True)[:12]:
                print("  long trip  (%s): %.0f min at %.0f, %s (%s)" % (r.cls, s / 60, lv, g, w))
            early = [(b - a) / 60 for a, b in zip(r.hearth_uses, r.hearth_uses[1:]) if b - a < 3600]
            print("  hearthstone (%s): %d uses, %d within an hour of the one before%s" % (
                r.cls, len(r.hearth_uses), len(early),
                (": " + ", ".join("%.0f min" % m for m in early)) if early else ""))


if __name__ == "__main__":
    main()
