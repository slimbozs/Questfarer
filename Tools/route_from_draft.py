"""Turn a plan_zone.py draft into a route: head + draft steps (comments stripped) + optional tail.

Usage:
    python -I route_from_draft.py routes/drafts/X.route routes/X.route head.txt [tail.txt]
    (use - for head.txt to read it from stdin)
"""
import re
import sys


def body(draft):
    out = []
    for line in open(draft, encoding="utf-8"):
        if line.startswith("#") or not line.strip():
            continue
        if re.match(r"(guide|file|faction|races|levels|map|next) ", line):
            continue
        out.append(line.split("#")[0].rstrip())
    return out


def main():
    draft, dest, head = sys.argv[1:4]
    tail = sys.argv[4] if len(sys.argv) > 4 else None
    head_text = sys.stdin.read() if head == "-" else open(head, encoding="utf-8").read()
    text = head_text.rstrip("\n") + "\n\n" + "\n".join(body(draft)) + "\n"
    if tail:
        text += "\n" + open(tail, encoding="utf-8").read().rstrip("\n") + "\n"
    with open(dest, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    print("wrote", dest)


if __name__ == "__main__":
    main()
