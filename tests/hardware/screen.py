#!/usr/bin/env python3
"""Reading the C64's screen back over the Ultimate's REST API.

Shared by hwtest.py, which prints the screen when a check fails, and by
basictest.py, which asserts on it.

SPDX-License-Identifier: MIT
"""

SCREEN_ADDR = 0x0400
SCREEN_LEN = 1000
SCREEN_COLS = 40
SCREEN_ROWS = 25


def decode_screen(raw):
    """C64 screen codes to something printable. Unknown glyphs become '.'.

    **Only $01-$1A are letters.** Screen codes $41-$5A are graphics symbols in
    the default character set, and they are what a program gets by writing
    PETSCII $C1-$DA - which is exactly what ca65's c64 charmap produces for an
    ordinary "ABC" in source. Decoding them back to letters here would be a
    decoder that agrees with the mistake: the wedge's banner was written that
    way, read back as clean text through such a decoder, and turned out to be
    a row of glyphs on the real screen. They stay '.' so that never happens
    quietly again.
    """
    out = []
    for row in range(SCREEN_ROWS):
        line = []
        for code in raw[row * SCREEN_COLS:(row + 1) * SCREEN_COLS]:
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


def screen_text(raw):
    """The whole screen as one string, for substring searches."""
    return "\n".join(decode_screen(raw))
