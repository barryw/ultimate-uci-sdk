#!/usr/bin/env python3
"""Typing at a real C64, through the Ultimate's REST input API.

The wedge's tokeniser only runs when a line is *typed*: ICRNCH is reached from
the editor, not from anything a program can call. So the only way to test it on
real hardware is to type, and this is the keyboard.

The API takes batches of key events by C64 matrix name, so this maps the
characters a test wants to send onto those names and the shift key.

    POST /v1/machine:input
    {"events": [{"kind": "keyboard", "inputs": ["u"], "transition": "tap"}]}

SPDX-License-Identifier: MIT
"""

import json
import time

MAX_EVENTS = 64         # INPUT_API_MAX_EVENTS in the firmware

# Unshifted keys, by the character they produce on a C64 at the READY prompt.
UNSHIFTED = {
    " ": "space", ",": "comma", ".": "period", ":": "colon", ";": "semicolon",
    "+": "plus", "-": "minus", "*": "star", "/": "slash", "=": "equals",
    "@": "at", "\n": "return",
}
for _c in "0123456789":
    UNSHIFTED[_c] = _c
for _c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
    UNSHIFTED[_c] = _c.lower()

# Characters that need SHIFT. The value is the key held with it.
SHIFTED = {
    '"': "2", "$": "4", "(": "8", ")": "9", "!": "1", "#": "3",
    "%": "5", "&": "6", "'": "7", "?": "slash", "<": "comma",
    ">": "period", "[": "colon", "]": "semicolon",
}


class Untypable(Exception):
    pass


def events_for_char(ch):
    """The key events that produce one character."""
    if ch in UNSHIFTED:
        return [{"kind": "keyboard", "inputs": [UNSHIFTED[ch]], "transition": "tap"}]
    if ch in SHIFTED:
        return [
            {"kind": "keyboard", "inputs": ["left_shift"], "transition": "press"},
            {"kind": "keyboard", "inputs": [SHIFTED[ch]], "transition": "tap"},
            {"kind": "keyboard", "inputs": ["left_shift"], "transition": "release"},
        ]
    raise Untypable("no key for %r" % ch)


def events_for(text):
    out = []
    for ch in text:
        out.extend(events_for_char(ch))
    return out


def batches(events, limit=MAX_EVENTS):
    """Split into batches the firmware will accept.

    A shifted character is three events that must not be split across two
    requests, or the shift would be released in the middle. Splitting only on
    a `tap` boundary keeps each group whole.
    """
    out, current = [], []
    for event in events:
        current.append(event)
        if len(current) >= limit - 2 and event["transition"] == "tap":
            out.append(current)
            current = []
    if current:
        out.append(current)
    return out


def type_text(ultimate, text, delay=0.12):
    """Type text, ending wherever the caller's newlines end it.

    One event per request with a pause between. The C64 scans its keyboard
    about once a frame, so a batch applied all at once is a batch it never
    sees - the first attempt at this typed "P" out of "PRINT 2+3". The same
    reason is why a shifted character's press, tap and release have to be
    paced: SHIFT has to be down across a scan, not just across a request.
    """
    for event in events_for(text):
        body = json.dumps({"events": [event]}).encode("ascii")
        ultimate._request("POST", "/machine:input", data=body,
                          content_type="application/json")
        time.sleep(delay)
    # Nothing is held down between calls, so a dropped connection cannot leave
    # a key stuck.
    body = json.dumps({"events": [{"kind": "release_all"}]}).encode("ascii")
    ultimate._request("POST", "/machine:input", data=body,
                      content_type="application/json")


def type_line(ultimate, line, delay=0.12):
    type_text(ultimate, line + "\n", delay)
