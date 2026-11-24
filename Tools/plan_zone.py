"""Draft a route for one zone from the QuestieDB Forever data.

Usage:
    python -I plan_zone.py --map 1436 --levels 10 16 [--races Human] [--name "Human 10-16 Westfall"]
                           [--out routes/drafts/Westfall.route] [--include 92909,...] [--exclude 117,...]

Continues from the end of routes/ORDER. The result is a DRAFT: check the notes at the top, then move it to
routes/ and add it to routes/ORDER.
"""
import argparse
import functools
import json
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
import build_guides as bg  # noqa: E402

LOG_LIMIT = 20
HUB_YARDS = 45        # tasks this close count as "here"
MERGE_YARDS = 120     # objective areas this close become one `complete` line
COLOCATE = True       # --no-colocate turns shared objective areas off (to compare)
JOINT_RADIUS = 8.0    # map %: every objective of both quests has spawns this close to a shared spot
JOINT_MIN = 4         # ...and each quest has at least this many spawns there (or all it has)
JOINT_COVER = 0.25    # ...and spawns there for at least this share of the kills it needs (respawns do the rest)
ELITE_RANKS = {1, 2, 3}
TALK_OBJECTIVE = 5     # third field of a creature objective: talk to this NPC, nothing to kill
WATCH_OBJECTIVE = 3    # third field of a creature objective: wait for this NPC to finish something
NO_KILL_OBJECTIVES = {TALK_OBJECTIVE, WATCH_OBJECTIVE}
SOLO_ELITE_MARGIN = 3  # elites this far below the zone's top level, and not above you, count as soloable

# Time model in seconds. Rough, but the same for every quest, so comparisons are fair.
RUN_SPEED = 7.0       # yards per second on foot
SEC_PER_KILL = 20     # fight + loot + short downtime, quest mob of your level (they are clustered)
GRIND_SEC_PER_KILL = 80  # hand-picked guess, 30 made grinding beat too many quests; calibrate from recorded play
OBJECT_SECONDS = 25   # per object to click / item to pick up from the ground
AREA_SECONDS = 30     # finding the mobs/objects once you are in the area
TALK_SECONDS = 6      # accept or turn in
MAX_GRIND = 0.25      # grind for a blocked quest only up to this part of a level; beyond it, leave the zone
MIN_RATE = 1.0        # keep a quest only if its XP per second (with follow-ups) beats grinding x this
# quests first: grind only when no quest is left, drop only quests below QUEST_FIRST_FLOOR x grinding
QUEST_FIRST = False
QUEST_FIRST_FLOOR = 0.25
if QUEST_FIRST:
    MIN_RATE = QUEST_FIRST_FLOOR


def kill_factor(diff):
    if diff <= 0:
        return max(0.7, 1 + 0.1 * diff)
    return 1 + 0.12 * diff + 0.04 * diff * diff


def load_bounds():
    conv = json.load(open(os.path.join(bg.QF, "conversion.json"), encoding="utf-8"))
    out = {}
    for t in conv["geometry"]["transforms"]:
        b = t["target_bounds"]
        out[t["ui_map_id"]] = (t["map_id"], b["left"], b["right"], b["top"], b["bottom"])
    return out


# Green Hills of Stranglethorn chapters (338-342) need random page drops, the planner can't time them
NEVER_PLAN = {338, 339, 340, 341, 342,
              79229,                # Highway Robbery: Season of Discovery, not confirmed on Forever
              635, 642,             # Pendant of Myzrael: a rare world drop starts the chain
              8260,                 # Arathi Basin reputation
              9419, 9422,           # Scouring the Desert: Silithyst PvP
              7028, 7029, 7041,     # Maraudon quests
              9665,                 # Bolstering Our Defenses: Eastern Plaguelands towers, PvP
              1173,                 # Challenge Overlord Mok'Morokk: group quest
              1486,                 # Deviate Hides: open-world sources are all elite
              8263, 8264, 8265,     # Defiler care packages need Defilers reputation
              7826, 7827, 7831, 7833, 7834, 7835,  # cloth donations: the DB has no count or source
              79624, 79677, 79678,  # Skonk's cooking quests: Season of Discovery, not confirmed on Forever
              96137,                # Ira's Dagger: Lost Stalkers are too rare to wait for
              # escorts with ambushes at about your own level, too hard solo
              219, 863, 898, 1440, 2767, 3367, 5821, 5943, 6641,
              # deep in caves where you get swarmed, and nothing needs them
              6421, 6481, 7701, 7722, 7727}
# Season of Discovery quests, not confirmed on Forever (--include overrides); Forever's own start at 86000
SEASON_IDS = range(78000, 86000)
# quests with only text objectives (no place or count) get a flat time, so they aren't free XP
TEXT_OBJECTIVE_SECONDS = 300
ESCORT_SECONDS = 300
ESCORT = re.compile(r"\b(escort|protect|go with)\b", re.I)
TEXT_TASK = re.compile(r"\b(slay|kill|destroy|escort|protect|go with|collect|gather|use|place|throw|solve|defeat|"
                       r"burn|free|rescue|obtain|recover|retrieve|hunt|capture|plant|light|cleanse|absorb)\b", re.I)
# a no-objective quest this far above you sends you somewhere too dangerous (deliveries are fine)
TEXT_LEVEL_GAP = 8
DELIVERY = re.compile(r"^\s*(deliver|return|bring|take|speak|talk|report|go to|find someone)\b", re.I)

# text-only tasks turned in at their giver and reputation goals can't be routed
REPUTATION_GOAL = re.compile(r"\braise your reputation\b|\breputation with\b.*\bto (neutral|friendly|honored|revered|exalted)\b", re.I)
TALK = re.compile(r"\b(speak|talk) (with|to)\b", re.I)


def self_task(q, otext):
    givers = set(bg.as_list(bg.slots(q.get("startedBy")).get(1)))
    return bool(givers) and givers == set(bg.as_list(bg.slots(q.get("finishedBy")).get(1))) \
        and not DELIVERY.search(otext) and not TALK.search(otext)


# solo route: no quests inside dungeons
DUNGEON_TEXT = re.compile(r"Blackrock Depths|Blackrock Spire|Maraudon|Scholomance|Stratholme|Dire Maul|Zul'?Farrak|Uldaman"
                          r"|Sunken Temple|Temple of Atal|Blackfathom|Gnomeregan|Wailing Caverns|Deadmines|Shadowfang"
                          r"|Stockade|Scarlet Monastery|Razorfen|Molten Core|Naxxramas|Ragefire", re.I)
DUNGEON_TEXT_OK = {721, 722}  # Hammertoe stands outside Uldaman
# capital city factions: every race is at least neutral with them
HOME_FACTIONS = {72, 47, 69, 54, 76, 81, 68, 530, 911, 930}


def needs_reputation(q):
    rep = q.get("requiredMinRep")
    return bool(rep) and rep[0] not in HOME_FACTIONS and (rep[1] or 0) > 0


def inside_dungeon(d, q, otext):
    if otext and DUNGEON_TEXT.search(otext):
        return True
    mobs = [c[0] if isinstance(c, list) else c for c in bg.as_list(bg.slots(q.get("objectives")).get(1))]
    return any(not d.points("npc", m) for m in mobs)


BOUNDS = load_bounds()
# Forever maps missing from conversion.json. Riverglades and Zephras Isle: estimated from flight master / airship
# dock positions (world positions from the OpenMap addon), 3:2 map assumed. Hyjal, Shen'dralas: measured, "/fg bounds".
ESTIMATED_BOUNDS = {2548: (0, -1888.0, -6747.0, -6463.1, -9702.4),  # Riverglades
                    2521: (2991, 4322.0, -1381.0, 5020.7, 1218.7),  # Zephras Isle
                    2482: (1, -922.9, -4395.8, 6304.2, 3989.6),     # Mount Hyjal (measured)
                    2652: (1, 2025.0, -25.0, -1900.0, -3266.7)}     # Shen'dralas (measured)
for _m, _b in ESTIMATED_BOUNDS.items():
    BOUNDS.setdefault(_m, _b)


@functools.lru_cache(maxsize=None)
def world(p):
    """(uiMap, x, y) -> (continent, worldX, worldY) in yards."""
    b = BOUNDS.get(p[0])
    if not b:
        return None
    cont, left, right, top, bottom = b
    return cont, top - (top - bottom) * p[2] / 100.0, left - (left - right) * p[1] / 100.0


def yards(a, b):
    wa, wb = world(tuple(a[:3])), world(tuple(b[:3]))
    if not wa or not wb or wa[0] != wb[0]:
        return 1e9
    return math.hypot(wa[1] - wb[1], wa[2] - wb[2])


def dynamic_fix_ids():
    ids = set()
    base = os.path.join(ROOT, "questiedb-forever-release", "extracted", "corrections")
    for f in ("foreverQuestFixes.lua", "classicQuestFixes.lua"):
        p = os.path.join(base, f)
        if os.path.exists(p):
            src = open(p, encoding="utf-8").read()
            m = re.search(r"LoadDynamic\(\)(.*)", src, re.S)
            if m:
                ids |= {int(x) for x in re.findall(r"^\s*\[(\d+)\]\s*=\s*\{", m.group(1), re.M)}
    return ids


class Planner:
    def __init__(self, data, comp, zone_map, lo, hi, races, faction, include=(), exclude=(), box=None):
        self.d, self.c = data, comp
        self._csecs = {}
        self.box = box  # (x1, y1, x2, y2): only plan inside this part of the map
        self.maps = {zone_map}  # plus neighbouring maps that belong to this area
        self.end = None  # where you leave the zone (the run there counts)
        self.next_rate = 0  # XP/h questing in the next zone ...
        self.next_level = 99  # ... from this level on
        self.next_ref = None  # level the next-zone rate was measured at (it scales with mob XP)
        self.keep = set()  # never dropped as too slow
        self.map, self.lo, self.hi = zone_map, lo, hi
        self.races, self.faction = races, faction
        self.include, self.exclude = set(include), set(exclude) | NEVER_PLAN
        self.exclude |= {int(k) for k in data.quests if int(k) in SEASON_IDS} - self.include
        self.notes = []
        self.dyn = dynamic_fix_ids()
        # quests that other quests need (a 0-XP breadcrumb can still unlock a chain)
        self.needed = set()
        for q in data.quests.values():
            self.needed.update(bg.as_list(q.get("preQuestSingle")) + bg.as_list(q.get("preQuestGroup")))

    def giver_points(self, q, field):
        npcs, objs, items = self.d.givers(q.get(field))
        pts = []
        for n in npcs:
            rec = self.d.npcs.get(str(n)) or {}
            fr = rec.get("friendlyToFaction")
            if field == "startedBy" and fr and self.faction[0] not in fr:
                continue  # hostile giver
            pts += [(p, self.d.name("npc", n)) for p in self.d.points("npc", n)]
        for o in objs:
            pts += [(p, self.d.name("object", o)) for p in self.d.points("object", o)]
        return pts, items

    def group_elite(self, nid):
        n =self.d.npcs.get(str(nid)) or {}
        if n.get("rank") not in ELITE_RANKS:
            return False
        level = n.get("maxLevel") or n.get("minLevel") or 99
        # soloable only if well below the zone's top and not above you (Forever has level-3 elites in Northshire)
        return level > min(self.hi - SOLO_ELITE_MARGIN, self.c.est_level())

    def objective_info(self, q):
        """(points on any map, elite?, has objectives?) for a quest."""
        pts, _ = self.c.objectives(q)
        elite = False
        ob = bg.slots(q.get("objectives"))
        mobs = [c[0] if isinstance(c, list) else c for c in bg.as_list(ob.get(1))
                if not (isinstance(c, list) and len(c) > 2 and c[2] in NO_KILL_OBJECTIVES)]
        for i in bg.as_list(ob.get(3)):
            iid = i[0] if isinstance(i, list) else i
            drops = bg.as_list((self.d.items.get(str(iid)) or {}).get("npcDrops"))
            if drops and all(self.group_elite(n) for n in drops):
                elite = True
        for m in mobs:
            if self.group_elite(m):
                elite = True
        has_obj = bool(ob) or bool(q.get("triggerEnd"))
        return pts, elite, has_obj

    def nearest(self, pts, frm):
        return min(pts, key=lambda p: yards(p[0] if isinstance(p[0], tuple) else p, frm))

    def inbox(self, p):
        if p[0] != self.map:
            return p[0] in self.maps
        if not self.box:
            return True
        x1, y1, x2, y2 = self.box
        return x1 <= p[1] <= x2 and y1 <= p[2] <= y2

    def candidates(self):
        done = {q for q, _ in self.c.turned}
        taken = {q for q, _ in self.c.accepted}
        cands, by_name = {}, {}
        for sid, q in self.d.quests.items():
            qid = int(sid)
            # quests earlier routes left in the log get finished here if they belong here
            in_log = qid in taken and qid not in done
            if (qid in self.c.routed and not in_log) or qid in done or qid in self.exclude:
                continue
            gpts, items = self.giver_points(q, "startedBy")
            here = [g for g in gpts if self.inbox(g[0])]
            item_start = False
            item_pts = []
            if not here and items and not in_log:
                item_pts = [p for p in self.c.item_points(items[0]) if self.inbox(p)]
                item_start = bool(item_pts)
            if not here and not item_start and not in_log:
                continue
            name = q.get("name") or "?"
            forced = qid in self.include

            def skip(why):
                if forced:
                    return False
                if why and not in_log:
                    self.notes.append("skip %6d %-36s %s" % (qid, name[:36], why))
                return True

            rm = q.get("requiredRaces") or 0
            if rm and not any(rm & bg.race_bit(r, self.faction) for r in self.races):
                continue
            ql0 = q.get("questLevel") or 0
            # no required level in the DB: assume quest level - 5
            req = q.get("requiredLevel") or (max(1, ql0 - 5) if ql0 > 0 else 1)
            ql = ql0 or req
            if in_log:
                pass
            elif req > self.hi or ql > self.hi + 4 or (ql > 0 and ql <= bg.gray_level(self.lo)):
                continue
            if (q.get("specialFlags") or 0) & 1:
                continue  # repeatable
            if q.get("requiredSkill"):
                continue  # profession quest
            if q.get("requiredClasses"):
                if skip("class quest (add by hand with the right class filter)"):
                    continue
            if qid in self.dyn and skip("has faction-specific QuestieDB corrections"):
                continue
            fpts, _ = self.giver_points(q, "finishedBy")
            if not fpts:
                if skip("no turn-in location in the DB"):
                    continue
            elif not any(self.inbox(p[0]) for p in fpts):
                maps = sorted({p[0][0] for p in fpts})
                if skip("turned in outside the zone/area (map %s) - schedule a trip by hand" % maps):
                    continue
            opts, elite, has_obj = self.objective_info(q)
            if elite and skip("elite/boss objective - group quest"):
                continue
            if has_obj and not any(self.inbox(p) for p in opts):
                if skip("objectives are not in this zone/area (dungeon or elsewhere)"):
                    continue
            if not has_obj and qid not in self.include \
                    and TEXT_TASK.search(" ".join(q.get("objectivesText") or [])):
                if skip("task only described in text, no place in the DB - add by hand if wanted"):
                    continue
            otext = " ".join(q.get("objectivesText") or [])
            if not in_log and qid not in DUNGEON_TEXT_OK and inside_dungeon(self.d, q, otext):
                if skip("objective is inside a dungeon"):
                    continue
            if not in_log and needs_reputation(q):
                if skip("needs reputation a leveling character doesn't have"):
                    continue
            if not has_obj and not in_log and qid not in self.include and otext:
                if REPUTATION_GOAL.search(otext):
                    if skip("reputation goal - other quests decide when it's done"):
                        continue
                elif self_task(q, otext):
                    if skip("task only described in text, turned in where it started - no place in the DB"):
                        continue
            if not has_obj and not in_log and qid not in self.include and ql0 - self.c.est_level() >= TEXT_LEVEL_GAP \
                    and not DELIVERY.search(otext):
                if skip("level %d task with no objectives in the DB - too far above you" % ql0):
                    continue
            if not self.d.xp.get(qid):
                # no XP value: mostly content leaked from other Classic versions, keep only if needed
                if qid not in self.needed:
                    if skip("no XP value in the DB and nothing needs it (probably not in Forever)"):
                        continue
                else:
                    self.notes.append("note %6d %-36s no XP value in the DB (kept: other quests need it)"
                                      % (qid, name[:36]))
            cands[qid] = {
                "q": q, "id": qid, "name": name, "req": req if in_log else max(req, bg.solo_level(self.d, q)), "ql": ql,
                "in_log": in_log,
                "giver": [g for g in gpts if self.inbox(g[0])] or None,
                "item_start": item_start,
                "item_pts": item_pts,
                "finish": [p for p in fpts if self.inbox(p[0])],
                "obj": [p for p in opts if self.inbox(p)] if has_obj else [],
            }
            by_name.setdefault(name, []).append(qid)
        # same-name variants that exclude each other: keep the first
        for name, ids in by_name.items():
            if len(ids) < 2:
                continue
            for qid in ids[1:]:
                ex = set(bg.as_list(cands[qid]["q"].get("exclusiveTo")))
                if ex & set(ids):
                    self.notes.append("skip %6d %-36s variant of %d (exclusive)" % (qid, name[:36], ids[0]))
                    del cands[qid]
        return cands

    def complete_seconds(self, q, level):
        key = id(q)  # quest records live as long as the Data object
        if key not in self._csecs:
            self._csecs[key] = (self._other_seconds(q), self.d.kill_estimate(q))
        secs, kills = self._csecs[key]
        level = int(level)
        for mlevel, n in kills:
            secs += n * SEC_PER_KILL * kill_factor(mlevel - level)
        return secs

    def _other_seconds(self, q):
        secs = AREA_SECONDS
        ob = bg.slots(q.get("objectives"))
        counts = [int(n) for t in bg.as_list(q.get("objectivesText"))
                  for n in re.findall(r"(\d+)", str(t))]
        n_obj = len(bg.as_list(ob.get(1)))
        for k, o in enumerate(bg.as_list(ob.get(2))):
            n = counts[n_obj + k] if n_obj + k < len(counts) else 1
            secs += min(n, 20) * OBJECT_SECONDS
        for i in bg.as_list(ob.get(3)):
            iid = i[0] if isinstance(i, list) else i
            it = self.d.items.get(str(iid)) or {}
            if not bg.as_list(it.get("npcDrops")) and bg.as_list(it.get("objectDrops")):
                secs += 6 * OBJECT_SECONDS  # gathered from objects on the ground
        return secs

    def grind_rate(self, level):
        lvl = max(1, int(level))
        return max(bg.mob_xp(lvl, lvl + d) / (GRIND_SEC_PER_KILL * kill_factor(d)) for d in range(-3, 2))

    def spots(self, points, maxn=3):
        """Up to maxn cluster centres (map, x, y), densest first."""
        pts = [p for p in points if p[0] in self.maps] or list(points)
        if not pts:
            return []
        tagged = len(pts[0]) > 3
        out, rest, first = [], list(pts), None
        while rest and len(out) < maxn:
            bp = bg.best_point(rest, self.map, None)
            near = [q for q in rest if math.hypot(q[1] - bp[1], q[2] - bp[2]) <= 6]
            cover = len({q[3] for q in near}) if tagged else 0
            if first:
                if cover < first[1] or bp[3] < max(3, first[0] * 0.3):
                    break
            else:
                first = (bp[3], cover)
            out.append((bp[0], bp[1], bp[2]))
            rest = [q for q in rest if math.hypot(q[1] - bp[1], q[2] - bp[2]) > 8]
        return out

    def prepare(self, cands):
        for c in cands.values():
            c["obj_spots"] = self.spots(c["obj"]) if c["obj"] else []
            c["item_spots"] = self.spots(c["item_pts"]) if c["item_start"] else []
            text = " ".join(c["q"].get("objectivesText") or [])
            c["t_secs"] = TEXT_OBJECTIVE_SECONDS if not c["obj"] and TEXT_TASK.search(text) else 0
            if ESCORT.search(text):  # escorts walk at NPC pace and get ambushed
                c["t_secs"] = max(c["t_secs"], ESCORT_SECONDS)

    def prereqs_ok(self, q, have):
        single = bg.as_list(q.get("preQuestSingle"))
        group = bg.as_list(q.get("preQuestGroup"))
        if single and not any(p in have for p in single):
            return False
        return not (group and not all(p in have for p in group))

    def joint_spot(self, cands, a, b):
        """A spot (map, x, y) where both quests' objectives can be done in one go, or None."""
        key = (min(a, b), max(a, b))
        if key not in self._shared:
            def tagged(q):
                pts = [pt for pt in cands[q]["obj"] if pt[0] in self.maps]
                return [(pt[0], pt[1], pt[2], (q, pt[3] if len(pt) > 3 else None)) for pt in pts]
            pa, pb = tagged(a), tagged(b)
            hit, best = None, 0
            need = {pt[3] for pt in pa + pb}
            need_a = sum(n for _, n in self.d.kill_estimate(cands[a]["q"])) or len(pa) or 1
            need_b = sum(n for _, n in self.d.kill_estimate(cands[b]["q"])) or len(pb) or 1
            # try every spawn as the centre; keep the one where the thinner of the two quests is best covered
            for c in pa + pb:
                na = [pt for pt in pa if pt[0] == c[0] and math.hypot(pt[1] - c[1], pt[2] - c[2]) <= JOINT_RADIUS]
                nb = [pt for pt in pb if pt[0] == c[0] and math.hypot(pt[1] - c[1], pt[2] - c[2]) <= JOINT_RADIUS]
                if len(na) < min(JOINT_MIN, len(pa)) or len(nb) < min(JOINT_MIN, len(pb)):
                    continue
                if {pt[3] for pt in na + nb} < need:
                    continue
                # spawns there per kill the quest needs
                score = min(min(1.0, len(na) / need_a), min(1.0, len(nb) / need_b))
                if score >= JOINT_COVER and score > best:
                    allp = na + nb
                    best = score
                    hit = (c[0], round(sum(pt[1] for pt in allp) / len(allp), 1),
                           round(sum(pt[2] for pt in allp) / len(allp), 1))
            self._shared[key] = hit
        return self._shared[key]

    def simulate(self, cands, start, banned=frozenset(), colocate=False):
        """Greedy playthrough: (steps, xp gained, seconds, quests turned in); compiler state is restored."""
        if not hasattr(self, "_shared"):
            self._shared = {}
        xp0, nturned = self.c.xp_total, len(self.c.turned)
        done = {q for q, _ in self.c.turned}
        accepted = {qid for qid, c in cands.items() if c["in_log"] and qid not in banned}
        log = {q for q, _ in self.c.accepted} - done - accepted
        pos = start
        completed, turned = set(), set()
        out, secs = [], 0.0
        near = lambda pts: min(pts, key=lambda p: yards(p, pos))  # noqa: E731
        try:
            for _ in range(3000):
                level = self.c.est_level()
                tasks = []
                for qid, c in cands.items():
                    if qid in banned or qid in turned:
                        continue
                    q = c["q"]
                    if qid not in accepted:
                        if len(log) + len(accepted - turned) >= LOG_LIMIT or c["req"] > int(level):
                            continue
                        if not self.prereqs_ok(q, done | turned):
                            continue
                        if set(bg.as_list(q.get("exclusiveTo"))) & (accepted | done):
                            continue
                        if c["item_start"]:
                            tasks.append(("accept", qid, near(c["item_spots"]), None))
                            continue
                        g = min(c["giver"], key=lambda gp: yards(gp[0], pos))
                        tasks.append(("accept", qid, g[0], g[1]))
                    elif c["obj"] and qid not in completed:
                        joint = []
                        if colocate:
                            joint = [self.joint_spot(cands, qid, o) for o in accepted - completed - turned
                                     if o != qid and o not in banned and cands[o]["obj"]]
                            joint = [j for j in joint if j]
                        if joint:
                            # an open objective shares an area with this one: do it there
                            tasks.append(("complete", qid, near(joint), None))
                        else:
                            tasks.append(("complete", qid, near(c["obj_spots"]), None))
                    else:
                        f = min(c["finish"], key=lambda fp: yards(fp[0], pos))
                        tasks.append(("turnin", qid, f[0], f[1]))
                if not tasks:
                    # only quests that the level alone holds back (not a prerequisite done elsewhere)
                    blocked = [c for qid, c in cands.items()
                               if qid not in banned and qid not in accepted and qid not in turned
                               and self.prereqs_ok(c["q"], done | turned)
                               and not set(bg.as_list(c["q"].get("exclusiveTo"))) & (accepted | done)]
                    # never past the level cap: XP stops at 60, so a grind to 61+ would never end
                    need = [c["req"] for c in blocked if int(level) < c["req"] <= 60]
                    if need:
                        target = min(need)
                        gain = max(0, sum(bg.XP_TO_LEVEL[1:target]) - self.c.xp_total)
                        if gain > MAX_GRIND * bg.XP_TO_LEVEL[min(int(level), 59)]:
                            break  # the rest is for later: questing elsewhere beats grinding here
                        secs += gain / self.grind_rate(level)
                        self.c.xp_total += gain
                        out.append(("level", target, pos, None))
                        continue
                    break
                if colocate:
                    # put an objective off while a quest you can take right now shares its area
                    new = {t[1] for t in tasks if t[0] == "accept" and cands[t[1]]["obj"]}
                    later = [t for t in tasks if t[0] == "complete"
                             and any(self.joint_spot(cands, t[1], b) for b in new)]
                    if later and len(later) < len(tasks):
                        tasks = [t for t in tasks if t not in later]
                here = [t for t in tasks if t[0] != "complete" and yards(t[2], pos) <= HUB_YARDS]
                if here:
                    here.sort(key=lambda t: (t[0] != "turnin", yards(t[2], pos)))
                    t = here[0]
                else:
                    t = min(tasks, key=lambda t: yards(t[2], pos) * (1.0 if t[0] != "accept" else 0.8))
                kind, qid, p, who = t
                c = cands[qid]
                secs += yards(p, pos) / RUN_SPEED
                if kind == "accept":
                    accepted.add(qid)
                    secs += 0 if c["item_start"] else TALK_SECONDS
                elif kind == "complete":
                    completed.add(qid)
                    self.c.add_kill_xp(c["q"])
                    secs += self.complete_seconds(c["q"], self.c.est_level())
                else:
                    turned.add(qid)
                    accepted.add(qid)
                    self.c.turned.append((qid, None))
                    self.c.xp_total += self.c.quest_xp(qid)
                    secs += TALK_SECONDS + c["t_secs"]
                pos = p
                out.append((kind, qid, p, who, round(self.c.est_level(), 1)))
                if colocate and kind == "complete":
                    # the other open objectives here are done in the same go
                    for o in sorted(accepted - completed - turned):
                        if o in banned or not cands[o]["obj"]:
                            continue
                        js = self.joint_spot(cands, qid, o)
                        if js and yards(js, p) <= MERGE_YARDS:
                            completed.add(o)
                            self.c.add_kill_xp(cands[o]["q"])
                            secs += self.complete_seconds(cands[o]["q"], self.c.est_level())
                            out.append(("complete", o, p, None, round(self.c.est_level(), 1)))
            if self.end:
                secs += yards(pos, self.end) / RUN_SPEED
            return out, self.c.xp_total - xp0, secs, turned
        finally:
            self.c.xp_total = xp0
            del self.c.turned[nturned:]

    def evaluate(self, steps, cands, start, removed=frozenset()):
        """Replay a fixed step order without `removed`: (xp gained, seconds, quests that dropped out)."""
        done = {q for q, _ in self.c.turned}
        out = set(removed)
        changed = True
        while changed:  # dependents of removed quests drop out too
            changed = False
            have = done | {s[1] for s in steps if s[0] == "turnin" and s[1] not in out}
            for s in steps:
                if s[0] == "accept" and s[1] not in out and not cands[s[1]]["in_log"] \
                        and not self.prereqs_ok(cands[s[1]]["q"], have):
                    out.add(s[1])
                    changed = True
        xp0, nturned = self.c.xp_total, len(self.c.turned)
        pos, secs = start, 0.0
        try:
            for s in steps:
                if s[0] == "level" or s[1] in out:
                    continue
                kind, qid, p = s[0], s[1], s[2]
                c = cands[qid]
                if kind == "accept" and c["req"] > int(self.c.est_level()):
                    gain = max(0, sum(bg.XP_TO_LEVEL[1:c["req"]]) - self.c.xp_total)
                    secs += gain / self.grind_rate(self.c.est_level())
                    self.c.xp_total += gain
                secs += yards(p, pos) / RUN_SPEED
                if kind == "accept":
                    secs += 0 if c["item_start"] else TALK_SECONDS
                elif kind == "complete":
                    self.c.add_kill_xp(c["q"])
                    secs += self.complete_seconds(c["q"], self.c.est_level())
                else:
                    self.c.turned.append((qid, None))
                    self.c.xp_total += self.c.quest_xp(qid)
                    secs += TALK_SECONDS + c["t_secs"]
                pos = p
            if self.end:
                secs += yards(pos, self.end) / RUN_SPEED
            return self.c.xp_total - xp0, secs, out
        finally:
            self.c.xp_total = xp0
            del self.c.turned[nturned:]

    def best_simulation(self, cands, start, banned=frozenset()):
        plain = self.simulate(cands, start, banned)
        if not COLOCATE:
            self.colocated = False
            return plain
        joint = self.simulate(cands, start, banned, colocate=True)
        rate = lambda r: r[1] / r[2] if r[2] > 0 else 0  # noqa: E731
        self.colocated = rate(joint) > rate(plain) * 1.001
        return joint if self.colocated else plain

    def threshold(self, level, min_rate):
        rate = min_rate * self.grind_rate(level)
        if self.next_rate and level >= self.next_level:
            ref = self.next_ref or self.next_level
            scale = bg.mob_xp(int(level), int(level)) / bg.mob_xp(int(ref), int(ref))
            rate = max(rate, self.next_rate / 3600.0 * scale)
        return rate

    def plan(self, start, min_rate=MIN_RATE):
        cands = self.candidates()
        self.prepare(cands)
        self.dropped = []
        steps = self.best_simulation(cands, start)[0]
        removed = set()
        while True:
            xp, secs, gone = self.evaluate(steps, cands, start, removed)
            level_at = {}
            for s in steps:
                if s[0] == "turnin":
                    level_at[s[1]] = s[4]
            worst = None
            for qid in sorted({s[1] for s in steps if s[0] == "turnin"} - gone - self.keep):
                xp2, secs2, gone2 = self.evaluate(steps, cands, start, removed | {qid})
                dxp, dsec = xp - xp2, secs - secs2
                if dsec <= 0:
                    continue
                rate = dxp / dsec
                margin = rate / self.threshold(level_at.get(qid, self.c.est_level()), min_rate)
                if worst is None or margin < worst[0]:
                    worst = (margin, qid, rate, dxp, dsec, gone2 - gone - {qid})
            if not worst or worst[0] >= 1.0:
                break
            margin, qid, rate, dxp, dsec, with_it = worst
            removed.add(qid)
            thr = self.threshold(level_at.get(qid, self.c.est_level()), min_rate)
            self.dropped.append((qid, cands[qid]["name"], rate * 3600, thr * 3600, dxp, dsec, with_it))
        banned = self.evaluate(steps, cands, start, removed)[2]
        steps, xp, secs, turned = self.best_simulation(cands, start, banned)
        for qid, name, rate, thr, dxp, dsec, with_it in self.dropped:
            extra = (" (with %s)" % ", ".join(map(str, sorted(with_it)))) if with_it else ""
            self.notes.append("drop %6d %-36s %5.0f XP/h vs %5.0f needed: +%d XP for %.1f min%s"
                              % (qid, name[:36], rate, thr, dxp, dsec / 60, extra))
        for qid, c in cands.items():
            if qid not in turned and qid not in banned:
                self.notes.append("left %6d %-36s never became available (prerequisite elsewhere, or log full)"
                                  % (qid, c["name"][:36]))
        # leave the compiler at the end-of-zone state
        self.c.xp_total += xp
        self.c.turned += [(q, None) for q in sorted(turned)]
        self.summary = (xp, secs)
        return steps, cands


def render(plan, cands, header, notes, zone_map):
    lines = ["# DRAFT generated by plan_zone.py - review before use.", "#"]
    lines += ["# " + n for n in notes]
    lines += ["#"] + header + [""]
    i = 0
    while i < len(plan):
        step = plan[i]
        if step[0] == "level":
            _, target, p, _ = step
            lines.append("level %d @%.1f,%.1f | grind to level %d here" % (target, p[1], p[2], target))
            i += 1
            continue
        kind, qid, p, who, lvl = step
        ids = [qid]
        j = i + 1
        # merge neighbouring objective areas into one `complete` line
        while kind == "complete" and j < len(plan) and plan[j][0] == "complete" and yards(plan[j][2], p) <= MERGE_YARDS:
            ids.append(plan[j][1])
            lvl = plan[j][4]
            j += 1
        names = ", ".join(cands[x]["name"] for x in ids)
        mapnote = "" if p[0] == zone_map else " (map %d)" % p[0]
        args = ", ".join(map(str, ids))
        if kind == "complete" or (kind == "accept" and cands[qid]["item_start"]):
            # the spot the planner timed, so the guide uses the same one
            args += " @%.1f,%.1f" % (p[1], p[2]) + ("" if p[0] == zone_map else ",%d" % p[0])
        lines.append("%-8s %-30s # %s%s  ~lvl %.1f" % (kind, args, names, mapnote, lvl))
        i = j
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", type=int, required=True)
    ap.add_argument("--levels", type=int, nargs=2, required=True)
    ap.add_argument("--races", default="Human")
    ap.add_argument("--faction", default="Alliance")
    ap.add_argument("--name")
    ap.add_argument("--file")
    ap.add_argument("--next")
    ap.add_argument("--out")
    ap.add_argument("--include", default="")
    ap.add_argument("--exclude", default="")
    ap.add_argument("--keep", default="", help="quest IDs never to drop as too slow (e.g. a start area's first "
                    "quests, which the time model would swap for grinding and then strand the chains they open)")
    ap.add_argument("--upto", help="only replay routes/ORDER up to and including this route file")
    ap.add_argument("--order", default="ORDER", help="track to replay: ORDER (main) or ORDER.<Race>")
    ap.add_argument("--fresh", action="store_true", help="plan from level 1 without replaying routes/ORDER")
    ap.add_argument("--start", help="x,y on --map to start from")
    ap.add_argument("--level", type=float, help="start at least at this level (a hand-written grind step before)")
    ap.add_argument("--box", help="x1,y1,x2,y2: only quests inside this part of the map")
    ap.add_argument("--also-maps", default="", help="neighbouring uiMap IDs that belong to this area")
    ap.add_argument("--no-colocate", action="store_true", help="don't do objectives that share an area together")
    ap.add_argument("--end", help="x,y[,map]: where you leave the zone (the run there is counted)")
    ap.add_argument("--next-rate", type=float, default=0,
                    help="XP/h questing in the next zone; from --next-level on, quests must beat it")
    ap.add_argument("--next-level", type=float, default=99)
    ap.add_argument("--next-ref", type=float, help="level --next-rate was measured at (default --next-level)")
    ap.add_argument("--min-rate", type=float, default=MIN_RATE,
                    help="drop quests slower than grinding x this (0 keeps everything)")
    a = ap.parse_args()
    global COLOCATE
    COLOCATE = not a.no_colocate

    data = bg.Data()
    comp = bg.Compiler(data)
    order = bg.read_order(a.order)
    if a.upto:
        order = order[:order.index(a.upto) + 1]
    if a.fresh:
        order = []
    start = None
    for rf in order:
        h, st = bg.parse_route(os.path.join(bg.ROUTES, rf))
        g = comp.compile_guide(h, st)
        for s in g["steps"]:
            if "x" in s:
                start = (s.get("map") or g["map"], s["x"], s["y"])
    if a.level:
        comp.xp_total = max(comp.xp_total, sum(bg.XP_TO_LEVEL[1:int(a.level)]))
    if start is None or start[0] != a.map and yards(start, (a.map, 50, 50)) > 1e8:
        start = (a.map, 50.0, 50.0)
    flts = lambda s: [float(x) for x in s.split(",")]  # noqa: E731
    if a.start:
        start = (a.map,) + tuple(flts(a.start))
    races = [r.strip() for r in a.races.split(",")]
    print("start: level %.1f at map %s (%.1f, %.1f), %d quests done" % (
        comp.est_level(), start[0], start[1], start[2], len(comp.turned)))

    ints = lambda s: [int(x) for x in s.split(",") if x.strip()]  # noqa: E731
    pl = Planner(data, comp, a.map, a.levels[0], a.levels[1], races, a.faction, ints(a.include), ints(a.exclude),
                 box=flts(a.box) if a.box else None)
    pl.maps |= set(ints(a.also_maps))
    pl.keep = set(ints(a.keep))
    if a.end:
        e = flts(a.end)
        pl.end = (int(e[2]) if len(e) > 2 else a.map, e[0], e[1])
    pl.next_rate, pl.next_level, pl.next_ref = a.next_rate, a.next_level, a.next_ref
    plan, cands = pl.plan(start, a.min_rate)
    name = a.name or "%s %d-%d map %d" % (races[0], a.levels[0], a.levels[1], a.map)
    header = ["guide " + name, "file " + (a.file or re.sub(r"\W+", "_", name)), "faction " + a.faction,
              "races " + ",".join(races), "levels %d %d" % tuple(a.levels), "map %d" % a.map]
    if a.next:
        header.append("next " + a.next)
    text = render(plan, cands, header, pl.notes, a.map)
    if a.out:
        os.makedirs(os.path.dirname(os.path.join(ROOT, a.out)), exist_ok=True)
        with open(os.path.join(ROOT, a.out), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        print("wrote", a.out)
    print(text)
    xp, secs = pl.summary
    print("end: level %.1f  (+%d XP in ~%.0f min = %.0f XP/h, %d quests dropped as too slow)" % (
        comp.est_level(), xp, secs / 60, xp / max(secs, 1) * 3600, len(pl.dropped)))


if __name__ == "__main__":
    main()
