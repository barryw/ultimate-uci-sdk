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

Part of the Ultimate SDK. SPDX-License-Identifier: MIT
"""

import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# The result block ucitest.prg publishes into the cassette buffer.
RESULT_ADDR = 0x033C
RESULT_LEN = 16
RESULT_MAGIC = b"UCIT"
RESULT_DONE = 0xA5

SCREEN_ADDR = 0x0400
SCREEN_LEN = 1000

# Settings this script drives. Category, item.
CMD_IF = ("C64 and Cartridge Settings", "Command Interface")
REU = ("C64 and Cartridge Settings", "RAM Expansion Unit")
IEC_DRIVE = ("SoftIEC Drive Settings", "IEC Drive")

TARGET_SOFTIEC_BIT = 1 << 5


class Ultimate:
    def __init__(self, host, port=80, timeout=15):
        self.base = "http://%s:%d/v1" % (host, port)
        self.timeout = timeout

    def _request(self, method, path, data=None, content_type=None):
        url = self.base + path
        req = urllib.request.Request(url, data=data, method=method)
        if content_type:
            req.add_header("Content-Type", content_type)
        with urllib.request.urlopen(req, timeout=self.timeout) as resp:
            return resp.read()

    def info(self):
        return json.loads(self._request("GET", "/info"))

    def get_setting(self, category, item):
        raw = self._request("GET", "/configs/" + urllib.parse.quote(category))
        return json.loads(raw)[category][item]

    def set_setting(self, category, item, value):
        path = "/configs/%s/%s?value=%s" % (
            urllib.parse.quote(category),
            urllib.parse.quote(item),
            urllib.parse.quote(str(value)),
        )
        body = json.loads(self._request("PUT", path))
        errors = body.get("errors") or []
        if errors:
            raise RuntimeError("setting %s/%s to %r failed: %s"
                               % (category, item, value, errors))

    def readmem(self, address, length):
        return self._request(
            "GET", "/machine:readmem?address=%x&length=%d" % (address, length))

    def writemem(self, address, data):
        self._request("POST", "/machine:writemem?address=%x" % address,
                      data=data, content_type="application/octet-stream")

    def run_prg(self, path):
        with open(path, "rb") as fh:
            payload = fh.read()
        self._request("POST", "/runners:run_prg", data=payload,
                      content_type="application/octet-stream")


def decode_screen(raw):
    """C64 screen codes to something printable. Unknown glyphs become '.'."""
    out = []
    for row in range(25):
        line = []
        for code in raw[row * 40:(row + 1) * 40]:
            if code == 0x00:
                line.append("@")
            elif 0x01 <= code <= 0x1A:
                line.append(chr(code + 64))
            elif 0x20 <= code <= 0x3F:
                line.append(chr(code))
            else:
                line.append(".")
        text = "".join(line).rstrip()
        if text:
            out.append(text)
    return out


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


def expect_no_device(r, state=None):
    if not r.done:
        return "the program did not finish - it should fail fast, not hang"
    if r.tests != 1 or r.failed != 1:
        return ("expected exactly one failing check (signature-present), "
                "saw tests=%d failed=%d" % (r.tests, r.failed))
    return None


def record_softiec(r, state):
    """Baseline step: note whether the target is visible, assert nothing.

    Absence cannot be asserted here. The firmware registers a UCI target when
    its subsystem starts and never unregisters it, so a SoftwareIEC target that
    was switched on earlier in this power cycle keeps answering after the drive
    is switched off again - /v1/drives reports enabled=false while target $05
    still returns SOFTWARE IEC TARGET V1.0. Detection is live in one direction
    only. See docs/compatibility.md.
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
        return ("switching the drive on should make detection see target $05, "
                "targets=$%04x" % r.targets)
    if state.get("softiec_before") is True:
        state["note"] = ("target $05 was already visible before this step - it "
                         "was latched by an earlier enable in this power cycle, "
                         "so this step only confirms it did not disappear")
    return None


SCENARIOS = [
    {
        "name": "uci-disabled",
        "why": "with the command interface switched off the SDK must report "
               "no device and return, not hang or misread open bus",
        "steps": [
            ({CMD_IF: "Disabled", REU: "Disabled"}, expect_no_device),
        ],
    },
    {
        "name": "uci-enabled",
        "why": "the baseline: everything passes with the interface on",
        "steps": [
            ({CMD_IF: "Enabled", REU: "Disabled"}, expect_clean_pass),
        ],
    },
    {
        "name": "uci-with-reu",
        "why": "the interface overlays the last five REU registers, so an "
               "enabled REU must not disturb it",
        "steps": [
            ({CMD_IF: "Enabled", REU: "Enabled"}, expect_clean_pass),
        ],
    },
    {
        "name": "softiec-detection-is-live",
        "why": "switching a subsystem on must change what capability detection "
               "reports, with no rebuild and no reboot of the C64 program",
        "steps": [
            ({CMD_IF: "Enabled", REU: "Disabled", IEC_DRIVE: "Disabled"},
             record_softiec),
            ({CMD_IF: "Enabled", REU: "Disabled", IEC_DRIVE: "Enabled"},
             expect_softiec_present),
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

    touched = {CMD_IF, REU, IEC_DRIVE}
    saved = {key: u.get_setting(*key) for key in touched}
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
            for key, value in saved.items():
                try:
                    u.set_setting(key[0], key[1], value)
                except Exception as exc:            # noqa: BLE001 - best effort
                    print("# WARNING: could not restore %s to %r: %s"
                          % (key[1], value, exc))
            print("# settings restored; flash was never written")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
