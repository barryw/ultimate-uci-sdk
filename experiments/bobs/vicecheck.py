#!/usr/bin/env python3
"""Run a bobs build in VICE for a few frames, dump memory, and check the back
buffer byte-for-byte against a Python reference blit.  python3 vicecheck.py bobs16.prg"""
import os, re, subprocess, sys, struct, tempfile, pathlib, shutil
HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from render import render, pixels

def main(prg_name, nbobs=16):
    prg_path = HERE / prg_name
    sym_path = HERE / (prg_name.replace(".prg", ".sym"))
    sym = {k: int(v, 16) for k, v in re.findall(r"\.label (\w+)=\$([0-9a-fA-F]+)", sym_path.read_text())}
    work = pathlib.Path(tempfile.mkdtemp(prefix="vicecheck-"))
    shutil.copy(prg_path, work / "t.prg")
    mon = "\n".join(["until %04x" % sym["frame_loop"], "> 0342 %02x" % nbobs] +
                    ["until %04x" % sym["frame_loop"]] * 4 + [
        'save "A.bin" 0 6000 7f3f', 'save "B.bin" 0 a000 bf3f',
        'save "S.bin" 0 033c 035d', 'save "T.bin" 0 %04x %04x' % (sym["bx"], sym["bx"] + 200*5),
        "quit", ""])
    (work / "mon.txt").write_text(mon)
    subprocess.run(["x64sc", "-console", "-warp", "+sound", "-moncommands", "mon.txt",
                    "-autostart", "t.prg"], cwd=work, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, timeout=180)
    A = (work / "A.bin").read_bytes()[2:]; B = (work / "B.bin").read_bytes()[2:]
    S = (work / "S.bin").read_bytes()[2:]; T = (work / "T.bin").read_bytes()[2:]
    prg = prg_path.read_bytes(); load = prg[0] | (prg[1] << 8)
    bob_h = 16 if "16" in prg_name else 32
    img_bytes = 5 * bob_h
    bx, by, bs = T[0:200], T[200:400], T[800:1000]
    front = S[19]; frames = S[8] | (S[9] << 8); nbobs = S[18]
    buf = B if front == 1 else A          # the buffer drawn last
    def image(k, s):
        off = sym["bobdata"] + (k*4+s)*img_bytes*2 - load + 2
        return prg[off:off+img_bytes], prg[off+img_bytes:off+2*img_bytes]
    ref = bytearray(8000)
    for cell in range(1000):
        ref[cell*8] = 0x55
        for l in range(1, 8): ref[cell*8+l] = 0x40
    for i in range(nbobs):
        x, y, k = bx[i], by[i], bs[i]
        img, msk = image(k, x & 3)
        for c in range(5):
            for r in range(bob_h):
                yy = y + r
                a = (yy >> 3)*320 + ((x >> 2) + c)*8 + (yy & 7)
                ref[a] = (ref[a] & msk[c*bob_h+r]) | img[c*bob_h+r]
    diff = sum(1 for a in range(8000) if ref[a] != buf[a])
    render_cycles = struct.unpack("<I", S[10:14])[0]; tenfr = struct.unpack("<I", S[14:18])[0]
    png = HERE / prg_name.replace(".prg", "-vice.png")
    render(buf, [0x00, 0x0B, 0x0E, 0x01], str(png))
    print("%s: magic %s frames %d bobs %d front %d  mismatching bytes %d  render %d cycles, frame %.0f  -> %s"
          % (prg_name, S[:4], frames, nbobs, front, diff, render_cycles, tenfr/10, png.name))
    shutil.rmtree(work)
    return diff == 0

if __name__ == "__main__":
    nb = int(os.environ.get("NBOBS", "16"))
    ok = all(main(p, nb) for p in sys.argv[1:])
    sys.exit(0 if ok else 1)
