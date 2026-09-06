#!/usr/bin/env python3
"""VICE smoke checks for the native-linked demos (no Ultimate hardware needed).

Follow Me injects one correct answer at the keyboard-return boundary, then
lets the next round time out. This checks game flow, not physical key input.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]


def check(demo):
    directory = REPO / "demos" / demo
    stem = "followme" if demo == "follow-me" else demo
    symbols = {}
    for value, name in re.findall(r"^al ([0-9a-fA-F]+) \.(\w+)$",
                                  (directory / (stem + ".lbl")).read_text(), re.M):
        symbols.setdefault(name, int(value, 16))

    def until(name):
        return f"until {symbols[name]:04x}"

    def save(name, address, size):
        return f'save "{name}.bin" 0 {address:04x} {address + size - 1:04x}'

    commands = ["until 0900"]
    if demo == "vsprites":
        commands += [until("frame_loop")] * 31
        commands += [save("status", 0x033c, 17),
                     'screenshot "first.png" 2', save("bitmap1", 0x4000, 8000)]
        commands += [until("frame_loop")] * 20
        commands += [save("later", 0x033c, 17), save("bitmap2", 0x4000, 8000)]
    else:
        commands += [until("local_main_3"), 'screenshot "first.png" 2',
                     f'> {symbols["GameMode"]:04x} 01',
                     f'> {symbols["GameSpeed"]:04x} 0c',
                     f'r pc = {symbols["GameLoop"]:04x}', until("HumanWaitForKey"),
                     save("pattern", symbols["GamePattern"], 32),
                     # r12L holds the expected note. Inject a correct "1".
                     '> 22 01', f'r pc = {symbols["HumanGotKey"]:04x}, a = 31',
                     until("HumanPatternComplete"), save("score", symbols["Score"], 2),
                     until("HumanWaitForKey"), until("WaitForReplayKey"),
                     save("mode", symbols["GameMode"], 1)]
    commands += ['screenshot "last.png" 2', "quit", ""]

    with tempfile.TemporaryDirectory(prefix=stem + "-vice-") as tmp:
        work = Path(tmp)
        (work / "monitor.txt").write_text("\n".join(commands))
        result = subprocess.run([
            "x64sc", "-default", "-console", "-warp", "+sound",
            "-autostartprgdiskimage", str(work / "autostart.d64"),
            "-moncommands", str(work / "monitor.txt"),
            "-autostart", str(directory / (stem + ".prg")),
        ], cwd=work, capture_output=True, timeout=60)
        assert result.returncode == 0, result.stderr.decode(errors="replace")

        def data(name):
            return (work / (name + ".bin")).read_bytes()[2:]

        if demo == "vsprites":
            first, last = data("status"), data("later")
            assert first[:4] == last[:4] == b"VSPR"
            assert last[14] == 1 and last[12] >= 1
            assert int.from_bytes(last[4:6], "little") > int.from_bytes(first[4:6], "little")
            assert data("bitmap1") != data("bitmap2"), "vsprites did not move"
        else:
            pattern = data("pattern")
            assert pattern[31] == 1 and 1 <= pattern[0] <= 4
            assert data("score") == b"\x00\x10", "correct move did not score"
            assert data("mode") == b"\x04", "timeout did not reach game over"
        assert (work / "first.png").stat().st_size > 1000
        assert (work / "last.png").stat().st_size > 1000
    print(f"ok - {demo}: VICE startup and " +
          ("moving bitmap vsprites" if demo == "vsprites" else "correct-answer score and timeout"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("demo", choices=("vsprites", "follow-me"))
    check(parser.parse_args().demo)
