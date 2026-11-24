"""Build the route chain after the start zones automatically, zone by zone, for XP per hour.

Tracks (--track): main, NightElf, Dwarf, SkyborneA (Alliance); Horde, Tauren, Undead, SkyborneH (Horde).

Usage:
    python -I auto_chain.py [--track main] [--target 37]
Then: python -I build_guides.py
"""
import argparse
import collections
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
import build_guides as bg  # noqa: E402
import compare_zones as cz  # noqa: E402
import plan_zone as pz  # noqa: E402

ROUTES = os.path.join(ROOT, "routes")
HAND = os.path.join(ROUTES, "hand")
# one main track per faction, plus one per race start area that `joins` the shared chain at --target
TRACKS = {
    "main": {"order": "ORDER", "fixed": ["Human_Northshire.route", "Human_Elwynn.route"], "races": ["Human"],
             "prefix": "Alliance_", "title": "Alliance", "first": 1436,  # Westfall: hand splice for the Stormwind trip
             "race_header": None, "faction": "Alliance", "joins": None},
    "NightElf": {"order": "ORDER.NightElf", "fixed": ["NightElf_Shadowglen.route", "NightElf_Teldrassil.route"],
                 "races": ["NightElf"], "prefix": "NightElf_", "title": "Night Elf", "first": 1439,  # Darkshore (user choice)
                 "race_header": "NightElf", "faction": "Alliance", "joins": "ORDER"},
    "Dwarf": {"order": "ORDER.Dwarf", "fixed": ["Dwarf_Coldridge.route", "Dwarf_DunMorogh.route"],
              "races": ["Dwarf", "Gnome"], "prefix": "Dwarf_", "title": "Dwarf & Gnome", "first": None,
              "race_header": "Dwarf,Gnome", "faction": "Alliance", "joins": "ORDER"},
    "SkyborneA": {"order": "ORDER.SkyborneA", "fixed": ["SkyborneA_ZephrasIsle.route"],
                  "races": ["Skyborne"], "prefix": "SkyborneA_", "title": "Skyborne (Alliance)", "first": None,
                  "race_header": "Skyborne", "faction": "Alliance", "joins": "ORDER"},
    # Horde
    "Horde": {"order": "ORDER.Horde", "fixed": ["OrcTroll_ValleyOfTrials.route", "OrcTroll_Durotar.route"],
              "races": ["Orc", "Troll"], "prefix": "Horde_", "title": "Horde", "first": None,
              "race_header": None, "faction": "Horde", "joins": None},
    "Tauren": {"order": "ORDER.Tauren", "fixed": ["Tauren_CampNarache.route", "Tauren_Mulgore.route"],
               "races": ["Tauren"], "prefix": "Tauren_", "title": "Tauren", "first": None,
               "race_header": "Tauren", "faction": "Horde", "joins": "ORDER.Horde"},
    "Undead": {"order": "ORDER.Undead", "fixed": ["Undead_Deathknell.route", "Undead_Tirisfal.route"],
               "races": ["Scourge"], "prefix": "Undead_", "title": "Undead", "first": None,
               "race_header": "Scourge", "faction": "Horde", "joins": "ORDER.Horde"},
    "SkyborneH": {"order": "ORDER.SkyborneH", "fixed": ["SkyborneH_ZephrasIsle.route"],
                  "races": ["Skyborne"], "prefix": "SkyborneH_", "title": "Skyborne (Horde)", "first": None,
                  "race_header": "Skyborne", "faction": "Horde", "joins": "ORDER.Horde"},
}
TRACK = TRACKS["main"]
FIXED = TRACK["fixed"]


def faction():
    return TRACK["faction"]


def alliance_main():
    return TRACK["order"] == "ORDER"


def boats():
    return HORDE_BOATS if faction() == "Horde" else BOATS

# flight master -> taxi node name (fly steps match by substring); per faction, some names exist on both sides
FP_NAMES = {
    352: "Stormwind", 523: "Sentinel Hill", 931: "Lakeshire", 1571: "Menethil Harbor", 1572: "Thelsamar",
    1573: "Ironforge", 2299: "Morgan's Vigil", 2409: "Darkshire", 2432: "Southshore", 2835: "Refuge Pointe",
    2859: "Booty Bay", 2941: "Thorium Point", 3838: "Rut'theran Village", 3841: "Auberdine", 4267: "Astranaar",
    4319: "Thalanaar", 4321: "Theramore", 4407: "Stonetalon Peak", 6706: "Nijel's Point", 7823: "Gadgetzan",
    8018: "Aerie Peak", 8019: "Feathermoon", 8609: "Nethergarde Keep", 257087: "Farholde Keep",
    # 40-60, from Forever's taxi node table (build 1.60.1)
    12596: "Chillwind Camp", 12617: "Light's Hope Chapel", 15177: "Cenarion Hold", 12577: "Talrendis Point",
    12578: "Talonbranch Glade", 10897: "Moonglade", 11138: "Everlook", 16227: "Ratchet",
    10583: "Marshal's Refuge",
}
# Horde, from Forever's taxi node table (build 1.60.1)
HORDE_FP_NAMES = {
    3310: "Orgrimmar", 2995: "Thunder Bluff", 4551: "Undercity", 2226: "The Sepulcher", 2389: "Tarren Mill",
    2851: "Hammerfall", 2858: "Booty Bay", 1387: "Grom'gol", 2861: "Kargath", 3305: "Thorium Point",
    3615: "Crossroads", 4312: "Sun Rock Retreat", 4314: "Revantusk Village", 4317: "Freewind Post",
    6026: "Stonard", 6726: "Shadowprey Village", 7824: "Gadgetzan", 8020: "Camp Mojache", 8610: "Valormok",
    10378: "Camp Taurajo", 10583: "Marshal's Refuge", 11139: "Everlook", 11899: "Brackenwall Village",
    11900: "Bloodvenom Post", 11901: "Zoram'gar Outpost", 12616: "Splintertree Post", 12636: "Light's Hope Chapel",
    12740: "Moonglade", 13177: "Flame Crest", 15178: "Cenarion Hold", 16227: "Ratchet", 255993: "Rog'mar",
}
FP_BY_FACTION = {"Alliance": FP_NAMES, "Horde": HORDE_FP_NAMES}
# cities with class trainers for every class: flying there adds a training stop
TRAIN_CITIES = {"Alliance": {"Stormwind": "Stormwind"},  # flight path name -> trainer area key
                "Horde": {"Orgrimmar": "Orgrimmar", "Thunder Bluff": "ThunderBluff", "Undercity": "Undercity"}}
# boats: (dock A, name A, dock B, name B)
BOATS = [((1445, 71.5, 56.4), "Theramore", (1437, 5.0, 63.4), "Menethil Harbor"),
         ((1439, 32.4, 43.8), "Auberdine", (1453, 22.6, 56.1), "Stormwind Harbor"),
         ((1413, 63.7, 38.6), "Ratchet", (1434, 25.9, 73.1), "Booty Bay"),
         ((1446, 68.6, 23.0), "Steamwheedle Port", (2548, 80.5, 54.6), "Powderfuse Port")]
# one-way ship loop: (dock, name, dock, name, stop you stay aboard past)
ONE_WAY_BOATS = [(cz.AUBERDINE_DOCK, "Auberdine", cz.MENETHIL_DOCK, "Menethil Harbor", None),
                 (cz.SOUTHSHORE_DOCK, "Southshore", cz.AUBERDINE_DOCK, "Auberdine", None),
                 (cz.MENETHIL_DOCK, "Menethil Harbor", cz.AUBERDINE_DOCK, "Auberdine", "Southshore"),
                 (cz.AUBERDINE_DOCK, "Auberdine", cz.SOUTHSHORE_DOCK, "Southshore", "Menethil Harbor")]
# Horde: zeppelins (5th item: how you cross) and the Ratchet boat
HORDE_BOATS = [((1411, 50.8, 13.5), "Orgrimmar", (1420, 60.7, 58.9), "Undercity", "zeppelin"),
               ((1411, 50.7, 12.9), "Orgrimmar", (1434, 31.5, 29.4), "Grom'gol", "zeppelin"),
               ((1413, 63.7, 38.6), "Ratchet", (1434, 25.9, 73.1), "Booty Bay"),
               ((1446, 68.6, 23.0), "Steamwheedle Port", (2548, 80.5, 54.6), "Powderfuse Port")]
DOCK_HINTS = {"Orgrimmar": "the zeppelin tower outside Orgrimmar's front gate",
              "Undercity": "the zeppelin tower north of the Undercity ruins",
              "Grom'gol": "the zeppelin tower at Grom'gol"}
SHORT = {1436: "Westfall", 1433: "Redridge", 1431: "Duskwood", 1432: "LochModan", 1437: "Wetlands",
         1439: "Darkshore", 1440: "Ashenvale", 1442: "Stonetalon", 1424: "Hillsbrad", 1417: "Arathi",
         1434: "STV", 1443: "Desolace", 1441: "ThousandNeedles", 1445: "Dustwallow", 1416: "Alterac",
         1418: "Badlands", 1435: "Swamp", 1444: "Feralas", 1425: "Hinterlands", 1446: "Tanaris",
         2548: "Riverglades", 1426: "DunMorogh", 1438: "Teldrassil", 1429: "Elwynn",
         1411: "Durotar", 1412: "Mulgore", 1413: "Barrens", 1420: "Tirisfal", 1421: "Silverpine",
         1427: "SearingGorge", 1428: "BurningSteppes", 1419: "BlastedLands", 1422: "WesternPlaguelands",
         1423: "EasternPlaguelands", 1447: "Azshara", 1448: "Felwood", 1449: "UnGoro", 1451: "Silithus",
         1452: "Winterspring", 1450: "Moonglade", 2652: "Shendralas", 2482: "Hyjal"}
# per-zone planner extras
EXTRA = {1424: "--also-maps 1416 --exclude 92432", 1434: "--include 328",
         1436: "--exclude 6181"}  # Westfall: A Swift Message is in the hand-written Stormwind trip
HORDE_EXTRA = {1424: "--also-maps 1416"}
# hand blocks: (anchor lines, first found wins; block file)
SPLICES = {1436: [(("turnin 13", "accept 6181"), "Alliance_Westfall.stormwind")]}
HEAD_EXTRA = {1436: ["accept 6181"]}  # the Stormwind trip starts at Sentinel Hill
OTHER_ZONES = {1453: "Stormwind", 1455: "Ironforge", 1430: "Deadwind Pass", 1419: "the Blasted Lands",
               1427: "Searing Gorge", 1428: "Burning Steppes", 1421: "Silverpine Forest", 1413: "the Barrens",
               1429: "Elwynn Forest", 1426: "Dun Morogh", 1457: "Darnassus",
               1454: "Orgrimmar", 1456: "Thunder Bluff", 1458: "the Undercity"}
DOCKS = {d: n for (d, n) in [(cz.FERRIES[0][0], "Rut'theran Village"), (cz.FERRIES[0][1], "Auberdine"),
                             (cz.HORDE_FERRIES[0][0], "Undercity"), (cz.HORDE_FERRIES[0][1], "Grom'gol")]}
MIN_ZONE_MINUTES = 5     # shorter plans aren't a guide, take the next zone
HEARTH_MIN_MINUTES = 60  # set the hearthstone in zones you stay in at least this long
HEARTH_COOLDOWN = 3600 + 300  # seconds, the hour plus a margin
HUB_NEAR = 500  # yards, a hub this close to the zone start is picked up first
GRIND_CLUSTER = 8  # a grind spot needs this many fitting spawns within 150 yards
GRIND_MARGIN = 1.0       # a zone must beat grinding by this factor


def run(*args):
    r = subprocess.run([sys.executable, "-I"] + list(args), cwd=ROOT, capture_output=True, text=True)
    if r.returncode:
        sys.exit("%s failed:\n%s%s" % (" ".join(args), r.stdout, r.stderr))
    return r.stdout


def write_order(files):
    with open(os.path.join(ROUTES, TRACK["order"]), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("# Guide build order (also the order quests are validated in)\n")
        fh.write("# Written by auto_chain.py from Westfall on.\n" if TRACK["order"] == "ORDER" else
                 "# Written by auto_chain.py --track: the hand-written start routes, then the chained zones.\n")
        for f in files:
            fh.write(f + "\n")


_sim_cache = {}


def hearth_age(data, files):
    """Simulated seconds since the last hearthstone use, or None."""
    if not files:
        return None
    sys.modules.setdefault("auto_chain", sys.modules[__name__])  # simulate imports this module
    import simulate as sim
    fac = faction()
    if fac not in _sim_cache:
        _sim_cache[fac] = (sim.load_trainers(), sim.load_spells("WARRIOR", fac), sim.fp_points(data, fac))
    trainers, spells, fps = _sim_cache[fac]
    comp, guides = sim.compile_playthrough(data, files)
    run = sim.Run(data, comp, guides, fac, "WARRIOR", trainers, spells, fps).run()
    return run.t - run.hearth_uses[-1] if run.hearth_uses else None


class State:
    def __init__(self, data):
        self.d = data
        self.comp = bg.Compiler(data)
        order = bg.read_order(TRACK["order"])
        self.pos, self.fps, self.hearth = None, {}, None
        for rf in order:
            h, st = bg.parse_route(os.path.join(ROUTES, rf))
            g = self.comp.compile_guide(h, st)
            for s in g["steps"]:
                if "x" in s:
                    self.pos = (s.get("map") or g["map"], s["x"], s["y"])
                if "getfp" in s:
                    self.fps[s["getfp"]] = self.pos
                if "sethearth" in s:
                    self.hearth = (s["sethearth"], self.pos)
        self.level = self.comp.est_level()
        cz.PLAYER_LEVEL = self.level  # trips avoid zones far above you
        age = hearth_age(data, order)
        self.hearth_ready = age is None or age >= HEARTH_COOLDOWN


def fp_npcs(data):
    out = {}
    for nid, name in FP_BY_FACTION[faction()].items():
        pts = data.points("npc", nid)
        n = data.npcs.get(str(nid)) or {}
        if pts:
            out[name] = (pts[0], n.get("name"))
    return out


def fmt(p, route_map):
    s = "@%.1f,%.1f" % (p[1], p[2])
    return s + (",%d" % p[0]) if p[0] != route_map else s


def same_continent(a, b):
    return cz.continent(a[0]) == cz.continent(b[0])


def run_lines(a, b):
    path = cz.walk_path(a[0], b[0]) or []
    for i, (m, n) in enumerate(zip(path, path[1:])):
        fe = cz.ferry(m, n)
        if fe:  # split at the boat
            how = "zeppelin" if faction() == "Horde" else "boat"
            note = "note Take the %s from %s to %s." % (how, DOCKS[fe[0]], DOCKS[fe[1]])
            if how == "zeppelin" and DOCKS[fe[0]] in DOCK_HINTS:
                note = note[:-1] + " (%s)." % DOCK_HINTS[DOCKS[fe[0]]]
            return run_lines(a, fe[0]) + [note] + run_lines(fe[1], b)
    names = [cz.ZONES.get(m) or OTHER_ZONES.get(m) or cz.zone_name(m, str(m)) for m in path[1:]]
    if not names:
        return []
    if set(cz.TRAM) <= set(path):
        to_sw = path.index(cz.TRAM[1]) < path.index(cz.TRAM[0])  # Ironforge -> Stormwind
        tram = "Ironforge (take the Deeprun Tram to Stormwind)" if to_sw else \
            "Ironforge (take the Deeprun Tram from Stormwind)"
        names = [tram if n == "Ironforge" else n for n in names]
    if len(names) == 1:
        return ["note Run to %s." % names[0]]
    return ["note Run to %s, through %s." % (names[-1], ", ".join(names[:-1]))]


def leg(a, b, fps, route_map):
    """Fastest way on one continent: (seconds, lines)."""
    best = (cz.run_seconds(a, b), run_lines(a, b))
    near = [(n, p) for n, (p, _) in fps.items() if same_continent(p, a)]
    if near:
        fa = min(near, key=lambda np: cz.run_seconds(a, np[1]))
        fb = min(near, key=lambda np: cz.run_seconds(np[1], b))
        if fa[0] != fb[0]:
            t = cz.run_seconds(a, fa[1]) + cz.run_seconds(fb[1], b) \
                + pz.yards(fa[1], fb[1]) / cz.FLIGHT_SPEED + cz.FLIGHT_OVERHEAD
            if t < best[0]:
                lines = run_lines(a, fa[1])
                if fa[0] in TRAIN_CITIES[faction()]:  # you're in the city anyway: a free training stop
                    lines.append("train %s" % TRAIN_CITIES[faction()][fa[0]])
                lines.append("fly %s %s {npc=%s}" % (fb[0], fmt(fa[1], route_map), fps[fa[0]][1]))
                if fb[0] in TRAIN_CITIES[faction()]:
                    lines.append("train %s" % TRAIN_CITIES[faction()][fb[0]])
                lines += run_lines(fb[1], b)
                best = (t, lines)
    return best


def trip(state, dest, route_map, data):
    """(seconds, lines) from the end of the last route to `dest`."""
    allfps = fp_npcs(data)
    fps = {n: allfps[n] for n in state.fps if n in allfps}
    a = state.pos
    options = []
    starts = [(0, [], a)]
    if state.hearth and state.hearth[1] and state.hearth_ready:
        starts.append((10, ["hearth %s" % state.hearth[0]], state.hearth[1]))
    for t0, l0, p0 in starts:
        if same_continent(p0, dest):
            t, lines = leg(p0, dest, fps, route_map)
            options.append((t0 + t, l0 + lines))
        for bt in boats():
            d1, n1, d2, n2 = bt[:4]
            how = bt[4] if len(bt) > 4 else "boat"
            for (da, na), (db, nb) in (((d1, n1), (d2, n2)), ((d2, n2), (d1, n1))):
                if same_continent(p0, da) and same_continent(db, dest) and not same_continent(p0, dest):
                    t1, la = leg(p0, da, fps, route_map)
                    t2, lb = leg(db, dest, fps, route_map)
                    boat = "note Take the %s from %s to %s%s." % (
                        how, na, nb, " (%s)" % DOCK_HINTS[na] if how == "zeppelin" and na in DOCK_HINTS else "")
                    extra = ["train Stormwind"] if na == "Stormwind Harbor" and "train Stormwind" not in la else []
                    after = ["train Stormwind"] if nb == "Stormwind Harbor" and "train Stormwind" not in lb else []
                    options.append((t0 + t1 + cz.BOAT_SECONDS + t2, l0 + la + extra + [boat] + after + lb))
        for da, na, db, nb, past in (ONE_WAY_BOATS if faction() == "Alliance" else []):
            if same_continent(p0, da) and same_continent(db, dest) and not same_continent(p0, dest):
                t1, la = leg(p0, da, fps, route_map)
                t2, lb = leg(db, dest, fps, route_map)
                boat = ("note Take the boat from %s and stay aboard past %s until %s." % (na, past, nb) if past
                        else "note Take the boat from %s to %s." % (na, nb))
                aboard = cz.BOAT_SECONDS + (cz.STAY_ABOARD_SECONDS if past else 0)
                options.append((t0 + t1 + aboard + t2, l0 + la + [boat] + lb))
    if not options:
        return 0, []
    t, lines = min(options, key=lambda o: o[0])
    if faction() != "Alliance":
        return t, lines
    if "Stormwind" not in state.fps and "train Stormwind" not in lines:
        # running through Stormwind: stop there to train
        for i, ln in enumerate(lines):
            m = re.match(r"note Run to (.+), through (.+)\.$", ln)
            via = m.group(2).split(", ") if m else []
            if "Stormwind" in via:
                k = via.index("Stormwind")
                first = "note Run to Stormwind%s." % (", through " + ", ".join(via[:k]) if k else "")
                rest = via[k + 1:]
                then = "note Run to %s%s." % (m.group(1), ", through " + ", ".join(rest) if rest else "")
                lines = lines[:i] + [first, "train Stormwind", then] + lines[i + 1:]
                break
    if "Stormwind" not in state.fps and "train Stormwind" in lines:
        # race tracks pass Stormwind without its flight path: pick it up
        i = lines.index("train Stormwind") + 1
        lines = lines[:i] + ["getfp Stormwind @71.3,72.2,1453 {npc=Dungar Longdrink}"] + lines[i:]
    return t, lines


def zone_hub(data, zmap, known):
    """(getfp line or None, innkeeper (name, point) or None, hub name) for a zone."""
    fps = [(n, p, npc) for n, (p, npc) in fp_npcs(data).items() if p[0] == zmap]
    get = None
    hub = None
    if fps:
        n, p, npc = fps[0]
        hub = n
        if n not in known:
            get = "getfp %s @%.1f,%.1f {npc=%s}" % (n, p[1], p[2], npc)
    inn = None
    for nid, nn in data.npcs.items():
        if (nn.get("subName") or "") == "Innkeeper" and faction()[0] in (nn.get("friendlyToFaction") or ""):
            pts = [q for q in data.points("npc", int(nid)) if q[0] == zmap]
            if pts and (not fps or pz.yards(pts[0], fps[0][1]) < 400):
                inn = (nn["name"], pts[0])
    return get, inn, hub


_MOBS = {}


FOREVER_NPC_IDS = 250000  # Forever's new NPCs start about here, no faction data
UNKNOWN_NPCS = {272291}   # Lost Knight (Duskwood), not a grind target


def grind_spot(data, zmap, near, level):
    """(point, [names]) of the nearest grind cluster on zmap, or None."""
    if zmap not in _MOBS:
        mobs = []
        for nid, n in data.npcs.items():
            lo, hi = n.get("minLevel") or 0, n.get("maxLevel") or n.get("minLevel") or 0
            if n.get("friendlyToFaction") or n.get("rank") or not lo or hi - lo > 4:
                continue  # friendly, elite or zone-scaled
            if not n.get("factionID") and (int(nid) < FOREVER_NPC_IDS or int(nid) in UNKNOWN_NPCS):
                continue  # no faction data; Forever's own mobs never have any
            pts = [p for p in data.points("npc", int(nid)) if p[0] == zmap]
            if len(pts) >= 5:  # named one-offs don't make a grind spot
                mobs += [(p, lo, hi, n.get("name")) for p in pts]
        _MOBS[zmap] = mobs
    fit = [m for m in _MOBS[zmap] if m[1] <= level + 1 and m[2] >= level - 3]
    best = None
    for p, _, _, _ in fit:
        group = [m for m in fit if pz.yards(p, m[0]) < 150]
        if len(group) >= GRIND_CLUSTER:
            d = pz.yards(near, p)
            if not best or d < best[0]:
                best = (d, p, group)
    if not best:
        return None
    names = [nm for nm, _ in collections.Counter(m[3] for m in best[2]).most_common(2)]
    return best[1], names


def grind_line(data, to, near, why="nothing beats grinding now"):
    spot = grind_spot(data, near[0], near, to - 1)
    if not spot:
        return "level %d @%.1f,%.1f | Kill monsters around this area until level %d (%s)." % (
            to, near[1], near[2], to, why)
    p, names = spot
    return "level %d @%.1f,%.1f | Kill %s here until level %d (%s)." % (to, p[1], p[2], " and ".join(names), to, why)


def finish_with_grind(data, st, last, to):
    path = os.path.join(ROUTES, last)
    txt = open(path, encoding="utf-8").read().rstrip("\n")
    txt = re.sub(r"\n+# On to [^\n]*\(the best zone from here\)\n.*\Z", "", txt, flags=re.S)
    txt = re.sub(r"(?m)^next .*\n", "", txt)
    txt = re.sub(r"\n+# The last level: [^\n]*\n.*\Z", "", txt, flags=re.S)  # an earlier run's ending
    txt += "\n\n# The last level: grinding is faster than travelling to new quests\n"
    near = st.pos
    if not grind_spot(data, near[0], near, to - 1):
        # zone too low by now: nearest zone on this continent with fitting mobs
        best = None
        for z in cz.ZONES:
            if z == near[0] or cz.continent(z) != cz.continent(near[0]):
                continue
            spot = grind_spot(data, z, near, to - 1)
            if spot and (not best or pz.yards(near, spot[0]) < best[0]):
                best = (pz.yards(near, spot[0]), z, spot[0])
        if best:
            near = best[2]
            txt += "note Head to %s: nothing here gives good XP at your level any more.\n" % cz.ZONES[best[1]]
    line = grind_line(data, to, near, "the end of the route")
    if near[0] != st.pos[0]:
        line = re.sub(r"^level (\d+) @([\d.]+),([\d.]+) ", r"level \1 @\2,\3,%d " % near[0], line)
    txt += line + "\n"
    open(path, "w", encoding="utf-8", newline="\n").write(txt)
    print("track ends: grind to %d at the end of %s" % (to, last), flush=True)


def _key(line):
    return re.sub(r"\s+", " ", line.split("@")[0].split("||")[0].strip())


def place_hub(data, path, hub_lines, hub_pt):
    lines = open(path, encoding="utf-8").read().split("\n")
    have = {_key(l) for l in lines}
    hub_lines = [h for h in hub_lines if _key(h) not in have]
    if not hub_lines:
        return
    h, st = bg.parse_route(path)
    g = bg.Compiler(data).compile_guide(h, st)
    at = None
    for s in g["steps"]:
        if "x" in s and (s.get("map") or g["map"]) == hub_pt[0] \
                and pz.yards((hub_pt[0], s["x"], s["y"]), hub_pt) <= HUB_NEAR:
            at = int(s["_where"].rsplit(":", 1)[1]) - 1
            break
    if at is None:  # the route never passes the hub: pick it up first after all
        at = next(i for i, l in enumerate(lines) if l.startswith("map ")) + 1
        while at < len(lines) and re.match(r"(next|levels|races|faction) ", lines[at]):
            at += 1
    lines[at:at] = hub_lines
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines))


# zone bands (--bands FILE): only pick among a level's band zones; levels below the first band are free
BANDS = []  # [(lo, hi, {zone ids})]


def load_bands(path):
    by_name = {v.lower(): k for k, v in SHORT.items()}
    out = []
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        line = line.split("#", 1)[0].split()
        if not line:
            continue
        lo, hi, names = int(line[0]), int(line[1]), line[2:]
        zones = set()
        for nm in names:
            z = by_name.get(nm.lower())
            if z is None or z not in cz.FACTION_ZONES[faction()]:
                sys.exit("%s:%d: unknown zone %r for %s (names as in SHORT)" % (path, n, nm, faction()))
            zones.add(z)
        out.append((lo, hi, zones))
    return out


def band_rows(ranked, level):
    if not BANDS or int(level) < BANDS[0][0]:
        return ranked
    allowed = set().union(*[zs for lo, hi, zs in BANDS if lo <= int(level) <= hi] or [set()])
    rows = [zr for zr in ranked if zr[0] in allowed]
    names = "/".join(sorted(SHORT.get(z, str(z)) for z in allowed)) or "none"
    if rows:
        print("   band at %.1f: %s -> %s" % (level, names, SHORT.get(rows[0][0], rows[0][0])), flush=True)
        return rows
    print("   band at %.1f: %s has nothing left - free choice %s"
          % (level, names, SHORT.get(ranked[0][0], ranked[0][0])), flush=True)
    return ranked


def best_zones(state, data, level=None):
    comp = state.comp
    if level:
        comp.xp_total = max(comp.xp_total, sum(bg.XP_TO_LEVEL[1:int(level)]))
    allfps = fp_npcs(data)
    fms = [allfps[n][0] for n in state.fps if n in allfps]
    rows = []
    for z in cz.FACTION_ZONES[faction()]:
        r = cz.evaluate_zone(data, comp, z, comp.est_level(), state.pos, TRACK["races"], faction(), fms)
        if r and r["quests"]:
            rows.append((z, r))
    rows.sort(key=lambda zr: -zr[1]["hrate"])
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", type=float, help="stop once a route ends at this level (main 37, race tracks 19)")
    ap.add_argument("--track", default="main", choices=sorted(TRACKS))
    ap.add_argument("--first", type=int, help="uiMap ID of the zone to go to first (default: the track's own, if any)")
    ap.add_argument("--max-steps", type=int, default=40)
    ap.add_argument("--resume", action="store_true",
                    help="keep the track's chained guides from routes/ORDER* and carry on after the last one")
    ap.add_argument("--bands", help="zone band file (see load_bands): only use these zones per level band")
    a = ap.parse_args()
    global TRACK, FIXED
    TRACK = TRACKS[a.track]
    FIXED = TRACK["fixed"]
    if a.first:
        TRACK = dict(TRACK, first=a.first)
    cz.FACTION = faction()
    if a.bands:
        BANDS[:] = load_bands(a.bands)
    target = a.target or (37 if a.track == "main" else 19)
    data = bg.Data()
    files, visits = [], {}
    if a.resume:
        # file names give each zone's part number
        by_short = {v: k for k, v in SHORT.items()}
        for rf in bg.read_order(TRACK["order"]):
            if rf in FIXED:
                continue
            files.append(rf)
            mm = re.match(r"%s(.+?)(\d*)\.route$" % re.escape(TRACK["prefix"]), rf)
            zz = by_short.get(mm.group(1)) if mm else None
            if zz:
                visits[zz] = max(visits.get(zz, 0), int(mm.group(2) or 1))
        print("resuming after %s (%d chained guides)" % ((FIXED + files)[-1], len(files)), flush=True)
    else:
        write_order(FIXED)
    if not alliance_main() and not files:
        # drop the trip an earlier run wrote, or the replay starts where it went
        path = os.path.join(ROUTES, FIXED[-1])
        txt = open(path, encoding="utf-8").read().rstrip("\n")
        txt = re.sub(r"\n+# On to [^\n]*\(the best zone from here\)\n.*\Z", "", txt, flags=re.S)
        txt = re.sub(r"\n+# On to the shared [^\n]*\n.*\Z", "", txt, flags=re.S)  # a hand-over (Skyborne)
        open(path, "w", encoding="utf-8", newline="\n").write(txt + "\n")
    elif TRACK["joins"]:
        # --resume: the hand-over is written again at the end
        path = os.path.join(ROUTES, (FIXED + files)[-1])
        txt = open(path, encoding="utf-8").read().rstrip("\n")
        txt = re.sub(r"\n+# On to the shared [^\n]*\n.*\Z", "", txt, flags=re.S)
        open(path, "w", encoding="utf-8", newline="\n").write(txt + "\n")
    for step in range(a.max_steps):
        st = State(data)
        if st.level >= target:
            break
        banned = set()  # zones whose plan came out empty
        while True:
            st = State(data)
            ranked = [zr for zr in best_zones(st, data) if zr[0] not in banned]
            if not ranked and not pz.QUEST_FIRST:
                break
            rows, z, r = [], None, None
            if ranked:
                rows = band_rows(ranked, st.level)
                z, r = rows[0]
                if step == 0 and not a.resume and TRACK["first"] and TRACK["first"] not in banned:
                    z = TRACK["first"]
                    r = dict(rows)[z]
            grind_to = None
            if pz.QUEST_FIRST:
                need_grind = not ranked
                if need_grind:
                    print("   no quests anywhere at %.1f: grind a level" % st.level, flush=True)
            else:
                grind_rate = pz.Planner(data, st.comp, z, 1, 60, TRACK["races"],
                                        faction()).grind_rate(st.level) * 3600
                need_grind = r["hrate"] < grind_rate * GRIND_MARGIN
            if need_grind:
                # grind a level, then go where that level leads
                grind_to = int(st.level) + 1
                if grind_to >= target and files:
                    break  # last level: grind it where you are
                st = State(data)
                ranked = [zr for zr in best_zones(st, data, grind_to) if zr[0] not in banned]
                if not ranked:
                    break
                rows = band_rows(ranked, grind_to)
                z, r = rows[0]
            # runner-up from the free ranking, a one-zone band has none
            runner = next((rr for zz, rr in ranked if zz != z), None)
            next_rate = runner["hrate"] if runner else 0
            st = State(data)
            lvl = max(st.level, grind_to or 0)
            part = visits.get(z, 0) + 1
            fname = "%s%s%s" % (TRACK["prefix"], SHORT.get(z, z), "" if part == 1 else part)
            zname = cz.zone_name(z, str(z))
            start = r["start"]

            args ="--map %d --levels %d %d --start %.1f,%.1f --next-level %.1f --next-ref %.1f" % (
                z, max(1, int(lvl) - 2), int(lvl) + 8, start[1], start[2], lvl, lvl)
            extra = (HORDE_EXTRA if faction() == "Horde" else EXTRA).get(z, "")
            if "--next-rate" not in extra:
                args += " --next-rate %d" % next_rate
            if grind_to:
                args += " --level %d" % grind_to
            draft = os.path.join("routes", "drafts", fname + ".route")
            out = run("plan_zone.py", *(args + " " + extra).split(), "--upto", (FIXED + files)[-1],
                      "--order", TRACK["order"], "--races", ",".join(TRACK["races"]), "--faction", faction(),
                      "--name", "x", "--file", fname, "--out", draft)
            m = re.search(r"end: level ([\d.]+) +\(\+(\d+) XP in ~(\d+) min", out)
            end_level, minutes = float(m.group(1)), int(m.group(3))
            if minutes >= MIN_ZONE_MINUTES:
                break
            print("   %s at %.1f: the plan came out empty (%d min) - trying the next zone" % (zname, lvl, minutes),
                  flush=True)
            banned.add(z)
        if not rows:
            if pz.QUEST_FIRST and files and State(data).level < target:
                print("no zone left with quests: grind to %d at the end" % int(target))
                finish_with_grind(data, State(data), files[-1], int(target))
            else:
                print("no zone left with quests")
            break
        if grind_to and grind_to >= target and files:
            finish_with_grind(data, st, files[-1], grind_to)
            break
        visits[z] = part
        drops = re.findall(r"(?m)^# drop +\d+ (.+?) {2,}", open(os.path.join(ROOT, draft), encoding="utf-8").read())

        # the trip there goes into the previous guide (Elwynn has its own)
        if files or not alliance_main():
            prev = os.path.join(ROUTES, files[-1] if files else FIXED[-1])
            ptxt = open(prev, encoding="utf-8").read().rstrip("\n")
            # drop the trip an earlier run wrote into a hand-written route
            ptxt = re.sub(r"\n+# On to [^\n]*\(the best zone from here\)\n.*\Z", "", ptxt, flags=re.S)
            pmap = int(re.search(r"(?m)^map (\d+)", ptxt).group(1))
            t, lines = trip(st, start, pmap, data)
            if lines or pmap != z:  # another part of the same zone needs no travel step
                ptxt += "\n\n# On to %s (the best zone from here)\n" % zname
                ptxt += "\n".join(lines or ["note Head to %s." % zname])
            open(prev, "w", encoding="utf-8", newline="\n").write(ptxt + "\n")

        get, inn, hub = zone_hub(data, z, st.fps)
        hub_pt = fp_npcs(data).get(hub, (None,))[0] if hub else None

        lo, hi = int(lvl), int(end_level)
        span = "%d" % lo if hi <= lo else "%d-%d" % (lo, hi)
        title = "%s %s %s%s" % (TRACK["title"], span, zname, "" if part == 1 else " (part %d)" % part)
        head = ["# %s" % title,
                "# Generated by auto_chain.py: the best zone at level %.1f (%.0f XP/h over the next 90 minutes, trip"
                % (lvl, r["hrate"]),
                "# included). Order from plan_zone.py (%s), time-optimised against grinding and the next best"
                % draft.replace("\\", "/"),
                "# zone (%s, ~%.0f XP/h)." % (cz.zone_name(next((zz for zz, _ in rows if zz != z), 0), "-"),
                                             next_rate)]
        if drops:
            head.append("# Skipped as too slow: %s." % ", ".join(drops[:8]))
        head += ["guide %s" % title, "file %s" % fname, "faction %s" % faction()]
        if TRACK["race_header"]:
            head.append("races %s" % TRACK["race_header"])
        head += [
                 "levels %d %d" % (max(1, lo - 1), hi + 1), "map %d" % z, ""]
        hub_lines = [get] if get else []
        if inn and minutes >= HEARTH_MIN_MINUTES and (not st.hearth or st.hearth[0] != hub):
            hub_lines.append('sethearth %s @%.1f,%.1f {npc=%s} || Talk to the innkeeper and choose "Make this inn '
                             'your home".' % (hub or zname, inn[1][1], inn[1][2], inn[0]))
        late_hub = hub_pt is not None and pz.yards(hub_pt, start) > HUB_NEAR
        if not late_hub:
            head += hub_lines
        head += HEAD_EXTRA.get(z, []) if part == 1 and alliance_main() else []
        if grind_to:
            head.append(grind_line(data, grind_to, start))
        hfile = os.path.join(HAND, fname + ".auto.head")
        open(hfile, "w", encoding="utf-8", newline="\n").write("\n".join(head) + "\n")
        dest = os.path.join("routes", fname + ".route")
        run("route_from_draft.py", draft, dest, hfile)
        path = os.path.join(ROOT, dest)
        text = open(path, encoding="utf-8").read()
        text = re.sub(r"(?m)^level (\d+) @([\d.]+),([\d.]+) \| grind to level \d+ here$",
                      lambda mm: grind_line(data, int(mm.group(1)), (z, float(mm.group(2)), float(mm.group(3))),
                                            "the next quests need it"), text)
        open(path, "w", encoding="utf-8", newline="\n").write(text)
        for anchors, block in (SPLICES.get(z, []) if alliance_main() else []):
            if part != 1:
                continue
            after = next((an for an in anchors if re.search(
                r"(?m)^%s\s*$" % r"\s+".join(map(re.escape, an.split())), text)), None)
            if after:
                run(os.path.join("routes", "hand", "splice.py"), dest, after, os.path.join(HAND, block))
            else:
                print("   note: none of %s in %s - %s not spliced" % (list(anchors), fname, block))
        if late_hub and hub_lines:
            place_hub(data, path, hub_lines, hub_pt)
        # link the previous guide to this one
        prev = os.path.join(ROUTES, files[-1] if files else FIXED[-1])
        ptxt = open(prev, encoding="utf-8").read()
        ptxt = re.sub(r"(?m)^next .*\n", "", ptxt)
        ptxt = re.sub(r"(?m)^(map \d+)$", lambda mm: mm.group(1) + "\nnext " + title, ptxt, count=1)
        open(prev, "w", encoding="utf-8", newline="\n").write(ptxt)
        files.append(fname + ".route")
        write_order(FIXED + files)
        print("%-24s %-28s -> %.1f  %4d min  %6.0f XP/h@90  (next best %6.0f)%s" % (
            fname, title, end_level, minutes, r["hrate"], next_rate, "  [grind to %d first]" % grind_to
            if grind_to else ""), flush=True)
    write_order(FIXED + files)
    if TRACK["joins"]:
        # also when the start routes already reach --target (Skyborne)
        join_shared(data, (FIXED + files)[-1])


def learn_on_the_way(data, st, first_shared, lines):
    order = bg.read_order(TRACK["joins"])
    known = set(st.fps)
    missing = []
    for rf in order[order.index(first_shared):]:
        for kind, name in re.findall(r"(?m)^(getfp|fly) +(.+?)\s*(?:@|\{|\||$)", open(
                os.path.join(ROUTES, rf), encoding="utf-8").read()):
            if kind == "getfp":
                known.add(name)
            elif name not in known and name not in missing:
                missing.append(name)
    allfps = fp_npcs(data)
    for name in missing:
        if name not in allfps:
            continue
        if any(ln.startswith("getfp %s " % name) for ln in lines):
            continue  # the trip itself picks it up
        p, npc = allfps[name]
        zone = cz.zone_name(p[0], "")
        # "stay aboard past X" doesn't stop at X
        i = next((k for k, ln in enumerate(lines)
                  if (name in ln and "past %s" % name not in ln) or (zone and zone in ln)), None)
        if i is None:
            if not fp_fallback(data, st, first_shared, name):
                print("  note: the shared guides later fly from %s, which this track never learns" % name)
            continue
        # after the line that gets you there, not one leaving from it or only running through its zone
        if "from %s" % name in lines[i] or (zone and zone in lines[i].partition(", through ")[2]):
            i -= 1
        lines = lines[:i + 1] + ["getfp %s @%.1f,%.1f,%d {npc=%s}" % (name, p[1], p[2], p[0], npc)] + lines[i + 1:]
    return lines


FPFB = re.compile(r"(?:^|;)\s*fpfb=([^;}]*)")


def _opts_set(line, key, value):
    m = re.search(r"\s*\{([^}]*)\}", line)
    items = [kv.strip() for kv in m.group(1).split(";") if kv.strip()] if m else []
    items = [kv for kv in items if not kv.startswith(key + "=")]
    if value is not None:
        items.append("%s=%s" % (key, value))
    block = (" {%s}" % ";".join(items)) if items else ""
    if m:
        return line[:m.start()] + block + line[m.end():]
    cut = line.find(" |")
    cut = len(line) if cut < 0 else cut
    return line[:cut] + block + line[cut:]


def _fpfb_races(tracks):
    return ",".join(r for r in FACTION_RACES[faction()] if not any(r in TRACKS[t]["races"] for t in tracks))


def track_key():
    return next(k for k, t in TRACKS.items() if t["order"] == TRACK["order"])


def strip_fp_fallback(key):
    for rf in bg.read_order(TRACK["joins"]):
        path = os.path.join(ROUTES, rf)
        lines = open(path, encoding="utf-8").read().split("\n")
        out, changed = [], False
        for ln in lines:
            if "fpfbalt=%s" % key in ln:
                changed = True
                continue
            m = FPFB.search(ln)
            if m and key in m.group(1).split(","):
                rest = [t for t in m.group(1).split(",") if t and t != key]
                ln = _opts_set(ln, "fpfb", ",".join(rest) or None)
                ln = _opts_set(ln, "race", _fpfb_races(rest) if rest else None)
                changed = True
            out.append(ln)
        if changed:
            open(path, "w", encoding="utf-8", newline="\n").write("\n".join(out))


def fp_fallback(data, st, first_shared, name):
    """Fly this track to its nearest known node and run on; True if a fallback was written."""
    allfps = fp_npcs(data)
    if name not in allfps:
        return False
    key = track_key()
    known = set(st.fps)
    order = bg.read_order(TRACK["joins"])
    p_dest, npc_dest = allfps[name]
    for rf in order[order.index(first_shared):]:
        path = os.path.join(ROUTES, rf)
        lines = open(path, encoding="utf-8").read().split("\n")
        for k, ln in enumerate(lines):
            m = re.match(r"(getfp|fly) +(.+?)\s*(?:@|\{|\||$)", ln)
            if not m:
                continue
            if m.group(1) == "getfp":
                known.add(m.group(2).strip())
                continue
            if m.group(2).strip() != name:
                continue
            o = re.search(r"\{([^}]*)\}", ln)
            if o and re.search(r"(?:^|;)\s*race=", o.group(1)) and not FPFB.search(o.group(1)):
                return False  # hand-made race split, leave it
            alts = [(pz.yards(allfps[n][0], p_dest), n) for n in known if n in allfps and n != name]
            if not alts:
                return False
            alt = min(alts)[1]
            prev = FPFB.search(ln)
            tracks = [t for t in (prev.group(1).split(",") if prev else []) if t] + [key]
            orig = _opts_set(_opts_set(ln, "race", _fpfb_races(tracks)), "fpfb", ",".join(tracks))
            mine = ",".join(TRACK["races"])
            base = re.sub(r"^fly +%s" % re.escape(name), "fly %s" % alt, ln.split(" |")[0])
            fly_alt = _opts_set(_opts_set(base, "race", mine), "fpfbalt", key)
            learn = ("getfp %s @%.1f,%.1f,%d {npc=%s;race=%s;fpfbalt=%s} || You don't have this flight path yet: "
                     "run here from %s." % (name, p_dest[1], p_dest[2], p_dest[0], npc_dest, mine, key, alt))
            lines[k:k + 1] = [orig, fly_alt, learn]
            open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
            print("  %s: the %s races fly to %s and run to %s (%s)" % (key, mine, alt, name, rf))
            return True
    return False


FACTION_RACES = {"Alliance": ["Human", "Dwarf", "NightElf", "Gnome", "Skyborne"],
                 "Horde": ["Orc", "Troll", "Tauren", "Scourge", "Skyborne"]}
CATCH_UP = "# Catch up with the shared route's quest levels"


class JoinReplay(bg.Compiler):
    def __init__(self, data, races, shared_files):
        super().__init__(data)
        self.races, self.shared, self.issues = set(races), set(shared_files), []

    def compile_step(self, st, guide, prev):
        r = st["opts"].get("race")
        if r and not {x.strip() for x in r.split(",")} & self.races:
            return []
        v = st["verb"]
        if v in ("accept", "turnin", "complete"):
            ids = [int(s) for s in st["args"].split(",") if s.strip()]
            acc, done = {q for q, _ in self.accepted}, {q for q, _ in self.turned}
            ids = [i for i in ids if i not in (acc if v == "accept" else done)]
            if not ids:
                return []
            st = dict(st, args=", ".join(map(str, ids)))
        ne, nw = len(self.errors), len(self.warnings)
        res = super().compile_step(st, guide, prev)
        if st["where"].split(":")[0] in self.shared:
            for msg in self.errors[ne:]:
                m = re.search(r": (\d+) .*? needs ", msg)
                if m:
                    self.issues.append(("pre", int(m.group(1))))
            for msg in self.warnings[nw:]:
                m = re.search(r": (\d+) .*? (?:requires level|solo before level) \d+", msg)
                if m:
                    self.issues.append(("level", int(m.group(1))))
        return res


def race_filter(qids, files):
    others = [r for r in FACTION_RACES[faction()] if r not in TRACK["races"]]
    for rf in files:
        path = os.path.join(ROUTES, rf)
        lines, out = open(path, encoding="utf-8").read().split("\n"), []
        for ln in lines:
            m = re.match(r"(accept|turnin|complete)(\s+)([\d, ]*\d)(.*)$", ln)
            ids = [int(x) for x in re.findall(r"\d+", m.group(3))] if m else []
            hit = [i for i in ids if i in qids]
            if not hit:
                out.append(ln)
                continue
            rest = [i for i in ids if i not in qids]
            if rest:
                out.append(m.group(1) + m.group(2) + ", ".join(map(str, rest)) + m.group(4))
            line = m.group(1) + m.group(2) + ", ".join(map(str, hit)) + m.group(4)
            o = re.search(r"\{([^}]*)\}", line)
            if o and re.search(r"(?:^|;)\s*race=", o.group(1)):
                line = re.sub(r"race=([^;}]*)", lambda mm: "race=" + ",".join(
                    r for r in mm.group(1).split(",") if r.strip() not in TRACK["races"]), line)
            elif o:
                line = line[:o.end() - 1] + ";race=" + ",".join(others) + line[o.end() - 1:]
            else:
                cut = line.find(" |")
                cut = len(line) if cut < 0 else cut
                line = line[:cut] + " {race=" + ",".join(others) + "}" + line[cut:]
            out.append(line)
        open(path, "w", encoding="utf-8", newline="\n").write("\n".join(out))


def fit_joiner(data, st, first_shared, last):
    order = bg.read_order(TRACK["joins"])
    shared = order[order.index(first_shared):]
    files = bg.read_order(TRACK["order"]) + shared
    grind = False
    for _ in range(12):
        comp = JoinReplay(data, TRACK["races"], shared)
        for rf in files:
            h, steps = bg.parse_route(os.path.join(ROUTES, rf))
            comp.compile_guide(h, steps)
        pre = {q for k, q in comp.issues if k == "pre"}
        low = {q for k, q in comp.issues if k == "level"}
        if not pre and not low:
            return
        if low and not pre and not grind:
            grind = True
            to = int(st.level) + 1
            path = os.path.join(ROUTES, last)
            txt = open(path, encoding="utf-8").read()
            line = grind_line(data, to, st.pos, "the shared route's next quests need it")
            txt = txt.replace("\n\n# On to the shared ", "\n\n%s\n%s\n\n# On to the shared " % (CATCH_UP, line), 1)
            open(path, "w", encoding="utf-8", newline="\n").write(txt)
            print("  catch-up grind to %d at the end of %s" % (to, last))
            continue
        bad = pre or low
        race_filter(bad, shared)
        print("  shared steps of %s filtered to the other races (%s)" % (
            ", ".join(map(str, sorted(bad))), "missing prerequisite" if pre else "above your level"))
    print("  !! the shared guides still have problems for this track")


def join_shared(data, last):
    strip_fp_fallback(track_key())  # an earlier run's fallbacks
    path = os.path.join(ROUTES, last)
    txt = open(path, encoding="utf-8").read()
    txt2 = re.sub(r"\n+%s\nlevel [^\n]*" % re.escape(CATCH_UP), "", txt)  # an earlier run's catch-up grind
    if txt2 != txt:
        open(path, "w", encoding="utf-8", newline="\n").write(txt2)
    st = State(data)
    level = int(st.level)
    done = {q for q, _ in st.comp.turned}
    for rf in bg.read_order(TRACK["joins"]):
        h, _ = bg.parse_route(os.path.join(ROUTES, rf))
        if h.get("races"):
            continue
        hi = int(h.get("levels", "1 60").split()[1])
        body = open(os.path.join(ROUTES, rf), encoding="utf-8").read()
        tq = {int(q) for line in re.findall(r"(?m)^turnin\s+([\d, ]+)", body) for q in re.findall(r"\d+", line)}
        if tq and len(tq & done) >= 0.5 * len(tq):
            continue
        if level < hi:
            path = os.path.join(ROUTES, last)
            txt = open(path, encoding="utf-8").read()
            txt = re.sub(r"(?m)^next .*\n", "", txt)
            txt = re.sub(r"(?m)^(map \d+)$", lambda mm: mm.group(1) + "\nnext " + h["guide"], txt, count=1)
            _, shared = bg.compile_track(data, TRACK["joins"])
            g = next(gg for gg in shared if gg["name"] == h["guide"])
            first = next(s for s in g["steps"] if "x" in s)
            dest = (first.get("map") or g["map"], first["x"], first["y"])
            pmap = int(re.search(r"(?m)^map (\d+)", txt).group(1))
            _, lines = trip(st, dest, pmap, data)
            lines = learn_on_the_way(data, st, rf, lines or [])
            txt = txt.rstrip("\n") + "\n\n# On to the shared %s route: %s\n" % (faction(), h["guide"])
            txt += "\n".join(lines or ["note Head to %s." % cz.zone_name(dest[0], "the next zone")]) + "\n"
            open(path, "w", encoding="utf-8", newline="\n").write(txt)
            print("track ends at %.1f: hands over to %s" % (st.level, h["guide"]))
            fit_joiner(data, st, rf, last)
            return
    print("track ends at %.1f: no shared guide covers that level" % st.level)


if __name__ == "__main__":
    main()
