"""Writes the shape, icon and compass textures in Questfarer/Media.

They are white (the needle is grey shaded) so the addon can tint them.
"""
import math
import os
import struct

SUB = 4  # samples per pixel side

OUT = os.path.join(os.path.dirname(__file__), '..', 'Questfarer', 'Media')


def cover(d, soft=0.0):
    """Alpha for a signed distance, with an optional soft edge."""
    if soft <= 0:
        return 1.0 if d <= 0 else 0.0
    return max(0.0, min(1.0, 0.5 - d / soft))


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)


def poly_dist(x, y, pts):
    """Signed distance to a polygon, negative inside."""
    d = min(seg_dist(x, y, *pts[i], *pts[(i + 1) % len(pts)]) for i in range(len(pts)))
    inside = False
    j = len(pts) - 1
    for i in range(len(pts)):
        (xi, yi), (xj, yj) = pts[i], pts[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return -d if inside else d


def write(name, size, fn):
    """fn(x, y) in pixels returns (value, alpha), both 0-1."""
    data = bytearray()
    for py in range(size):
        for px in range(size):
            v = a = 0.0
            for sy in range(SUB):
                for sx in range(SUB):
                    sv, sa = fn(px + (sx + 0.5) / SUB, py + (sy + 0.5) / SUB)
                    v += sv * sa
                    a += sa
            c = round(255 * v / a) if a else 255
            data += bytes((c, c, c, round(255 * a / SUB ** 2)))
    # uncompressed 32-bit tga, rows from the top
    header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 0x28)
    with open(os.path.join(OUT, name + '.tga'), 'wb') as f:
        f.write(header + data)


def white(test):
    return lambda x, y: (1.0, 1.0 if test(x, y) else 0.0)


def circle(x, y):
    return math.hypot(x - 32, y - 32) <= 30


def ring(x, y):
    return 27 <= math.hypot(x - 32, y - 32) <= 30


def diamond(x, y):
    return abs(x - 16) + abs(y - 16) <= 14


def square(x, y):
    qx, qy = abs(x - 16) - 9, abs(y - 16) - 9
    return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) <= 4


def cross(x, y):
    a = seg_dist(x, y, 9, 9, 23, 23)
    b = seg_dist(x, y, 23, 9, 9, 23)
    return min(a, b) <= 2


def minus(x, y):
    return seg_dist(x, y, 8, 16, 24, 16) <= 2


def plus(x, y):
    return minus(x, y) or seg_dist(x, y, 16, 8, 16, 24) <= 2


def gear(x, y):
    r = math.hypot(x - 16, y - 16)
    if r <= 4.5:
        return False
    tooth = math.cos(8 * math.atan2(y - 16, x - 16)) > 0.15
    return r <= (13 if tooth else 10)


def disc(x, y):
    return math.hypot(x - 64, y - 64) <= 60


def compass_ring(x, y):
    r = math.hypot(x - 64, y - 64)
    if 54 <= r <= 61:
        return True
    angle = math.atan2(y - 64, x - 64)
    # dashed inner ring
    if 45 <= r <= 47 and math.sin(36 * angle) > -0.2:
        return True
    # four notches pointing in
    for k in range(4):
        a = k * math.pi / 2
        ca, sa = math.cos(a), math.sin(a)
        tip = (64 + 47 * ca, 64 + 47 * sa)
        left = (64 + 55 * ca - 5 * sa, 64 + 55 * sa + 5 * ca)
        right = (64 + 55 * ca + 5 * sa, 64 + 55 * sa - 5 * ca)
        if poly_dist(x, y, [tip, left, right]) <= 0:
            return True
    return False


NEEDLE = [(64, 14), (90, 96), (64, 80), (38, 96)]


def needle(x, y):
    d = poly_dist(x, y, NEEDLE)
    if d > 3:
        return 0.0, 0.0
    if d > 0:
        return 0.12, 0.9  # dark outline
    # the left half is in shadow
    return (1.0 if x >= 64 else 0.66), 1.0


# 64 px pictograms for the settings menu and the target button

def stroke(x, y, a, b, w):
    return seg_dist(x, y, *a, *b) <= w


def ring_at(x, y, cx, cy, r, w):
    return abs(math.hypot(x - cx, y - cy) - r) <= w


def round_rect(x, y, x0, y0, x1, y1, r):
    qx = abs(x - (x0 + x1) / 2) - ((x1 - x0) / 2 - r)
    qy = abs(y - (y0 + y1) / 2) - ((y1 - y0) / 2 - r)
    return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) <= r


MAP = [(8, 16), (23, 10), (41, 16), (56, 10), (56, 48), (41, 54), (23, 48), (8, 54)]


def menu_guide(x, y):
    d = poly_dist(x, y, MAP)
    if d > 0:
        return 0.0, 0.0
    # folds, the middle panel a shade darker
    if stroke(x, y, (23, 10), (23, 48), 1.6) or stroke(x, y, (41, 16), (41, 54), 1.6):
        return 0.0, 0.0
    return (0.72 if 23 < x < 41 else 1.0), 1.0


def menu_automation(x, y):
    r = math.hypot(x - 32, y - 32)
    if r <= 9:
        return False
    tooth = math.cos(8 * math.atan2(y - 32, x - 32)) > 0.1
    return r <= (27 if tooth else 20)


def menu_navigation(x, y):
    if ring_at(x, y, 32, 32, 26, 2.5):
        return 1.0, 1.0
    if poly_dist(x, y, [(32, 11), (40, 32), (32, 53), (24, 32)]) <= 0:
        return (1.0 if y <= 32 else 0.5), 1.0
    return 0.0, 0.0


def menu_helpers(x, y):
    # wrench: round head with a slot, handle down to the left
    if stroke(x, y, (14, 50), (36, 28), 5):
        return True
    head = math.hypot(x - 42, y - 22) <= 13
    slot = math.hypot(x - 42, y - 22) <= 5.5 or stroke(x, y, (42, 22), (56, 8), 5.5)
    return head and not slot


def menu_appearance(x, y):
    # palette with a thumb hole and paint wells
    if ((x - 32) / 27) ** 2 + ((y - 32) / 23) ** 2 > 1:
        return False
    if math.hypot(x - 54, y - 49) <= 9 or math.hypot(x - 36, y - 40) <= 5:
        return False
    return all(math.hypot(x - cx, y - cy) > 4.5 for cx, cy in ((18, 28), (28, 19), (41, 19), (19, 41)))


SHIELD = [(13, 10), (32, 15), (51, 10), (51, 32), (45, 44), (32, 56), (19, 44), (13, 32)]


def menu_character(x, y):
    d = poly_dist(x, y, SHIELD)
    # filled with an inner line cut out
    return d <= 0 and not (-8 < d < -5)


def menu_journal(x, y):
    left = poly_dist(x, y, [(6, 15), (30, 19), (30, 53), (6, 49)])
    right = poly_dist(x, y, [(34, 19), (58, 15), (58, 49), (34, 53)])
    if left <= 0:
        return 0.75, 1.0
    if right <= 0:
        return 1.0, 1.0
    return 0.0, 0.0


def foot(x, y, cx, cy):
    sole = ((x - cx) / 7.5) ** 2 + ((y - cy) / 10) ** 2 <= 1
    heel = math.hypot(x - cx, y - (cy + 16)) <= 5.5
    return sole or heel


def menu_travels(x, y):
    return foot(x, y, 21, 30) or foot(x, y, 43, 14)


def menu_data(x, y):
    return (round_rect(x, y, 9, 34, 20, 56, 3) or round_rect(x, y, 26, 22, 38, 56, 3)
            or round_rect(x, y, 44, 8, 55, 56, 3))


def menu_about(x, y):
    if ring_at(x, y, 32, 32, 26, 3):
        return True
    return math.hypot(x - 32, y - 19) <= 4.5 or stroke(x, y, (32, 29), (32, 46), 3.5)


def icon_target(x, y):
    if ring_at(x, y, 32, 32, 17, 3):
        return True
    for a, b in (((32, 3), (32, 19)), ((32, 45), (32, 61)), ((3, 32), (19, 32)), ((45, 32), (61, 32))):
        if stroke(x, y, a, b, 2.5):
            return True
    return math.hypot(x - 32, y - 32) <= 4


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for name, size, test in (('shape_circle', 64, circle), ('shape_ring', 64, ring),
                             ('shape_diamond', 32, diamond), ('shape_square', 32, square),
                             ('icon_close', 32, cross), ('icon_minus', 32, minus),
                             ('icon_plus', 32, plus), ('icon_gear', 32, gear),
                             ('compass_disc', 128, disc), ('compass_ring', 128, compass_ring),
                             ('menu_automation', 64, menu_automation), ('menu_helpers', 64, menu_helpers),
                             ('menu_appearance', 64, menu_appearance), ('menu_character', 64, menu_character),
                             ('menu_travels', 64, menu_travels), ('menu_data', 64, menu_data),
                             ('menu_about', 64, menu_about), ('icon_target', 64, icon_target)):
        write(name, size, white(test))
    write('compass_needle', 128, needle)
    for name, fn in (('menu_guide', menu_guide), ('menu_navigation', menu_navigation),
                     ('menu_journal', menu_journal)):
        write(name, 64, fn)
    print('ok')
