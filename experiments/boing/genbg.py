#!/usr/bin/env python3
"""Background and shadow for the Boing ball.

bg.bin     8000-byte hires bitmap: grey field, purple grid on the wall above the
           horizon, a perspective floor below it (horizontal lines that bunch up
           toward the wall, verticals fanning out from a vanishing point).
bgscr.bin  1000 screen RAM bytes: foreground purple, background grey.
shadow.bin the ball's shadow, a 96 x 84 ellipse, 12 bytes x 84 rows, row-major,
           bit set inside.
bg-preview.png for the eye.
"""
from PIL import Image, ImageDraw

W, H = 320, 200
HORIZON, FLOOR = 176, 190          # wall/floor line, and the floor's near edge
WALL_L, WALL_R, WALL_T = 24, 296, 12   # the wall grid's margins
FLOOR_L, FLOOR_R = 14, 306         # the floor fans out toward the viewer
COLS, ROWS = 12, 12
COL_GRID, COL_BG = 0x04, 0x0C
SW, SH = 96, 84

def bitmap():
    """The original's proportions: a 12 x 12 wall grid with margins, and a
    thin perspective floor of four lines under it."""
    img = Image.new("1", (W, H), 0)
    d = ImageDraw.Draw(img)
    for i in range(COLS + 1):
        xw = WALL_L + i * (WALL_R - WALL_L) / COLS
        xf = FLOOR_L + i * (FLOOR_R - FLOOR_L) / COLS
        d.line([(round(xw), WALL_T), (round(xw), HORIZON)], fill=1)      # wall
        d.line([(round(xw), HORIZON), (round(xf), FLOOR)], fill=1)       # floor, fanning out
    for j in range(ROWS + 1):
        y = round(WALL_T + j * (HORIZON - WALL_T) / ROWS)
        d.line([(WALL_L, y), (WALL_R, y)], fill=1)
    for y in (HORIZON, HORIZON + 3, HORIZON + 8, FLOOR):                  # bunched toward the wall
        t = (y - HORIZON) / (FLOOR - HORIZON)
        d.line([(round(WALL_L + t * (FLOOR_L - WALL_L)), y), (round(WALL_R + t * (FLOOR_R - WALL_R)), y)], fill=1)
    out = bytearray(8000)
    px = img.load()
    for cr in range(25):
        for c in range(40):
            for l in range(8):
                v = 0
                for p in range(8):
                    if px[c * 8 + p, cr * 8 + l]:
                        v |= 128 >> p
                out[cr * 320 + c * 8 + l] = v
    img.convert("RGB").resize((640, 400)).save("bg-preview.png")
    return out

def shadow():
    img = Image.new("1", (SW, SH), 0)
    ImageDraw.Draw(img).ellipse([0, 0, SW - 1, SH - 1], fill=1)
    px = img.load()
    out = bytearray()
    for r in range(SH):
        for b in range(SW // 8):
            v = 0
            for p in range(8):
                if px[b * 8 + p, r]:
                    v |= 128 >> p
            out.append(v)
    return out

if __name__ == "__main__":
    bg = bitmap()
    open("bg.bin", "wb").write(bg)
    open("bgscr.bin", "wb").write(bytes([(COL_GRID << 4) | COL_BG] * 1000))
    sh = shadow()
    open("shadow.bin", "wb").write(sh)
    assert len(bg) == 8000 and len(sh) == 12 * 84
    assert sum(bin(b).count("1") for b in sh) > 5500, "ellipse too thin"
