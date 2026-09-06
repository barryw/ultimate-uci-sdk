#!/usr/bin/env python3
"""Small build check for the embedded SDK, PCM loops, and Simon palette."""

import re
import hashlib
from pathlib import Path


ROOT = Path(__file__).parent
prg = (ROOT / "followme.prg").read_bytes()
load = int.from_bytes(prg[:2], "little")
symbol_text = (ROOT / "followme.lbl").read_text()
symbols = {
    name: int(value, 16)
    for value, name in re.findall(
        r"^al ([0-9a-fA-F]+) \.([A-Za-z][A-Za-z0-9_]*)$", symbol_text, re.M
    )
}


def memory(address, length):
    offset = address - load + 2
    return prg[offset : offset + length]


modules = set(re.findall(r"ultimate\.lib\(([^)]+)\)", (ROOT / "followme.map").read_text()))
assert modules == {"uci_core.o", "service_common.o", "ultimate.o", "palette.o", "reu.o", "audio.o"}
assert symbols["INPUT_TIMEOUT"] == 180
assert symbols["PatternLength"] - symbols["GamePattern"] == 31
# The PRG must include the gap up to the SDK's linked address, not merely
# concatenate its two memory areas. Check a real SDK instruction at that address.
assert memory(symbols["ultimate_init"], 3) == b"\x20" + symbols["uci_init"].to_bytes(2, "little")
# Preserve the original sprites and screen-code text/color data across the port.
for start, size, digest in (
    ("Sprites", 640, "ae2e27ed53249c2a667c5a8bd54b2c9cf23ee861e0f08c428ba3d1d5d26335c8"),
    ("StartMessage", 1137, "1581eb873374b7aa575376ffd9bc8064e7e5b580c151cda848b67a411786ad3c"),
):
    assert hashlib.sha256(memory(symbols[start], size)).hexdigest() == digest

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

print("ok - selective SDK link, bounded game loop, five PCM loops, and glow palette")
