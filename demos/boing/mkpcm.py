#!/usr/bin/env python3
"""Turn a sample into what the demo plays: signed 8-bit mono PCM
in boing.pcm, and boing_pcm.inc with its byte length and 6.25 MHz rate divider.

    python3 mkpcm.py boing.wav        # any mono/stereo 8/16-bit PCM WAV
    python3 mkpcm.py raw8.pcm RATE    # raw signed 8-bit at RATE Hz
    python3 mkpcm.py                  # the synthesised fallback from genboing.py
"""
import struct, sys, wave

def from_wav(path):
    w = wave.open(path, "rb")
    ch, width, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
    raw = w.readframes(n); w.close()
    out = []
    for i in range(n):
        if width == 1:
            v = (raw[i*ch] - 128) << 8
        else:
            v = struct.unpack_from("<h", raw, i*ch*width)[0]
        out.append(v)
    return out, rate

def from_raw8(path, rate):
    raw = open(path, "rb").read()
    return [((b - 256) if b > 127 else b) << 8 for b in raw], rate

def main():
    if len(sys.argv) >= 3:
        samples, rate = from_raw8(sys.argv[1], int(sys.argv[2]))
    elif len(sys.argv) == 2:
        samples, rate = from_wav(sys.argv[1])
    else:
        import genboing; genboing.main()
        samples, rate = from_raw8("boing8.pcm", 11025)
    # Signed 8-bit, resident in the PRG in two pieces around the I/O area:
    # 8,912 bytes at $ad30-$cfff and up to 8,186 at $e000-$fff9. The short tail
    # trim keeps the IRQ vectors at $fffa-$ffff out of the resident sample.
    PIECE_A, PIECE_B_MAX = 8912, 8186
    data = bytes(max(-128, min(127, v >> 8)) & 0xFF for v in samples)[:PIECE_A + PIECE_B_MAX]
    open("boing.pcm", "wb").write(data)
    a = min(PIECE_A, len(data)); b = len(data) - a
    div = round(6250000 / rate)
    open("boing_pcm.inc", "w").write(".const PCM_A    = %d\n.const PCM_B    = %d\n.const PCM_LEN  = %d\n.const PCM_RATE = %d   // 6250000 / %d Hz\n" % (a, b, len(data), div, rate))
    print("boing.pcm: %d bytes of 8-bit PCM at %d Hz (divider %d), pieces %d + %d" % (len(data), rate, div, a, b))

if __name__ == "__main__":
    main()
