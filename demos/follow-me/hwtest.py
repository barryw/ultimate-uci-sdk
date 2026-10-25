#!/usr/bin/env python3
"""Real keyboard/score/timeout checks, with PCM+palette and SID fallback."""
import argparse
from pathlib import Path
import re
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tests/hardware"))
from u64_settings import Ultimate, read_settings, restore_settings
from keyboard import type_text
from screen import screen_text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True)
    args = parser.parse_args()
    symbols = dict((name, int(value, 16)) for value, name in re.findall(
        r"^al ([0-9a-fA-F]+) \.(\w+)$", (HERE / "followme.lbl").read_text(), re.M))
    u = Ultimate(args.host)
    print(u.info(), flush=True)
    category = "C64 and Cartridge Settings"
    requirements = {
        (category, "Command Interface"): "Enabled",
        (category, "RAM Expansion Unit"): "Enabled",
        (category, "Map Ultimate Audio $DF20-DFFF"): "Enabled",
        ("U64 Specific Settings", "Turbo Control"): "Off",
    }
    saved = read_settings(u, requirements)

    def read(name, size=1):
        return u.readmem(symbols[name], size)

    def wait_for(predicate, description, timeout=20):
        deadline = time.monotonic() + timeout
        while not predicate():
            if time.monotonic() > deadline:
                raise AssertionError(description + "\n" + screen_text(u.readmem(0x400, 1000)))
            time.sleep(0.05)

    game_running = False
    try:
        for key, value in requirements.items():
            u.set_setting(*key, value)
        for enabled in (True, False):
            u.set_setting(category, "Command Interface", "Enabled" if enabled else "Disabled")
            u.run_prg(HERE / "followme.prg")
            game_running = True
            time.sleep(3)
            wait_for(lambda: read("GameMode") == b"\0",
                     "attract mode did not start")
            assert read("AudioReady") == bytes([enabled]), "PCM availability"
            assert read("PaletteReady") == bytes([enabled]), "palette availability"
            type_text(u, "1")
            wait_for(lambda: read("GameMode") == b"\2", "human turn did not start")
            note = read("GamePattern")[0]
            assert 1 <= note <= 4, note
            type_text(u, str(note))
            wait_for(lambda: read("Score", 2) == b"\0\x10", "correct answer did not score")
            wait_for(lambda: read("GameMode") == b"\4", "no-input timeout did not end game")
            time.sleep(0.2)
            type_text(u, "N")
            wait_for(lambda: "READY." in screen_text(u.readmem(0x400, 1000)),
                     "N did not exit to BASIC")
            game_running = False
            print(f"ok - {'PCM/palette' if enabled else 'SID fallback'}: keyboard, "
                  "correct answer, score 10, timeout, exit", flush=True)
    finally:
        try:
            if game_running:
                # Use the game's exit path so a failure restores its palette.
                u.writemem(symbols["GameMode"], b"\4")
                time.sleep(2)
                type_text(u, "N")
                wait_for(lambda: "READY." in screen_text(u.readmem(0x400, 1000)),
                         "cleanup could not exit game (palette may need restoration)", 5)
        finally:
            restore_settings(u, saved)
            print("# settings restored", flush=True)


if __name__ == "__main__":
    main()
