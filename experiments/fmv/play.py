#!/usr/bin/env python3
"""Upload and leave the sample looping; --stop exits and restores settings."""
import argparse
import ftplib
import json
from pathlib import Path
import re
import sys
import time

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / "tools"))
from u64_settings import Ultimate, require_settings, restore_settings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True)
    parser.add_argument("--stop", action="store_true")
    parser.add_argument("--assets", type=Path, default=HERE / "build" / "dragons-lair")
    args = parser.parse_args()
    u = Ultimate(args.host, timeout=60)
    saved_path = HERE / "build" / "player-settings.json"
    if args.stop:
        saved = json.loads(saved_path.read_text())
        if saved["host"] != args.host:
            raise ValueError("saved settings belong to another host")
        status = u.readmem(0x033c, 16)
        if status[:4] == b"FMVP" and status[4] in (1, 2):
            u.writemem(0x0342, b"\x01")
            for _ in range(100):
                time.sleep(0.1)
                if u.readmem(0x033c, 16)[4] in (3, 0x80):
                    break
            else:
                raise RuntimeError("player did not stop; settings left intact")
        restore_settings(u, {tuple(k): v for k, v in saved["changed"]})
        saved_path.unlink()
        print("Stopped; original device settings restored.")
        return
    if saved_path.exists():
        raise RuntimeError("previous settings are saved; use --stop before relaunching")
    assets = args.assets
    manifest = json.loads((assets / "manifest.json").read_text())
    assert (manifest["fps"], manifest["frame_count"], manifest["bytes_per_frame"]) == (24, 288, 10049)
    assert (assets / "custom.frames").stat().st_size == 288 * 10049
    assert (assets / "audio-16000hz-mono.s8").stat().st_size == 192000
    link_map = (HERE / "build" / "player.map").read_text()
    bss = re.search(r"^BSS\s+[0-9A-F]+\s+([0-9A-F]+)", link_map, re.M)
    assert bss and int(bss[1], 16) < 0x4400, "program overlaps screen buffer"
    category = "C64 and Cartridge Settings"
    changed = require_settings(u, {
        (category, "Command Interface"): "Enabled",
        (category, "RAM Expansion Unit"): "Enabled",
        (category, "REU Size"): "16 MB",
        (category, "Map Ultimate Audio $DF20-DFFF"): "Enabled",
    })
    saved_path.write_text(json.dumps({"host": args.host, "changed": list(changed.items())}, indent=2))
    launched = False
    try:
        with ftplib.FTP(args.host, timeout=60) as ftp:
            ftp.login()
            ftp.cwd("/Temp")
            for path, name in [(assets / "custom.frames", "fmv-custom.frames"),
                               (assets / "audio-16000hz-mono.s8", "fmv-audio.s8")]:
                print("Uploading", name, path.stat().st_size, flush=True)
                with path.open("rb") as data:
                    ftp.storbinary("STOR " + name, data)
        u.run_prg(HERE / "player.prg")
        launched = True
        for _ in range(180):
            time.sleep(0.5)
            status = u.readmem(0x033c, 16)
            if status[:4] == b"FMVP":
                if status[4] == 0x80:
                    raise RuntimeError(f"SDK error {status[5]}, stage {status[13]}")
                if status[4] == 2:
                    print("Playing on HDMI; RUN/STOP exits. Status:", status.hex(), flush=True)
                    return
        raise RuntimeError("player did not enter playback")
    except Exception:
        if launched:
            # Preserve settings until a confirmed stop; --stop performs cleanup.
            u.writemem(0x0342, b"\x01")
        else:
            restore_settings(u, changed)
            saved_path.unlink()
        raise


if __name__ == "__main__":
    main()
