"""Find trips a route makes only because a step waited for a later visit to the same place.

A step is pulled to an earlier visit to the same spot (or pushed to a later one) when quest order,
level, prerequisites and the 20-quest log still allow it and the run gets no longer.
Non-quest steps (notes, flights, hearth, training, level) stay put and nothing moves across them.

    python round_trips.py             # report, every track
    python round_trips.py --write     # also rewrite the route files
Then: python build_guides.py
"""
import collections
import os
import re
import sys

import build_guides as bg
import plan_zone as pz

HERE = 60          # yards: steps this close are done in the same visit
HERE_AREA = 120    # ...for a kill or collect area, which is spread out anyway
LATER_SAVES = 25   # yards a step must save to wait for a later visit
MIN_SAVED = 150    # yards a route must save before it is rewritten
LEVEL_SLACK = 1.0  # an objective may move this many levels earlier
LOG_LIMIT = 20
QUEST_VERBS = ("accept", "turnin", "complete")


def verb(s):
    return next((v for v in QUEST_VERBS if v in s), None)


def movable(s):
    # class and race steps are only walked by some players, they stay where they are
    return verb(s) and not any(k in s for k in ("class", "race", "notclass"))


def qids(s):
    v = s[verb(s)]
    return v if isinstance(v, list) else [v]


def line_of(s):
    return int(s["_where"].rsplit(":", 1)[1])


def record(comp):
    """Keep level and log size before every compiled step."""
    inner = comp.compile_step

    def wrapped(st, guide, prev):
        lv = comp.est_level()
        log = len({q for q, _ in comp.accepted} - {q for q, _ in comp.turned})
        res = inner(st, guide, prev)
        for r in res:
            r["_lv"], r["_log"], r["_st"] = lv, log, st
        return res
    comp.compile_step = wrapped


def compile_tracks(data):
    out = []
    for order in ["ORDER"] + bg.track_files():
        comp = bg.Compiler(data)
        record(comp)
        for rf in bg.read_order(order):
            header, steps = bg.parse_route(os.path.join(bg.ROUTES, rf))
            before = snapshot(comp)
            guide = comp.compile_guide(header, steps)
            guide["_check"] = Check(data, header, before, guide["steps"])
            out.append((rf, guide))
    return out


def snapshot(comp):
    return {"accepted": list(comp.accepted), "turned": list(comp.turned), "solo_checked": set(comp.solo_checked),
            "level": comp.level, "class_level": dict(comp.class_level), "xp_total": comp.xp_total,
            "routed": set(comp.routed), "optional": set(comp.optional)}


def route_steps(steps):
    """Route steps for compiled steps in a new order; a multi-quest line that got split is cut up."""
    out, i = [], 0
    while i < len(steps):
        st = steps[i]["_st"]
        k = sum(1 for t in steps if t["_st"] is st)
        if all(t["_st"] is st for t in steps[i:i + k]):
            out.append(st)
            i += k
        else:
            out.append(dict(st, args=str(qids(steps[i])[0])))
            i += 1
    return out


class Check:
    """Compiles the guide again in a new order: no new warning and no lower level at the end."""

    def __init__(self, data, header, state, steps):
        self.d, self.header, self.state = data, header, state
        self.base, self.end = self.run(steps)

    def run(self, steps):
        comp = bg.Compiler(self.d)
        for k, v in self.state.items():
            setattr(comp, k, v.copy() if hasattr(v, "copy") else v)
        comp.compile_guide(self.header, route_steps(steps))
        msgs = collections.Counter(re.sub(r"^\S+:\d+: ", "", m) for m in comp.warnings + comp.errors)
        return msgs, comp.est_level()

    def ok(self, steps):
        msgs, end = self.run(steps)
        return not (msgs - self.base) and end >= self.end - 0.02


class Segment:
    """Quest steps between two fixed steps, the fixed ends as start and end points."""

    def __init__(self, data, steps, start, end, gmap, check):
        self.d, self.steps, self.start, self.end, self.check = data, steps, start, end, check
        for s in steps:
            s["_pos"] = (s.get("map") or gmap, s["x"], s["y"]) if "x" in s else None
        self.slots = [s["_lv"] for s in steps]
        self.log_limit = max(LOG_LIMIT, self.peak_log(steps))

    def length(self, order):
        pts = [p for p in [self.start] + [s["_pos"] for s in order] + [self.end] if p]
        return sum(min(pz.yards(a, b), 5000) for a, b in zip(pts, pts[1:]))

    def peak_log(self, order):
        log = peak = self.steps[0]["_log"]
        for s in order:
            if verb(s) == "accept":
                log += len(qids(s))
            elif verb(s) == "turnin":
                log -= len(qids(s))
            peak = max(peak, log)
        return peak

    def valid(self, order, moved):
        at = {}
        for i, s in enumerate(order):
            for q in qids(s):
                at[(verb(s), q)] = i
        i = order.index(moved)
        # a fight may come a little earlier in levels, not much
        if verb(moved) == "complete" and self.slots[i] < moved["_lv"] - LEVEL_SLACK:
            return False
        for i, s in enumerate(order):
            v = verb(s)
            for q in qids(s):
                if v != "accept" and at.get(("accept", q), -1) > i:
                    return False
                if v == "turnin" and at.get(("complete", q), -1) > i:
                    return False
                if v == "accept":
                    quest = self.d.quest(q) or {}
                    if (quest.get("requiredLevel") or 0) > int(self.slots[i]):
                        return False
                    pre = bg.as_list(quest.get("preQuestSingle")) + bg.as_list(quest.get("preQuestGroup"))
                    if any(at.get(("turnin", p), -1) > i for p in pre):
                        return False
        return self.peak_log(order) <= self.log_limit

    def near(self, a, b):
        reach = HERE_AREA if "complete" in (verb(a), verb(b)) else HERE
        return a["_pos"] and b["_pos"] and pz.yards(a["_pos"], b["_pos"]) <= reach

    def improve(self):
        order = list(self.steps)
        best = self.length(order)
        self.moved = []
        changed, moves = True, 0
        while changed and moves < 4 * len(order):
            changed = False
            for s in list(order):
                # an item that drops at random is picked up wherever it drops
                if not s["_pos"] or (s.get("text") or "").startswith("Loot "):
                    continue
                i = order.index(s)
                # only a step that starts a visit of its own is worth pulling to an earlier one
                starts = i == 0 or not self.near(order[i - 1], s)
                for other in order:
                    if other is s or not self.near(other, s):
                        continue
                    trial = [t for t in order if t is not s]
                    k = trial.index(other) + 1
                    trial.insert(k, s)
                    gain = best - self.length(trial)
                    # earlier is fine when it costs nothing, later only when it saves
                    if not ((starts and k < i and gain >= 0) or gain > LATER_SAVES):
                        continue
                    if self.valid(trial, s) and self.check(trial):
                        order, best, changed = trial, best - gain, True
                        moves += 1
                        self.moved.append(s)
                        break
                if changed:
                    break
        return order, best


def improve_guide(data, guide):
    """(new step order, yards saved, moved steps)."""
    gmap = guide["map"]
    full = list(guide["steps"])
    saved, moved = 0, []
    a, start = None, None

    def flush(b, end):
        nonlocal saved
        if a is None:
            return
        cur = full[a:b]
        seg = Segment(data, cur, start, end, gmap, lambda trial: guide["_check"].ok(full[:a] + trial + full[b:]))
        before = seg.length(cur)
        order, after = seg.improve()
        if before - after > 1:
            saved += before - after
            moved.extend(s for i, s in enumerate(seg.moved) if not any(s is t for t in seg.moved[:i]))
            full[a:b] = order

    for i, s in enumerate(full):
        if movable(s):
            if a is None:
                a = i
            continue
        # after a flight, a hearth or a step only some players walk, where you stand is unknown
        jump = s.get("fly") or s.get("hearth") or verb(s)
        here = (s.get("map") or gmap, s["x"], s["y"]) if "x" in s and not jump else None
        flush(i, here)
        a, start = None, None if jump else here
    flush(len(full), None)
    return full, saved, moved


def rewrite(path, steps):
    """Write the route's step lines in the new order; comments travel with the line below them."""
    raw = open(path, encoding="utf-8").read().split("\n")
    lines = sorted({line_of(s) for s in steps})
    first, last = lines[0] - 1, lines[-1] - 1
    lead, block = {}, []
    for n in range(first, last + 1):
        text = raw[n].strip()
        if not text or text.startswith("#"):
            block.append(raw[n])
        elif n + 1 in lines:
            lead[n + 1], block = block, []
        else:
            return False  # a line that compiled to nothing: leave this route alone
    body, done, whole = [], set(), set()
    for i, s in enumerate(steps):
        n = line_of(s)
        if n in whole:
            continue
        same = [t for t in steps if line_of(t) == n]
        if n not in done:
            body += lead.get(n, [])
        line = raw[n - 1]
        if n not in done and all(a is b for a, b in zip(steps[i:i + len(same)], same)):
            whole.add(n)  # the line's steps still follow each other: keep it as it is
        elif len(same) > 1:
            line = re.sub(r"^(\s*\w+\s+)[\d\s,]*\d", lambda m: m.group(1) + str(qids(s)[0]), line, count=1)
        body.append(line)
        done.add(n)
    raw[first:last + 1] = body
    open(path, "w", encoding="utf-8", newline="").write("\n".join(raw))
    return True


def main():
    write = "--write" in sys.argv
    data = bg.Data()
    total = 0
    for rf, guide in compile_tracks(data):
        steps, saved, moved = improve_guide(data, guide)
        if saved < MIN_SAVED:
            continue
        total += saved
        print("%-36s %5d yards shorter  (%s)" % (guide["name"][:36], saved, rf))
        for s in moved:
            title = s.get("title") or ", ".join(s.get("titles", []))
            print("    %-8s %-40s line %d -> after line %d" % (
                verb(s), title[:40], line_of(s), line_of(steps[steps.index(s) - 1]) if steps.index(s) else 0))
        if write and not rewrite(os.path.join(bg.ROUTES, rf), steps):
            print("    not rewritten: the route has a line that compiled to nothing")
    print("total: %d yards (about %d minutes on foot)" % (total, total / pz.RUN_SPEED / 60))


if __name__ == "__main__":
    main()
