#!/usr/bin/env python3
"""
Drive the hardware tests against a real Ultimate over its REST API.

The Ultimate can be reconfigured remotely, which means the settings a program
has to cope with in the field are testable rather than merely documented. This
runs tests/hardware/ucitest.prg once per configuration and checks the SDK
behaved correctly in each - including the configurations where the right
behaviour is to fail cleanly.

    python3 hwtest.py --host 192.168.1.62

Every setting it touches is read first and put back afterwards, including on
Ctrl-C or an exception. Nothing is written to the Ultimate's flash: the config
endpoint used here changes the running configuration only, so a power cycle
restores the machine regardless.

The REST client and the read/restore helpers live in tools/u64_settings.py,
shared with the settings guard that tests/emulator/Makefile wraps its own
hardware run with - see that module for the single source of truth on both.

Part of the Ultimate SDK. SPDX-License-Identifier: MIT
"""

import argparse
import os
import sys
import time
import urllib.error

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "tools"))

from u64_settings import Ultimate, read_settings, restore_settings  # noqa: E402

# The result block ucitest.prg publishes into the cassette buffer.
RESULT_ADDR = 0x033C
RESULT_LEN = 24        # room for the format-3 flags and a little growth
RESULT_MAGIC = b"UCIT"
RESULT_DONE = 0xA5

from screen import decode_screen, SCREEN_ADDR, SCREEN_LEN  # noqa: E402

# Settings this script drives. Category, item.
CMD_IF = ("C64 and Cartridge Settings", "Command Interface")
REU = ("C64 and Cartridge Settings", "RAM Expansion Unit")
REU_SIZE = ("C64 and Cartridge Settings", "REU Size")
# What each configured size should measure as, in 64K banks. 16 MB is 256, which
# is why the SDK reports banks in a word: it does not fit a byte, and neither
# does the same size counted in 256-byte pages fit one.
REU_BANKS = {"128 KB": 2, "256 KB": 4, "512 KB": 8, "1 MB": 16,
             "2 MB": 32, "4 MB": 64, "8 MB": 128, "16 MB": 256}
IEC_DRIVE = ("SoftIEC Drive Settings", "IEC Drive")
# "Off", "Manual", "U64 Turbo Registers" or "TurboEnable Bit". Only the third
# gives a program control of $D031; the others leave it reading $FF, which is
# the state every other scenario here runs in.
TURBO = ("U64 Specific Settings", "Turbo Control")

TARGET_SOFTIEC_BIT = 1 << 5


class Result:
    def __init__(self, block):
        self.valid = block[0:4] == RESULT_MAGIC
        self.format = block[4]
        self.tests = block[5]
        self.passed = block[6]
        self.failed = block[7]
        self.skipped = block[8]
        self.ident = block[9]
        self.targets = block[10] | (block[11] << 8)
        self.done = block[12] == RESULT_DONE
        # Format 2 and later: whether the turbo checks ran rather than skipped.
        self.turbo_ran = bool(block[13]) if self.format >= 2 else False
        # Format 3 and later: whether the network checks ran, and separately
        # whether a socket really carried bytes - which needs a peer, so it is
        # reported rather than required. See ucitest.c's fixtures.
        self.net_ran = bool(block[14]) if self.format >= 3 else False
        self.net_sock_ran = bool(block[15]) if self.format >= 3 else False
        self.http_ran = bool(block[16]) if self.format >= 3 else False
        # The size the C64 measured for itself, in 64K banks.
        self.reu_banks = (block[17] | (block[18] << 8)) if self.format >= 3 else 0
        self.reu_probe_clean = bool(block[19]) if self.format >= 3 else False

    def __str__(self):
        if not self.valid:
            return "no result block (the program did not reach the end)"
        return ("tests=%d passed=%d failed=%d skipped=%d ident=$%02x targets=$%04x"
                % (self.tests, self.passed, self.failed, self.skipped,
                   self.ident, self.targets))


def run_once(u, prg, settle=6.0, poll_timeout=20.0):
    """Boot the test program and wait for it to publish a result."""
    # Clear the block first. The KERNAL's reset clears this page too, so this is
    # belt and braces - but a stale result would be a silent wrong answer.
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


# --------------------------------------------------------------------------
# Scenarios. Each one sets every relevant setting explicitly, so the order the
# scenarios run in cannot change what any of them means.
# --------------------------------------------------------------------------

def expect_clean_pass(r, state=None):
    if not r.done:
        return "the program did not finish"
    if r.failed != 0:
        return "%d test(s) failed on the C64" % r.failed
    if r.tests < 13:
        return "expected at least 13 tests, saw %d" % r.tests
    if r.ident != 0xC9:
        return "expected the identification register to read $C9, saw $%02x" % r.ident
    return None


def expect_clean_pass_with_net(r, state=None):
    """A clean pass, and the network checks really ran.

    u64sim implements no network command at all, so tests/hardware is the only
    place they are exercised, which makes a silent skip the difference between
    covered and not covered. What is required here is the half that needs
    nothing on the network: the interface count, the addresses and the argument
    checks.

    **The socket round trip is reported, not required.** It needs a peer, and
    ucitest.c will not assume one exists - see its fixtures for what happened
    when it did. Build with NET_PEER=<dotted-quad>:<port> to run it.
    """
    problem = expect_clean_pass(r)
    if problem:
        return problem
    if not r.net_ran:
        return ("the network checks skipped: either this firmware has no "
                "network target, or no interface had an address")
    missing = []
    if not r.net_sock_ran:
        missing.append("the socket round trip (NET_PEER=<dotted-quad>:<port>)")
    if not r.http_ran:
        missing.append("the http checks (HTTP_PEER=<dotted-quad>:<port>)")
    if missing:
        state = state if state is not None else {}
        state["note"] = ("skipped for want of a peer: " + ", ".join(missing))
    return None


def expect_reu_size(want):
    """The size the SDK measured must be the size the harness configured.

    Nothing in the protocol reports it, so the SDK finds it by writing past each
    power-of-two boundary and seeing which one comes back round to offset zero.
    That is only trustworthy if it agrees with a size set from outside, which is
    what this does - and it is checked at the top end especially, because 16 MB
    is the one value that does not fit the obvious compact encodings and so is
    the one most likely to be got wrong.
    """
    def check(r, state=None):
        problem = expect_clean_pass(r)
        if problem:
            return problem
        if r.reu_banks != REU_BANKS[want]:
            return ("with the expansion set to %s the SDK should measure %d "
                    "banks, and it measured %d"
                    % (want, REU_BANKS[want], r.reu_banks))
        if not r.reu_probe_clean:
            return "the size probe changed the bytes it borrowed"
        return None
    return check


def expect_no_device(r, state=None):
    if not r.done:
        return "the program did not finish - it should fail fast, not hang"
    if r.tests != 1 or r.failed != 1:
        return ("expected exactly one failing check (signature-present), "
                "saw tests=%d failed=%d" % (r.tests, r.failed))
    return None


def record_softiec(r, state):
    """Drive off: note whether the target is still visible, assert nothing.

    Presence here is the interesting observation, and it is the expected one -
    GideonZ/1541ultimate#794 confirms that disabling the drive removes it from
    the IEC bus and not from UCI, because UCI is how the hyperspeed kernal
    reaches it. /v1/drives reports enabled=false while target $05 still returns
    SOFTWARE IEC TARGET V1.0.

    It is still not asserted, for one reason: this run cannot prove what a cold
    boot with the drive already disabled would report, and this bench machine
    cannot be power cycled remotely. Absence here would be a finding to chase,
    not a failure to fail on.
    """
    problem = expect_clean_pass(r)
    if problem:
        return problem
    state["softiec_before"] = bool(r.targets & TARGET_SOFTIEC_BIT)
    return None


def expect_softiec_present(r, state):
    problem = expect_clean_pass(r)
    if problem:
        return problem
    if not r.targets & TARGET_SOFTIEC_BIT:
        return ("detection must see target $05 with the IEC drive enabled, "
                "targets=$%04x" % r.targets)
    if state.get("softiec_before") is True:
        state["note"] = ("target $05 was visible with the drive disabled too, "
                         "which is the documented intent (#794) - the SDK's "
                         "SoftwareIEC path needs no drive setting from the user")
    return None


def expect_turbo_measured(r, state=None):
    """The turbo checks must have run, not skipped.

    Every other scenario leaves "Turbo Control" alone, so ucitest.c skips its
    turbo section and says so - which is the normal case in the field and not a
    failure. This scenario is the one that switches the registers on, so a skip
    here means the setting did not take, and a passing run that quietly proved
    nothing is exactly what this file exists to prevent.
    """
    problem = expect_clean_pass(r)
    if problem:
        return problem
    if not r.turbo_ran:
        return ("the turbo checks skipped with Turbo Control set to "
                "U64 Turbo Registers - the setting did not reach the machine")
    return None


SCENARIOS = [
    {
        "name": "uci-disabled",
        "why": "with the command interface switched off the SDK must report "
               "no device and return, not hang or misread open bus",
        "steps": [
            ({CMD_IF: "Disabled", REU: "Disabled", TURBO: "Off"},
             expect_no_device),
        ],
    },
    {
        "name": "uci-enabled",
        "why": "the baseline: everything passes with the interface on, and "
               "the sockets reach the machine's own web server",
        "steps": [
            ({CMD_IF: "Enabled", REU: "Disabled", TURBO: "Off"},
             expect_clean_pass_with_net),
        ],
    },
    {
        "name": "reu-size-is-measured",
        "why": "no command reports the expansion's size, so the SDK measures "
               "it - and the only way to know the measurement is right is to "
               "set the size from outside and see whether it agrees. The three "
               "steps are the three structurally different answers: the first "
               "boundary, a middle one, and the top end that falls through "
               "every boundary there is",
        "steps": [
            ({CMD_IF: "Enabled", REU: "Enabled", TURBO: "Off",
              REU_SIZE: "128 KB"}, expect_reu_size("128 KB")),
            ({CMD_IF: "Enabled", REU: "Enabled", TURBO: "Off",
              REU_SIZE: "2 MB"}, expect_reu_size("2 MB")),
            ({CMD_IF: "Enabled", REU: "Enabled", TURBO: "Off",
              REU_SIZE: "16 MB"}, expect_reu_size("16 MB")),
        ],
    },
    {
        "name": "uci-with-reu",
        "why": "the interface overlays the last five REU registers, so an "
               "enabled REU must not disturb it",
        "steps": [
            ({CMD_IF: "Enabled", REU: "Enabled", TURBO: "Off"},
             expect_clean_pass),
        ],
    },
    {
        "name": "softiec-survives-drive-disabled",
        "why": "target $05 must stay reachable over UCI with the IEC drive "
               "switched off - see #794, it is the path the hyperspeed kernal "
               "uses, and the SDK's fast load depends on it",
        "steps": [
            ({CMD_IF: "Enabled", REU: "Disabled", IEC_DRIVE: "Disabled",
              TURBO: "Off"}, record_softiec),
            ({CMD_IF: "Enabled", REU: "Disabled", IEC_DRIVE: "Enabled",
              TURBO: "Off"}, expect_softiec_present),
        ],
    },
    {
        "name": "turbo-registers",
        "why": "turbo is memory-mapped I/O rather than a UCI command, and the "
               "only way to show it works is to time a loop against the raster "
               "with the registers switched on - which only their owner can do",
        "steps": [
            ({CMD_IF: "Enabled", REU: "Disabled",
              TURBO: "U64 Turbo Registers"}, expect_turbo_measured),
        ],
    },
]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", required=True, help="hostname or IP of the Ultimate")
    ap.add_argument("--port", type=int, default=80)
    ap.add_argument("--prg", default="ucitest.prg", help="test program to run")
    ap.add_argument("--verbose", action="store_true",
                    help="print the C64 screen after every scenario")
    ap.add_argument("--keep", action="store_true",
                    help="leave the settings as the last scenario set them")
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

    touched = {CMD_IF, REU, IEC_DRIVE, TURBO}
    saved = read_settings(u, touched)
    print("# saved settings: %s"
          % ", ".join("%s=%s" % (k[1], v) for k, v in saved.items()))

    failures = 0
    try:
        for index, scenario in enumerate(SCENARIOS, 1):
            state = {}
            problem = None
            result = None
            screen = []

            for settings, check in scenario["steps"]:
                for key, value in settings.items():
                    u.set_setting(key[0], key[1], value)
                result, screen = run_once(u, args.prg)
                problem = check(result, state)
                if problem is not None:
                    break

            if problem is None:
                print("ok %d - %s" % (index, scenario["name"]))
                print("#   %s" % result)
                if state.get("note"):
                    print("#   note: %s" % state["note"])
            else:
                failures += 1
                print("not ok %d - %s" % (index, scenario["name"]))
                print("#   %s" % scenario["why"])
                print("#   %s" % problem)
                print("#   %s" % result)

            if args.verbose or problem is not None:
                for line in screen:
                    print("#   | %s" % line)

        print("1..%d" % len(SCENARIOS))
        print("# %d passed, %d failed" % (len(SCENARIOS) - failures, failures))
    finally:
        if args.keep:
            print("# --keep given: settings left as the last scenario set them")
        else:
            restore_settings(u, saved, warn=lambda msg: print("# WARNING: %s" % msg))
            print("# settings restored; flash was never written")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
