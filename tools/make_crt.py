#!/usr/bin/env python3
"""Wrap a raw 8K cartridge image in the .crt container emulators and the
Ultimate expect.

    python3 tools/make_crt.py uci-cart.bin uci.crt "ULTIMATE UCI WEDGE"

The format is two headers and the bytes. Both are big-endian, which is worth
saying out loud in a 6502 repository where nothing else is.

  64 byte cartridge header
      +$00  16  "C64 CARTRIDGE   ", padded with spaces
      +$10   4  header length, always $40
      +$14   2  version, $0100
      +$16   2  hardware type, 0 for a plain cartridge
      +$18   1  EXROM line
      +$19   1  GAME line
      +$1A   6  reserved
      +$20  32  name, NUL padded

  16 byte CHIP packet, then the image
      +$00   4  "CHIP"
      +$04   4  packet length, including these 16 bytes
      +$08   2  chip type, 0 for ROM
      +$0A   2  bank
      +$0C   2  load address
      +$0E   2  image size

EXROM low and GAME high is the 8K configuration: the cartridge appears at
$8000-$9FFF and the machine is otherwise normal. The lines are recorded here
as their pin states, which is why the useful one is the zero.
"""

import sys

SIGNATURE = b"C64 CARTRIDGE   "
HEADER_LEN = 0x40
LOAD_ADDRESS = 0x8000
IMAGE_SIZE = 0x2000

EXROM_ASSERTED = 0      # pulled low: the cartridge is mapped
GAME_INACTIVE = 1       # left high: 8K, not 16K and not ultimax


def build(image, name):
    if len(image) != IMAGE_SIZE:
        raise SystemExit(
            "make_crt.py: expected exactly %d bytes, got %d. The linker fills "
            "the image, so a short one means the ROM memory area is not "
            "declared with fill = yes." % (IMAGE_SIZE, len(image)))

    header = bytearray(HEADER_LEN)
    header[0x00:0x10] = SIGNATURE
    header[0x10:0x14] = HEADER_LEN.to_bytes(4, "big")
    header[0x14:0x16] = (0x0100).to_bytes(2, "big")
    header[0x16:0x18] = (0x0000).to_bytes(2, "big")
    header[0x18] = EXROM_ASSERTED
    header[0x19] = GAME_INACTIVE
    header[0x20:0x40] = name.encode("ascii", "replace")[:32].ljust(32, b"\0")

    chip = bytearray(16)
    chip[0x00:0x04] = b"CHIP"
    chip[0x04:0x08] = (16 + len(image)).to_bytes(4, "big")
    chip[0x08:0x0A] = (0).to_bytes(2, "big")
    chip[0x0A:0x0C] = (0).to_bytes(2, "big")
    chip[0x0C:0x0E] = LOAD_ADDRESS.to_bytes(2, "big")
    chip[0x0E:0x10] = len(image).to_bytes(2, "big")

    return bytes(header) + bytes(chip) + image


def main():
    if len(sys.argv) != 4:
        raise SystemExit("usage: make_crt.py <image.bin> <out.crt> <name>")
    with open(sys.argv[1], "rb") as fh:
        image = fh.read()
    out = build(image, sys.argv[3])
    with open(sys.argv[2], "wb") as fh:
        fh.write(out)
    print("wrote %s (%d bytes)" % (sys.argv[2], len(out)))


if __name__ == "__main__":
    main()
