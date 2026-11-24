"""Compare generated guides with the hand-written reference copies (Tools/reference)."""
import math
import os
import re

ROOT = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(os.path.dirname(ROOT), "Questfarer", "Guides")
STEP_RE = re.compile(r'\{\s*(accept|turnin|complete|train|level|getfp|sethearth)\s*=\s*(\{[^}]*\}|"[^"]*"|\d+)(.*?)\}\s*,', re.S)
NPC_RE = re.compile(r'npc\s*=\s*"((?:[^"\\]|\\.)*)"')


def steps(path):
    src = open(path, encoding="utf-8").read()
    out = {}
    for m in STEP_RE.finditer(src):
        body = m.group(3)
        cls = re.search(r'class\s*=\s*"(\w+)"', body)
        x = re.search(r"\bx\s*=\s*([\d.]+)", body)
        y = re.search(r"\by\s*=\s*([\d.]+)", body)
        npc = NPC_RE.search(body)
        key = (m.group(1), re.sub(r"\s", "", m.group(2)), cls.group(1) if cls else "")
        n = 0
        while key + (n,) in out:
            n += 1
        out[key + (n,)] = (float(x.group(1)) if x else None, float(y.group(1)) if y else None,
                           npc.group(1) if npc else None)
    return out


for f in ("Human_Northshire.lua", "Human_Elwynn.lua"):
    ref, gen = steps(os.path.join(ROOT, "reference", f)), steps(os.path.join(GEN, f))
    print("==", f, len(ref), "ref steps,", len(gen), "generated")
    for k, (rx, ry, rn) in ref.items():
        g = gen.get(k)
        if not g:
            print("  missing in generated:", k)
            continue
        gx, gy, gn = g
        d = math.hypot(rx - gx, ry - gy) if None not in (rx, ry, gx, gy) else None
        flag = []
        if d is None or d > 1.0:
            flag.append("dist %s" % (None if d is None else round(d, 1)))
        if rn and gn and rn != gn:
            flag.append("npc %r -> %r" % (rn, gn))
        if flag:
            print("  %-40s ref (%s,%s) gen (%s,%s)  %s" % (k[:3], rx, ry, gx, gy, "; ".join(flag)))
