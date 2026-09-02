#!/usr/bin/env python3
"""Rotating checkered sphere as C64 sprite data.

Grid: 48 sprite pixels wide (2 columns of 24, X-expanded so each is 2 hires
pixels) by 84 lines (4 rows of 21). ball.bin = 16 frames x 8 sprites x 64
bytes, white tiles only, sprite order row*2+col. disc.bin = 8 x 64 bytes, the
ball's silhouette; red = disc AND NOT white at run time.
"""
import math, sys
from PIL import Image

FRAMES, COLS, ROWS = 16, 48, 84
RX, RY = 45.0, 42.0          # hires px, lines: nearly fills 96x84
TILT = math.radians(17)
LON_BANDS, LAT_BANDS = 8, 8

def tile(nx, ny, phi):
    """0 = outside, 1 = white, 2 = red."""
    r2 = nx*nx + ny*ny
    if r2 > 1.0:
        return 0
    nz = math.sqrt(1.0 - r2)
    c, s = math.cos(TILT), math.sin(TILT)
    x, y = nx*c + ny*s, -nx*s + ny*c
    lon = (math.atan2(x, nz) + phi) % (2*math.pi)
    lat = math.asin(max(-1.0, min(1.0, y))) + math.pi/2
    band = int(lon / (2*math.pi/LON_BANDS)) + int(lat / (math.pi/LAT_BANDS))
    return 1 if band & 1 == 0 else 2

def frame_pixels(f):
    phi = f * (math.pi/2) / FRAMES
    px = [[0]*COLS for _ in range(ROWS)]
    for row in range(ROWS):
        ny = (row + 0.5 - ROWS/2) / RY
        for col in range(COLS):
            nx = ((col + 0.5)*2 - COLS) / RX
            px[row][col] = tile(nx, ny, phi)
    return px

def sprite(px, r, c, want):
    out = bytearray(64)
    for line in range(21):
        for b in range(3):
            v = 0
            for p in range(8):
                if want(px[r*21 + line][c*24 + b*8 + p]):
                    v |= 128 >> p
            out[line*3 + b] = v
    return out

def main():
    ball, disc = bytearray(), bytearray()
    frames = [frame_pixels(f) for f in range(FRAMES)]
    for f in range(FRAMES):
        for r in range(4):
            for c in range(2):
                ball += sprite(frames[f], r, c, lambda t: t == 1)
    for r in range(4):
        for c in range(2):
            disc += sprite(frames[0], r, c, lambda t: t != 0)
    open("ball.bin", "wb").write(ball)
    open("disc.bin", "wb").write(disc)
    for f in (0, 4, 8):
        img = Image.new("RGB", (COLS*2*3, ROWS*3), (0x7B, 0x7B, 0x7B))
        for row in range(ROWS):
            for col in range(COLS):
                t = frames[f][row][col]
                if t:
                    rgb = (0xEF, 0xEF, 0xEF) if t == 1 else (0xC0, 0x30, 0x30)
                    for dy in range(3):
                        for dx in range(6):
                            img.putpixel((col*6 + dx, row*3 + dy), rgb)
        img.save("preview%02d.png" % f)
    assert len(ball) == FRAMES*8*64 and len(disc) == 8*64
    # self-check: the disc is the union, red never overlaps white
    for f in range(FRAMES):
        for i in range(8):
            w = ball[f*512 + i*64: f*512 + i*64 + 63]
            d = disc[i*64: i*64 + 63]
            assert all((wb & ~db) == 0 for wb, db in zip(w, d)), "white outside disc"
    print("ball.bin %d bytes, disc.bin %d bytes" % (len(ball), len(disc)))

if __name__ == "__main__":
    main()
