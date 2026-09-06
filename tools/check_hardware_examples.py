#!/usr/bin/env python3
"""Run built, standalone C/assembly examples on an Ultimate (resets the C64).

Build first: make examples; make -C guide check-examples
Run: python3 tools/check_hardware_examples.py --host <Ultimate IP>
Checks screen RAM and border registers, not HDMI appearance or audio.
"""
import argparse
from pathlib import Path
import sys
import time

from u64_settings import Ultimate, read_settings, restore_settings

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests/hardware"))
from screen import screen_text

CMD = ("C64 and Cartridge Settings", "Command Interface")
TURBO = ("U64 Specific Settings", "Turbo Control")


def run(u, path, expected=(), border=None):
    u.run_prg(ROOT / path)
    time.sleep(3)
    deadline = time.monotonic() + 20
    while True:
        text = screen_text(u.readmem(0x0400, 1000))
        # The loader prints READY before RUN too; require the one after RUN.
        finished = "RUN\n" in text and "READY." in text.split("RUN\n", 1)[1]
        color = u.readmem(0xD020, 1)[0] & 15
        if finished and all(part in text for part in expected) and (
                border is None or color == border):
            assert "?" not in text, text
            print(f"ok - {path}" + (f" border={color}" if border is not None else ""))
            print(text, flush=True)
            return
        if time.monotonic() >= deadline:
            raise AssertionError(f"{path}: expected {expected}, border={border}; "
                                 f"actual border={color}; "
                                 f"UCI={u.get_setting(*CMD)}, "
                                 f"turbo={u.get_setting(*TURBO)}, "
                                 f"DF1D={u.readmem(0xDF1D, 1).hex()}\n{text}")
        time.sleep(0.25)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True)
    args = parser.parse_args()
    u = Ultimate(args.host)
    print(u.info(), flush=True)
    saved = read_settings(u, [CMD, TURBO])
    print(f"# saved settings: {saved}", flush=True)
    failures = []

    def check(path, expected=(), border=None):
        try:
            run(u, path, expected, border)
        except AssertionError as exc:
            failures.append(str(exc))
            print(f"not ok - {exc}", flush=True)

    try:
        u.set_setting(*TURBO, "Off")
        for enabled in ("Disabled", "Enabled"):
            u.set_setting(*CMD, enabled)
            print(f"# UCI {enabled}", flush=True)
            check("guide/examples/hello-c.prg",
                ("ULTIMATE: NO ULTIMATE FOUND",) if enabled == "Disabled"
                else ("RUN\nREADY.",))
            for variant in ("asm", "custom"):
                check(f"guide/examples/hello-{variant}.prg",
                    ("\nNO ULTIMATE FOUND\n" if enabled == "Disabled"
                     else "\nULTIMATE FOUND\n",))
        check("guide/examples/discover.prg", ("DOS: ULTIMATE", "MODEL RECEIVED:"))
        for language in ("cc65", "asm"):
            check(f"examples/{language}/identify.prg", ("ULTIMATE SDK - IDENTIFY",))
            check(f"examples/{language}/sid-info.prg", ("SID COUNT:",))
        check("examples/cc65/files.prg", ("REU     :",))
        # fileinfo deliberately references an emulator fixture; accept its
        # missing-file report on hardware, but require a real drive response.
        check("examples/asm/fileinfo.prg", ("DRIVE AT DEVICE $",))
        u.set_setting(*CMD, "Disabled")  # turbo requires no UCI transport
        for setting, color in (("Off", 2), ("U64 Turbo Registers", 5)):
            u.set_setting(*TURBO, setting)
            print(f"# Turbo {setting}, UCI disabled", flush=True)
            for language in ("c", "asm"):
                check(f"guide/examples/selective-{language}.prg", border=color)
    finally:
        restore_settings(u, saved)
        print("# settings restored; flash was not written", flush=True)
    print(f"# {len(failures)} failed example runs", flush=True)
    return int(bool(failures))


if __name__ == "__main__":
    sys.exit(main())
