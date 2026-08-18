#!/usr/bin/env python3
"""
How long is one UCI round trip, in frames?

Runs tests/hardware/ucitime.prg on a real Ultimate and reads its results back by
DMA. The C64 measures; this only divides and prints.

    python3 ucitime.py --host 192.168.1.62

Every number the program publishes is in CIA cycles off one chained 32-bit
counter, and one of those numbers is the length of a raster frame measured on
that same counter. So "frames per call" is a ratio of two figures from one
clock: it does not care whether the machine is PAL or NTSC, what the CIA is
really clocked at on an Ultimate 64, or whether the CPU is in turbo. The turbo
register is reported so the answer can be read in context.

This touches no settings. Wrap it in tools/u64_settings.py if the command
interface might be disabled, which on the bench machine it usually is - the
Makefile's time-run target does exactly that.

Part of the Ultimate SDK. SPDX-License-Identifier: MIT
"""

import argparse
import math
import os
import sys
import time
import urllib.error

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "tools"))

from u64_settings import Ultimate  # noqa: E402

from screen import decode_screen, SCREEN_ADDR, SCREEN_LEN  # noqa: E402

# The result block ucitime.prg publishes into the cassette buffer. Layout is
# documented beside publish() in ucitime.c; keep the two in step.
RESULT_ADDR = 0x033C
RESULT_LEN = 59
RESULT_MAGIC = b"UCIM"
RESULT_DONE = 0xA5
MAX_SLOTS = 8

# Slot names, in the order ucitime.c fills them. A slot the program measured but
# this list does not name still reports, under its number - so adding a
# measurement to the C side and forgetting this list degrades rather than lies.
NAMES = [
    "identify",
    "echo",
    "echo (no reply)",
    "get-palette",
    "set-palette-color",
    "set-palette-color (no reply)",
    "set-palette (all 16)",
    "set-palette (no reply)",
]

def error_names():
    """ULTIMATE_* codes, read out of the generated header rather than copied.

    A transcribed copy of this table was wrong within five minutes of being
    written, which is the same lesson the argument shapes taught in
    docs/handover.md section 2: the generated file is the source of truth, so
    read it.
    """
    out = {}
    path = os.path.join(REPO, "include", "uci_protocol.h")
    with open(path) as fh:
        for line in fh:
            parts = line.split()
            if len(parts) >= 3 and parts[0] == "#define" and \
                    (parts[1] == "ULTIMATE_OK" or parts[1].startswith("ULTIMATE_ERR_")):
                name = parts[1].replace("ULTIMATE_ERR_", "").replace("ULTIMATE_", "")
                out[int(parts[2])] = name.lower().replace("_", " ")
    return out


ERRORS = error_names()


def u32(block, at):
    return (block[at] | (block[at + 1] << 8) |
            (block[at + 2] << 16) | (block[at + 3] << 24))


class Result:
    def __init__(self, block):
        self.valid = block[0:4] == RESULT_MAGIC
        if not self.valid:
            return
        self.format = block[4]
        self.slots = block[5]
        self.pal = block[6]
        self.iters = block[7]
        self.turbo = block[8]
        self.frame = u32(block, 10)
        self.overhead = u32(block, 14)
        self.cycles = [u32(block, 18 + 4 * i) for i in range(MAX_SLOTS)]
        self.errors = list(block[50:50 + MAX_SLOTS])
        self.done = block[58] == RESULT_DONE


def run_once(u, prg, settle=6.0, poll_timeout=60.0):
    """Boot the program and wait for it to publish. Same shape as hwtest.py."""
    u.writemem(RESULT_ADDR, bytes(RESULT_LEN))
    u.run_prg(prg)

    deadline = time.time() + poll_timeout
    time.sleep(settle)
    result = None
    while time.time() < deadline:
        result = Result(u.readmem(RESULT_ADDR, RESULT_LEN))
        if result.valid and result.done:
            break
        time.sleep(1.0)
    screen = decode_screen(u.readmem(SCREEN_ADDR, SCREEN_LEN))
    return result, screen


# What a frame is on a stock machine, printed beside the measured figure. The
# measurement is the one used for every ratio below; this is only here so that a
# broken measurement is obvious instead of merely plausible - which is exactly
# how the first version's missing raster sync was caught.
TEXTBOOK_FRAME = {1: ("PAL", 63 * 312), 0: ("NTSC", 65 * 263)}


def report(result):
    kind, expected = TEXTBOOK_FRAME.get(result.pal, ("unknown", 0))
    print("# frame        = %d cycles, measured (%s; a stock one is %d)"
          % (result.frame, kind, expected))
    print("# turbo reg    = $%02X (%s)"
          % (result.turbo,
             "turbo unavailable" if result.turbo == 0xFF
             else "turbo on, speed index %d" % (result.turbo & 0x0F)))
    print("# timer cost   = %d cycles, subtracted from every measurement"
          % result.overhead)
    print("# %d calls averaged per measurement" % result.iters)
    print()
    print("%-30s %9s %8s %10s" % ("command", "cycles", "frames", "per frame"))

    fastest = None
    for i in range(result.slots):
        name = NAMES[i] if i < len(NAMES) else "measurement %d" % i
        err = result.errors[i]
        if err != 0 or result.cycles[i] == 0:
            print("%-30s %9s %8s %10s   %s"
                  % (name, "-", "-", "-", ERRORS.get(err, "error %d" % err)))
            continue
        per_call = result.cycles[i] / result.iters
        frames = per_call / result.frame
        print("%-30s %9d %8.2f %10.1f"
              % (name, round(per_call), frames, 1.0 / frames))
        if fastest is None or frames < fastest[1]:
            fastest = (name, frames)

    if fastest is None:
        print("\nnothing measured.")
        return

    # The question this was written to answer: a colour cycle is every colour
    # moving at once, so the whole-palette write is the number that decides
    # whether the boing ball can cycle per frame. See docs/handover-next.md.
    rotation = NAMES.index("set-palette (all 16)")
    if rotation < result.slots and result.errors[rotation] == 0 \
            and result.cycles[rotation]:
        per_call = result.cycles[rotation] / result.iters
        frames = per_call / result.frame
        print()
        print("a whole-palette rotation - all 16 colours, one command - costs")
        print("%.2f frames (%.1f per frame)." % (frames, 1.0 / frames))

    name, frames = fastest
    print()
    print("cheapest round trip: %s, %.2f frames (%.1f per frame)"
          % (name, frames, 1.0 / frames))
    if frames <= 0.5:
        print("verdict: several fit in a frame. cycle the palette directly.")
    elif frames <= 1.0:
        print("verdict: one fits in a frame, with nothing to spare. cycle every")
        print("         frame only if the demo has cycles left over.")
    else:
        print("verdict: a round trip costs more than a frame. cycle every %d"
              % math.ceil(frames))
        print("         frames, or drive the C64's own colour registers and use")
        print("         the Ultimate's palette to change what they mean.")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", required=True, help="hostname or IP of the Ultimate")
    ap.add_argument("--port", type=int, default=80)
    ap.add_argument("--prg", default="ucitime.prg")
    ap.add_argument("--verbose", action="store_true", help="print the C64 screen")
    args = ap.parse_args()

    u = Ultimate(args.host, args.port)
    try:
        info = u.info()
    except (urllib.error.URLError, OSError) as exc:
        print("cannot reach the Ultimate at %s: %s" % (args.host, exc))
        return 2

    print("# %s, firmware %s (fpga %s, core %s)"
          % (info.get("product"), info.get("firmware_version"),
             info.get("fpga_version"), info.get("core_version")))

    result, screen = run_once(u, args.prg)

    if result is None or not result.valid or not result.done:
        print("no result block: the program did not reach the end.")
        for line in screen:
            print("| %s" % line)
        return 1

    report(result)

    if args.verbose:
        print()
        for line in screen:
            print("| %s" % line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
