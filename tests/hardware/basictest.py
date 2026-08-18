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
# UTURBO writes $D031, which only answers when its owner has chosen to let it.
# Required here for the same reason the command interface is: the point of this
# script is to type at a machine set up the way the keyword needs, and both
# settings are read first and put back afterwards.
TURBO = ("U64 Specific Settings", "Turbo Control")
# USTASH and UFETCH drive the REU's own DMA registers, which answer only when
# the expansion is switched on. Enabling it here is safe in a way that touching
# a file would not be: the machine had it off, so the expansion's contents are
# this script's own from the moment it appears, and the setting goes back
# afterwards with the others.
REU = ("C64 and Cartridge Settings", "RAM Expansion Unit")
# UREU measures the expansion rather than being told its size, so the size is
# pinned here and the machine has to agree. 2 MB is 32 banks of 64K.
REU_SIZE = ("C64 and Cartridge Settings", "REU Size")
REU_SIZE_WANT = "2 MB"
REU_BANKS_WANT = 32

BASIC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         "..", "..", "src", "basic")
WEDGE_PRG = os.path.join(BASIC_DIR, "uci.prg")
WEDGE_CRT = os.path.join(BASIC_DIR, "uci.crt")

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

    # UTURBO is the one keyword that does not go through UCI at all: turbo is
    # memory-mapped I/O, because the firmware has no command for CPU speed.
    # One token, two forms, so both are typed.
    ("UTURBO 3", "READY.",
     "the statement writes the speed index and does not error"),

    ("PRINT UERR", " 0",
     "and the machine accepted it - anything else means Turbo Control is not "
     "set to U64 Turbo Registers, which this script requires"),

    ("PRINT UTURBO", " 3",
     "the function form reads back what the statement wrote, sharing its token"),

    ("UTURBO 0", "READY.",
     "back to 1MHz, so the machine is left as it was found"),

    ("PRINT UTURBO", " 0",
     "and it really went back"),

    # The file keywords. $CB00 is 51968: above the wedge, which ends around
    # $CAB5, and below the I/O area - somewhere a load can land without
    # writing over the thing doing the loading.
    ('ULOAD "/USB1/DATA/HELLO.TXT",51968', "READY.",
     "a PRG load, with the address given rather than taken from the file"),

    ("PRINT UERR", " 0",
     "and the Ultimate found the file: this is the SoftwareIEC fast path, on "
     "the only machine that has one"),

    ("PRINT PEEK(51968)", " 76",
     "'L' - hello.txt starts HELLO, and a load eats the first two bytes as the "
     "PRG header whichever tier ran"),

    ('UBLOAD "/USB1/DATA/HELLO.TXT",51968,4', "READY.",
     "raw bytes, and a limit the SDK insists on"),

    ("PRINT PEEK(51968)", " 72",
     "'H' - bload strips nothing, which is the whole difference from ULOAD"),

    # The RAM expansion, typed. The C side of this is proved in ucitest.c; this
    # is the same DMA through the wedge, which is the promise the SDK is built
    # on - one operation, one call, from all three languages.
    # UREU is the only REU keyword that asks a question rather than moving
    # bytes, and it is how a BASIC program discovers there is an expansion at
    # all: zero means none, so one test covers both.
    ("PRINT UREU", " 32",
     "the expansion measures 32 banks, which is the 2 MB the harness set - and "
     "the C64 worked that out for itself, because no command reports it"),

    ("PRINT UREU*64", " 2048",
     "banks times 64 is kilobytes, which is why the unit is banks: 16 MB would "
     "be 256 here and 65536 as pages, and only one of those fits a word"),

    ("USTASH 51968,0,16", "READY.",
     "sixteen bytes of C64 memory into the expansion"),

    ("PRINT UERR", " 0",
     "and the expansion answered - anything else means it is switched off"),

    ("POKE 51968,0", "READY.",
     "wipe the byte, so the fetch below cannot pass on what was already there"),

    ("UFETCH 51968,0,16", "READY.",
     "and back out again"),

    ("PRINT PEEK(51968)", " 72",
     "'H' came back through the expansion, which is a round trip no register "
     "readback could have faked"),

    # USAVE, on /Temp: the FAT filesystem the firmware formats in RAM at boot.
    # A mutating test needs somewhere to write, not somewhere in particular, and
    # the RAM disk cannot fill anybody's medium, cannot wear flash, and is gone
    # on the next power cycle whatever happens here.
    ('USAVE "/TEMP/SV.TMP",51968,4', "READY.",
     "four bytes of memory become a file"),

    ("PRINT UERR", " 0",
     "and the write was accepted"),

    ("POKE 51968,0", "READY.",
     "wipe the byte, so reading it back cannot pass on what was already there"),

    ('UBLOAD "/TEMP/SV.TMP",51968,4', "READY.",
     "read the file back over the top of it"),

    ("PRINT PEEK(51968)", " 72",
     "'H' - what USAVE wrote is what UBLOAD reads, which is the only proof a "
     "status code cannot give"),

    ('UCI 1,9,"/TEMP/SV.TMP"', "READY.",
     "DOS_CMD_DELETE_FILE through the generic form: the wedge has no delete "
     "keyword, and every mutating test cleans up after itself"),

    ("PRINT UERR", " 0",
     "and the file is gone"),

    # UDIR last, because it needs the current directory to be somewhere known.
    # That directory belongs to the firmware and not to the C64, so it outlives
    # a reset and whatever ran before this - the generic form puts it back.
    ('UCI 1,17,"/"', "READY.",
     "CHANGE_DIR to the root, so the listing below is the same every run"),

    ("UDIR", "TEMP/",
     "the directory prints itself, one entry per line, with a slash on the "
     "directories - and the letters arrive as letters, which is the whole "
     "point of folding ASCII on the way to CHROUT"),
]


def install(u, as_crt):
    """Get the wedge onto the machine, and say how much BASIC RAM is left.

    The .prg is loaded and RUN; the cartridge autostarts on the CBM80 signature
    with nothing typed at all. Either way the banner is the proof it is in.
    """
    if as_crt:
        u.run_crt(os.path.normpath(WEDGE_CRT))
    else:
        u.run_prg(os.path.normpath(WEDGE_PRG))
    time.sleep(6)
    return decode_screen(u.readmem(0x0400, 1000))


def run(host, port, verbose, as_crt):
    u = Ultimate(host, port)
    info = u.info()
    print("# %s, firmware %s (fpga %s, core %s)"
          % (info["product"], info["firmware_version"],
             info["fpga_version"], info["core_version"]))

    changed = require_settings(u, {CMD_IF: "Enabled",
                                   TURBO: "U64 Turbo Registers",
                                   REU: "Enabled",
                                   REU_SIZE: REU_SIZE_WANT})
    if changed:
        print("# saved settings: %s"
              % ", ".join("%s=%s" % (k[1], v) for k, v in changed.items()))
    failures = 0
    try:
        print("# installing the wedge from the %s"
              % ("cartridge" if as_crt else ".prg"))
        screen = install(u, as_crt)
        if not any("ULTIMATE UCI BASIC WEDGE INSTALLED." in line for line in screen):
            print("not ok 1 - the wedge did not install")
            print("#   the banner never appeared. Screen:")
            for line in screen[-6:]:
                print("#   |", line)
            return 1
        free = [t for t in screen if "BASIC BYTES FREE" in t]
        if free:
            print("# %s" % free[0].strip())
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
        if as_crt:
            # The cartridge stays mapped until something else starts the
            # machine, and a reset would just run it again. Leave the bench
            # the way it was found.
            print("# unmapping the cartridge")
            u.run_prg(os.path.normpath(WEDGE_PRG))
            time.sleep(5)
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
    ap.add_argument("--crt", action="store_true",
                    help="install from uci.crt instead of uci.prg. The same "
                         "checks run either way, which is the point: the "
                         "cartridge is a delivery mechanism, not a second "
                         "implementation")
    args = ap.parse_args()
    sys.exit(run(args.host, args.port, args.verbose, args.crt))


if __name__ == "__main__":
    main()
