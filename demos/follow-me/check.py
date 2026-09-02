#!/usr/bin/env python3
"""Small build check for the embedded SDK, PCM loops, and Simon palette."""

import re
from pathlib import Path


ROOT = Path(__file__).parent
prg = (ROOT / "followme.prg").read_bytes()
load = int.from_bytes(prg[:2], "little")
symbol_text = (ROOT / "followme.sym").read_text()
symbols = {
    name: int(value, 16)
    for name, value in re.findall(
        r"\.label ([A-Za-z][A-Za-z0-9_]*)=\$([0-9a-f]+)", symbol_text
    )
}


def memory(address, length):
    offset = address - load + 2
    return prg[offset : offset + length]


assert memory(0x7000, 4) == bytes((0xD5, 0xC3, 0xC9, 1))
assert memory(0x72E8, 24)[::3] == bytes((0x4C,)) * 8
assert symbols["INPUT_TIMEOUT"] == 180
assert symbols["PatternLength"] - symbols["GamePattern"] == 31

tones = (
    ("ToneFail", "ToneRed", 42),
    ("ToneRed", "ToneYellow", 310),
    ("ToneYellow", "ToneGreen", 252),
    ("ToneGreen", "ToneBlue", 415),
    ("ToneBlue", "ToneBankEnd", 209),
)
for start, end, expected_hz in tones:
    loop = memory(symbols[start], symbols[end] - symbols[start])
    assert set(loop) == {0x48, 0xB8}
    assert loop.count(0x48) == loop.count(0xB8)
    assert abs(25000 / len(loop) - expected_hz) < 3

palette = memory(symbols["SimonPalette"], 48)
for index, expected in {
    2: (72, 8, 14),
    5: (8, 56, 26),
    6: (7, 24, 62),
    8: (96, 88, 8),
}.items():
    assert palette[index * 3 : index * 3 + 3] == bytes(expected)
for dim, bright in ((2, 10), (8, 7), (5, 13), (6, 14)):
    assert sum(palette[bright * 3 : bright * 3 + 3]) > sum(
        palette[dim * 3 : dim * 3 + 3]
    )

print("ok - SDK blob, bounded game loop, five PCM loops, and glow palette")
