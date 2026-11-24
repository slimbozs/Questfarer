"""Insert a hand-written block into a route after the first line that starts with a given text.

Usage: python -I splice.py routes/X.route "turnin 13" routes/hand/X.block
"""
import sys

route, after, block = sys.argv[1:4]
lines = open(route, encoding="utf-8").read().split("\n")
add = open(block, encoding="utf-8").read().rstrip("\n").split("\n")
for i, line in enumerate(lines):
    if " ".join(line.split("#")[0].split()) == " ".join(after.split()):
        lines[i + 1:i + 1] = add
        break
else:
    sys.exit("no line '%s' in %s" % (after, route))
open(route, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print("spliced after", after)
