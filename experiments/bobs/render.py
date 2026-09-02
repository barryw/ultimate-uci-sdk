#!/usr/bin/env python3
"""Render a C64 multicolour bitmap frame to a PNG.

render(bitmap, colours, path) takes one palette for the whole screen (mode 0);
render_cells(bitmap, screen, colram, bg, path, sprites=None) uses the per-cell
colours the VIC would, and optionally composites expanded hires hardware
sprites given as (x, y, colour, 63 bytes)."""
import sys
from PIL import Image

PAL = [(0,0,0),(0xEF,0xEF,0xEF),(0x8D,0x2F,0x34),(0x6A,0xD4,0xCD),(0x98,0x35,0xA4),
       (0x4C,0xB4,0x42),(0x2C,0x29,0xB1),(0xEF,0xEF,0x5D),(0x98,0x4E,0x20),(0x5B,0x38,0),
       (0xD1,0x67,0x6D),(0x4A,0x4A,0x4A),(0x7B,0x7B,0x7B),(0x9F,0xEF,0x93),(0x6D,0x6A,0xEF),
       (0xB2,0xB2,0xB2)]

def pixels(bitmap):
    """-> 200 rows of 160 colour-pair indices (0..3)."""
    rows = [[0]*160 for _ in range(200)]
    for cr in range(25):
        for c in range(40):
            for l in range(8):
                b = bitmap[cr*320 + c*8 + l]
                y = cr*8 + l
                for p in range(4):
                    rows[y][c*4 + p] = (b >> (6 - 2*p)) & 3
    return rows

def _colour_rows(bitmap, cell_colours):
    """cell_colours(cr, c) -> 4 colour indices. -> 200 rows of 160 colour indices."""
    rows = pixels(bitmap)
    out = []
    for y in range(200):
        cr = y >> 3
        line = []
        for x in range(160):
            line.append(cell_colours(cr, x >> 2)[rows[y][x]])
        out.append(line)
    return out

def _save(colour_rows, path, scale=2, sprites=None):
    img = Image.new("RGB", (320*scale, 200*scale))
    px = img.load()
    for y in range(200):
        for x in range(160):
            rgb = PAL[colour_rows[y][x]]
            for dy in range(scale):
                for dx in range(2*scale):
                    px[x*2*scale + dx, y*scale + dy] = rgb
    for (sx, sy, col, data) in sprites or []:
        rgb = PAL[col & 15]
        for row in range(21):
            for b in range(3):
                for p in range(8):
                    if data[row*3 + b] & (128 >> p):
                        hx = (sx - 24) + 2*(b*8 + p)     # expanded x2
                        hy = (sy - 50) + 2*row
                        for ddy in range(2):
                            for ddx in range(2):
                                X, Y = hx + ddx, hy + ddy
                                if 0 <= X < 320 and 0 <= Y < 200:
                                    for dy in range(scale):
                                        for dx in range(scale):
                                            px[X*scale + dx, Y*scale + dy] = rgb
    img.save(path)

def render(bitmap, colours, path, scale=2):
    _save(_colour_rows(bitmap, lambda cr, c: colours), path, scale)

def render_cells(bitmap, screen, colram, bg, path, scale=2, sprites=None):
    def cc(cr, c):
        s = screen[cr*40 + c]
        return [bg & 15, s >> 4, s & 15, colram[cr*40 + c] & 15]
    _save(_colour_rows(bitmap, cc), path, scale, sprites)

def ascii_region(bitmap, x0, y0, w, h):
    rows = pixels(bitmap)
    return "\n".join("".join(".123"[rows[y][x]] for x in range(x0, x0+w)) for y in range(y0, y0+h))

if __name__ == "__main__":
    data = open(sys.argv[1], "rb").read()
    if len(data) == 8002:
        data = data[2:]
    render(data, [0x00, 0x0b, 0x0e, 0x01], sys.argv[2])
