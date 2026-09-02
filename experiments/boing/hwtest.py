#!/usr/bin/env python3
"""Run the Boing ball on a real Ultimate and watch it bounce.

    python3 hwtest.py --host 192.168.1.62 [--prg boing.prg]

The PRG is over the REST runner's 16 KB body limit (blob, frames, background
and sample inside), so it goes to /Temp over FTP and runs from there. Then the
status block at $033C is read back: frame rate, feature flags, bounces and the
last SDK result, and x/y/rotation every half second for eight seconds.
"""
import argparse
import ftplib
import io
import pathlib
import sys
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from u64_settings import Ultimate, require_settings, restore_settings  # noqa: E402

STATUS = 0x033C
REMOTE = "/Temp/boing.prg"
AUDIO = ("C64 and Cartridge Settings", "Map Ultimate Audio $DF20-DFFF")
REU = ("C64 and Cartridge Settings", "RAM Expansion Unit")
TURBO = ("U64 Specific Settings", "Turbo Control")


def upload(host, path):
    data = open(path, "rb").read()
    f = ftplib.FTP(host, timeout=30)
    f.login()
    try:
        f.cwd("/Temp")
        f.storbinary("STOR boing.prg", io.BytesIO(data))
    finally:
        f.quit()
    return len(data)


def status(u):
    b = u.readmem(STATUS, 14)
    return dict(magic=b[:4], frames=b[4] | (b[5] << 8), x=b[6] | (b[7] << 8), y=b[8],
                rot=b[9], flags=b[10], bounces=b[11], result=b[12])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", required=True)
    ap.add_argument("--prg", default=str(pathlib.Path(__file__).with_name("boing.prg")))
    args = ap.parse_args()
    u = Ultimate(args.host)
    changed = require_settings(u, {AUDIO: "Enabled", REU: "Enabled", TURBO: "U64 Turbo Registers"})
    try:
        print("uploaded %d bytes to %s" % (upload(args.host, args.prg), REMOTE))
        u._request("PUT", "/machine:reset")
        time.sleep(2.0)
        req = urllib.request.Request(u.base + "/runners:run_prg?file=" + REMOTE, method="PUT")
        urllib.request.urlopen(req, timeout=15).read()
        deadline = time.time() + 15
        while time.time() < deadline and status(u)["magic"] != b"BONG":
            time.sleep(0.2)
        s = status(u)
        if s["magic"] != b"BONG":
            print("not ok - the demo did not start"); return 1
        a = s; t0 = time.time()
        time.sleep(2.0)
        b = status(u); t1 = time.time()
        fps = ((b["frames"] - a["frames"]) & 0xFFFF) / (t1 - t0)
        f = b["flags"]
        print("%.1f fps; turbo %s, REU+shadow %s, audio %s; last SDK result %d" % (
            fps, "yes" if f & 1 else "no", "yes" if f & 2 else "no", "yes" if f & 4 else "no", b["result"]))
        for _ in range(16):
            s = status(u)
            print("  x %3d y %3d rot %2d bounces %3d" % (s["x"], s["y"], s["rot"], s["bounces"]))
            time.sleep(0.5)
        ok = fps > 50 and s["bounces"] > b["bounces"]
        print(("ok" if ok else "not ok") + " - %.1f fps, %d bounces in eight seconds" % (fps, s["bounces"] - b["bounces"]))
        return 0 if ok else 1

    finally:
        restore_settings(u, changed, warn=lambda m: print("warning: " + m, file=sys.stderr))

if __name__ == "__main__":
    sys.exit(main())
