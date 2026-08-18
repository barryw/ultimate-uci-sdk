#!/usr/bin/env python3
"""The BASIC wedge, typed at a real C64.

    make basic-run U64_HOST=192.168.1.62

Everything here exists because the emulator suite cannot reach it. The wedge's
tokeniser runs only when a line is *typed*: ICRNCH is reached from the screen
editor, and no program can call it. So basic.suite drives the wedge's entry
points directly, and that is exactly where four bugs hid - every one of them
found by this script on the first run against real hardware:

  - IGONE's CMP cleared the carry GONE3 needs, so every statement the wedge
    does not own dispatched one token low. PRINT became PRINT#.
  - CRUNCH returns the line length in Y and its caller stores the line by it.
    The wedge returned whatever Y its loop ended on.
  - CRUNCH plants a null link two bytes past the terminator, and NEWSTT reads
    it to decide a direct line has finished. Compaction moved the terminator
    and left that zero stranded, so BASIC ran on into what had been typed.
  - The observers left TXTPTR on their own token, so PRINT UDOS1 printed 1 for
    ever.

None of those is reachable by calling a routine. All of them are obvious the
moment a person types a line.

Settings are read first and restored afterwards, including on Ctrl-C, through
the same guard hwtest.py uses. Nothing is written to flash.

SPDX-License-Identifier: MIT
"""

import argparse
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "..", "tools"))

from u64_settings import Ultimate, require_settings, restore_settings  # noqa: E402

from screen import decode_screen  # noqa: E402
from keyboard import type_line    # noqa: E402

CMD_IF = ("C64 and Cartridge Settings", "Command Interface")

WEDGE_PRG = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         "..", "..", "src", "basic", "uci.prg")

# (line to type, what has to appear on the screen afterwards, why)
CHECKS = [
    ("PRINT 2+3", " 5",
     "ordinary BASIC still works - the wedge owns four vectors and has to hand "
     "back everything it does not recognise, exactly as it found it"),

    ("PRINT UDOS1", " 1",
     "a target constant evaluates, and evaluates once"),

    ("PRINT UHTTP", " 6",
     "the last constant, so the whole keyword table is walked"),

    ("UCI 1,1", "READY.",
     "the generic statement runs a command and returns without an error"),

    ("PRINT UERR", " 0",
     "and the command reported success"),

    ("PRINT UBYTE(0);UBYTE(1);UBYTE(2)", " 85  76  84",
     "the reply is readable byte by byte: 'U' 'L' 'T'"),

    ("PRINT UDAT$", "ULTIMATE",
     "and as a string - this is the real Ultimate naming itself through BASIC"),
]


def run(host, port, verbose):
    u = Ultimate(host, port)
    info = u.info()
    print("# %s, firmware %s (fpga %s, core %s)"
          % (info["product"], info["firmware_version"],
             info["fpga_version"], info["core_version"]))

    changed = require_settings(u, {CMD_IF: "Enabled"})
    if changed:
        print("# saved settings: %s"
              % ", ".join("%s=%s" % (k[1], v) for k, v in changed.items()))
    failures = 0
    try:
        print("# installing the wedge")
        u.run_prg(os.path.normpath(WEDGE_PRG))
        time.sleep(5)

        screen = decode_screen(u.readmem(0x0400, 1000))
        if not any("ULTIMATE UCI BASIC WEDGE INSTALLED." in line for line in screen):
            print("not ok 1 - the wedge did not install")
            print("#   the banner never appeared. Screen:")
            for line in screen[-6:]:
                print("#   |", line)
            return 1
        print("ok 1 - wedge installed, banner readable")

        for index, (line, expected, why) in enumerate(CHECKS, start=2):
            type_line(u, line)
            time.sleep(2)
            screen = decode_screen(u.readmem(0x0400, 1000))
            tail = screen[-6:]

            # The typed line is echoed, so look only at what came after it.
            after = []
            for i, text in enumerate(screen):
                if text.strip() == line:
                    after = screen[i + 1:]
            hit = any(expected in text for text in after)
            errors = [t for t in after if "ERROR" in t]

            if hit and not errors:
                print("ok %d - %s" % (index, line))
            else:
                failures += 1
                print("not ok %d - %s" % (index, line))
                print("#   expected %r after the line" % expected)
                if errors:
                    print("#   BASIC reported: %s" % errors[0])
                for text in tail:
                    print("#   |", text)
            print("#   %s" % why)
            if verbose:
                for text in tail:
                    print("#   |", text)
    finally:
        restore_settings(u, changed)
        print("# settings restored; flash was never written")

    print("1..%d" % (len(CHECKS) + 1))
    print("# %d passed, %d failed" % (len(CHECKS) + 1 - failures, failures))
    return 1 if failures else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", required=True)
    ap.add_argument("--port", type=int, default=80)
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()
    sys.exit(run(args.host, args.port, args.verbose))


if __name__ == "__main__":
    main()
