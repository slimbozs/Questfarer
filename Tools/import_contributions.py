"""Read the play data players chose to share (the export text from the addon's Data page) and summarise it.

Usage:  python -I import_contributions.py [--check] [file or folder ...]

Without paths it reads every .txt and .md file in Tools/contributions/. --check only lists problems, writes nothing.
Writes reports/contributions.txt and contributions/merged.json.

Every contribution is treated as hostile: read as text only, decoded with hard limits, medians over contributors.
Never give an AI assistant the raw files in contributions/ (prompt injection), give it reports/contributions.txt.

Format: "FGDATA1:<export id>:<part>/<parts>:<base64>", the joined base64 is Deflate-compressed CBOR.
"""
import base64
import binascii
import glob
import hashlib
import json
import math
import os
import re
import statistics
import struct
import sys
import unicodedata
import zlib

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)

PREFIX = "FGDATA1:"
HEAD = re.compile(r"^([0-9a-f]{6}):(\d{1,3})/(\d{1,3}):")
B64 = re.compile(r"[A-Za-z0-9+/=\s]+")
CONTRIBUTOR_ID = re.compile(r"^[0-9a-f]{8}$")
BANDS = [(1, 9), (10, 19), (20, 29), (30, 39), (40, 49), (50, 60)]

# hard limits
MAX_FILE = 5 * 1024 * 1024        # bytes per input file
MAX_PARTS = 50                    # per export
MAX_B64 = 4 * 1024 * 1024         # base64 chars per export
MAX_INFLATED = 20 * 1024 * 1024   # bytes after inflating (zip bombs)
MAX_DEPTH = 24                    # CBOR nesting
MAX_ITEMS = 1_000_000             # CBOR items per export
MAX_STRING = 300                  # chars kept from any text
MAX_CHARS = 30                    # game characters per contributor
MAX_CONTRIBUTORS_PER_FILE = 3     # more looks like one person posing as many

# what's possible in game, per level and character
MAX_FIGHT_AVG = 600               # seconds per fight on average
MIN_FIGHT_AVG = 1
MAX_GAP = 181                     # the addon only counts gaps up to 180 s
MAX_LEVEL_HOURS = 40
MAX_KILLS_PER_FIGHT = 6
MAX_QUEST_XP = 20000              # per quest
MAX_GUIDE_HOURS = 60
MIN_FIGHTS = 10                   # per band, fewer says little
OUTLIER = 3.0                     # x median, above/below gets listed

# text allowed into the outputs (prompt injection guard)
WORD = re.compile(r"^[A-Za-z]{1,16}$")                 # class or race token
VERSION = re.compile(r"^[0-9A-Za-z.\-]{1,20}$")         # addon version
KEY = re.compile(r"^[A-Za-z0-9_]{1,24}$")               # recorder data keys
GAME_PUNCT = set(" '\u2019-,.:!?()/&+%")               # besides letters and digits
MAX_GAME_TEXT = 64                 # longest Classic quest titles fit
MAX_GAME_WORDS = 8
LONG_TEXT_KEYS = {"objText", "text"}   # quest objective lines run longer than names
MAX_LONG_TEXT = 160
MAX_LONG_WORDS = 28
SUSPICIOUS = re.compile(
    r"(\b(ignore|disregard|instructions?|prompt|claude|anthropic|assistant|chatgpt|openai|gpt|llm|powershell|cmd|"
    r"bash|terminal|sudo|curl|wget|execute|install|download|password|admin|system|delete|http|https|www|email|"
    r"e-mail|computer|owner|folder|files?|reviewer|approved|model|agent|bot)\b"
    r"|://|\.(exe|ps1|bat|cmd|vbs|js|sh|dll|py|scr|msi)\b)", re.IGNORECASE)
SHOUTED_AI = re.compile(r"\bA\.?I\b")                  # "AI" as a word, in capitals


class Rejected(Exception):
    pass


def input_files(args):
    paths = []
    for a in args or [os.path.join(ROOT, "contributions")]:
        if os.path.isdir(a):
            for p in sorted(glob.glob(os.path.join(a, "*"))):
                if os.path.isfile(p) and os.path.basename(p).lower() != "readme.md":
                    paths.append(p)
        elif os.path.isfile(a):
            paths.append(a)
    return paths


def read_text(path):
    """Text of a sane-sized UTF-8 file, or raises Rejected."""
    name = os.path.basename(path)
    if not name.lower().endswith((".txt", ".md")):
        raise Rejected("not a .txt or .md file - don't open it")
    size = os.path.getsize(path)
    if size > MAX_FILE:
        raise Rejected("file is %d bytes, more than the %d limit" % (size, MAX_FILE))
    with open(path, "rb") as fh:
        raw = fh.read(MAX_FILE + 1)
    if raw[:2] == b"MZ" or raw[:4] in (b"PK\x03\x04", b"\x7fELF") or raw[:5] == b"%PDF-":
        raise Rejected("this is a program or archive, not text - delete it and don't open it")
    if b"\x00" in raw:
        raise Rejected("binary data in the file")
    try:
        return raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        raise Rejected("not UTF-8 text")


def find_parts(text):
    """[(export id, part, parts, base64)] for every FGDATA1 part in the text."""
    found = []
    for seg in text.split(PREFIX)[1:]:
        m = HEAD.match(seg)
        if not m:
            continue
        body = B64.match(seg, m.end())
        if body:
            found.append((m.group(1), int(m.group(2)), int(m.group(3)), re.sub(r"\s+", "", body.group(0))))
    return found


def inflate(raw):
    for wbits in (-15, 15, 31):  # raw Deflate (what the game writes), zlib, gzip
        d = zlib.decompressobj(wbits)
        try:
            out = d.decompress(raw, MAX_INFLATED)
        except zlib.error:
            continue
        if d.unconsumed_tail:
            raise Rejected("unpacks to more than %d MB (a zip bomb?)" % (MAX_INFLATED // 2**20))
        return out
    raise Rejected("not Deflate data")


class SafeCBOR:
    def __init__(self, data):
        self.d, self.i, self.items = data, 0, 0

    def need(self, n):
        if n < 0 or self.i + n > len(self.d):
            raise Rejected("CBOR length runs past the end of the data")

    def byte(self):
        self.need(1)
        b = self.d[self.i]
        self.i += 1
        return b

    def arg(self, info):
        if info < 24:
            return info
        if info not in (24, 25, 26, 27):
            raise Rejected("CBOR with indefinite or reserved length")
        n = {24: 1, 25: 2, 26: 4, 27: 8}[info]
        self.need(n)
        v = int.from_bytes(self.d[self.i:self.i + n], "big")
        self.i += n
        return v

    def item(self, depth=0):
        if depth > MAX_DEPTH:
            raise Rejected("data nested deeper than %d" % MAX_DEPTH)
        self.items += 1
        if self.items > MAX_ITEMS:
            raise Rejected("more than %d items" % MAX_ITEMS)
        ib = self.byte()
        major, info = ib >> 5, ib & 31
        if major == 0:
            return self.arg(info)
        if major == 1:
            return -1 - self.arg(info)
        if major in (2, 3):
            n = self.arg(info)
            self.need(n)
            s = self.d[self.i:self.i + n]
            self.i += n
            return s.decode("utf-8", "replace") if major == 3 else s.decode("latin-1")
        if major in (4, 5):
            n = self.arg(info)
            self.need(n * (1 if major == 4 else 2))  # every item takes at least one byte
            if major == 4:
                return [self.item(depth + 1) for _ in range(n)]
            out = {}
            for _ in range(n):
                k = self.item(depth + 1)
                if not isinstance(k, (str, int)) or isinstance(k, bool):
                    raise Rejected("a map key that is not text or a number")
                out[str(k)] = self.item(depth + 1)
            return out
        if major == 6:
            self.arg(info)
            return self.item(depth + 1)
        if info == 20:
            return False
        if info == 21:
            return True
        if info in (22, 23):
            return None
        if info in (25, 26, 27):
            n = {25: 2, 26: 4, 27: 8}[info]
            self.need(n)
            v = struct.unpack({2: ">e", 4: ">f", 8: ">d"}[n], self.d[self.i:self.i + n])[0]
            self.i += n
            return v if math.isfinite(v) else None  # NaN and infinity count as missing
        raise Rejected("unknown CBOR value")


def decode(parts, n):
    if not 1 <= n <= MAX_PARTS:
        raise Rejected("%d parts (at most %d)" % (n, MAX_PARTS))
    missing = [i for i in range(1, n + 1) if i not in parts]
    if missing:
        raise Rejected("missing part(s) %s of %d" % (missing, n))
    b64 = "".join(parts[i] for i in range(1, n + 1))
    if len(b64) > MAX_B64:
        raise Rejected("export text is too long")
    try:
        raw = base64.b64decode(b64 + "=" * (-len(b64) % 4), validate=True)
    except (binascii.Error, ValueError):
        raise Rejected("broken base64")
    reader = SafeCBOR(inflate(raw))
    data = reader.item()
    if not isinstance(data, dict) or data.get("format") != 1:
        raise Rejected("not a Questfarer export (format 1)")
    return data


def clean_text(s):
    if not isinstance(s, str):
        return None
    s = "".join(ch for ch in s if unicodedata.category(ch)[0] != "C")
    return s[:MAX_STRING]


def label(s, pattern):
    return s if isinstance(s, str) and pattern.match(s) else None


def safe_file_name(name):
    s = re.sub(r"[^A-Za-z0-9._-]", "_", name)
    return s if len(s) <= 40 else s[:37] + "..."


def game_text(s, longest=MAX_GAME_TEXT, words=MAX_GAME_WORDS):
    s = clean_text(s)
    if not s or len(s) > longest or len(s.split()) > words:
        return None
    if any(not (ch.isalnum() or unicodedata.category(ch)[0] == "M" or ch in GAME_PUNCT) for ch in s):
        return None
    if SUSPICIOUS.search(s) or SHOUTED_AI.search(s):
        return None
    return s


def clean_tree(v, removed, depth=0, long_ok=False):
    """Recorder data with only game-like text; what was taken out is counted in removed[0]."""
    if depth > MAX_DEPTH:
        return None
    if isinstance(v, dict):
        out = {}
        for k, x in v.items():
            if isinstance(k, int) and not isinstance(k, bool):
                key = str(k)
            else:
                # spell names are keys under trainer services
                key = label(k, KEY) or game_text(k)
            if key is None:
                removed[0] += 1
                continue
            out[key] = clean_tree(x, removed, depth + 1, key in LONG_TEXT_KEYS)
        return out
    if isinstance(v, list):
        return [clean_tree(x, removed, depth + 1) for x in v]
    if isinstance(v, str):
        if v == "":
            return v    # spells without a rank
        t = game_text(v, MAX_LONG_TEXT, MAX_LONG_WORDS) if long_ok else game_text(v)
        if t is None:
            removed[0] += 1
        return t
    if isinstance(v, bool) or v is None:
        return v
    if isinstance(v, (int, float)) and math.isfinite(v):
        return v
    return None


def as_map(v):
    if isinstance(v, list):
        return {str(i + 1): x for i, x in enumerate(v)}
    return v if isinstance(v, dict) else {}


def number(v, hi=None):
    if isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) or v < 0:
        return None
    if hi is not None and v > hi:
        return None
    return v


def kill_xp_cap(level):
    # same-level mob XP, x2 elite, x2 rested, x1.5 for higher mobs
    return (level * 5 + 45) * 2 * 2 * 1.5


def check_level(level, l):
    """(clean level dict, None) or (None, reason)."""
    if not isinstance(l, dict):
        return None, "level %d is not a table" % level
    v = {}
    for k in ("f", "fs", "k", "kx", "qx", "q", "g", "gs", "d"):
        x = number(l.get(k, 0))
        if x is None:
            return None, "level %d: %s is not a sane number" % (level, k)
        v[k] = x
    f, k = v["f"], v["k"]
    if f and not MIN_FIGHT_AVG <= v["fs"] / f <= MAX_FIGHT_AVG:
        return None, "level %d: %.1f s per fight" % (level, v["fs"] / f)
    if v["fs"] + v["gs"] > MAX_LEVEL_HOURS * 3600:
        return None, "level %d: more than %d hours" % (level, MAX_LEVEL_HOURS)
    if k > f * MAX_KILLS_PER_FIGHT + 5:
        return None, "level %d: %d kills in %d fights" % (level, k, f)
    if k and v["kx"] / k > kill_xp_cap(level):
        return None, "level %d: %.0f XP per kill" % (level, v["kx"] / k)
    if v["qx"] > (v["q"] + 1) * MAX_QUEST_XP:
        return None, "level %d: %.0f quest XP from %d quests" % (level, v["qx"], v["q"])
    if v["g"] > f + 1 or (v["g"] and v["gs"] / v["g"] > MAX_GAP):
        return None, "level %d: downtime numbers don't fit" % level
    if v["d"] > f + 1:
        return None, "level %d: more deaths than fights" % level
    diff = {}
    for dk, dd in as_map(l.get("diff")).items():
        try:
            dn = int(dk)
        except ValueError:
            return None, "level %d: odd level difference key" % level
        if not -5 <= dn <= 5 or not isinstance(dd, dict):
            return None, "level %d: odd level difference" % level
        df, dfs = number(dd.get("f"), f), number(dd.get("fs"))
        if df is None or dfs is None or (df and not MIN_FIGHT_AVG <= dfs / df <= MAX_FIGHT_AVG):
            return None, "level %d: odd fight times by level difference" % level
        if df:
            diff[dn] = (df, dfs)
    v["diff"] = diff
    return v, None


STEP_KEY = re.compile(r"^\d{3,5}:\d{1,3}\.\d:\d{1,3}\.\d$")    # map:x:y of a guide step
PAIR_KEY = re.compile(r"^\d{3,5}-\d{3,5}$")                     # two zone map IDs
MAX_STEPS = 3000
MAX_PATHS_PER_STEP = 5
MAX_VIA = 20
MAX_CROSSINGS = 10


def map_point(v, extra=0):
    """[x, y] (and extra numbers) in map percent, or None. A path can start a little outside its map."""
    p = list(as_map(v).values())
    if len(p) != 2 + extra or not all(isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x)
                                      for x in p):
        return None
    if not all(-100 <= x <= 200 for x in p[:2]):
        return None
    return p


def check_paths(v):
    """Learned paths and crossings with nothing but map IDs and numbers."""
    v = as_map(v)
    learned, crossings, maps, bad = {}, {}, {}, 0
    for key, paths in list(as_map(v.get("learned")).items())[:MAX_STEPS]:
        if not STEP_KEY.match(str(key)):
            bad += 1
            continue
        keep = []
        for path in list(as_map(paths).values())[:MAX_PATHS_PER_STEP]:
            path = as_map(path)
            start = map_point(path.get("start"))
            via = [map_point(p) for p in list(as_map(path.get("via")).values())[:MAX_VIA + 1]]
            if start and via and len(via) <= MAX_VIA and all(via):
                keep.append({"start": start, "via": via})
            else:
                bad += 1
        if keep:
            learned[key] = keep
    for key, pts in as_map(v.get("crossings")).items():
        if not PAIR_KEY.match(str(key)):
            bad += 1
            continue
        keep = [p for p in (map_point(x, 1) for x in list(as_map(pts).values())[:MAX_CROSSINGS]) if p]
        if keep:
            crossings[key] = [[x, y, int(min(max(n, 1), 10000))] for x, y, n in keep]
    for key, wh in as_map(v.get("maps")).items():
        wh = list(as_map(wh).values())
        if str(key).isdigit() and len(wh) == 2 and all(number(x, 100000) for x in wh):
            maps[str(key)] = wh
    return {"learned": learned, "crossings": crossings, "maps": maps}, bad


def check_contribution(data):
    """(clean contribution, [trim reasons]), or raises Rejected."""
    cid = data.get("id")
    if not isinstance(cid, str) or not CONTRIBUTOR_ID.match(cid):
        raise Rejected("no valid contributor ID")
    chars = as_map(data.get("chars"))
    if len(chars) > MAX_CHARS:
        raise Rejected("%d characters in one export" % len(chars))
    notes, clean_chars, bad, total = [], [], 0, 0
    for char in chars.values():
        if not isinstance(char, dict):
            raise Rejected("a character that is not a table")
        levels = {}
        for key, l in as_map(char.get("levels")).items():
            total += 1
            try:
                level = int(key)
            except ValueError:
                level = 0
            if not 1 <= level <= 60:
                bad += 1
                notes.append("a level key that is not 1-60")
                continue
            v, why = check_level(level, l)
            if why:
                bad += 1
                notes.append(why)
            else:
                levels[level] = v
        clean_chars.append({"class": (label(char.get("class"), WORD) or "?").upper(),
                            "race": label(char.get("race"), WORD), "levels": levels})
    if total and bad / total > 0.3:
        raise Rejected("%d of %d levels have impossible numbers (first: %s)" % (bad, total, notes[0]))
    times = []
    for t in as_map(data.get("times")).values():
        if not isinstance(t, dict):
            continue
        lv = {}
        for key, sec in as_map(t.get("levels")).items():
            s = number(sec, MAX_LEVEL_HOURS * 3600)
            if key.isdigit() and 1 <= int(key) <= 60 and s:
                lv[int(key)] = s
        gd = {}
        for guide, sec in as_map(t.get("guides")).items():
            s = number(sec, MAX_GUIDE_HOURS * 3600)
            name = game_text(guide)
            if name and s:
                gd[name] = s
        times.append({"class": (label(t.get("class"), WORD) or "?").upper(), "levels": lv, "guides": gd})
    if len(times) > MAX_CHARS:
        raise Rejected("%d characters in the time data" % len(times))
    removed = [0]
    recorder = clean_tree(data.get("recorder"), removed)
    if removed[0]:
        notes.append("%d text(s) removed that didn't look like names from the game (code, links or instructions?)"
                     % removed[0])
    paths, bad_paths = check_paths(data.get("paths"))
    if bad_paths:
        notes.append("%d learned path(s) or crossing(s) with odd numbers" % bad_paths)
    return {"id": cid, "made": number(data.get("made")) or 0, "addon": label(data.get("addon"), VERSION),
            "chars": clean_chars, "times": times, "recorder": recorder, "paths": paths}, notes


def fingerprint(c):
    body = [sorted((lv, sorted((k, v) for k, v in d.items() if k != "diff")) for lv, d in ch["levels"].items())
            for ch in c["chars"]]
    return hashlib.sha1(json.dumps(sorted(map(json.dumps, body))).encode()).hexdigest() if any(body) else None


def known_guides():
    names = set()
    for p in glob.glob(os.path.join(ROOT, "..", "Questfarer", "Guides", "*.lua")):
        with open(p, encoding="utf-8", errors="replace") as fh:
            m = re.search(r'^\s*name = "((?:[^"\\]|\\.)*)",\s*$', fh.read(), re.M)
        if m:
            names.add(m.group(1).replace('\\"', '"'))
    return names


def model_reference():
    try:
        import plan_zone as pz
    except Exception as e:  # noqa: BLE001 - the report still works without it
        return ["(plan_zone.py could not be imported: %s)" % e], None
    lines = ["Model: SEC_PER_KILL %s s (quest mobs), GRIND_SEC_PER_KILL %s s (grinding), per kill incl. downtime."
             % (getattr(pz, "SEC_PER_KILL", "?"), getattr(pz, "GRIND_SEC_PER_KILL", "?"))]
    speed = getattr(pz, "CLASS_SPEED", None)
    if isinstance(speed, dict):
        lines.append("Model class speed: " + ", ".join("%s %s" % kv for kv in sorted(speed.items())))
    return lines, getattr(pz, "kill_factor", None)


def collect(paths):
    """(accepted by ID, [(source, problem)], [(source, note)])"""
    rejected, notes = [], []
    parts, counts, sources, conflicts = {}, {}, {}, set()
    for path in paths:
        name = safe_file_name(os.path.basename(path))
        try:
            text = read_text(path)
        except Rejected as e:
            rejected.append((name, str(e)))
            continue
        found = find_parts(text)
        if not found:
            notes.append((name, "no export text in the file"))
        for eid, i, n, b64 in found:
            have = parts.setdefault(eid, {})
            if i in have and have[i] != b64 or eid in counts and counts[eid] != n:
                conflicts.add(eid)
            have[i] = b64
            counts[eid] = n
            sources.setdefault(eid, set()).add(name)

    accepted, by_file, prints = {}, {}, {}
    for eid in parts:
        src = ", ".join(sorted(sources[eid]))
        if eid in conflicts:
            rejected.append((src, "export %s: two different texts for the same part" % eid))
            continue
        try:
            c, trimmed = check_contribution(decode(parts[eid], counts[eid]))
        except Rejected as e:
            rejected.append((src, "export %s: %s" % (eid, e)))
            continue
        except RecursionError:
            rejected.append((src, "export %s: nested too deep" % eid))
            continue
        for why in trimmed[:6]:
            notes.append((src, "left out: " + why))
        for s in sources[eid]:
            by_file.setdefault(s, set()).add(c["id"])
        old = accepted.get(c["id"])
        if not old or c["made"] > old["made"]:
            accepted[c["id"]] = c

    for name, ids in by_file.items():
        if len(ids) > MAX_CONTRIBUTORS_PER_FILE:
            notes.append((name, "%d different contributor IDs in one file: one person posing as many?" % len(ids)))
    for cid, c in list(accepted.items()):
        fp = fingerprint(c)
        if fp and fp in prints:
            notes.append((cid, "same numbers as contributor %s: counted once" % prints[fp]))
            del accepted[cid]
        elif fp:
            prints[fp] = cid
    return accepted, rejected, notes


def band_of(level):
    return next(b for b in BANDS if b[0] <= level <= b[1])


def main():
    args = [a for a in sys.argv[1:] if a != "--check"]
    check_only = "--check" in sys.argv[1:]
    accepted, rejected, notes = collect(input_files(args))

    out = ["Shared play data: %d contributor(s) accepted, %d problem(s)." % (len(accepted), len(rejected))]
    if rejected:
        out += ["", "== Rejected (not used)"] + ["  %s: %s" % r for r in rejected]
    if notes:
        out += ["", "== Notes"] + ["  %s: %s" % n for n in notes]
    if check_only:
        print("\n".join(out))
        return

    # medians over contributors: one contributor, one vote
    ref, kill_factor = model_reference()
    per_band = {}   # (class, band) -> {cid: stats}
    diff_rel = {}   # diff -> [time relative to own same-level time]
    guide_h, level_m = {}, {}
    known = known_guides()
    unknown_guides = set()
    for cid, c in accepted.items():
        sums = {}
        dsum = {}
        for ch in c["chars"]:
            for level, v in ch["levels"].items():
                s = sums.setdefault((ch["class"], band_of(level)), dict.fromkeys(("f", "fs", "k", "kx", "qx", "g",
                                                                                   "gs", "d"), 0))
                for k in s:
                    s[k] += v[k]
                for dn, (df, dfs) in v["diff"].items():
                    t = dsum.setdefault(dn, [0, 0])
                    t[0] += df
                    t[1] += dfs
        for key, s in sums.items():
            if s["f"] < MIN_FIGHTS or not s["k"]:
                continue
            xp = s["qx"] + s["kx"]
            per_band.setdefault(key, {})[cid] = {
                "s/fight": s["fs"] / s["f"], "kill/f": s["k"] / s["f"], "s/gap": s["gs"] / s["g"] if s["g"] else 0,
                "s/kill": (s["fs"] + s["gs"]) / s["k"], "xp/kill": s["kx"] / s["k"],
                "dth/%": 100 * s["d"] / s["k"], "questXP": 100 * s["qx"] / xp if xp else 0}
        if dsum.get(0) and dsum[0][0] >= MIN_FIGHTS:
            base = dsum[0][1] / dsum[0][0]
            for dn, (df, dfs) in dsum.items():
                if df >= 3:
                    diff_rel.setdefault(dn, []).append((dfs / df) / base)
        mine_g, mine_l = {}, {}
        for t in c["times"]:
            for g, sec in t["guides"].items():
                if g in known:
                    mine_g.setdefault(g, []).append(sec / 3600)
                else:
                    unknown_guides.add(g)
            for lv, sec in t["levels"].items():
                mine_l.setdefault((t["class"], lv), []).append(sec / 60)
        for g, hs in mine_g.items():
            guide_h.setdefault(g, []).append(statistics.median(hs))
        for k, ms in mine_l.items():
            level_m.setdefault(k, []).append(statistics.median(ms))

    cols = ("s/fight", "kill/f", "s/gap", "s/kill", "xp/kill", "dth/%", "questXP")
    out += ["", "== Fights per class and level band (median over contributors; n = contributors)"] + ref
    out.append("%-8s %-6s %3s " % ("class", "levels", "n") + " ".join("%8s" % c for c in cols))
    outliers = []
    for (cls, band), by_c in sorted(per_band.items()):
        # outliers are listed and left out
        first = statistics.median(v["s/kill"] for v in by_c.values())
        if len(by_c) >= 3 and first:
            for cid, v in list(by_c.items()):
                r = v["s/kill"] / first
                if r > OUTLIER or r < 1 / OUTLIER:
                    outliers.append("  %s %s %d-%d: %.1f s per kill vs median %.1f (left out)" % (
                        cid, cls, band[0], band[1], v["s/kill"], first))
                    del by_c[cid]
        med = {c: statistics.median(v[c] for v in by_c.values()) for c in cols}
        out.append("%-8s %2d-%-3d %3d " % (cls, band[0], band[1], len(by_c)) + " ".join("%8.1f" % med[c] for c in cols)
                   + ("" if len(by_c) >= 3 else "   (fewer than 3: don't trust yet)"))
    out.append("s/kill = (fight + downtime) / kills. Downtime only counts gaps of up to 3 minutes between fights.")
    if outliers:
        out += ["", "== Far from the median (left out of the table above; look at these by hand)"] + outliers

    out += ["", "== Fight time by mob level difference (median over contributors, relative to their same-level fights)"]
    for dn in sorted(diff_rel):
        rel = diff_rel[dn]
        model = kill_factor(dn) if kill_factor else None
        out.append("  %+d: x%.2f  (n=%d)%s" % (dn, statistics.median(rel), len(rel),
                                              (" (model x%.2f)" % model) if model is not None else ""))

    out += ["", "== Real hours per guide (median over contributors, n)"]
    for g, hs in sorted(guide_h.items()):
        out.append("  %-50s %5.2f h  (%d)" % (g, statistics.median(hs), len(hs)))
    if unknown_guides:
        out.append("  Left out %d guide name(s) that are not Questfarer guides." % len(unknown_guides))

    out += ["", "== Minutes per level (median over contributors, n)"]
    for (cls, lv), ms in sorted(level_m.items()):
        out.append("  %-8s %3d %6.1f min  (%d)" % (cls, lv, statistics.median(ms), len(ms)))

    os.makedirs(os.path.join(ROOT, "reports"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "contributions"), exist_ok=True)
    with open(os.path.join(ROOT, "reports", "contributions.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")
    out += ["", "== Learned paths (python -I suggest_checkpoints.py turns them into route checkpoints)"]
    for cid, c in sorted(accepted.items()):
        p = c["paths"]
        out.append("  %s: %d path(s) to %d step(s), %d zone crossing(s)" % (
            cid, sum(len(x) for x in p["learned"].values()), len(p["learned"]),
            sum(len(x) for x in p["crossings"].values())))

    merged = [{"id": c["id"], "made": c["made"], "addon": c["addon"], "recorder": c["recorder"], "paths": c["paths"],
               "untrusted": "player-sent data: check by hand before using any of it in a route"}
              for c in accepted.values()]
    with open(os.path.join(ROOT, "contributions", "merged.json"), "w", encoding="utf-8") as fh:
        json.dump(merged, fh, indent=1, sort_keys=True, ensure_ascii=True)
    print(out[0])
    for r in rejected:
        print("  rejected %s: %s" % r)
    print("wrote reports/contributions.txt and contributions/merged.json")


if __name__ == "__main__":
    main()
