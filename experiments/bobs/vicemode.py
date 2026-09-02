#!/usr/bin/env python3
"""Screenshot a colour mode in VICE: python3 vicemode.py bobs32.prg 3 [nbobs]"""
import re, subprocess, sys, tempfile, pathlib, shutil
HERE = pathlib.Path(__file__).resolve().parent
prg, mode = sys.argv[1], int(sys.argv[2])
nbobs = int(sys.argv[3]) if len(sys.argv) > 3 else 24
sym = {k: int(v, 16) for k, v in re.findall(r"\.label (\w+)=\$([0-9a-fA-F]+)", (HERE / prg.replace(".prg", ".sym")).read_text())}
work = pathlib.Path(tempfile.mkdtemp(prefix="vicemode-"))
shutil.copy(HERE / prg, work / "t.prg")
out = HERE / ("%s-mode%d-vice.png" % (prg.replace(".prg", ""), mode))
mon = ["until %04x" % sym["frame_loop"], "> 0342 %02x" % nbobs, "> 035e %02x" % mode]
mon += ["until %04x" % sym["frame_loop"]] * 40
mon += ['screenshot "%s" 2' % out, "quit", ""]
(work / "mon.txt").write_text("\n".join(mon))
subprocess.run(["x64sc", "-console", "-warp", "+sound", "-moncommands", "mon.txt", "-autostart", "t.prg"],
               cwd=work, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=300)
shutil.rmtree(work)
print("wrote", out.name if out.exists() else "NOTHING")
