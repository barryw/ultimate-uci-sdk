#!/usr/bin/env python3
"""Combine the official Machine Yearning PSID and the cc65 visualizer."""

import hashlib
import pathlib
import sys

SID_SHA256 = "a9d67055c72eebe32a5a1f683b157d24c00b9f13a9d2d312ce7751cd16640bf5"
OUTER_LOAD = 0x0801
SID_LOAD = 0x1000
CORE_LOAD = 0x3000


def psid_payload(raw):
    if raw[:4] != b"PSID" or hashlib.sha256(raw).hexdigest() != SID_SHA256:
        raise ValueError("expected the official Machine_Yearning_2SID.sid")
    offset = int.from_bytes(raw[6:8], "big")
    load = int.from_bytes(raw[8:10], "big")
    init = int.from_bytes(raw[10:12], "big")
    play = int.from_bytes(raw[12:14], "big")
    songs = int.from_bytes(raw[14:16], "big")
    payload = raw[offset:]
    if load == 0:
        load = int.from_bytes(payload[:2], "little")
        payload = payload[2:]
    if (load, init, play, songs) != (SID_LOAD, 0x1000, 0x1003, 7):
        raise ValueError("unexpected Machine Yearning player layout")
    return payload


def basic_entry(core):
    if int.from_bytes(core[:2], "little") != CORE_LOAD:
        raise ValueError("visualizer core must load at $3000")
    return CORE_LOAD, core[2:]


def basic_stub(entry):
    digits = str(entry).encode("ascii")
    end = OUTER_LOAD + 2 + 2 + 1 + len(digits) + 1
    return (end.to_bytes(2, "little") + b"\x0a\x00\x9e" + digits +
            b"\x00\x00\x00")


def build(sid, core):
    music = psid_payload(sid)
    entry, core_payload = basic_entry(core)
    if SID_LOAD + len(music) > CORE_LOAD:
        raise ValueError("music overlaps the visualizer core")
    end = CORE_LOAD + len(core_payload)
    memory = bytearray(end - OUTER_LOAD)
    stub = basic_stub(entry)
    memory[:len(stub)] = stub
    memory[SID_LOAD - OUTER_LOAD:SID_LOAD - OUTER_LOAD + len(music)] = music
    memory[CORE_LOAD - OUTER_LOAD:] = core_payload
    return OUTER_LOAD.to_bytes(2, "little") + memory


def main(argv):
    if len(argv) != 4:
        raise SystemExit("usage: pack.py MUSIC.sid CORE.prg OUTPUT.prg")
    sid, core, output = map(pathlib.Path, argv[1:])
    result = build(sid.read_bytes(), core.read_bytes())
    output.write_bytes(result)
    print(f"wrote {output} ({len(result)} bytes)")


if __name__ == "__main__":
    main(sys.argv)
