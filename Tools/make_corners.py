"""Writes the rounded corner textures in Questfarer/Media.

Each texture is a white rounded box on a 32x32 unit tile, 4 pixels per unit.
Widgets.lua cuts it into nine pieces and tints it, so the numbers here must
match ROUND_* there: corner piece 12 units, margin 3, radius 6, border 2.
"""
import math
import os
import struct

PX = 128
UNIT = 4
TILE = PX / UNIT
MARGIN, RADIUS, BORDER = 3, 6, 2
SHADE = 7     # how far the darkened paper reaches in from the border
SHADOW = 3
SUB = 4       # samples per pixel side

OUT = os.path.join(os.path.dirname(__file__), '..', 'Questfarer', 'Media')


def dist(x, y):
    """Signed distance to the box edge, negative inside."""
    half = TILE / 2 - MARGIN
    qx = abs(x - TILE / 2) - (half - RADIUS)
    qy = abs(y - TILE / 2) - (half - RADIUS)
    outside = math.hypot(max(qx, 0), max(qy, 0))
    return outside + min(max(qx, qy), 0) - RADIUS


def solid(d): return 1.0 if d <= 0 else 0.0
def fill(d): return 1.0 if d <= -BORDER else 0.0
def ring(d): return 1.0 if -BORDER < d <= 0 else 0.0
def inner(d): return 1.0 if -BORDER - 1 < d <= -BORDER else 0.0


def shadow(d):
    if d <= 0 or d >= SHADOW:
        return 0.0
    return (1 - d / SHADOW) ** 2


def shade(d):
    depth = -d - BORDER
    if depth < 0 or depth >= SHADE:
        return 0.0
    return (1 - depth / SHADE) ** 1.5


def write(name, fn):
    data = bytearray()
    for py in range(PX):
        for px in range(PX):
            a = 0.0
            for sy in range(SUB):
                for sx in range(SUB):
                    x = (px + (sx + 0.5) / SUB) / UNIT
                    y = (py + (sy + 0.5) / SUB) / UNIT
                    a += fn(dist(x, y))
            a = round(255 * a / SUB ** 2)
            data += bytes((255, 255, 255, a))
    # uncompressed 32-bit tga, rows from the top
    header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, PX, PX, 32, 0x28)
    with open(os.path.join(OUT, name + '.tga'), 'wb') as f:
        f.write(header + data)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for name, fn in (('solid', solid), ('fill', fill), ('ring', ring), ('inner', inner),
                     ('shadow', shadow), ('shade', shade)):
        write('round_' + name, fn)
    print('ok')
