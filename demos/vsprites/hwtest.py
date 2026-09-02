#!/usr/bin/env python3
"""Run the vsprites demo on a real Ultimate and check it fills the frame.

    python3 hwtest.py --host 192.168.1.62 --prg vsprites.prg [--png shot.png]

The PRG is bigger than the REST runner's 16 KB body limit (the SDK blob is
inside it), so it goes to the Ultimate's /Temp RAM disk over FTP and runs from
there with runners:run_prg?file=. The demo publishes a status block in the
cassette buffer; this reads it back over REST. Turbo Control is required to be
"U64 Turbo Registers" for the run and put back afterwards, because the check
is that the demo reaches the frame rate and the bob count only turbo allows.

Part of the Ultimate SDK. SPDX-License-Identifier: MIT
"""
import argparse
import ftplib
import io
import pathlib
import struct
import sys
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from u64_settings import Ultimate, require_settings, restore_settings  # noqa: E402

STATUS = 0x033C
MAGIC = b"VSPR"
TURBO = ("U64 Specific Settings", "Turbo Control")
BITMAP = {0: 0x4000, 1: 0xE000}
COLOURS = [0x00, 0x0B, 0x0E, 0x01]
REMOTE = "/Temp/vsprites.prg"


class Status:
    def __init__(self, raw):
        self.valid = raw[:4] == MAGIC
        self.frames = raw[4] | (raw[5] << 8)
        self.render = struct.unpack("<I", raw[6:10])[0]
        self.frame = raw[10] | (raw[11] << 8)
        self.bobs = raw[12]
        self.front = raw[13]
        self.state = raw[14]
        self.turbo = raw[15]


def status(u):
    return Status(u.readmem(STATUS, 17))


def upload(host, path):
    data = open(path, "rb").read()
    f = ftplib.FTP(host, timeout=30)
    f.login()
    try:
        f.cwd("/Temp")
        f.storbinary("STOR " + REMOTE.rsplit("/", 1)[1], io.BytesIO(data))
    finally:
        f.quit()
    return len(data)


def run_from_file(u, remote):
    req = urllib.request.Request(u.base + "/runners:run_prg?file=" + remote, method="PUT")
    with urllib.request.urlopen(req, timeout=15) as r:
        return r.read()


def wait_running(u, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        s = status(u)
        if s.valid and s.state == 1:
            return s
        time.sleep(0.2)
    raise RuntimeError("the demo did not start")


def snapshot(u, path):
    """Freeze the demo after a flip, read the front bitmap, render it."""
    from PIL import Image
    pal = [(0,0,0),(0xEF,0xEF,0xEF),(0x8D,0x2F,0x34),(0x6A,0xD4,0xCD),(0x98,0x35,0xA4),
           (0x4C,0xB4,0x42),(0x2C,0x29,0xB1),(0xEF,0xEF,0x5D),(0x98,0x4E,0x20),(0x5B,0x38,0),
           (0xD1,0x67,0x6D),(0x4A,0x4A,0x4A),(0x7B,0x7B,0x7B),(0x9F,0xEF,0x93),(0x6D,0x6A,0xEF),
           (0xB2,0xB2,0xB2)]
    u.writemem(STATUS + 16, b"\x01")
    time.sleep(0.1)
    try:
        s = status(u)
        bitmap = u.readmem(BITMAP[s.front], 8000)
    finally:
        u.writemem(STATUS + 16, b"\x00")
    img = Image.new("RGB", (640, 400))
    px = img.load()
    for cr in range(25):
        for c in range(40):
            for l in range(8):
                b = bitmap[cr*320 + c*8 + l]
                for p in range(4):
                    rgb = pal[COLOURS[(b >> (6 - 2*p)) & 3]]
                    x0, y0 = (c*4 + p) * 4, (cr*8 + l) * 2
                    for dy in range(2):
                        for dx in range(4):
                            px[x0 + dx, y0 + dy] = rgb
    img.save(path)
    return s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", required=True)
    ap.add_argument("--prg", default=str(pathlib.Path(__file__).with_name("vsprites.prg")))
    ap.add_argument("--png", default=None)
    args = ap.parse_args()

    u = Ultimate(args.host)
    changed = {}
    try:
        changed = require_settings(u, {TURBO: "U64 Turbo Registers"})
        print("uploaded %d bytes to %s" % (upload(args.host, args.prg), REMOTE))
        u._request("PUT", "/machine:reset")
        time.sleep(2.0)
        run_from_file(u, REMOTE)
        s = wait_running(u)
        print("running: frame = %d CIA cycles, $d031 = $%02x" % (s.frame, s.turbo))
        time.sleep(4.0)                      # let the bob count settle
        a = status(u); t0 = time.time()
        time.sleep(2.0)
        b = status(u); t1 = time.time()
        fps = ((b.frames - a.frames) & 0xFFFF) / (t1 - t0)
        print("%d bobs at %.1f fps, render %d of %d cycles" % (b.bobs, fps, b.render, b.frame))
        if args.png:
            snapshot(u, args.png)
            print("wrote", args.png)
        ok = True
        if b.turbo == 0xFF:
            print("not ok - turbo unavailable: is Turbo Control 'U64 Turbo Registers'?")
            ok = False
        if fps < 50:
            print("not ok - expected at least 50 fps, measured %.1f" % fps)
            ok = False
        if b.bobs < 30:
            print("not ok - expected at least 30 bobs at full turbo, got %d" % b.bobs)
            ok = False
        if ok:
            print("ok - vsprites fills the frame at %.1f fps with %d bobs" % (fps, b.bobs))
        return 0 if ok else 1
    finally:
        restore_settings(u, changed,
                         warn=lambda m: print("warning: " + m, file=sys.stderr))


if __name__ == "__main__":
    sys.exit(main())
