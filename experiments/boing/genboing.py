#!/usr/bin/env python3
"""The boing: signed 8-bit mono PCM at 11,025 Hz, about 0.35 s. A sine falling
from 420 Hz to 160 Hz with an exponential decay and a little second harmonic."""
import math

RATE = 11025
SECONDS = 0.35
F0, F1 = 420.0, 160.0

def main():
    n = int(RATE * SECONDS)
    out = bytearray()
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = F0 * (F1 / F0) ** (t / SECONDS)
        env = math.exp(-t * 9.0)
        s = math.sin(phase) + 0.25 * math.sin(2 * phase)
        out.append(int(max(-127, min(127, round(s * env * 0.9 * 127 / 1.25)))) & 0xFF)
        phase += 2 * math.pi * f / RATE
    open("boing8.pcm", "wb").write(out)
    print("boing.pcm: %d bytes, rate divider %d" % (len(out), round(6250000 / RATE)))
    assert len(out) < 4096 and out[0] == 0

if __name__ == "__main__":
    main()
