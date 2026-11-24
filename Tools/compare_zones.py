"""Compare zones by questing XP per hour from a given point in the route chain.

Usage:
    python -I compare_zones.py [--upto Alliance_Westfall.route] [--zones 1433,1431,...] [--level 15]

The runner-up's rate is a good --next-rate for planning the current zone.
"""
import argparse
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
import build_guides as bg  # noqa: E402
import plan_zone as pz  # noqa: E402

# Alliance zones up to 60 (Classic uiMap IDs, which Forever uses)
ZONES = {
    1429: "Elwynn Forest", 1436: "Westfall", 1433: "Redridge Mountains", 1431: "Duskwood",
    1432: "Loch Modan", 1437: "Wetlands", 1426: "Dun Morogh", 1438: "Teldrassil", 1439: "Darkshore",
    1440: "Ashenvale", 1442: "Stonetalon Mountains", 1424: "Hillsbrad Foothills", 1417: "Arathi Highlands",
    1434: "Stranglethorn Vale", 1443: "Desolace", 1441: "Thousand Needles", 1445: "Dustwallow Marsh",
    1416: "Alterac Mountains", 1418: "Badlands", 1435: "Swamp of Sorrows", 1444: "Feralas",
    1425: "The Hinterlands", 1446: "Tanaris", 2548: "Riverglades",
    1427: "Searing Gorge", 1428: "Burning Steppes", 1419: "Blasted Lands", 1422: "Western Plaguelands",
    1423: "Eastern Plaguelands", 1447: "Azshara", 1448: "Felwood", 1449: "Un'Goro Crater", 1451: "Silithus",
    1452: "Winterspring", 2652: "Shen'dralas", 2482: "Mount Hyjal",
}
# Horde-side zones, kept out of ZONES so the Alliance list stays as it is
HORDE_ZONES = {1411: "Durotar", 1412: "Mulgore", 1413: "The Barrens", 1420: "Tirisfal Glades", 1421: "Silverpine Forest"}
# zones each faction's chain may pick; ALLIANCE_ONLY has no Horde quest hubs
ALLIANCE_ONLY = {1429, 1436, 1433, 1432, 1426, 1438, 1439, 1437}
FACTION_ZONES = {
    "Alliance": list(ZONES),
    "Horde": list(HORDE_ZONES) + [z for z in ZONES if z not in ALLIANCE_ONLY],
}
FACTION = "Alliance"  # for the travel model, auto_chain sets it


def zone_name(m, default=None):
    return ZONES.get(m) or HORDE_ZONES.get(m) or default


KALIMDOR = {1438, 1439, 1440, 1442, 1443, 1441, 1445, 1444, 1446, 1447, 1448, 1449, 1450, 1451, 1452, 1413}
BOAT_SECONDS = 420     # incl. waiting for the boat
FLIGHT_SPEED = 20.0    # yards/s, calibrated on Forever flight times
FLIGHT_OVERHEAD = 60   # seconds, finding the flight master and landing


def flight_masters(data, faction=None):
    letter = (faction or FACTION)[0]
    out = []
    for nid, n in data.npcs.items():
        if (n.get("subName") or "") in ("Gryphon Master", "Hippogryph Master", "Flight Master", "Wind Rider Master",
                                        "Bat Handler") and letter in (n.get("friendlyToFaction") or ""):
            out += data.points("npc", int(nid))
    return out


# boats between the continents: (Kalimdor dock, Eastern Kingdoms dock)
BOATS = [((1445, 71.5, 56.4), (1437, 5.0, 63.4)),   # Theramore <-> Menethil Harbor
         ((1439, 32.4, 43.8), (1453, 22.0, 56.0)),   # Auberdine <-> Stormwind Harbor (Forever; spot approximate)
         ((1413, 63.7, 38.6), (1434, 25.9, 73.1)),   # Ratchet <-> Booty Bay (neutral; docks approximate)
         ((1446, 68.6, 23.0), (2548, 80.5, 54.6))]   # Steamwheedle Port (Tanaris) <-> Powderfuse Port (Riverglades)
# one-way loop Auberdine > Menethil > Southshore > Auberdine (guide sites, not confirmed); against it you stay aboard
STAY_ABOARD_SECONDS = 240  # estimate, not measured in game
AUBERDINE_DOCK, MENETHIL_DOCK, SOUTHSHORE_DOCK = (1439, 32.4, 43.8), (1437, 4.6, 57.1), (1424, 50.7, 70.4)
ONE_WAY_BOATS = [(AUBERDINE_DOCK, MENETHIL_DOCK, 0),                     # (from, to, extra seconds aboard)
                 (SOUTHSHORE_DOCK, AUBERDINE_DOCK, 0),
                 (MENETHIL_DOCK, AUBERDINE_DOCK, STAY_ABOARD_SECONDS),   # via Southshore
                 (AUBERDINE_DOCK, SOUTHSHORE_DOCK, STAY_ABOARD_SECONDS)]  # via Menethil Harbor
# Horde: zeppelins (docks = zeppelin masters' DB positions) and the Ratchet boat
HORDE_BOATS = [((1411, 50.8, 13.5), (1420, 60.7, 58.9)),   # Orgrimmar (Durotar tower) <-> Undercity (Tirisfal tower)
               ((1411, 50.7, 12.9), (1434, 31.5, 29.4)),   # Orgrimmar <-> Grom'gol
               ((1413, 63.7, 38.6), (1434, 25.9, 73.1)),   # Ratchet <-> Booty Bay
               ((1446, 68.6, 23.0), (2548, 80.5, 54.6))]   # Steamwheedle Port <-> Powderfuse Port, neutral


def boats():
    return HORDE_BOATS if FACTION == "Horde" else BOATS


def crossings():
    """Every boat trip between the continents: (from dock, to dock, seconds)."""
    trips = [(x, y, BOAT_SECONDS) for a, b in boats() for x, y in ((a, b), (b, a))]
    if FACTION != "Horde":
        trips += [(x, y, BOAT_SECONDS + extra) for x, y, extra in ONE_WAY_BOATS]
    return trips


# zones you can walk between; runs follow this graph so they don't cut through mountains
WALK = [(1429, 1436), (1429, 1433), (1429, 1431), (1429, 1453), (1436, 1431), (1431, 1433), (1431, 1434),
        (1431, 1430), (1430, 1435), (1435, 1419), (1433, 1428), (1428, 1427), (1418, 1432),
        (1432, 1426), (1426, 1455), (1432, 1437), (1437, 1417), (1417, 1424), (1424, 1416), (1424, 1421),
        (1424, 1425), (1421, 1420), (1420, 1422), (1422, 1423), (1416, 1421), (1416, 1422),
        (2548, 1433), (2548, 1418), (2548, 1435), (2548, 1428),  # Riverglades (Forever, from the wiki)
        (2652, 1443), (2652, 1444),  # Shen'dralas (Forever guides)
        (2482, 1452),  # Mount Hyjal via Darkwhisper Gorge (Forever guides)
        (1439, 1440), (1440, 1442), (1440, 1413), (1440, 1448), (1440, 1447), (1442, 1443), (1442, 1413),
        (1443, 1444), (1413, 1445), (1413, 1441), (1413, 1411), (1413, 1412), (1441, 1444), (1441, 1446),
        (1446, 1449), (1449, 1451), (1448, 1452), (1448, 1450), (1452, 1450)]
# Searing Gorge's Badlands gate is locked in Classic, so the way in is from Burning Steppes
TRAM = (1453, 1455)    # Deeprun Tram
TRAM_SECONDS = 150
# boats within a continent: (dock A, dock B, seconds incl. waiting)
FERRIES = [((1438, 55.0, 96.5), (1439, 33.2, 40.3), 240)]  # Rut'theran Village (Teldrassil) <-> Auberdine
WALK += [(1438, 1457)]  # Teldrassil <-> Darnassus
# Horde-only: capitals, and the Undercity <-> Grom'gol zeppelin
HORDE_WALK = [(1411, 1454), (1412, 1456), (1420, 1458)]
HORDE_FERRIES = [((1420, 61.8, 59.2), (1434, 31.4, 29.9), 420)]  # Tirisfal tower <-> Grom'gol
ALLIANCE_CITIES = {1453, 1455, 1457}   # Stormwind, Ironforge, Darnassus; Horde can't run through
HORDE_CITIES = {1454, 1456, 1458}      # Orgrimmar, Thunder Bluff, Undercity


def ferries():
    return HORDE_FERRIES if FACTION == "Horde" else FERRIES


def ferry(m, n):
    """(dock on m, dock on n, seconds) when a boat links maps m and n, else None."""
    for a, b, t in ferries():
        if (a[0], b[0]) == (m, n):
            return a, b, t
        if (b[0], a[0]) == (m, n):
            return b, a, t
    return None
DETOUR = 1.15          # roads aren't straight lines


def continent(m):
    b = pz.BOUNDS.get(m)
    return b[0] if b else None


def _neighbours(m):
    if FACTION == "Horde":
        edges = [e for e in WALK + HORDE_WALK if not set(e) & ALLIANCE_CITIES]
    else:
        edges = WALK + [TRAM]
    for x, y in edges + [(a[0], b[0]) for a, b, _ in ferries()]:
        if x == m:
            yield y
        elif y == m:
            yield x


# lowest mob level per zone; walk_path avoids zones over PLAYER_LEVEL + ZONE_GAP (None = no limit)
ZONE_MIN = {1418: 35, 2548: 35, 1427: 43, 1428: 50, 1419: 45, 1430: 55, 1435: 35, 1416: 30, 1417: 30,
            1425: 40, 1434: 30, 1424: 20, 1437: 20, 1431: 18, 1440: 18, 1442: 15, 1443: 30, 1441: 25, 1445: 35,
            1444: 40, 1446: 40, 1422: 50, 1423: 53, 1447: 45, 1448: 47, 1449: 48, 1451: 54, 1452: 53,
            2652: 40, 2482: 55}
ZONE_GAP = 5
PLAYER_LEVEL = None


def walk_path(ma, mb):
    """List of maps from ma to mb, or None."""
    import heapq
    if ma == mb:
        return [ma]
    centre = lambda m: (m, 50.0, 50.0)  # noqa: E731
    dist, prev, heap = {ma: 0.0}, {}, [(0.0, ma)]
    while heap:
        d, m = heapq.heappop(heap)
        if m == mb:
            path = [m]
            while m in prev:
                m = prev[m]
                path.append(m)
            return path[::-1]
        if d > dist.get(m, 1e18):
            continue
        for n in _neighbours(m):
            if n != mb and PLAYER_LEVEL is not None and ZONE_MIN.get(n, 0) > PLAYER_LEVEL + ZONE_GAP:
                continue  # too dangerous to run through
            fe = ferry(m, n)
            if {m, n} == set(TRAM):
                step = TRAM_SECONDS * pz.RUN_SPEED
            elif fe:
                step = pz.yards(centre(m), fe[0]) + fe[2] * pz.RUN_SPEED + pz.yards(fe[1], centre(n))
            else:
                step = pz.yards(centre(m), centre(n))
            if step >= 1e8:
                continue
            if d + step < dist.get(n, 1e18):
                dist[n], prev[n] = d + step, m
                heapq.heappush(heap, (d + step, n))
    return None


def run_seconds(a, b):
    """Seconds on foot from a to b, inf if there's no way."""
    path = walk_path(a[0], b[0])
    if not path:
        return float("inf")
    pts = [a] + [(m, 50.0, 50.0) for m in path[1:-1]] + [b]
    secs = 0.0
    for p, q in zip(pts, pts[1:]):
        if {p[0], q[0]} == set(TRAM):
            secs += TRAM_SECONDS
        elif ferry(p[0], q[0]):
            da, db, t = ferry(p[0], q[0])
            secs += (pz.yards(p, da) + pz.yards(db, q)) * DETOUR / pz.RUN_SPEED + t
        else:
            secs += pz.yards(p, q) * DETOUR / pz.RUN_SPEED
    return secs


def travel_seconds(a, b, fms):
    if b is None or a is None:
        return 0
    if continent(a[0]) != continent(b[0]):
        best = float("inf")
        for da, db, secs in crossings():
            if continent(da[0]) != continent(a[0]) or continent(db[0]) != continent(b[0]):
                continue
            best = min(best, travel_seconds(a, da, fms) + secs + travel_seconds(db, b, fms))
        return best
    run = run_seconds(a, b)
    same = [f for f in fms if continent(f[0]) == continent(a[0])]
    if not same:
        return run
    fa = min(same, key=lambda f: run_seconds(a, f))
    fb = min(same, key=lambda f: run_seconds(f, b))
    fly = run_seconds(a, fa) + run_seconds(fb, b) + pz.yards(fa, fb) / FLIGHT_SPEED + FLIGHT_OVERHEAD
    return min(run, fly)


def replay(comp, upto, order_name="ORDER"):
    order = bg.read_order(order_name)
    if upto:
        order = order[:order.index(upto) + 1]
    pos, known = None, []
    for rf in order:
        h, st = bg.parse_route(os.path.join(bg.ROUTES, rf))
        g = comp.compile_guide(h, st)
        for s in g["steps"]:
            if "x" in s:
                pos = (s.get("map") or g["map"], s["x"], s["y"])
                if "getfp" in s:
                    known.append(pos)
    return pos, known


def horizon_rate(pl, steps, cands, start, trip, horizon):
    """XP/h over the first `horizon` seconds of the plan, trip included."""
    lo, hi = 1, len(steps)
    while lo < hi:  # shortest prefix that takes at least `horizon`
        mid = (lo + hi) // 2
        _, secs, _ = pl.evaluate(steps[:mid], cands, start)
        if secs + trip >= horizon:
            hi = mid
        else:
            lo = mid + 1
    xp, secs, _ = pl.evaluate(steps[:lo], cands, start)
    used = secs + trip
    if used < horizon:
        # short zone: add the trip back and grind the rest, so a far zone with little to do doesn't win
        used += trip
        xp += pl.grind_rate(pl.c.est_level()) * max(0, horizon - used)
        used = max(used, horizon)
    return xp / max(used, 1) * 3600


def evaluate_zone(data, comp, zmap, level, pos, races, faction, fms, span=8, min_rate=pz.MIN_RATE,
                  horizon=5400):
    xp0, nturned = comp.xp_total, len(comp.turned)
    try:
        pl = pz.Planner(data, comp, zmap, int(level), int(level) + span, races, faction)
        cands = pl.candidates()
        if not cands:
            return None
        givers = [g[0] for c in cands.values() for g in (c["giver"] or [])]
        if not givers:
            return None
        start = min(givers, key=lambda g: travel_seconds(pos, g, fms)) if pos else givers[0]
        trip = travel_seconds(pos, start, fms) if pos else 0
        steps, cands = pl.plan(start, min_rate)
        xp, secs = pl.summary
        comp.xp_total, comp.turned[nturned:] = xp0, []
        hrate = horizon_rate(pl, steps, cands, start, trip, horizon)
        nq = sum(1 for s in steps if s[0] == "turnin")
        return {"xp": xp, "secs": secs, "trip": trip, "quests": nq, "end": pz.bg.level_from_xp(xp0 + xp),
                "rate": xp / max(secs + trip, 1) * 3600, "hrate": hrate, "start": start}
    finally:
        comp.xp_total = xp0
        del comp.turned[nturned:]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--upto")
    ap.add_argument("--order", default="ORDER", help="track to replay: ORDER (main) or ORDER.<Race>")
    ap.add_argument("--zones", help="comma-separated uiMap IDs (default: all of the faction's zones)")
    ap.add_argument("--level", type=float, help="pretend to be this level (grinds the difference)")
    ap.add_argument("--races", default="Human")
    ap.add_argument("--faction", default="Alliance")
    ap.add_argument("--span", type=int, default=8, help="quests up to this many levels above you")
    ap.add_argument("--horizon", type=float, default=90, help="minutes to compare zones over")
    ap.add_argument("--from", dest="frm", help="x,y,map: start the trips here instead of the route's end")
    a = ap.parse_args()

    global FACTION
    FACTION = a.faction
    data = bg.Data()
    comp = bg.Compiler(data)
    pos, known = replay(comp, a.upto, a.order)
    if a.frm:
        f = [float(v) for v in a.frm.split(",")]
        pos = (int(f[2]), f[0], f[1])
    if a.level:
        comp.xp_total = max(comp.xp_total, sum(bg.XP_TO_LEVEL[1:int(a.level)]))
    level = comp.est_level()
    fms = known  # only flight paths the route has picked up
    zones = [int(z) for z in a.zones.split(",")] if a.zones else FACTION_ZONES[a.faction]
    print("from level %.1f at %s, %d quests done" % (level, pos, len(comp.turned)))
    rows = []
    for z in zones:
        r = evaluate_zone(data, comp, z, level, pos, [x.strip() for x in a.races.split(",")], a.faction, fms, a.span,
                          horizon=a.horizon * 60)
        if r:
            rows.append((z, r))
    rows.sort(key=lambda zr: -zr[1]["hrate"])
    print("%-22s %8s %8s %6s %6s %5s %6s" % ("zone", "XP/h@%d" % a.horizon, "XP/h all", "min", "trip", "qst", "->lvl"))
    for z, r in rows:
        print("%-22s %8.0f %8.0f %6.0f %6.1f %5d %6.1f" % (zone_name(z, z), r["hrate"], r["rate"], r["secs"] / 60,
                                                         r["trip"] / 60, r["quests"], r["end"]))


if __name__ == "__main__":
    main()
