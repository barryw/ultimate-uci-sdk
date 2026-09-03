#!/usr/bin/env python3
"""Verify that Boing refuses to start without UCI, then bypass that guard in
VICE to check its video and motion. Hardware tests cover the real turbo path."""
import re, subprocess, sys, tempfile, pathlib, shutil
from PIL import Image
HERE = pathlib.Path(__file__).resolve().parent

def classify(rgb):
    r, g, b = rgb
    if r > 200 and g > 200 and b > 200:
        return "white"
    if r > 100 and g < 80 and b < 80:
        return "red"
    if abs(r - g) < 12 and abs(g - b) < 12 and 45 < r < 100:
        return "dark"
    if b > 120 and r > 100 and g < 90:
        return "purple"
    return None

def run():
    sym = {k: int(v, 16) for k, v in re.findall(r"\.label (\w+)=\$([0-9a-fA-F]+)", (HERE / "boing.sym").read_text())}
    work = pathlib.Path(tempfile.mkdtemp(prefix="boing-"))
    shutil.copy(HERE / "boing.prg", work / "t.prg")
    (work / "guard.txt").write_text("until %04x\nquit\n" % sym["no_ultimate"])
    subprocess.run(["x64sc", "-console", "-warp", "+sound", "-moncommands", "guard.txt", "-autostart", "t.prg"],
                   cwd=work, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60, check=True)
    print("no-UCI startup: correctly returned to BASIC")
    mon = ["until %04x" % sym["main"], "r pc = %04x" % sym["start"]]
    shots = []
    for n, frames in enumerate((30, 24, 106, 100, 200)):
        mon += ["until %04x" % sym["irq_vbl"]] * frames
        shot = HERE / ("vice-%d.png" % n)
        mon += ['screenshot "%s" 2' % shot, 'save "st%d.bin" 0 033c 034a' % n]
        shots.append((shot, work / ("st%d.bin" % n)))
    mon += ["quit", ""]
    (work / "mon.txt").write_text("\n".join(mon))
    subprocess.run(["x64sc", "-console", "-warp", "+sound", "-moncommands", "mon.txt", "-autostart", "t.prg"],
                   cwd=work, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)
    ok, ys, bounces, darks = True, [], [], []
    for shot, st in shots:
        s = st.read_bytes()[2:]
        frames, x, y, rot = s[4] | (s[5] << 8), s[6] | (s[7] << 8), s[8], s[9]
        flags, nb, res = s[10], s[11], s[12]
        ys.append(y); bounces.append(nb)
        img = Image.open(shot).convert("RGB")
        w, h = img.size
        px = img.load()
        count = {"white": 0, "red": 0, "dark": 0, "purple": 0}
        box = {"white": [9999, 9999, -1, -1], "dark": [9999, 9999, -1, -1]}
        for yy in range(h):
            for xx in range(w):
                c = classify(px[xx, yy])
                if c is None:
                    continue
                count[c] += 1
                key = "white" if c in ("white", "red") else c
                if key in box:
                    bb = box[key]
                    bb[0], bb[1], bb[2], bb[3] = min(bb[0], xx), min(bb[1], yy), max(bb[2], xx), max(bb[3], yy)
        bw = box["white"][2] - box["white"][0] + 1
        bh = box["white"][3] - box["white"][1] + 1
        db = box["dark"]
        dw, dh = db[2] - db[0] + 1, db[3] - db[1] + 1
        # ball present and two-coloured, background intact, REU on (flags bit 1),
        # every SDK call ok. Shadow is checked across the set, below.
        ball_ok = s[:4] == b"BONG" and count["white"] > 1500 and count["red"] > 1500 and 84 <= bw <= 100 and 78 <= bh <= 90
        good = ball_ok and count["purple"] > 3000 and (flags & 2) and res == 0
        ok &= good
        darks.append(count["dark"])
        print("%s: frames %d x %d y %d rot %d flags %d bounces %d res %d | ball %dx%d at (%d,%d) w%d r%d | shadow %d px | purple %d %s" % (
            shot.name, frames, x, y, rot, flags, nb, res, bw, bh, box["white"][0], box["white"][1],
            count["white"], count["red"], count["dark"], count["purple"], "OK" if good else "BAD"))
    if len(set(ys)) < 2:
        print("y did not change between shots"); ok = False
    if bounces[-1] <= bounces[0]:
        print("no bounces counted"); ok = False
    if sum(1 for d in darks if d > 600) < 2:
        print("shadow not seen in flight"); ok = False
    shutil.rmtree(work)
    return ok

if __name__ == "__main__":
    sys.exit(0 if run() else 1)
