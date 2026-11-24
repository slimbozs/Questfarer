"""Compare what the in-game recorder saw with the QuestieDB data and the generated guides.

Usage:  python -I check_recorded.py [path\\to\\Questfarer.lua]

Without a path it looks in E:\\World of Warcraft\\_forever_\\WTF\\Account\\*\\SavedVariables\\.
Writes Tools/reports/recorded_diff.txt.
"""
import glob
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
import build_guides as bg  # noqa: E402

SV_GLOB = r"E:\World of Warcraft\_forever_\WTF\Account\*\SavedVariables\Questfarer.lua"
FAR = 2.0  # map-% distance that counts as "different"


class LuaReader:
    TOKEN = re.compile(r"""\s*(?:--[^\n]*\n\s*)*(?:
        (?P<str>"(?:[^"\\]|\\.)*")|
        (?P<num>-?\d+\.?\d*(?:[eE][-+]?\d+)?)|
        (?P<name>[A-Za-z_]\w*)|
        (?P<sym>[{}\[\]=,;]))""", re.X | re.S)

    def __init__(self, src):
        self.toks = []
        pos = 0
        while pos < len(src):
            m = self.TOKEN.match(src, pos)
            if not m:
                if src[pos:].strip() == "":
                    break
                raise ValueError("cannot parse at %d: %r" % (pos, src[pos:pos + 40]))
            pos = m.end()
            kind = m.lastgroup
            self.toks.append((kind, m.group(kind)))
        self.i = 0

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else (None, None)

    def next(self):
        t = self.peek()
        self.i += 1
        return t

    def value(self):
        kind, v = self.next()
        if kind == "str":
            return bytes(v[1:-1], "utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8", "replace")
        if kind == "num":
            return float(v) if any(c in v for c in ".eE") else int(v)
        if kind == "name":
            return {"true": True, "false": False, "nil": None}.get(v, v)
        if v == "{":
            return self.table()
        raise ValueError("unexpected %r" % v)

    def table(self):
        out, n = {}, 1
        while True:
            kind, v = self.peek()
            if v == "}":
                self.next()
                return out
            if v == "[":
                self.next()
                key = self.value()
                self.next()  # ]
                self.next()  # =
                out[key] = self.value()
            elif kind == "name" and self.toks[self.i + 1][1] == "=":
                self.next()
                self.next()
                out[v] = self.value()
            else:
                out[n] = self.value()
                n += 1
            if self.peek()[1] in (",", ";"):
                self.next()

    def assignments(self):
        out = {}
        while self.i < len(self.toks):
            _, name = self.next()
            self.next()  # =
            out[name] = self.value()
        return out


def guide_steps():
    """[(file, kind, qids, map, x, y, where)] from the generated guides."""
    out = []
    for path in glob.glob(os.path.join(bg.OUT, "*.lua")):
        src = open(path, encoding="utf-8").read()
        gmap = re.search(r"^\s*map = (\d+),", src, re.M)
        gmap = int(gmap.group(1)) if gmap else None
        for line in src.splitlines():
            m = re.match(r"\s*\{ (accept|turnin|complete) = (\{[^}]*\}|\d+), (.*)\}, -- (.*)$", line)
            if not m:
                continue
            body = m.group(3)
            x = re.search(r"\bx = ([\d.]+)", body)
            y = re.search(r"\by = ([\d.]+)", body)
            mp = re.search(r"\bmap = (\d+)", body)
            qids = [int(q) for q in re.findall(r"\d+", m.group(2))]
            if x and y:
                out.append((os.path.basename(path), m.group(1), qids, int(mp.group(1)) if mp else gmap,
                            float(x.group(1)), float(y.group(1)), m.group(4)))
    return out


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def main():
    paths = sys.argv[1:] or glob.glob(SV_GLOB)
    if not paths:
        print("No SavedVariables found. Play with /fg record on, then /reload or log out.")
        return
    data = bg.Data()
    rec = {"quests": {}, "npcs": {}, "trainers": {}, "taxi": {}, "log": {}}
    for p in paths:
        sv = LuaReader(open(p, encoding="utf-8", errors="replace").read()).assignments()
        db = sv.get("QuestfarerRecorderDB") or {}
        for k in rec:
            if isinstance(db.get(k), dict):
                rec[k].update(db[k])
        print("read", p)

    lines = []
    quests = rec["quests"]

    lines.append("== Quests seen in-game that are NOT in the Forever DB")
    for qid, q in sorted(quests.items()):
        if not data.quest(qid):
            a = q.get("accept") or {}
            lines.append("  %6s  %-40s from %s (id %s) map %s %.1f, %.1f  lvl %s" % (
                qid, q.get("title"), a.get("npc"), a.get("npcId"), a.get("map"),
                a.get("x") or 0, a.get("y") or 0, a.get("level")))

    lines.append("")
    lines.append("== Quest givers / turn-ins that differ from the DB")
    for qid, q in sorted(quests.items()):
        dq = data.quest(qid)
        if not dq:
            continue
        for field, key in (("startedBy", "accept"), ("finishedBy", "turnin")):
            w = q.get(key)
            if not w or not w.get("npcId") or w.get("kind") not in ("Creature", "GameObject"):
                continue
            npcs, objs, _ = data.givers(dq.get(field))
            ids = npcs if w["kind"] == "Creature" else objs
            if w["npcId"] not in ids:
                lines.append("  %6s %-36s %s: in-game %s (%s), DB has %s" % (
                    qid, dq.get("name"), key, w.get("npc"), w["npcId"], ids))
                continue
            pts = data.points("npc" if w["kind"] == "Creature" else "object", w["npcId"])
            here = [p for p in pts if p[0] == w.get("map")]
            if here and w.get("x") is not None:
                d = min(dist((p[1], p[2]), (w["x"], w["y"])) for p in here)
                if d > FAR:
                    lines.append("  %6s %-36s %s: %s stands at %.1f, %.1f in-game, DB is %.1f away" % (
                        qid, dq.get("name"), key, w.get("npc"), w["x"], w["y"], d))

    lines.append("")
    lines.append("== Guide steps far from where you actually were (fix with @x,y in the route)")
    for f, kind, qids, mp, x, y, where in guide_steps():
        q = quests.get(qids[0]) or {}
        if kind in ("accept", "turnin"):
            w = q.get(kind)
            if w and w.get("map") == mp and w.get("x") is not None:
                d = dist((x, y), (w["x"], w["y"]))
                if d > FAR:
                    lines.append("  %-28s %-7s %6d guide %.1f, %.1f  in-game %.1f, %.1f  (%.1f)" % (
                        where, kind, qids[0], x, y, w["x"], w["y"], d))
        else:
            pts = []
            for qid in qids:
                for plist in ((quests.get(qid) or {}).get("points") or {}).values():
                    pts += [(p["x"], p["y"]) for p in plist.values()] if isinstance(plist, dict) else []
            if pts:
                d = min(dist((x, y), p) for p in pts)
                cx = sum(p[0] for p in pts) / len(pts)
                cy = sum(p[1] for p in pts) / len(pts)
                if d > FAR * 2:
                    lines.append("  %-28s complete %s guide %.1f, %.1f  progress happened around %.1f, %.1f (%d points)" % (
                        where, qids, x, y, cx, cy, len(pts)))

    lines.append("")
    lines.append("== Class trainers seen")
    for nid, t in sorted(rec["trainers"].items()):
        n = rec["npcs"].get(nid) or {}
        lines.append("  %-24s %-8s id %-6s map %s %.1f, %.1f  %d services" % (
            t.get("name"), t.get("class") or t.get("tradeskill") and "prof", nid, n.get("map"),
            n.get("x") or 0, n.get("y") or 0, len(t.get("services") or {})))

    lines.append("")
    lines.append("== Flight paths seen")
    for node, e in sorted(rec["taxi"].items()):
        if isinstance(e, dict) and e.get("npc"):  # taxi list has nil holes for unseen nodes
            lines.append("  node %-4s %-34s %s (id %s) map %s %.1f, %.1f" % (
                node, e.get("name"), e.get("npc"), e.get("npcId"), e.get("map"), e.get("x") or 0, e.get("y") or 0))

    os.makedirs(bg.REPORTS, exist_ok=True)
    out = os.path.join(bg.REPORTS, "recorded_diff.txt")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    print("\nwritten to", out)


if __name__ == "__main__":
    main()
