"""Real leveling times next to the route model's estimate.

Usage: python level_times.py [SavedVariables file]
Writes reports/level_times.txt. Play with the addon on, then /reload or log out so the game saves the times.
"""
import glob
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
from check_recorded import SV_GLOB, LuaReader  # noqa: E402

BANDS = [(1, 9), (10, 19), (20, 29), (30, 39), (40, 49), (50, 59)]
TRACKS = {"Human": "main", "NightElf": "NightElf", "Dwarf": "Dwarf", "Gnome": "Dwarf", "Skyborne": "SkyborneA"}


def load(path):
    src = open(path, encoding="utf-8").read()
    m = re.search(r"^QuestfarerDB\s*=\s*", src, re.M)
    if not m:
        return {}
    db = LuaReader(src[m.end():]).value()
    return db.get("times") or {}


def model_bands(track, cls):
    """Hours per band for this class on this track, or None."""
    out = subprocess.run([sys.executable, os.path.join(ROOT, "simulate.py"), track, "--class", cls],
                         capture_output=True, text=True, cwd=ROOT).stdout
    m = re.search(r"^\s*%s\s+[\d.]+ h.*\|\s*([\d./ ]+)$" % cls, out, re.M)
    return [float(x) for x in m.group(1).split("/")] if m else None


def main():
    files = sys.argv[1:] or glob.glob(SV_GLOB)
    if not files:
        print("No SavedVariables found. Play with the addon on, then /reload or log out.")
        return
    lines = []
    for path in files:
        for char, data in sorted(load(path).items()):
            levels = {int(k): v for k, v in (data.get("levels") or {}).items()}
            cls, race = data.get("class"), data.get("race")
            top = max(levels) if levels else 0
            lines.append("%s (%s %s), measured up to level %d" % (char, race, cls, top))
            for lv in sorted(levels):
                lines.append("  level %2d  %6.1f min" % (lv, levels[lv] / 60))
            track = TRACKS.get(race)
            model = model_bands(track, cls) if track and cls else None
            lines.append("  band     real h   model h   (only bands you have played all of)")
            for i, (lo, hi) in enumerate(BANDS):
                if all(lv in levels for lv in range(lo, hi + 1)):
                    real = sum(levels[lv] for lv in range(lo, hi + 1)) / 3600
                    lines.append("  %2d-%-2d   %7.1f   %7s" % (lo, hi, real, "%.1f" % model[i] if model else "-"))
            lines.append("")
    text = "\n".join(lines) or "No measured times yet."
    os.makedirs(os.path.join(ROOT, "reports"), exist_ok=True)
    with open(os.path.join(ROOT, "reports", "level_times.txt"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text + "\n")
    print(text)


if __name__ == "__main__":
    main()
