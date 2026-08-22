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
STATUS_LEN = 22
COLOR_RAM = 0xD800
MAGIC = b"SVIZ"
CMD_IF = ("C64 and Cartridge Settings", "Command Interface")
SID1 = ("SID Addressing", "SID Socket 1 Address")
SID2 = ("SID Addressing", "SID Socket 2 Address")
TURBO = ("U64 Specific Settings", "Turbo Control")
SONGS = ("DIVISION BY ZERO", "DEVICE NOT PRESENT", "FORMULA TOO COMPLEX",
         "OVERFLOW", "CAN'T CONTINUE", "REDO FROM START",
         "RETURN WITHOUT GOSUB")


def run_stop(u):
    for transition in ("press", "release"):
        body = json.dumps({"events": [{"kind": "keyboard",
                                       "inputs": ["run_stop"],
                                       "transition": transition}]}).encode("ascii")
        u._request("POST", "/machine:input", data=body,
                   content_type="application/json")
        time.sleep(0.25)


def press_key(u, name):
    for transition in ("press", "release"):
        body = json.dumps({"events": [{"kind": "keyboard",
                                       "inputs": [name],
                                       "transition": transition}]}).encode("ascii")
        u._request("POST", "/machine:input", data=body,
                   content_type="application/json")
        time.sleep(0.25)


def wait_tune(u, tune, timeout=3.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if u.readmem(STATUS_ADDR, STATUS_LEN)[14] == tune:
            return
        time.sleep(0.1)
    raise RuntimeError("song key did not select tune %d" % (tune + 1))


def wait_screen(u, text, timeout=3.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if text in screen_text(u.readmem(SCREEN_ADDR, SCREEN_LEN)):
            return
        time.sleep(0.1)
    raise RuntimeError("screen did not show %r after song change" % text)


def wait_screen_codes(u, codes, timeout=3.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if codes in u.readmem(SCREEN_ADDR, SCREEN_LEN):
            return
        time.sleep(0.1)
    raise RuntimeError("screen did not contain %r" % codes)


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
        if (status[6] != first[6] and status[15:21] != first[15:21]
                and any(status[15:21])):
            return status
        time.sleep(0.1)
    raise RuntimeError("music advanced but bar heights did not animate")


def check_render(u, status):
    colors = u.readmem(COLOR_RAM, SCREEN_LEN)
    if any((color & 0x0F) != 15 for color in colors[40:80]):
        raise RuntimeError("song title is not using the fixed white palette entry")
    for voice, height in enumerate(status[15:21]):
        if height:
            x = 2 + voice * 6
            if not any((colors[y * 40 + x] & 0x0F) in (voice + 1, 15)
                       for y in range(3, 21)):
                raise RuntimeError("voice %d height was not rendered" % (voice + 1))


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


def check_frame_rate(u, sample=1.0):
    before = u.readmem(STATUS_ADDR, STATUS_LEN)[21]
    started = time.monotonic()
    time.sleep(sample)
    after = u.readmem(STATUS_ADDR, STATUS_LEN)[21]
    elapsed = time.monotonic() - started
    return ((after - before) & 0xFF) / elapsed


def check_palette_motion(u, sample=1.0):
    samples = []
    deadline = time.monotonic() + sample
    while time.monotonic() < deadline:
        samples.append(u.readmem(STATUS_ADDR, STATUS_LEN)[7:13])
        time.sleep(0.05)
    spread = max(max(values) - min(values) for values in zip(*samples))
    if spread < 32:
        raise RuntimeError("palette intensity changed by only %d" % spread)
    return spread


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--prg", default=str(pathlib.Path(__file__).with_name(
        "sid-visualizer.prg")))
    args = parser.parse_args()

    u = Ultimate(args.host)
    original = read_settings(u, (CMD_IF, SID2, TURBO))
    launched = False
    try:
        require_settings(u, {CMD_IF: "Enabled", SID2: "$D500",
                             TURBO: "U64 Turbo Registers"})
        sid1_address = int(u.get_setting(*SID1)[1:], 16)
        sid2_address = int(u.get_setting(*SID2)[1:], 16)
        u.run_prg(args.prg)
        launched = True
        first = wait_running(u)
        stores = (int.from_bytes(u.readmem(0x100F, 2), "little"),
                  int.from_bytes(u.readmem(0x1016, 2), "little"))
        if stores != (sid1_address, sid2_address):
            raise RuntimeError("player used SID stores $%04X/$%04X, expected "
                               "$%04X/$%04X" %
                               (stores[0], stores[1], sid1_address, sid2_address))
        wait_screen_codes(u, ("$%04X + $%04X" %
                              (sid1_address, sid2_address)).encode("ascii"))
        second = wait_animation(u, first)
        check_render(u, second)
        rate = check_tick_rate(u)
        frame_rate = check_frame_rate(u)
        if frame_rate < 45.0:
            raise RuntimeError("visualizer frame rate is %.1f fps" % frame_rate)
        palette_spread = check_palette_motion(u)
        tune = second[14]
        press_key(u, "d")
        wait_tune(u, (tune + 1) % 7)
        wait_screen(u, SONGS[(tune + 1) % 7])
        press_key(u, "a")
        wait_tune(u, tune)
        wait_screen(u, SONGS[tune])
        print("ok - Ultimate SID visualizer heights %s -> %s at %.1f Hz, "
              "%.1f fps, palette delta %d; A/D changed tunes" %
              (list(first[15:21]), list(second[15:21]), rate, frame_rate,
               palette_spread))
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
