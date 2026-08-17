#!/usr/bin/env python3
"""
Emit a relocation table for the standalone SDK blob.

Two builds of identical source one page apart differ in exactly the bytes that
hold the high half of an absolute address. Diffing them finds every one without
teaching this script anything about 6502 addressing modes, which is the point:
there is no instruction table here to fall behind the assembler.

    python3 tools/gen_reloc.py low.bin high.bin out.reloc

The output is a little-endian count followed by that many little-endian 16-bit
offsets, sorted. A relocator adds (wanted_base_high - built_base_high) to the
byte at each offset.

SPDX-License-Identifier: MIT
"""

import struct
import sys


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        return 2

    low = open(sys.argv[1], "rb").read()
    high = open(sys.argv[2], "rb").read()

    if len(low) != len(high):
        print("the two builds differ in length: %d vs %d" % (len(low), len(high)))
        return 1

    offsets = []
    for i, (a, b) in enumerate(zip(low, high)):
        if a == b:
            continue
        if b - a != 1:
            print("offset %d differs by %d, not 1 - the two builds are not "
                  "one page apart, or something other than an address moved"
                  % (i, b - a))
            return 1
        offsets.append(i)

    with open(sys.argv[3], "wb") as fh:
        fh.write(struct.pack("<H", len(offsets)))
        for off in offsets:
            fh.write(struct.pack("<H", off))

    print("wrote %s: %d relocations in %d bytes (%d bytes of table)"
          % (sys.argv[3], len(offsets), len(low), 2 + 2 * len(offsets)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
