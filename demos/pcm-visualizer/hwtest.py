#!/usr/bin/env python3
"""Run the disk PCM visualizer and verify a live buffer swap."""

import argparse
import json
import pathlib
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tests" / "hardware"))

from screen import SCREEN_ADDR, SCREEN_LEN, screen_text  # noqa: E402
from u64_settings import (Ultimate, read_settings, require_settings,
                          restore_settings)  # noqa: E402

STATUS_ADDR = 0x033C
STATUS_LEN = 22
MAGIC = b"PVIZ"
CMD_IF = ("C64 and Cartridge Settings", "Command Interface")
REU = ("C64 and Cartridge Settings", "RAM Expansion Unit")
REU_SIZE = ("C64 and Cartridge Settings", "REU Size")
AUDIO = ("C64 and Cartridge Settings", "Map Ultimate Audio $DF20-DFFF")
TURBO = ("U64 Specific Settings", "Turbo Control")


def run_stop(u):
    for transition in ("press", "release"):
        body = json.dumps({"events": [{"kind": "keyboard",
                                       "inputs": ["run_stop"],
                                       "transition": transition}]}).encode("ascii")
        u._request("POST", "/machine:input", data=body,
                   content_type="application/json")
        time.sleep(0.25)


def wait_running(u, timeout=60.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        status = u.readmem(STATUS_ADDR, STATUS_LEN)
        if status[:4] == MAGIC:
            if status[4] == 0x80:
                raise RuntimeError("demo failed with SDK error %d" % status[5])
            if status[4] == 2:
                return status
        time.sleep(0.1)
    screen = screen_text(u.readmem(SCREEN_ADDR, SCREEN_LEN))
    raise RuntimeError("demo did not start streaming; screen=%r" % screen)


def wait_swaps_and_motion(u, first, timeout=25.0):
    deadline = time.time() + timeout
    levels = {bytes(first[8:14])}
    while time.time() < deadline:
        status = u.readmem(STATUS_ADDR, STATUS_LEN)
        if status[:4] != MAGIC or status[4] != 2:
            raise RuntimeError("demo left streaming: error=%d stage=%d slice=%d" %
                               (status[5], status[15], status[16]))
        if status[14]:
            raise RuntimeError("audio underrun count reached %d" % status[14])
        levels.add(bytes(status[8:14]))
        if ((status[7] - first[7]) & 0xFF) >= 3 and len(levels) >= 4 and any(status[8:14]):
            return status, len(levels)
        time.sleep(0.1)
    raise RuntimeError("audio did not swap buffers while six-band levels moved")


def wait_ready(u, timeout=6.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if "READY." in screen_text(u.readmem(SCREEN_ADDR, SCREEN_LEN)):
            return True
        time.sleep(0.2)
    return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--prg", type=pathlib.Path, required=True)
    args = parser.parse_args()

    u = Ultimate(args.host)
    keys = (CMD_IF, REU, REU_SIZE, AUDIO, TURBO)
    original = read_settings(u, keys)
    changed = {}
    launched = False
    try:
        changed = require_settings(u, {
            CMD_IF: "Enabled", REU: "Enabled", REU_SIZE: "16 MB",
            AUDIO: "Enabled", TURBO: "U64 Turbo Registers",
        })
        u._request("PUT", "/machine:reset")
        time.sleep(2.0)
        u.run_prg(args.prg)
        launched = True
        first = wait_running(u)
        last, states = wait_swaps_and_motion(u, first)
        screen = screen_text(u.readmem(SCREEN_ADDR, SCREEN_LEN))
        if "HALL OF THE MOUNTAIN KING" not in screen:
            raise RuntimeError("title is missing from the screen")
        print("ok - disk PCM crossed %d buffers; %d visual states; levels %s" %
              (((last[7] - first[7]) & 0xFF), states, list(last[8:14])))
    finally:
        if launched:
            try:
                run_stop(u)
                if not wait_ready(u):
                    print("warning: RUN/STOP did not reach BASIC", file=sys.stderr)
            except Exception as exc:  # noqa: BLE001 - cleanup must continue
                print("warning: could not exit demo: %s" % exc, file=sys.stderr)
        restore_settings(u, changed,
                         warn=lambda message: print("warning: " + message,
                                                    file=sys.stderr))


if __name__ == "__main__":
    main()
