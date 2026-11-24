"""Find where walkable zones meet (clusters of nearby spawns), for the crossings in Data/Paths.lua.

Usage:  python find_crossings.py [mapA mapB]
"""
import math
import sys
from collections import defaultdict

import build_guides as bg
import compare_zones as cz
import plan_zone as pz

NEAR = 120       # yards, spawn pair this close = meeting point
CLUSTER = 300   # yards, meeting points this close = same crossing
CELL = NEAR


def map_coords(m, wx, wy):
    cont, left, right, top, bottom = pz.BOUNDS[m]
    return round((left - wy) / (left - right) * 100, 1), round((top - wx) / (top - bottom) * 100, 1)


def spawn_points(data):
    by_map = defaultdict(list)
    for kind, table in (("npc", data.npcs), ("object", data.objects)):
        for eid in table:
            for p in data.points(kind, eid):
                w = pz.world(p)
                if w:
                    by_map[p[0]].append((w[1], w[2]))
    return by_map


def grid(points):
    g = defaultdict(list)
    for p in points:
        g[(int(p[0] // CELL), int(p[1] // CELL))].append(p)
    return g


def meetings(pa, gb):
    out = []
    for p in pa:
        cx, cy = int(p[0] // CELL), int(p[1] // CELL)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for q in gb.get((cx + dx, cy + dy), ()):
                    if math.hypot(p[0] - q[0], p[1] - q[1]) <= NEAR:
                        out.append(((p[0] + q[0]) / 2, (p[1] + q[1]) / 2))
    return out


def clusters(points):
    cl = []
    for p in points:
        for c in cl:
            if math.hypot(p[0] - c["x"], p[1] - c["y"]) <= CLUSTER:
                c["pts"].append(p)
                n = len(c["pts"])
                c["x"] += (p[0] - c["x"]) / n
                c["y"] += (p[1] - c["y"]) / n
                break
        else:
            cl.append({"x": p[0], "y": p[1], "pts": [p]})
    return sorted(cl, key=lambda c: -len(c["pts"]))


def main():
    data = bg.Data()
    pts = spawn_points(data)
    edges = cz.WALK + cz.HORDE_WALK + [cz.TRAM]
    if len(sys.argv) == 3:
        edges = [(int(sys.argv[1]), int(sys.argv[2]))]
    for a, b in edges:
        if a not in pz.BOUNDS or b not in pz.BOUNDS or pz.BOUNDS[a][0] != pz.BOUNDS[b][0]:
            print(f"{a}-{b}: different continents / no bounds")
            continue
        cl = clusters(meetings(pts[a], grid(pts[b])))
        if not cl:
            print(f"{a}-{b}: no meeting points")
            continue
        out = []
        for c in cl[:4]:
            xa, ya = map_coords(a, c["x"], c["y"])
            xb, yb = map_coords(b, c["x"], c["y"])
            out.append(f"[{len(c['pts'])}] {a}@{xa},{ya} = {b}@{xb},{yb}")
        print(f"{a}-{b}: " + " | ".join(out))


if __name__ == "__main__":
    main()
