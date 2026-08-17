#!/usr/bin/env python3
"""CRUNCH, as the C64 BASIC ROM implements it.

The BASIC wedge hooks ICRNCH, which means it sees each input line *after* the
ROM has tokenised it. So the question "what bytes does UCI look like in a
tokenised line?" has to be answered before the wedge's match table can be
written, and the only correct answer is whatever CRUNCH produces.

Two facts out of the ROM decide the whole design of the wedge's tokeniser, and
both are easy to get wrong from memory:

  - **CRUNCH drops input bytes >= $80** (pi, $FF, is the sole exception). It
    copies through a separate output index and simply skips them. So a wedge
    cannot pre-substitute its own tokens into the input buffer and let CRUNCH
    run afterwards - the tokens would vanish. Substitution has to happen after.

  - **A keyword is matched anywhere, not only at a word boundary.** The first
    reserved word in list order that prefixes the input wins. So ULEN contains
    LEN and tokenises to 'U' $C3, and the wedge has to match that sequence
    rather than the four letters a user typed.

Modelled on basic/code2.s (ncrnch) in the Commodore source. Nothing is copied
from the ROM: this is a reimplementation of the algorithm, and RESERVED below
is the published keyword-to-token mapping that has been in every C64 manual
since 1982.

Verified against real tokenisations in tools/test_c64_crunch.py.
"""

# (token, spelling). Token $80 upward, in the order CRUNCH tries them, which is
# also the order that decides which of two overlapping keywords wins.
RESERVED = [
    (0x80, 'END'),     (0x81, 'FOR'),     (0x82, 'NEXT'),    (0x83, 'DATA'),
    (0x84, 'INPUT#'),  (0x85, 'INPUT'),   (0x86, 'DIM'),     (0x87, 'READ'),
    (0x88, 'LET'),     (0x89, 'GOTO'),    (0x8A, 'RUN'),     (0x8B, 'IF'),
    (0x8C, 'RESTORE'), (0x8D, 'GOSUB'),   (0x8E, 'RETURN'),  (0x8F, 'REM'),
    (0x90, 'STOP'),    (0x91, 'ON'),      (0x92, 'WAIT'),    (0x93, 'LOAD'),
    (0x94, 'SAVE'),    (0x95, 'VERIFY'),  (0x96, 'DEF'),     (0x97, 'POKE'),
    (0x98, 'PRINT#'),  (0x99, 'PRINT'),   (0x9A, 'CONT'),    (0x9B, 'LIST'),
    (0x9C, 'CLR'),     (0x9D, 'CMD'),     (0x9E, 'SYS'),     (0x9F, 'OPEN'),
    (0xA0, 'CLOSE'),   (0xA1, 'GET'),     (0xA2, 'NEW'),     (0xA3, 'TAB('),
    (0xA4, 'TO'),      (0xA5, 'FN'),      (0xA6, 'SPC('),    (0xA7, 'THEN'),
    (0xA8, 'NOT'),     (0xA9, 'STEP'),    (0xAA, '+'),       (0xAB, '-'),
    (0xAC, '*'),       (0xAD, '/'),       (0xAE, '^'),       (0xAF, 'AND'),
    (0xB0, 'OR'),      (0xB1, '>'),       (0xB2, '='),       (0xB3, '<'),
    (0xB4, 'SGN'),     (0xB5, 'INT'),     (0xB6, 'ABS'),     (0xB7, 'USR'),
    (0xB8, 'FRE'),     (0xB9, 'POS'),     (0xBA, 'SQR'),     (0xBB, 'RND'),
    (0xBC, 'LOG'),     (0xBD, 'EXP'),     (0xBE, 'COS'),     (0xBF, 'SIN'),
    (0xC0, 'TAN'),     (0xC1, 'ATN'),     (0xC2, 'PEEK'),    (0xC3, 'LEN'),
    (0xC4, 'STR$'),    (0xC5, 'VAL'),     (0xC6, 'ASC'),     (0xC7, 'CHR$'),
    (0xC8, 'LEFT$'),   (0xC9, 'RIGHT$'),  (0xCA, 'MID$'),    (0xCB, 'GO'),
]

TOKEN_OF = {word: token for token, word in RESERVED}
WORD_OF = {token: word for token, word in RESERVED}

DATATK = TOKEN_OF['DATA']
REMTK = TOKEN_OF['REM']
PRINTTK = TOKEN_OF['PRINT']
PI = 0xFF

# Tokens the wedge may claim: above the last reserved word, below pi.
FIRST_FREE_TOKEN = RESERVED[-1][0] + 1
LAST_FREE_TOKEN = PI - 1


def _armed(byte, dores):
    """stuffh's tail: DATA and REM arm verbatim mode, ':' disarms it.

    dores is the ROM's flag; bit 6 set means "stop tokenising". The value is
    always the stuffed byte minus ':', which is why ':' itself lands on zero.
    """
    if byte in (ord(':'), DATATK, REMTK):
        return (byte - 0x3A) & 0xFF
    return dores


def crunch(line):
    """Tokenise one input line the way ncrnch does. Returns a list of bytes."""
    src = [ord(c) for c in line]
    out = []
    dores = 4          # ncrnch seeds it with 4: bit 6 clear, so tokenising is on
    i = 0
    while i < len(src):
        c = src[i]

        if c >= 0x80:
            if c == PI:
                out.append(c)
            # Anything else >= $80 is skipped without being copied out. This is
            # the fact that forces the wedge to substitute after CRUNCH.
            i += 1
            continue

        if c == ord(' '):
            out.append(c)
            i += 1
            continue

        if c == ord('"'):              # copy a string constant verbatim
            out.append(c)
            i += 1
            while i < len(src):
                out.append(src[i])
                i += 1
                if src[i - 1] == ord('"'):
                    break
            continue

        if dores & 0x40:               # inside DATA or REM
            out.append(c)
            dores = _armed(c, dores)   # ...but ':' still ends the statement
            i += 1
            continue

        if c == ord('?'):
            out.append(PRINTTK)
            dores = _armed(PRINTTK, dores)
            i += 1
            continue

        if 0x30 <= c < 0x3C:           # '0'..';' are never the start of a keyword
            out.append(c)
            dores = _armed(c, dores)
            i += 1
            continue

        match = None
        for token, word in RESERVED:
            if all(i + k < len(src) and src[i + k] == ord(word[k])
                   for k in range(len(word))):
                match = (token, len(word))
                break
        if match:
            token, length = match
            out.append(token)
            dores = _armed(token, dores)
            i += length
        else:
            out.append(c)
            dores = _armed(c, dores)
            i += 1
    return out


def arms_verbatim_mode(seq):
    """True when this byte sequence leaves CRUNCH not tokenising.

    A keyword whose crunched form does this cannot be used: everything after it
    up to the next ':' stops being tokenised, so the rest of the statement
    reaches the interpreter as raw text.
    """
    dores = 4
    for byte in seq:
        dores = _armed(byte, dores)
    return bool(dores & 0x40)


def render(seq):
    """Human rendering of a crunched sequence: [LEN] for an embedded token."""
    out = []
    for byte in seq:
        if byte >= 0x80:
            out.append("[%s]" % WORD_OF.get(byte, "$%02X" % byte))
        else:
            out.append(chr(byte))
    return "".join(out)
