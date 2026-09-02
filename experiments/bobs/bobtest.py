#!/usr/bin/env python3
"""Drive experiments/bobs/bobs.prg on a real Ultimate 64 and tabulate throughput.

    python3 bobtest.py --host 192.168.1.62 [--sweep] [--png shot.png]

The program renders N software sprites per frame into a double-buffered
multicolour bitmap and publishes, in the cassette buffer, the CIA cycles the
render took and a frame counter. This sets speed, badline mode and bob count
over the REST API and reads those numbers back. Frames per second come from the
frame counter against wall-clock time, so they do not depend on what turbo does
to the CIA. The bitmap is read back by DMA and rendered to a PNG.
"""
import argparse, os, struct, sys, time, pathlib
ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from u64_settings import Ultimate, read_settings, require_settings, restore_settings  # noqa: E402
from render import render, render_cells  # noqa: E402

STATUS = 0x033C
STATUS_LEN = 38
MAGIC = b"BOBS"
BITMAP = {0: 0x6000, 1: 0xA000}
SCREEN = {0: 0x5C00, 1: 0x8000}
BANK = {0: 0x4000, 1: 0x8000}
BLOB_ADDR = 0x3400
MODE_NAMES = {0: "one palette", 1: "per-bob cells", 2: "per-bob colour RAM too",
              3: "hardware sprites on top", 4: "dithered shapes", 5: "palette animation (blob)"}
COLOURS = [0x00, 0x0B, 0x0E, 0x01]
TURBO = ("U64 Specific Settings", "Turbo Control")
REU = ("C64 and Cartridge Settings", "RAM Expansion Unit")
SPEEDS_U64 = [1, 2, 3, 4, 5, 6, 8, 10, 12, 14, 16, 20, 24, 32, 40, 48]


class Status:
    def __init__(self, raw):
        self.valid = raw[:4] == MAGIC
        self.d031 = raw[7]
        self.frames = raw[8] | (raw[9] << 8)
        self.render = struct.unpack("<I", raw[10:14])[0]
        self.tenfr = struct.unpack("<I", raw[14:18])[0]
        self.drawn = raw[18]
        self.front = raw[19]
        self.state = raw[20]
        self.test = raw[21]
        self.reu_fetch = struct.unpack("<I", raw[22:26])[0]
        self.cpu_copy = struct.unpack("<I", raw[26:30])[0]
        self.reu_stash = struct.unpack("<I", raw[30:34])[0]
        self.mode = raw[35]
        self.blob = raw[36]


def status(u):
    return Status(u.readmem(STATUS, STATUS_LEN))


def control(u, speed=None, nobad=None, nbobs=None, test=None, mode=None):
    if mode is not None:
        u.writemem(STATUS + 34, bytes([mode]))
    if speed is not None:
        u.writemem(STATUS + 4, bytes([speed]))
    if nobad is not None:
        u.writemem(STATUS + 5, bytes([nobad]))
    if nbobs is not None:
        u.writemem(STATUS + 6, bytes([nbobs]))
    if test is not None:
        u.writemem(STATUS + 21, bytes([test]))


def wait_running(u, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        s = status(u)
        if s.valid and s.state == 1:
            return s
        time.sleep(0.2)
    raise RuntimeError("bobs.prg did not start")


def measure(u, speed, nobad, nbobs, seconds=1.0):
    control(u, speed=speed, nobad=nobad, nbobs=nbobs)
    # settle: two whole frames at the new setting, which at 1 MHz can be seconds
    f0 = status(u).frames
    deadline = time.time() + 6
    while ((status(u).frames - f0) & 0xFFFF) < 2 and time.time() < deadline:
        time.sleep(0.05)
    a = status(u); t0 = time.time()
    time.sleep(seconds)
    b = status(u); t1 = time.time()
    frames = (b.frames - a.frames) & 0xFFFF
    fps = frames / (t1 - t0)
    frame_us = b.tenfr / 10.0
    return dict(speed=speed, mhz=SPEEDS_U64[speed], nobad=nobad, nbobs=b.drawn,
                fps=fps, render=b.render, frame_us=frame_us,
                per_bob=b.render / max(1, b.drawn), d031=b.d031,
                frac=b.render / frame_us)


def bench(u, speed, nobad):
    control(u, speed=speed, nobad=nobad, test=1)
    deadline = time.time() + 5
    while time.time() < deadline:
        s = status(u)
        if s.test == 0 and s.cpu_copy:
            return s
        time.sleep(0.1)
    raise RuntimeError("benchmark did not complete")


def upload_blob(u, path):
    """The REST writemem takes 4 KB per call, so the blob goes up in pieces."""
    data = open(path, "rb").read()
    for off in range(0, len(data), 4096):
        u.writemem(BLOB_ADDR + off, data[off:off + 4096])
    back = u.readmem(BLOB_ADDR, len(data))
    if back != data:
        raise RuntimeError("blob readback differs at %d" % next(i for i in range(len(data)) if back[i] != data[i]))
    return len(data)


def snapshot(u, path):
    """Freeze the demo after a flip, read the whole front frame, let it go."""
    u.writemem(STATUS + 37, b"\x01")
    time.sleep(0.1)
    try:
        s = status(u)
        bitmap = u.readmem(BITMAP[s.front], 8000)
        if s.mode == 0:
            render(bitmap, COLOURS, path)
            return s
        return _snapshot_cells(u, s, bitmap, path)
    finally:
        u.writemem(STATUS + 37, b"\x00")


def _snapshot_cells(u, s, bitmap, path):
    screen = u.readmem(SCREEN[s.front], 1000)
    colram = u.readmem(0xD800, 1000)
    bg = u.readmem(0xD021, 1)[0]
    sprites = None
    if s.mode == 3:
        regs = u.readmem(0xD000, 0x2F)
        if regs[0x15] == 0xFF:
            ptrs = u.readmem(SCREEN[s.front] + 0x3F8, 8)
            sprites = []
            for i in range(8):
                x = regs[2*i] | (256 if regs[0x10] & (1 << i) else 0)
                y = regs[2*i + 1]
                data = u.readmem(BANK[s.front] + ptrs[i] * 64, 63)
                sprites.append((x, y, regs[0x27 + i], data))
    render_cells(bitmap, screen, colram, bg, path, sprites=sprites)
    return s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", required=True)
    ap.add_argument("--prg", default=str(pathlib.Path(__file__).with_name("bobs.prg")))
    ap.add_argument("--sweep", action="store_true")
    ap.add_argument("--png", default=None)
    ap.add_argument("--speeds", default="0,3,6,9,12,15")
    ap.add_argument("--bobs", default="16,64,128,200")
    ap.add_argument("--leave", default="15,1,128", help="speed,nobad,nbobs to leave running")
    ap.add_argument("--mode", type=int, default=None, help="colour mode 0-5 to switch to")
    ap.add_argument("--blob", default=str(ROOT / "bindings" / "blob" / "build" / "ultimate-3400.bin"))
    ap.add_argument("--attach", action="store_true", help="do not reset or load; the demo is already running")
    args = ap.parse_args()

    u = Ultimate(args.host)
    original = read_settings(u, (TURBO, REU))
    changed = {}
    try:
        changed = require_settings(u, {TURBO: "U64 Turbo Registers", REU: "Enabled"})
        if not args.attach or not status(u).valid:
            u._request("PUT", "/machine:reset")
            time.sleep(2.0)
            u.run_prg(args.prg)
        s = wait_running(u)
        if args.mode is not None:
            if args.mode == 5:
                print("blob: %d bytes at $%04x" % (upload_blob(u, args.blob), BLOB_ADDR))
            control(u, mode=args.mode)
            deadline = time.time() + 10
            while status(u).mode != args.mode and time.time() < deadline:
                time.sleep(0.1)
            s = status(u)
            print("mode %d (%s)%s" % (s.mode, MODE_NAMES.get(s.mode, "?"),
                  ", blob result %d" % s.blob if args.mode == 5 else ""))
        print("running: frame = %.0f CIA cycles (ten frames %d), $d031 = $%02x" %
              (s.tenfr / 10.0, s.tenfr, s.d031))
        if s.d031 == 0xFF:
            print("turbo register reads $ff: Turbo Control is not 'U64 Turbo Registers'")
        if args.sweep:
            speeds = [int(x) for x in args.speeds.split(",")]
            bobs = [int(x) for x in args.bobs.split(",")]
            print("%5s %5s %8s %5s %8s %10s %9s %7s" %
                  ("MHz", "bad", "bobs", "fps", "render", "cyc/bob", "frame", "frac"))
            rows = []
            for speed in speeds:
                for nobad in (0, 1):
                    for nb in bobs:
                        r = measure(u, speed, nobad, nb)
                        rows.append(r)
                        print("%5d %5s %8d %5.1f %8d %10.0f %9.0f %7.2f" %
                              (r["mhz"], "off" if nobad else "on", r["nbobs"], r["fps"],
                               r["render"], r["per_bob"], r["frame_us"], r["frac"]))
            print()
            for speed in (0, 15):
                for nobad in (0, 1):
                    b = bench(u, speed, nobad)
                    print("copy 4096 bytes at %2d MHz, badlines %s: REU stash %6d  REU fetch %6d  CPU %6d  (CIA cycles)" %
                          (SPEEDS_U64[speed], "off" if nobad else "on ", b.reu_stash, b.reu_fetch, b.cpu_copy))
        speed, nobad, nb = [int(x) for x in args.leave.split(",")]
        r = measure(u, speed, nobad, nb)
        print("left running: %d MHz, badlines %s, %d bobs, %.1f fps, render %d cycles of a %.0f-cycle frame" %
              (r["mhz"], "off" if nobad else "on", r["nbobs"], r["fps"], r["render"], r["frame_us"]))
        if args.png:
            snapshot(u, args.png)
            print("wrote", args.png)
    finally:
        restore_settings(u, changed, warn=lambda m: print("warning:", m, file=sys.stderr))


if __name__ == "__main__":
    main()
