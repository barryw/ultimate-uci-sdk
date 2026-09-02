#!/usr/bin/env python3
"""The WAV files tests/emulator/sdk.suite feeds ultimate_audio_load_wav.

They are committed with the other fixtures under tests/emulator/fixtures/usb0;
run this to regenerate them. The values the suite asserts:

    mono16.wav    16-bit mono, 8,000 Hz, 128 data bytes, a 13-byte LIST chunk
                  (odd, so padded) in front of fmt: divider 781, flags $10
    stereo16.wav  16-bit stereo, 11,025 Hz, 128 data bytes: divider 566, flags $50
    mono8.wav     8-bit mono, 8,363 Hz, 100 data bytes: divider 747, flags $00
    notwav.bin    64 bytes that are not RIFF at all
"""
import os
import struct

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "tests/emulator/fixtures/usb0/wav")


def chunk(tag, body):
    pad = b"\x00" if len(body) & 1 else b""
    return tag + struct.pack("<I", len(body)) + body + pad


def fmt(channels, rate, bits):
    block = channels * bits // 8
    return chunk(b"fmt ", struct.pack("<HHIIHH", 1, channels, rate, rate * block, block, bits))


def wav(chunks):
    body = b"WAVE" + b"".join(chunks)
    return b"RIFF" + struct.pack("<I", len(body)) + body


FILES = {
    "mono16.wav": wav([chunk(b"LIST", b"INFOISFT\x01\x00\x00\x00s"),
                       fmt(1, 8000, 16),
                       chunk(b"data", struct.pack("<64h", *range(64)))]),
    "stereo16.wav": wav([fmt(2, 11025, 16),
                         chunk(b"data", struct.pack("<64h", *range(64)))]),
    "mono8.wav": wav([fmt(1, 8363, 8),
                      chunk(b"data", bytes(range(100)))]),
    "notwav.bin": b"NOPE" * 16,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, data in FILES.items():
        with open(os.path.join(OUT, name), "wb") as fh:
            fh.write(data)
        print("%s: %d bytes" % (name, len(data)))


if __name__ == "__main__":
    main()
