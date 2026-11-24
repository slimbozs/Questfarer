"""Questfarer guide compiler: Tools/routes/*.route (order in routes/ORDER) -> Questfarer/Guides/*.lua.

Usage:  python -I build_guides.py [--check]      (--check: validate only, write nothing)

Route lines: <verb> <args> [@x,y[,map]] [{k=v;k=v}] [| text] [|| tip], '#' starts a comment.
Options in {..}: class=WARRIOR,MAGE  race=Human  notclass=..  npc=Name  radius=20  title=..
"""
import json
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(ROOT, "db")
QF = os.path.join(ROOT, "questie-forever")
ROUTES = os.path.join(ROOT, "routes")
REPORTS = os.path.join(ROOT, "reports")
OUT = os.path.join(os.path.dirname(ROOT), "Questfarer", "Guides")

RACE_BITS = {"Human": 1, "Orc": 2, "Dwarf": 4, "NightElf": 8, "Scourge": 16, "Tauren": 32, "Gnome": 64, "Troll": 128}
# Forever's Skyborne get a race bit per faction, but UnitRace says "Skyborne" for both
SKYBORNE_BITS = {"Alliance": 2 ** 32, "Horde": 2 ** 33}


def race_bit(race, faction=None):
    if race == "Skyborne":
        return SKYBORNE_BITS[faction] if faction else SKYBORNE_BITS["Alliance"] | SKYBORNE_BITS["Horde"]
    return RACE_BITS[race]
CLASS_BITS = {"WARRIOR": 1, "PALADIN": 2, "HUNTER": 4, "ROGUE": 8, "PRIEST": 16, "SHAMAN": 64,
              "MAGE": 128, "WARLOCK": 256, "DRUID": 1024}
ALLIANCE = ["Human", "Dwarf", "NightElf", "Gnome"]
HORDE = ["Orc", "Scourge", "Tauren", "Troll"]
FACTION_CLASSES = {
    "Alliance": ["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"],  # Forever: Dwarf shamans
    "Horde": ["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"],  # Forever: Horde paladins
}
XP_TO_LEVEL = [0, 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400,
               16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300,
               47400, 50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300,
               111800, 117500, 123200, 129100, 135100, 141200, 147500, 153900, 160400, 167100, 173900, 180800,
               187900, 195000, 202300, 209800]


def gray_level(level):
    if level <= 5:
        return 0
    if level <= 39:
        return level - 5 - level // 10
    return level - 1 - level // 5


def zero_difference(level):
    for top, zd in ((7, 5), (9, 6), (11, 7), (15, 8), (19, 9), (29, 11), (39, 12), (44, 13), (49, 14), (54, 15)):
        if level <= top:
            return zd
    return 16


def mob_xp(plevel, mlevel):
    base = plevel * 5 + 45
    if mlevel >= plevel:
        return base * (1 + 0.05 * min(mlevel - plevel, 4))
    if mlevel <= gray_level(plevel):
        return 0
    return base * (1 - (plevel - mlevel) / zero_difference(plevel))


DROP_RATE = 0.55      # average chance a quest item drops from the right mob
EXTRA_KILLS = 1.3     # mobs killed on the way / in the way


def level_from_xp(total):
    lvl, need = 1, 0
    while lvl < 60 and total >= need + XP_TO_LEVEL[lvl]:
        need += XP_TO_LEVEL[lvl]
        lvl += 1
    return lvl + (total - need) / XP_TO_LEVEL[lvl] if lvl < 60 else 60.0


def load_json(name):
    with open(os.path.join(DB, name), encoding="utf-8") as fh:
        return json.load(fh)


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def parse_lua_int_map(src):
    return {int(a): int(b) for a, b in re.findall(r"\[(\d+)\]\s*=\s*(\d+)", src)}


def load_area_map():
    src = read(os.path.join(QF, "areaIdToUiMapId.lua"))
    m = re.search(r"areaIdToUiMapIdOverride\s*=\s*\[\[(.*?)\]\]", src, re.S)
    override = parse_lua_int_map(m.group(1)) if m else {}
    base = parse_lua_int_map(src[m.end():] if m else src)
    base.update(override)
    return base


def load_xp():
    xp = {}
    for f in ("xpDB-classic.lua", "xpDB-traces.lua"):
        p = os.path.join(QF, f)
        if os.path.exists(p):
            for qid, lvl, val in re.findall(r"\[(\d+)\]\s*=\s*\{\s*(-?\d+)\s*,\s*(\d+)", read(p)):
                xp[int(qid)] = (int(lvl), int(val))
    return xp


def slots(v, n=6):
    """QuestieDB sparse tables arrive either as a list (1-based) or a dict with string keys."""
    out = {}
    if isinstance(v, list):
        for i, x in enumerate(v, 1):
            out[i] = x
    elif isinstance(v, dict):
        for k, x in v.items():
            out[int(k)] = x
    return out


def as_list(v):
    if v is None:
        return []
    if isinstance(v, list):
        return v
    if isinstance(v, dict):
        return [v[k] for k in sorted(v, key=int)]
    return [v]


# Solo rule: kill targets at most MOB_GAP levels above you. +2 from MOB_GAP_HIGH_FROM on: with +1, Classic has
# too few fitting quests at 30-55 and the route turned into hours of grinding.
MOB_GAP = 1
MOB_GAP_HIGH = 2
MOB_GAP_HIGH_FROM = 29  # the +2 chain starts after Duskwood, at ~29.3


def gap_below(level):
    return level - MOB_GAP_HIGH if level - MOB_GAP_HIGH >= MOB_GAP_HIGH_FROM else level - MOB_GAP


def mob_level(data, q):
    top = lambda n: n.get("maxLevel") or n.get("minLevel") or 0  # noqa: E731
    ob = slots(q.get("objectives"))
    lv = 0
    for c in as_list(ob.get(1)):
        n = data.npcs.get(str(c[0] if isinstance(c, list) else c)) or {}
        if not n.get("friendlyToFaction"):  # friendly ones are talk/interact credit
            lv = max(lv, top(n))
    for i in as_list(ob.get(3)):
        it = data.items.get(str(i[0] if isinstance(i, list) else i)) or {}
        if it.get("objectDrops"):
            continue  # can be looted from objects
        drops = [top(data.npcs.get(str(n)) or {}) for n in as_list(it.get("npcDrops"))]
        if drops:
            lv = max(lv, min(drops))
    return lv


# escorts have no kill targets in the DB but get ambushed at about quest level: take them at quest level
ESCORT_TEXT = re.compile(r"\b(escort|protect|go with)\b", re.I)
USE_ITEM = re.compile(r"\buse\b", re.I)


def solo_level(data, q):
    ql = q.get("questLevel") or 0
    mob = mob_level(data, q)
    need = gap_below(mob)
    if mob:
        need = max(need, gap_below(ql))
    if not slots(q.get("objectives")).get(1) and ESCORT_TEXT.search(" ".join(q.get("objectivesText") or [])):
        need = max(need, ql)
    elite = elite_level(data, q)
    if elite:
        need = max(need, elite + elite_gap(elite))
    camp = camp_level(data, q)
    if camp:
        need = max(need, gap_below(camp))
    return need


# Objects inside a mob camp: you fight the camp to reach them, so its mobs count like kill targets.
# Camp = at least CAMP_MIN hostile spawns within CAMP_RADIUS (map %).
CAMP_RADIUS = 2.0
CAMP_MIN = 4
CAMP_MAX_ID = 200000  # higher ids in Classic zones are content leaked from other Classic versions
# Forever's new zones: every creature there has an id above CAMP_MAX_ID
FOREVER_MAPS = {2548, 2482, 2652, 2521, 2524}
CAMP_ABOVE_QUEST = 3  # camps further above the quest level are noise


def camp_index(data):
    if not hasattr(data, "_camp_index"):
        idx = {}
        for nid, n in data.npcs.items():
            if n.get("friendlyToFaction"):
                continue
            top = n.get("maxLevel") or n.get("minLevel") or 0
            if not 1 <= top <= 63:
                continue
            for p in data.points("npc", nid):
                if int(nid) >= CAMP_MAX_ID and p[0] not in FOREVER_MAPS:
                    continue  # leaked content in a Classic zone
                idx.setdefault(p[0], []).append((p[1], p[2], top))
        data._camp_index = idx
    return data._camp_index


def camp_level(data, q):
    idx = camp_index(data)
    ob = slots(q.get("objectives"))
    objs = as_list(slots(q.get("finishedBy")).get(2)) + [o[0] if isinstance(o, list) else o
                                                        for o in as_list(ob.get(2))]
    ql = q.get("questLevel") or 0
    lv = 0
    for o in objs:
        best = None
        for m, x, y in data.points("object", o):
            near = sorted(t for px, py, t in idx.get(m, []) if math.hypot(px - x, py - y) <= CAMP_RADIUS)
            c = near[len(near) // 2] if len(near) >= CAMP_MIN else 0
            best = c if best is None else min(best, c)
        if best and best <= ql + CAMP_ABOVE_QUEST:
            lv = max(lv, best)
    return lv


def elite_gap(level):
    return min(3, max(1, int(level) // 5))


def elite_level(data, q, ranks=(1, 2, 3, 4)):
    top = lambda n: n.get("maxLevel") or n.get("minLevel") or 0  # noqa: E731
    ob = slots(q.get("objectives"))
    lv = 0
    for c in as_list(ob.get(1)):
        n = data.npcs.get(str(c[0] if isinstance(c, list) else c)) or {}
        if n.get("rank") in ranks and not n.get("friendlyToFaction"):
            lv = max(lv, top(n))
    for i in as_list(ob.get(3)):
        it = data.items.get(str(i[0] if isinstance(i, list) else i)) or {}
        if it.get("objectDrops"):
            continue
        drops = [data.npcs.get(str(n)) or {} for n in as_list(it.get("npcDrops"))]
        if drops and all(n.get("rank") in ranks for n in drops):
            lv = max(lv, min(top(n) for n in drops))
    return lv


def is_elite(data, q):
    # rank 4 is a rare, not an elite
    return elite_level(data, q, ranks=(1, 2, 3)) > 0


# Mount Hyjal required levels missing from the DB, as reported by foreverchanges.pro (not confirmed)
REQUIRED_LEVEL_OVERRIDES = {92100: 54, 92147: 55, 93197: 56, 94479: 54, 95320: 54, 96145: 55, 96321: 54, 96796: 54}


class Data:
    def __init__(self):
        self.quests = load_json("quests.json")
        for qid, level in REQUIRED_LEVEL_OVERRIDES.items():
            self.quests[str(qid)]["requiredLevel"] = level
        # 5249 and 5250 exclude each other, either one opens The Ruins of Kel'Theril
        self.quests["5244"].update(preQuestGroup=None, preQuestSingle=[5249, 5250])
        self.npcs = load_json("npcs.json")
        self.objects = load_json("objects.json")
        self.items = load_json("items.json")
        self.area = load_area_map()
        self.xp = load_xp()

    def quest(self, qid):
        return self.quests.get(str(qid))

    def points(self, kind, eid):
        """[(uiMap, x, y)] for an npc/object spawn table."""
        rec = (self.npcs if kind == "npc" else self.objects).get(str(eid))
        if not rec:
            return []
        out = []
        for area, pts in slots(rec.get("spawns")).items():
            ui = self.area.get(int(area))
            if not ui:
                continue
            for p in as_list(pts):
                if isinstance(p, list) and len(p) >= 2 and p[0] is not None and p[0] >= 0:
                    out.append((ui, float(p[0]), float(p[1])))
        return out

    def name(self, kind, eid):
        table = {"npc": self.npcs, "object": self.objects, "item": self.items}[kind]
        rec = table.get(str(eid))
        return rec.get("name") if rec else None

    def kill_estimate(self, q):
        """[(mob level, kills)], estimated from the objective text counts."""
        counts = [int(n) for t in as_list(q.get("objectivesText")) for n in re.findall(r"\b(\d+)\b", str(t))]
        ob = slots(q.get("objectives"))
        out = []

        def lvl(nid):
            n = self.npcs.get(str(nid)) or {}
            lo, hi = n.get("minLevel"), n.get("maxLevel")
            return ((lo or hi or 1) + (hi or lo or 1)) / 2

        objs = []
        for c in as_list(ob.get(1)):
            objs.append(("kill", [c[0] if isinstance(c, list) else c]))
        for i in as_list(ob.get(3)):
            iid = i[0] if isinstance(i, list) else i
            drops = as_list((self.items.get(str(iid)) or {}).get("npcDrops"))
            if drops:
                objs.append(("loot", drops[:3]))
        for k, (kind, npcs) in enumerate(objs):
            n = counts[k] if k < len(counts) else (counts[-1] if counts else 1)
            n = min(n, 30)
            kills = n / DROP_RATE if kind == "loot" else n
            out.append((sum(lvl(x) for x in npcs) / len(npcs), kills * EXTRA_KILLS))
        return out

    def givers(self, field):
        """startedBy/finishedBy -> (npcs, objects, items)."""
        s = slots(field)
        return as_list(s.get(1)), as_list(s.get(2)), as_list(s.get(3))


def best_point(points, prefer_map, prev, radius=3.0):
    """Densest spawn cluster, biased toward prev. Returns (map, x, y, n)."""
    if not points:
        return None
    on_map = [p for p in points if p[0] == prefer_map]
    if not on_map and prev:
        on_map = [p for p in points if p[0] == prev[0]]
    pts = on_map or [p for p in points if p[0] == points[0][0]]
    tagged = len(pts[0]) > 3
    best, best_score = None, None
    for p in pts:
        near = [q for q in pts if math.hypot(q[1] - p[1], q[2] - p[2]) <= radius]
        cx = sum(q[1] for q in near) / len(near)
        cy = sum(q[2] for q in near) / len(near)
        density = len(near)
        if prev and prev[0] == p[0]:
            density = density / (1 + math.hypot(cx - prev[1], cy - prev[2]) / 10)
        distinct = len({q[3] for q in pts if math.hypot(q[1] - p[1], q[2] - p[2]) <= radius * 2}) if tagged else 0
        score = (distinct, density)
        if best_score is None or score > best_score:
            best_score, best = score, (p[0], round(cx, 1), round(cy, 1), len(near))
    return best


def parse_route(path):
    header, steps = {}, []
    for lineno, raw in enumerate(read(path).splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        tip = text = None
        if "||" in line:
            line, tip = [s.strip() for s in line.split("||", 1)]
        if "|" in line:
            line, text = [s.strip() for s in line.split("|", 1)]
        opts = {}
        m = re.search(r"\{([^}]*)\}", line)
        if m:
            for kv in m.group(1).split(";"):
                if "=" in kv:
                    k, v = kv.split("=", 1)
                    opts[k.strip()] = v.strip()
            line = (line[:m.start()] + line[m.end():]).strip()
        coord = None
        m = re.search(r"@\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)(?:\s*,\s*(\d+))?", line)
        if m:
            coord = (int(m.group(3)) if m.group(3) else None, float(m.group(1)), float(m.group(2)))
            line = (line[:m.start()] + line[m.end():]).strip()
        verb, _, args = line.partition(" ")
        args = args.strip()
        if verb in ("guide", "file", "faction", "races", "levels", "map", "next", "side", "ability") and not steps:
            header[verb] = args
            continue
        steps.append({"verb": verb, "args": args, "opts": opts, "coord": coord, "text": text, "tip": tip,
                      "where": "%s:%d" % (os.path.basename(path), lineno)})
    return header, steps


class Compiler:
    def __init__(self, data):
        self.d = data
        self.errors, self.warnings = [], []
        self.accepted, self.turned = [], []  # (qid, classes or None)
        self.solo_checked = set()
        self.optional = set()  # elite quests and the quests that follow them
        self.level = 1
        self.class_level = {}
        self.xp_total = 0
        self.routed = set()

    def err(self, where, msg):
        self.errors.append("%s: %s" % (where, msg))

    def warn(self, where, msg):
        self.warnings.append("%s: %s" % (where, msg))

    @staticmethod
    def compatible(a, b):
        return a is None or b is None or bool(set(a) & set(b))

    def has(self, lst, qid, classes):
        return any(q == qid and self.compatible(c, classes) for q, c in lst)

    def quest_filters(self, q, step, guide):
        """Class/race filters from the quest's masks: (classes, races), or raises ValueError."""
        classes = [c.strip().upper() for c in step["opts"]["class"].split(",")] if "class" in step["opts"] else None
        races = [r.strip() for r in step["opts"]["race"].split(",")] if "race" in step["opts"] else None
        cmask = q.get("requiredClasses") or 0
        if cmask:
            allowed = [c for c, b in CLASS_BITS.items() if cmask & b and c in FACTION_CLASSES[guide["faction"]]]
            classes = [c for c in (classes or allowed) if c in allowed]
            if not classes:
                raise ValueError("quest %s is for classes %s only" % (q["name"], cmask))
        rmask = q.get("requiredRaces") or 0
        greaces = races or guide["races"]
        if rmask:
            ok = [r for r in greaces if rmask & race_bit(r, guide["faction"])]
            if not ok:
                raise ValueError("quest %s is not available to %s" % (q["name"], ",".join(greaces)))
            if len(ok) < len(greaces):
                races = ok
        return classes, races

    def xp_level(self):
        return int(level_from_xp(self.xp_total))

    def est_level(self):
        return level_from_xp(self.xp_total)

    def add_kill_xp(self, q):
        plevel = int(self.est_level())
        for mlevel, kills in self.d.kill_estimate(q):
            self.xp_total += mob_xp(plevel, mlevel) * kills

    def quest_xp(self, qid):
        lv, val = self.d.xp.get(qid, (None, 0))
        if not val:
            return 0
        plevel = max(self.level, self.xp_level())
        diff = plevel - (lv or plevel)
        factor = 1.0 if diff <= 5 else {6: .8, 7: .6, 8: .4, 9: .2}.get(diff, .1)
        return int(val * factor)

    def place(self, step, out, points, guide, prev, label):
        if step["coord"]:
            mp, x, y = step["coord"]
            out["map"], out["x"], out["y"] = mp or guide["map"], x, y
            return
        bp = best_point(points, guide["map"], prev)
        if bp:
            out["map"], out["x"], out["y"] = bp[0], bp[1], bp[2]
        else:
            self.warn(step["where"], "no coordinates for %s" % label)

    def giver(self, q, field, step, guide, prev):
        npcs, objs, items = self.d.givers(q.get(field))
        out = {}
        cands = []
        for n in npcs:
            for p in self.d.points("npc", n):
                cands.append((p, "npc", n))
        for o in objs:
            for p in self.d.points("object", o):
                cands.append((p, "object", o))
        if "npc" in step["opts"]:
            want = step["opts"]["npc"].lower()
            cands = [c for c in cands if (self.d.name(c[1], c[2]) or "").lower() == want] or cands
        # quests that start from a dropped item sometimes list a giver in another zone
        if items and field == "startedBy":
            cands = [c for c in cands if c[0][0] == guide["map"]]
        if cands:
            bp = best_point([c[0] for c in cands], guide["map"], prev, radius=0.01)
            pick = min(cands, key=lambda c: (c[0][0] != bp[0], math.hypot(c[0][1] - bp[1], c[0][2] - bp[2])))
            out["npc"] = self.d.name(pick[1], pick[2])
            if pick[1] == "npc":
                out["_npcid"] = int(pick[2])
            if pick[1] == "object":
                out["object"] = True
            if not step["coord"]:
                out["map"], out["x"], out["y"] = pick[0][0], round(pick[0][1], 1), round(pick[0][2], 1)
        elif items and field == "startedBy":
            iname = self.d.name("item", items[0]) or ("item %s" % items[0])
            out["item"] = iname
            pts = self.item_points(items[0])
            if not step["coord"] and pts:
                bp = best_point(pts, guide["map"], prev)
                out["map"], out["x"], out["y"] = bp[0], bp[1], bp[2]
        elif not step["coord"]:
            self.warn(step["where"], "no %s location for quest %s" % (field, q.get("name")))
        if step["coord"]:
            mp, x, y = step["coord"]
            out["map"], out["x"], out["y"] = mp or guide["map"], x, y
        return out

    def item_points(self, iid):
        it = self.d.items.get(str(iid)) or {}
        pts = []
        for n in as_list(it.get("npcDrops")):
            pts += self.d.points("npc", n)
        for o in as_list(it.get("objectDrops")):
            pts += self.d.points("object", o)
        return pts

    def objectives(self, q):
        """(points, text parts) for a quest's objectives."""
        pts, parts = [], []
        ob = slots(q.get("objectives"))

        def tag(points, t):
            return [(p[0], p[1], p[2], t) for p in points]
        for c in as_list(ob.get(1)):
            cid = c[0] if isinstance(c, list) else c
            pts += tag(self.d.points("npc", cid), ("n", cid))
            parts.append("Kill " + (self.d.name("npc", cid) or "?"))
        for o in as_list(ob.get(2)):
            oid = o[0] if isinstance(o, list) else o
            pts += tag(self.d.points("object", oid), ("o", oid))
            label = (o[1] if isinstance(o, list) and len(o) > 1 and o[1] else None) or self.d.name("object", oid) or "?"
            parts.append("Use " + label)
        for i in as_list(ob.get(3)):
            iid = i[0] if isinstance(i, list) else i
            ipts = self.item_points(iid)
            pts += tag(ipts, ("i", iid))
            it = self.d.items.get(str(iid)) or {}
            srcs = [self.d.name("npc", n) for n in as_list(it.get("npcDrops"))[:2]]
            srcs += [self.d.name("object", o) for o in as_list(it.get("objectDrops"))[:2]]
            iname = self.d.name("item", iid)
            srcs = [s for s in srcs if s and s != iname]
            parts.append("Collect " + (self.d.name("item", iid) or "?") + (" (%s)" % ", ".join(srcs) if srcs else ""))
        for k in as_list(ob.get(5)):  # kill credit: {{npcIds}, creditId, text}
            if isinstance(k, list) and k and isinstance(k[0], list):
                for nid in k[0]:
                    pts += tag(self.d.points("npc", nid), ("k", id(k)))
                if len(k) > 2 and k[2]:
                    parts.append(k[2])
        trig = q.get("triggerEnd")
        if isinstance(trig, list) and len(trig) >= 2:
            parts.append(trig[0] or "Explore")
            for area, tp in slots(trig[1]).items():
                ui = self.d.area.get(int(area))
                for p in as_list(tp):
                    if ui and isinstance(p, list):
                        pts.append((ui, float(p[0]), float(p[1]), ("t", q.get("name"))))
        return pts, parts

    def compile_guide(self, header, steps):
        guide = {
            "name": header["guide"],
            "faction": header.get("faction", "Alliance"),
            "races": [r.strip() for r in header.get("races", "").split(",") if r.strip()]
                     or (ALLIANCE if header.get("faction", "Alliance") == "Alliance" else HORDE),
            "map": int(header.get("map", 0)) or None,
            "next": header.get("next"),
            # no races header: every race of the faction (new races too), the addon only checks the faction
            "raceLimited": bool(header.get("races", "").strip()),
            "side": header.get("side"),        # class quest side guide: the class it is for
            "ability": header.get("ability"),  # what the class quests teach
        }
        lv = header.get("levels", "1 60").split()
        guide["minLevel"], guide["maxLevel"] = int(lv[0]), int(lv[1])
        self.level = max(self.level, guide["minLevel"])
        out_steps = []
        prev = None
        before = {q for q, _ in self.accepted} - {q for q, _ in self.turned}  # in the log as the guide starts
        for st in steps:
            try:
                res = self.compile_step(st, guide, prev)
            except ValueError as e:
                self.err(st["where"], str(e))
                continue
            for r in res:
                tip = NPC_TIPS.get(r.get("_npcid"))
                if tip and tip not in (r.get("tip") or ""):
                    r["tip"] = (r["tip"] + " " + tip) if r.get("tip") else tip
                self.add_helpers(r, guide)
                if "x" in r:
                    prev = (r.get("map") or guide["map"], r["x"], r["y"])
                out_steps.append(r)
        guide["steps"] = out_steps
        self.on_the_way(guide, before)
        guide["_endLevel"] = self.est_level()
        return guide

    def add_helpers(self, r, guide):
        """Adds items, targets and area (flat x, y list) for the addon's buttons and map dots."""
        if isinstance(r.get("accept"), int):
            _, _, starters = self.d.givers((self.d.quest(r["accept"]) or {}).get("startedBy"))
            if starters:
                r["items"] = list(starters)[:2]
        if "complete" not in r:
            return
        qids = r["complete"] if isinstance(r["complete"], list) else [r["complete"]]
        mp = r.get("map") or guide["map"]
        items, targets, pts = [], [], []
        for qid in qids:
            q = self.d.quest(qid)
            ob = slots(q.get("objectives"))
            items += [i for i in [q.get("sourceItemId")] + as_list(q.get("requiredSourceItems")) if i]
            targets += [c[0] if isinstance(c, list) else c for c in as_list(ob.get(1))]
            for k in as_list(ob.get(5)):
                if isinstance(k, list) and k and isinstance(k[0], list):
                    targets += k[0][:2]
            for i in as_list(ob.get(3)):
                iid = i[0] if isinstance(i, list) else i
                it = self.d.items.get(str(iid)) or {}
                drops = [n for n in as_list(it.get("npcDrops")) if any(p[0] == mp for p in self.d.points("npc", n))]
                drops = [n for n in drops if not (self.d.npcs.get(str(n)) or {}).get("friendlyToFaction")]
                drops.sort(key=lambda n: -len(self.d.points("npc", n)))
                targets += drops[:3]
                if it.get("vendors") and not it.get("npcDrops") and not it.get("objectDrops"):
                    sellers = [self.d.name("npc", v) for v in as_list(it["vendors"])
                               if any(p[0] == mp for p in self.d.points("npc", v))] or \
                              [self.d.name("npc", v) for v in as_list(it["vendors"])[:2]]
                    sold = "%s is sold by vendors such as %s." % (it.get("name"), ", ".join(s for s in sellers[:2] if s))
                    r["tip"] = (r["tip"] + " " + sold) if r.get("tip") else sold
            pts += self.objectives(q)[0]
        names = []
        for n in targets:
            name = self.d.name("npc", n)
            if name and name not in names:
                names.append(name)
        if items:
            r["items"] = sorted(set(items), key=items.index)
        if names:
            r["targets"] = names[:AREA_TARGETS]
        if "x" in r:
            near = sorted({(p[1], p[2]) for p in pts if p[0] == mp and math.hypot(p[1] - r["x"], p[2] - r["y"]) <= AREA_RADIUS},
                          key=lambda p: math.hypot(p[0] - r["x"], p[1] - r["y"]))
            cells = {}
            for x, y in near:
                cells.setdefault((int(x / AREA_CELL), int(y / AREA_CELL)), (x, y))
            pick = list(cells.values())[:AREA_MAX]
            if len(pick) >= 2:
                r["area"] = [round(v, 1) for p in pick for v in p]

    def on_the_way(self, guide, before):
        import plan_zone as pz  # lazy: circular import
        if not hasattr(self, "_obj_cache"):
            self._obj_cache = {}

        def ids(v):
            return v if isinstance(v, list) else [v]

        def seg_dist(p, a, b):
            wp, wa, wb = pz.world(p), pz.world(a), pz.world(b)
            if not (wp and wa and wb) or not (wp[0] == wa[0] == wb[0]):
                return 1e9
            ax, ay, bx, by, px, py = wa[1], wa[2], wb[1], wb[2], wp[1], wp[2]
            dx, dy = bx - ax, by - ay
            ll = dx * dx + dy * dy
            t = 0 if ll == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / ll))
            return math.hypot(px - (ax + t * dx), py - (ay + t * dy))

        steps = guide["steps"]
        complete_at = {}
        for j, s in enumerate(steps):
            for q in ids(s.get("complete", [])):
                complete_at.setdefault(q, []).append(j)
        accepted = set(before)
        prev = None
        for i, s in enumerate(steps):
            m = s.get("map") or guide["map"]
            here = (m, s["x"], s["y"]) if "x" in s else None
            if here and prev and prev[0] == m and pz.yards(prev, here) >= ONWAY_MIN_LEG:
                names, quests = [], []
                for q in sorted(accepted):
                    later = [j for j in complete_at.get(q, []) if j > i]
                    if not later or i in complete_at.get(q, []):
                        continue
                    qd = self.d.quest(q)
                    if not qd:
                        continue
                    if q not in self._obj_cache:
                        self._obj_cache[q] = self.objectives(qd)[0]
                    pts = self._obj_cache[q]
                    near = [pt for pt in pts if pt[0] == m and seg_dist(pt, prev, here) <= ONWAY_YARDS]
                    if len(near) < ONWAY_MIN_SPAWNS:
                        continue
                    quests.append(qd.get("name") or str(q))
                    for t in sorted({pt[3] for pt in near}, key=str):
                        kind = {"n": "npc", "o": "object", "i": "item"}.get(t[0])
                        nm = self.d.name(kind, t[1]) if kind else None
                        if nm and nm not in names:
                            names.append(nm)
                if quests:
                    what = (" (" + ", ".join(names) + ")") if names else ""
                    tip = "On the way you pass objectives of %s%s - do them as you go." % (
                        ", ".join('"%s"' % n for n in quests), what)
                    s["tip"] = (s["tip"] + " " + tip) if s.get("tip") else tip
            for q in ids(s.get("accept", [])):
                accepted.add(q)
            for q in ids(s.get("turnin", [])):
                accepted.discard(q)
            for q in ids(s.get("complete", [])):
                if complete_at.get(q) and complete_at[q][-1] == i:
                    accepted.discard(q)  # objectives done
            if s.get("fly") or s.get("hearth"):
                prev = None  # no running past anything on a flight or hearth
            elif here:
                prev = here

    def common(self, st, out, classes=None, races=None):
        if classes:
            out["class"] = classes if len(classes) > 1 else classes[0]
        if races:
            out["race"] = races if len(races) > 1 else races[0]
        if "notclass" in st["opts"]:
            out["notclass"] = [c.strip().upper() for c in st["opts"]["notclass"].split(",")]
        if st["tip"]:
            out["tip"] = st["tip"]
        if "cp" in st["opts"]:
            # {cp=x,y/x,y,map}: arrow checkpoints in order, map defaults to the step's (not "via", crosszone uses that)
            via = []
            for part in st["opts"]["cp"].split("/"):
                nums = [n.strip() for n in part.split(",") if n.strip()]
                if len(nums) not in (2, 3):
                    raise ValueError("cp: expected x,y or x,y,map, got %r" % part)
                pt = [float(nums[0]), float(nums[1])]
                if len(nums) == 3:
                    pt.append(int(nums[2]))
                via.append(pt)
            out["via"] = via
        out["_where"] = st["where"]
        return out

    def compile_step(self, st, guide, prev):
        v, a = st["verb"], st["args"]
        if v in ("accept", "turnin"):
            res = []
            for qs in [s.strip() for s in a.split(",") if s.strip()]:
                res.append(self.quest_step(v, int(qs), st, guide, prev))
                if "x" in res[-1]:
                    prev = (res[-1].get("map") or guide["map"], res[-1]["x"], res[-1]["y"])
            return res
        if v == "complete":
            return [self.complete_step(st, guide, prev)]
        classes = [c.strip().upper() for c in st["opts"]["class"].split(",")] if "class" in st["opts"] else None
        races = [r.strip() for r in st["opts"]["race"].split(",")] if "race" in st["opts"] else None
        out = {}
        if v == "train":
            out["train"] = a
        elif v == "level":
            out["level"] = int(a)
            if classes:  # a class-only level step says nothing about other classes
                for c in classes:
                    self.class_level[c] = max(self.class_level.get(c, 0), int(a))
            else:
                self.level = max(self.level, int(a))
                need = sum(XP_TO_LEVEL[1:int(a)])
                self.xp_total = max(self.xp_total, need)
        elif v in ("getfp", "fly", "sethearth", "hearth"):
            out[v] = a
            if "npc" in st["opts"]:
                out["npc"] = st["opts"]["npc"]
        elif v == "go":
            out["go"] = True
            if "radius" in st["opts"]:
                out["radius"] = int(st["opts"]["radius"])
        elif v == "note":
            out["note"] = st["text"] or a
            st = dict(st, text=None)
        else:
            raise ValueError("unknown step '%s'" % v)
        if st["coord"]:
            mp, x, y = st["coord"]
            out["map"], out["x"], out["y"] = mp or guide["map"], x, y
        if st["text"]:
            out["text"] = st["text"]
        return [self.common(st, out, classes, races)]

    def quest_step(self, v, qid, st, guide, prev):
        q = self.d.quest(qid)
        if not q:
            raise ValueError("quest %d does not exist in the Forever DB" % qid)
        classes, races = self.quest_filters(q, st, guide)
        self.routed.add(qid)
        out = {v: qid, "title": st["opts"].get("title") or q.get("name")}
        out.update(self.giver(q, "startedBy" if v == "accept" else "finishedBy", st, guide, prev))
        w = st["where"]
        if v == "accept":
            self.check_accept(q, qid, classes, w)
            self.accepted.append((qid, classes))
            # for the addon at runtime: quest level (gray check) and prerequisites (skip unreachable quests)
            if (q.get("questLevel") or 0) > 0:
                out["qlevel"] = q["questLevel"]
            single = [p for p in as_list(q.get("preQuestSingle")) if not self.prereq_not_for(p, classes)]
            group = [p for p in as_list(q.get("preQuestGroup")) if not self.prereq_not_for(p, classes)]
            if single:
                out["pre"] = single
            if group:
                out["preall"] = group
            if is_elite(self.d, q):
                self.optional.add(qid)
                out["elite"] = True
            elif (single and all(p in self.optional for p in single)) or any(p in self.optional for p in group):
                self.optional.add(qid)
            if out.get("item"):
                out["text"] = self.item_start_text(q, out.pop("item"))
        else:
            if not self.has(self.accepted, qid, classes):
                self.err(w, "turn-in of %d %s before it is accepted" % (qid, q.get("name")))
            if qid not in self.solo_checked:
                self.check_solo(q, qid, classes, w)
            if self.has(self.turned, qid, classes):
                self.err(w, "quest %d turned in twice" % qid)
            self.turned.append((qid, classes))
            if not classes:
                self.xp_total += self.quest_xp(qid)
        if st["text"]:
            out["text"] = st["text"]
        if qid in self.optional:
            out["optional"] = [qid]
        out.pop("object", None)
        return self.common(st, out, classes, races)

    def item_start_text(self, q, iname):
        _, _, items = self.d.givers(q.get("startedBy"))
        it = (self.d.items.get(str(items[0])) or {}) if items else {}
        srcs = [self.d.name("npc", n) for n in as_list(it.get("npcDrops"))[:2]]
        srcs += [self.d.name("object", o) for o in as_list(it.get("objectDrops"))[:2]]
        srcs = [s for s in srcs if s and s != iname]
        return "Loot the %s%s and use it to start the quest" % (iname, " (%s)" % ", ".join(srcs) if srcs else "")

    @staticmethod
    def use_item_tip(q):
        for sentence in re.split(r"(?<=[.!?])\s+", " ".join(str(t) for t in as_list(q.get("objectivesText")))):
            if USE_ITEM.search(sentence) and len(sentence) <= 170:
                return sentence.strip()
        return None

    def check_accept(self, q, qid, classes, w):
        name = q.get("name")
        if self.has(self.accepted, qid, classes):
            self.err(w, "quest %d %s accepted twice" % (qid, name))
        single = as_list(q.get("preQuestSingle"))
        if single and not any(self.has(self.turned, p, classes) or self.prereq_not_for(p, classes) for p in single):
            self.err(w, "%d %s needs one of %s turned in first" % (qid, name, single))
        for p in as_list(q.get("preQuestGroup")):
            if not (self.has(self.turned, p, classes) or self.prereq_not_for(p, classes)):
                self.err(w, "%d %s needs %d turned in first" % (qid, name, p))
        for ex in as_list(q.get("exclusiveTo")):
            if self.has(self.accepted, ex, classes):
                self.err(w, "%d %s is exclusive with %d, which is already accepted" % (qid, name, ex))
        need = q.get("requiredLevel") or 1
        guessed = not q.get("requiredLevel") and (q.get("questLevel") or 0) > 5
        if guessed:  # no required level in the DB: assume quest level - 5
            need = q["questLevel"] - 5
        have = max(self.level, self.xp_level())
        if classes:
            have = max(have, min(self.class_level.get(c, 0) for c in classes))
        if need > have:
            if guessed:
                name += " (required level missing in the DB; estimated)"
            self.warn(w, "%d %s requires level %d, route level is ~%d (add a 'level %d' step?)"
                      % (qid, name, need, have, need))

    def check_solo(self, q, qid, classes, w):
        self.solo_checked.add(qid)
        if classes:
            return
        have = max(self.level, self.xp_level())
        solo = solo_level(self.d, q)
        if solo > have:
            self.warn(w, "%d %s is too hard solo before level %d, route level is ~%d" % (qid, q.get("name"), solo, have))

    def prereq_not_for(self, pid, classes):
        p = self.d.quest(pid)
        cm = (p or {}).get("requiredClasses") or 0
        if not cm or not classes:
            return False
        return not any(cm & CLASS_BITS[c] for c in classes)

    def complete_step(self, st, guide, prev):
        qids = [int(s) for s in st["args"].split(",") if s.strip()]
        pts, parts = [], []
        classes = races = None
        titles = []
        for qid in qids:
            q = self.d.quest(qid)
            if not q:
                raise ValueError("quest %d does not exist in the Forever DB" % qid)
            c, r = self.quest_filters(q, st, guide)
            classes, races = c or classes, r or races
            if not self.has(self.accepted, qid, c):
                self.err(st["where"], "complete %d %s before it is accepted" % (qid, q.get("name")))
            self.check_solo(q, qid, c, st["where"])
            p, t = self.objectives(q)
            pts += p
            parts += t
            titles.append(q.get("name"))
            self.routed.add(qid)
            if not c:
                self.add_kill_xp(q)
        out = {"complete": qids if len(qids) > 1 else qids[0]}
        if len(qids) > 1:
            out["titles"] = titles
        else:
            out["title"] = titles[0]
        out["text"] = st["text"] or (". ".join(parts) + "." if parts else None)
        if not out["text"]:
            del out["text"]
        skip = [q for q in qids if q in self.optional]
        if skip:
            out["optional"] = skip
            if any(is_elite(self.d, self.d.quest(q)) for q in skip):
                out["elite"] = True
        self.place(st, out, pts, guide, prev, "objectives of %s" % ", ".join(map(str, qids)))
        res = self.common(st, out, classes, races)
        tips = [t for t in (self.use_item_tip(self.d.quest(q)) for q in qids) if t and t != res.get("text")
                and not st["text"]]  # hand-written step text already says what to do
        if tips:
            res["tip"] = " ".join(([res["tip"]] if res.get("tip") else []) + tips)
        return res

    def finish(self):
        for qid, c in self.accepted:
            if not self.has(self.turned, qid, c):
                q = self.d.quest(qid) or {}
                self.warn("route", "quest %d %s is accepted but never turned in" % (qid, q.get("name")))


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


# on-the-way tip: a run passes ONWAY_MIN_SPAWNS of a later quest's spawns within ONWAY_YARDS of the line
ONWAY_YARDS = 90
ONWAY_MIN_SPAWNS = 4
ONWAY_MIN_LEG = 200

# objective map dots: within AREA_RADIUS map-% of the step, one per AREA_CELL map-% square, at most AREA_MAX
AREA_RADIUS = 14
AREA_CELL = 2.5
AREA_MAX = 10
AREA_TARGETS = 3

# tips for every accept/turn-in at these NPCs (npc ID -> text)
NPC_TIPS = {
    # Stitches walks the Duskwood road and kills the Night Watch (seen on Forever)
    888: "Watcher Dodds can be dead after Stitches comes down the road - wait for him to respawn.",
}


def lua_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return ("%g" % v) if isinstance(v, float) else str(v)
    if isinstance(v, list):
        return "{ " + ", ".join(lua_val(x) for x in v) + " }"
    return lua_str(v)


KEY_ORDER = ["accept", "turnin", "complete", "train", "getfp", "fly", "sethearth", "hearth", "level", "go", "note",
             "title", "titles", "npc", "text", "map", "x", "y", "radius", "class", "race", "notclass", "tip",
             "qlevel", "pre", "preall", "optional", "elite", "via", "items", "targets", "area"]


def write_guide(guide, fname, route_name):
    lines = [
        "-- Questfarer - %s" % guide["name"],
        "-- GENERATED by Tools/build_guides.py from Tools/routes/%s - edit the route, not this file." % route_name,
        "-- Quest, NPC and coordinate data: QuestieDB (Forever flavor, https://github.com/Questie/QuestieDB), used under GPLv3.",
        "-- Questfarer is free software under the GNU GPL v3, see LICENSE.md.",
        "",
        "local _, ns = ...",
        "local QF = ns.QF",
        "",
        "QF:RegisterGuide({",
        "    name = %s," % lua_str(guide["name"]),
        "    faction = %s," % lua_str(guide["faction"]),
    ]
    if guide.get("raceLimited"):
        lines.append("    races = %s," % lua_val(guide["races"]))
    lines += [
        "    minLevel = %d," % guide["minLevel"],
        "    maxLevel = %d," % guide["maxLevel"],
    ]
    if guide["map"]:
        lines.append("    map = %d," % guide["map"])
    if guide.get("next"):
        lines.append("    next = %s," % lua_str(guide["next"]))
    if guide.get("side"):
        lines.append("    side = true,")
        lines.append("    class = %s," % lua_str(guide["side"]))
        lines.append("    ability = %s," % lua_str(guide["ability"]))
    lines.append("    steps = {")
    for s in guide["steps"]:
        if s.get("map") == guide["map"]:
            s = {k: v for k, v in s.items() if k != "map"}
        parts = ["%s = %s" % (k, lua_val(s[k])) for k in KEY_ORDER if k in s]
        lines.append("        { %s }, -- %s" % (", ".join(parts), s["_where"]))
    lines += ["    },", "})", ""]
    with open(os.path.join(OUT, fname + ".lua"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))


def unrouted_report(data, comp, guides):
    by_map = {}
    for g in guides:
        maps = {s.get("map") or g["map"] for s in g["steps"]}
        for m in maps:
            lo, hi, races = by_map.get(m, (99, 0, set()))
            by_map[m] = (min(lo, g["minLevel"]), max(hi, g["maxLevel"]), races | set(g["races"]))
    lines = []
    for m, (lo, hi, races) in sorted(by_map.items(), key=lambda kv: kv[0] or 0):
        rows = []
        for qid, q in data.quests.items():
            qid = int(qid)
            if qid in comp.routed:
                continue
            req = q.get("requiredLevel") or 1
            ql = q.get("questLevel") or req
            if req > hi or (ql > 0 and ql < lo - 2) or ql > hi + 10:
                continue
            rm = q.get("requiredRaces") or 0
            if rm and not any(rm & race_bit(r) for r in races):
                continue
            npcs, objs, _ = data.givers(q.get("startedBy"))
            here = None
            for n in npcs:
                for p in data.points("npc", n):
                    if p[0] == m:
                        here = (data.name("npc", n), p[1], p[2])
                        break
            if not here:
                for o in objs:
                    for p in data.points("object", o):
                        if p[0] == m:
                            here = (data.name("object", o), p[1], p[2])
                            break
            if here:
                cm = q.get("requiredClasses") or 0
                cls = ",".join(c for c, b in CLASS_BITS.items() if cm & b) if cm else ""
                rows.append((req, qid, q.get("name"), ql, cls, here))
        lines.append("== map %s (levels %d-%d): %d unrouted quests" % (m, lo, hi, len(rows)))
        for req, qid, name, ql, cls, here in sorted(rows):
            tag = " [Forever]" if qid >= 90000 else ""
            lines.append("  req %2d  q%-3s %6d  %-40s %-16s from %s (%.1f, %.1f)%s"
                         % (req, ql, qid, name, cls, here[0], here[1], here[2], tag))
    os.makedirs(REPORTS, exist_ok=True)
    with open(os.path.join(REPORTS, "unrouted.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def read_order(name="ORDER"):
    """Route files of a track: ORDER is the main track, ORDER.<Race> the race tracks."""
    return [l.strip() for l in read(os.path.join(ROUTES, name)).splitlines()
            if l.strip() and not l.startswith("#")]


def track_files():
    return sorted(f for f in os.listdir(ROUTES) if f.startswith("ORDER."))


def compile_track(data, order_name):
    comp = Compiler(data)
    guides = []
    for rf in read_order(order_name):
        header, steps = parse_route(os.path.join(ROUTES, rf))
        g = comp.compile_guide(header, steps)
        g["_file"] = header.get("file") or re.sub(r"\W+", "_", g["name"])
        g["_route"] = rf
        guides.append(g)
    comp.finish()
    return comp, guides


def compile_side_guides(data):
    """routes/class side guides, each compiled on its own. Returns (guides, warnings, errors)."""
    folder = os.path.join(ROUTES, "class")
    guides, warnings, errors = [], [], []
    if not os.path.isdir(folder):
        return guides, warnings, errors
    for rf in sorted(f for f in os.listdir(folder) if f.endswith(".route")):
        comp = Compiler(data)
        header, steps = parse_route(os.path.join(folder, rf))
        g = comp.compile_guide(header, steps)
        comp.finish()
        g["_file"] = header["file"]
        g["_route"] = "class/" + rf
        guides.append(g)
        warnings += ["[class] " + w for w in comp.warnings]
        errors += ["[class] " + e for e in comp.errors]
    return guides, warnings, errors


def main():
    check_only = "--check" in sys.argv
    data = Data()
    comp, guides = compile_track(data, "ORDER")
    warnings, errors = list(comp.warnings), list(comp.errors)
    track_guides = []
    for tf in track_files():
        tcomp, tg = compile_track(data, tf)
        warnings += ["[%s] %s" % (tf, w) for w in tcomp.warnings]
        errors += ["[%s] %s" % (tf, e) for e in tcomp.errors]
        comp.routed |= tcomp.routed
        track_guides += tg
    side_guides, side_warn, side_err = compile_side_guides(data)
    warnings += side_warn
    errors += side_err
    for g in guides + track_guides:
        print("%-32s %3d steps   est. level at the end: %.1f" % (g["name"], len(g["steps"]), g["_endLevel"]))
    for g in side_guides:
        print("%-32s %3d steps   class quests" % (g["name"], len(g["steps"])))
    for w in warnings:
        print("WARN  " + w)
    for e in errors:
        print("ERROR " + e)
    comp.errors = errors
    # load order is the order the addon searches: race-limited guides first, so a race finds its own guides first
    guides = [g for g in guides if g["raceLimited"]] + [g for g in track_guides if g["raceLimited"]] \
        + [g for g in track_guides if not g["raceLimited"]] + [g for g in guides if not g["raceLimited"]]
    all_side = side_guides
    unrouted_report(data, comp, guides)
    print("unrouted quest report: Tools/reports/unrouted.txt")
    if comp.errors:
        print("%d errors - guides NOT written" % len(comp.errors))
        sys.exit(1)
    if not check_only:
        guides = guides + all_side
        for g in guides:
            write_guide(g, g["_file"], g["_route"])
        # Guides.xml load list for the TOC, in route order
        xml = ['<Ui xmlns="http://www.blizzard.com/wow/ui/">',
               "    <!-- GENERATED by Tools/build_guides.py from Tools/routes/ORDER and ORDER.<race> -->"]
        xml += ['    <Script file="%s.lua"/>' % g["_file"] for g in guides]
        xml.append("</Ui>")
        with open(os.path.join(OUT, "Guides.xml"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(xml) + "\n")
        print("wrote %d guide files to Questfarer/Guides" % len(guides))


if __name__ == "__main__":
    main()
