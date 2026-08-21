#!/usr/bin/env python3
"""Run the SID visualizer on an Ultimate and verify live voice animation."""

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
STATUS_LEN = 14
MAGIC = b"SVIZ"
CMD_IF = ("C64 and Cartridge Settings", "Command Interface")
SID2 = ("SID Addressing", "SID Socket 2 Address")


def run_stop(u):
    for transition in ("press", "release"):
        body = json.dumps({"events": [{"kind": "keyboard",
                                       "inputs": ["run_stop"],
                                       "transition": transition}]}).encode("ascii")
        u._request("POST", "/machine:input", data=body,
                   content_type="application/json")
        time.sleep(0.25)


def wait_ready(u, timeout=6.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if "READY." in screen_text(u.readmem(SCREEN_ADDR, SCREEN_LEN)):
            return True
        time.sleep(0.2)
    return False


def wait_running(u, timeout=12.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        status = u.readmem(STATUS_ADDR, STATUS_LEN)
        if status[:4] == MAGIC:
            if status[4] == 0x80:
                raise RuntimeError("demo stopped with SDK error %d" % status[5])
            if status[4] == 4:
                return status
        time.sleep(0.1)
    raise RuntimeError("demo did not enter its music loop")


def wait_animation(u, first, timeout=8.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        status = u.readmem(STATUS_ADDR, STATUS_LEN)
        if status[:4] != MAGIC or status[4] != 4:
            raise RuntimeError("demo left its music loop")
        if status[6] != first[6] and status[7:13] != first[7:13] and any(status[7:13]):
            return status
        time.sleep(0.1)
    raise RuntimeError("music advanced but voice intensities did not animate")


def check_tick_rate(u, sample=1.0):
    before = u.readmem(STATUS_ADDR, STATUS_LEN)[6]
    started = time.monotonic()
    time.sleep(sample)
    after = u.readmem(STATUS_ADDR, STATUS_LEN)[6]
    elapsed = time.monotonic() - started
    rate = ((after - before) & 0xFF) / elapsed
    if not 75.0 <= rate <= 125.0:
        raise RuntimeError("music tick rate is %.1f Hz, expected about 100 Hz" % rate)
    return rate


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--prg", default=str(pathlib.Path(__file__).with_name(
        "sid-visualizer.prg")))
    args = parser.parse_args()

    u = Ultimate(args.host)
    original = read_settings(u, (CMD_IF, SID2))
    launched = False
    try:
        require_settings(u, {CMD_IF: "Enabled", SID2: "$D500"})
        u.run_prg(args.prg)
        launched = True
        first = wait_running(u)
        second = wait_animation(u, first)
        rate = check_tick_rate(u)
        print("ok - Ultimate SID visualizer animated %s -> %s at %.1f Hz" %
              (list(first[7:13]), list(second[7:13]), rate))
    finally:
        if launched:
            try:
                u.writemem(STATUS_ADDR + 13, b"\x01")
                if not wait_ready(u):
                    run_stop(u)
                    if not wait_ready(u):
                        print("warning: RUN/STOP did not reach BASIC",
                              file=sys.stderr)
            except Exception as exc:  # noqa: BLE001 - cleanup must continue
                print("warning: could not exit demo cleanly: %s" % exc,
                      file=sys.stderr)
        restore_settings(u, original,
                         warn=lambda message: print("warning: " + message,
                                                    file=sys.stderr))


if __name__ == "__main__":
    main()
