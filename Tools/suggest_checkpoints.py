"""Route checkpoints from the paths players' arrows learned.

Usage:  python -I import_contributions.py   (first, it checks the exports and writes contributions/merged.json)
        python -I suggest_checkpoints.py

Writes Tools/reports/checkpoints.txt. Only map IDs and numbers come from the players, the step names are
read from our own guides. Nothing is changed: copy a {cp=...} into the route by hand if it looks right.
"""
import glob
import json
import math
import os
import re

ROOT = os.path.dirname(os.path.abspath(__file__))
MERGED = os.path.join(ROOT, "contributions", "merged.json")
GUIDES = os.path.join(ROOT, "..", "Questfarer", "Guides", "*.lua")
PATHS_LUA = os.path.join(ROOT, "..", "Questfarer", "Paths.lua")
REPORT = os.path.join(ROOT, "reports", "checkpoints.txt")

LEARN_TYPES = ("accept", "turnin", "getfp", "fly", "sethearth", "go", "train")
SAME_START = 250    # yards: paths starting this close came the same way
NEAR_STEP = 80      # yards: points this close to the step are left out, like the arrow does
SEED_FAR = 150      # yards: a learned crossing this far from the estimate is a different one

STEP = re.compile(r"^\s*\{ (%s) = ([^,]+),(.*)\}, -- (\S+)$" % "|".join(LEARN_TYPES))
FIELD = {k: re.compile(r"\b%s = (-?[\d.]+)" % k) for k in ("map", "x", "y")}
TEXT = {k: re.compile(r'\b%s = "((?:[^"\\]|\\.)*)"' % k) for k in ("title", "npc")}
SEED = re.compile(r"\{ (\d+), (\d+), (\d+), ([\d.]+), ([\d.]+), \"([^\"]*)\" \}")


def num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def guide_steps():
    """step key -> [(route ref, description, has checkpoints)]"""
    steps = {}
    for path in sorted(glob.glob(GUIDES)):
        with open(path, encoding="utf-8") as fh:
            src = fh.read()
        m = re.search(r"^    map = (\d+),$", src, re.M)
        guide_map = int(m.group(1)) if m else 0
        for line in src.splitlines():
            s = STEP.match(line)
            if not s:
                continue
            kind, what, rest, ref = s.groups()
            f = {k: r.search(rest) for k, r in FIELD.items()}
            if not (f["x"] and f["y"]):
                continue
            mp = int(f["map"].group(1)) if f["map"] else guide_map
            key = "%d:%.1f:%.1f" % (mp, float(f["x"].group(1)), float(f["y"].group(1)))
            t = {k: r.search(rest) for k, r in TEXT.items()}
            desc = "%s %s" % (kind, what.strip('"'))
            if t["title"]:
                desc += " " + t["title"].group(1)
            if t["npc"]:
                desc += " (%s)" % t["npc"].group(1)
            steps.setdefault(key, []).append((ref, desc, " via = " in rest))
    return steps


def seeds():
    with open(PATHS_LUA, encoding="utf-8") as fh:
        src = fh.read()
    out = {}
    for a, b, mp, x, y, name in SEED.findall(src):
        a, b = sorted((int(a), int(b)))
        out.setdefault("%d-%d" % (a, b), []).append((int(mp), float(x), float(y), name))
    return out


def yards(size, a, b):
    w, h = size
    return math.hypot((a[0] - b[0]) * w / 100, (a[1] - b[1]) * h / 100)


def load():
    with open(MERGED, encoding="utf-8") as fh:
        data = json.load(fh)
    return [c for c in data if isinstance(c, dict) and isinstance(c.get("paths"), dict)]


def fmt(p):
    return "%.1f,%.1f" % (p[0], p[1])


def main():
    contribs = load()
    steps = guide_steps()
    sizes, by_step, crossings = {}, {}, {}
    for c in contribs:
        cid = str(c.get("id"))[:8]
        p = c["paths"]
        for mp, wh in p.get("maps", {}).items():
            if isinstance(wh, list) and len(wh) == 2 and all(num(x) and x > 0 for x in wh):
                sizes[mp] = wh
        for key, paths in p.get("learned", {}).items():
            for path in paths:
                by_step.setdefault(key, []).append((cid, path["start"], path["via"]))
        for key, pts in p.get("crossings", {}).items():
            for x, y, n in pts:
                crossings.setdefault(key, []).append((cid, (x, y), n))

    strong, weak, covered, gone = [], [], [], 0
    for key, paths in sorted(by_step.items()):
        here = steps.get(key)
        if not here:
            gone += 1
            continue
        mp, sx, sy = key.split(":")
        size = sizes.get(mp)
        if not size:
            continue
        target = (float(sx), float(sy))
        # one group per direction the players came from
        groups = []
        for cid, start, via in paths:
            for g in groups:
                if yards(size, g["start"], start) <= SAME_START:
                    g["who"].add(cid)
                    break
            else:
                groups.append({"start": start, "via": via, "who": {cid}})
        for g in groups:
            pts = [v for v in g["via"] if yards(size, v, target) > NEAR_STEP]
            if not pts:
                continue
            outside = any(not (0 <= v[0] <= 100 and 0 <= v[1] <= 100) for v in pts)
            entry = (len(g["who"]), here, g["start"], pts, outside)
            if any(has_via for _, _, has_via in here):
                covered.append(entry)
            elif len(g["who"]) >= 2:
                strong.append(entry)
            else:
                weak.append(entry)

    def block(entries):
        lines = []
        for n, here, start, pts, outside in sorted(entries, key=lambda e: (-e[0], e[1][0][0])):
            lines.append("  %d player(s), coming from %s%s" % (n, fmt(start),
                                                              "  (a point is outside the step's map)" if outside else ""))
            for ref, desc, _ in here:
                lines.append("    %s  %s" % (ref, desc))
            lines.append("    {cp=%s}" % "/".join(fmt(p) for p in pts))
        return lines or ["  (none)"]

    out = ["Checkpoints from learned paths: %d contributor(s), %d step(s) with paths." % (len(contribs), len(by_step)),
           "A learned path is a run to the step that was much longer than the straight line. It can also be someone",
           "who got lost, so look at the map before you put a {cp=...} in a route.",
           "", "== Steps without checkpoints, two or more players went round the same way"] + block(strong)
    out += ["", "== Steps without checkpoints, one player"] + block(weak)
    out += ["", "== Steps that already have checkpoints (compare by hand)"] + block(covered)
    if gone:
        out.append("\n%d step(s) with paths are no longer in the guides (moved or changed)." % gone)

    seed = seeds()
    out += ["", "== Zone crossings used by two or more players, away from the estimate in Paths.SEED"]
    found = False
    for key, pts in sorted(crossings.items()):
        mp = key.split("-")[0]
        size = sizes.get(mp)
        if not size:
            continue
        merged = []
        for cid, p, n in pts:
            for m in merged:
                if yards(size, m["p"], p) <= SEED_FAR:
                    m["who"].add(cid)
                    m["n"] += n
                    break
            else:
                merged.append({"p": p, "who": {cid}, "n": n})
        known = [(x, y, name) for smp, x, y, name in seed.get(key, []) if str(smp) == mp]
        other = ["\"%s\" is given on map %d, compare by hand" % (name, smp)
                 for smp, x, y, name in seed.get(key, []) if str(smp) != mp]
        for m in merged:
            if len(m["who"]) < 2:
                continue
            near = min(((yards(size, m["p"], (x, y)), name) for x, y, name in known), default=None)
            if near and near[0] <= SEED_FAR:
                continue
            found = True
            if near:
                why = "%.0f yd from \"%s\"" % near
            else:
                why = "; ".join(other) or "no estimate for this pair"
            out.append("  %s at %s on map %s, %d player(s), %d time(s): %s" % (
                key, fmt(m["p"]), mp, len(m["who"]), m["n"], why))
    if not found:
        out.append("  (none)")

    os.makedirs(os.path.dirname(REPORT), exist_ok=True)
    with open(REPORT, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")
    print("%d strong, %d single, %d already covered. Wrote reports/checkpoints.txt" % (len(strong), len(weak),
                                                                                    len(covered)))


if __name__ == "__main__":
    main()
