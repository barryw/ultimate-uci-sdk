#!/usr/bin/env python3
"""Single source of truth for the BASIC wedge's keywords and tokens.

Run:  python3 tools/gen_keywords.py
Emits:
    bindings/asm/uci_keywords.inc       (ca65)
    docs/generated/basic-keywords.md

Three consumers walk one table, which is the point: tokenising (the ICRNCH
hook), LIST detokenising (the IQPLOP hook) and dispatch all read the same
bytes, so a keyword cannot exist in one and not the others.

**Token values are a file format.** A tokenised BASIC program stores the token
byte, not the name, so a saved program is only readable by a wedge that assigns
the same numbers. KEYWORDS is therefore append-only: never reorder it, never
remove an entry, and add new keywords at the end even when that puts them out
of alphabetical order.

Two constraints come from CRUNCH rather than from taste, and both were found by
modelling it (see tools/c64_crunch.py) rather than by reasoning about it:

  - The wedge substitutes its tokens *after* the ROM has crunched the line,
    because CRUNCH drops input bytes >= $80. So the match pattern is whatever
    the ROM leaves behind, which for ULEN is 'U' followed by the LEN token.

  - A keyword whose crunched form contains DATA or REM arms verbatim mode and
    stops the rest of the statement being tokenised. That ruled out UDATA$,
    which is why the reply string is UDAT$.
"""

import os

import c64_crunch as cc

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STATEMENT = "statement"
FUNCTION = "function"
CONSTANT = "constant"

# (name, kind, note). Append only - see the module docstring.
#
# Single-letter names are impossible: CRUNCH matches a keyword anywhere, not
# only at a word boundary, so claiming "W" would tokenise the W in FOR W=1 TO 10
# and break every program that uses it as a variable. The width forcers follow
# the ROM's own TAB( and SPC( instead and take the paren into their name, which
# keeps UW and UL usable as ordinary variables.
KEYWORDS = [
    ("UCI",    STATEMENT, "execute any command on any target; also the "
                          "function form, which returns the reply length"),
    ("UERR",   FUNCTION,  "ULTIMATE_* result code, 0 is OK"),
    ("UDEV",   FUNCTION,  "raw device code the target reported"),
    ("ULEN",   FUNCTION,  "reply length in bytes"),
    ("UST$",   FUNCTION,  "status string exactly as the target sent it"),
    ("UDAT$",  FUNCTION,  "reply as a string, clipped to 255 bytes"),
    ("UBYTE(", FUNCTION,  "byte n of the reply"),
    ("UW(",    FUNCTION,  "force a 16-bit argument"),
    ("UL(",    FUNCTION,  "force a 32-bit argument"),
    ("UDOS1",  CONSTANT,  "target $01, Ultimate DOS instance 1"),
    ("UDOS2",  CONSTANT,  "target $02, Ultimate DOS instance 2"),
    ("UNET",   CONSTANT,  "target $03, network"),
    ("UCTRL",  CONSTANT,  "target $04, machine and cartridge control"),
    ("UIEC",   CONSTANT,  "target $05, SoftwareIEC"),
    ("UHTTP",  CONSTANT,  "target $06, HTTP client"),
    ("UTURBO", STATEMENT, "CPU speed index as a statement, and the current "
                          "index as a function - 255 when the machine's turbo "
                          "is switched off in its settings"),
    ("ULOAD",  STATEMENT, "ULOAD name$ [,address] - a PRG, with the header "
                          "consumed; no address means the file's own, exactly "
                          "as LOAD\"X\",8,1"),
    ("UBLOAD", STATEMENT, "UBLOAD name$, address, length - raw bytes, nothing "
                          "interpreted and nothing past the length"),
    ("USAVE",  STATEMENT, "USAVE name$, start, length - memory to a file"),
    ("UDIR",   STATEMENT, "UDIR - the current directory, printed"),
    ("USTASH", STATEMENT, "USTASH address, reu address, length - C64 memory "
                          "into the RAM expansion"),
    ("UFETCH", STATEMENT, "UFETCH address, reu address, length - and back "
                          "out of it"),
    ("UREU",   FUNCTION,  "size of the RAM expansion in 64K banks, 0 when "
                          "there is none - so it answers 'is there one' and "
                          "'how much' in a single question"),
]

# Constants resolve to a protocol value rather than to a handler.
CONSTANT_VALUES = {
    "UDOS1": 0x01, "UDOS2": 0x02, "UNET": 0x03,
    "UCTRL": 0x04, "UIEC": 0x05, "UHTTP": 0x06,
}


def symbol(name):
    """ca65 symbol suffix for a keyword name."""
    return (name.replace("$", "S").replace("(", "").upper())


def entries():
    """(name, kind, note, token, match bytes, display bytes)."""
    out = []
    for index, (name, kind, note) in enumerate(KEYWORDS):
        token = cc.FIRST_FREE_TOKEN + index
        match = cc.crunch(name)
        display = [ord(c) for c in name]
        out.append((name, kind, note, token, match, display))
    return out


def check(rows):
    problems = []

    if len(KEYWORDS) > cc.LAST_FREE_TOKEN - cc.FIRST_FREE_TOKEN + 1:
        problems.append("%d keywords but only %d free tokens"
                        % (len(KEYWORDS),
                           cc.LAST_FREE_TOKEN - cc.FIRST_FREE_TOKEN + 1))

    names = [name for name, *_ in rows]
    if len(names) != len(set(names)):
        problems.append("duplicate keyword name")

    for name, kind, _note, _token, match, _display in rows:
        if kind not in (STATEMENT, FUNCTION, CONSTANT):
            problems.append("%s: unknown kind %r" % (name, kind))
        if cc.arms_verbatim_mode(match):
            problems.append(
                "%s crunches to %s, which arms CRUNCH's verbatim mode and stops "
                "the rest of the statement being tokenised. Rename it."
                % (name, cc.render(match)))
        if len(match) < 2:
            problems.append(
                "%s crunches to a single byte, so it would match that byte "
                "wherever it appears - including in a variable name." % name)

    # No match pattern may prefix another, or the scan's answer would depend on
    # the order entries happen to sit in rather than on what the user typed.
    for i, (name_a, _k, _n, _t, match_a, _d) in enumerate(rows):
        for j, (name_b, _k2, _n2, _t2, match_b, _d2) in enumerate(rows):
            if i != j and match_b[:len(match_a)] == match_a:
                problems.append("%s's pattern is a prefix of %s's"
                                % (name_a, name_b))

    if problems:
        raise SystemExit("gen_keywords.py: keyword table is inconsistent:\n  "
                         + "\n  ".join(problems))


def asm_include(rows):
    out = [
        "; Generated by tools/gen_keywords.py - DO NOT EDIT BY HAND.",
        ";",
        "; BASIC wedge keywords: one table walked by the tokeniser, by LIST and",
        "; by dispatch.",
        ";",
        "; TOKEN VALUES ARE A FILE FORMAT. A tokenised BASIC program stores the",
        "; token byte, so renumbering silently changes what saved programs mean.",
        "; The table is append-only.",
        ";",
        "; Each entry:",
        ";",
        ";     .byte matchlen",
        ";     .byte match...        ; the bytes CRUNCH leaves in the line, which",
        ";                           ; is not always the text the user typed",
        ";     .byte displaylen      ; 0 when the display text is the match bytes",
        ";     .byte display...      ; only present when displaylen is not 0",
        ";",
        "; Tokens run from UCI_TOK_FIRST upward in table order, so a scan can",
        "; count entries instead of storing the token in each one.",
        ";",
        "; SPDX-License-Identifier: MIT",
        "",
        "UCI_TOK_FIRST  = $%02X" % cc.FIRST_FREE_TOKEN,
        "UCI_TOK_LAST   = $%02X" % (cc.FIRST_FREE_TOKEN + len(rows) - 1),
        "UCI_TOK_COUNT  = %d" % len(rows),
        "",
    ]
    width = max(len(symbol(name)) for name, *_ in rows)
    for name, kind, _note, token, _match, _display in rows:
        out.append("UCI_TOK_%-*s = $%02X   ; %s" % (width, symbol(name), token, kind))
    out.append("")
    out.append("; Target constants, in table order, for the constant handler.")
    for name, kind, _note, _token, _match, _display in rows:
        if kind == CONSTANT:
            out.append("UCI_KWVAL_%-*s = $%02X" % (width, symbol(name),
                                                   CONSTANT_VALUES[name]))
    out.append("")
    out.append("uci_keywords:")
    for name, _kind, _note, token, match, display in rows:
        same = (match == display)
        out.append("        ; $%02X %s%s" % (token, name,
                                             "" if same else
                                             "   (crunches to %s)" % cc.render(match)))
        out.append("        .byte %d, %s"
                   % (len(match), ", ".join("$%02X" % b for b in match)))
        if same:
            out.append("        .byte 0")
        else:
            out.append("        .byte %d, %s"
                       % (len(display), ", ".join("$%02X" % b for b in display)))
    out.append("        .byte 0                 ; end of table")
    out.append("")
    out.append("uci_keywords_size = * - uci_keywords")
    out.append("")
    return "\n".join(out)


def markdown(rows):
    out = [
        "<!-- Generated by tools/gen_keywords.py - DO NOT EDIT BY HAND. -->",
        "",
        "# BASIC wedge keywords",
        "",
        "Token values are a file format: a tokenised BASIC program stores the",
        "token byte rather than the name, so the table is append-only and these",
        "numbers never change.",
        "",
        "The **crunched form** column is what the BASIC ROM leaves in the line by",
        "the time the wedge sees it. It is not always the text that was typed:",
        "CRUNCH matches a reserved word anywhere, so the `LEN` inside `ULEN`",
        "becomes a token before the wedge gets a look. The wedge matches the",
        "crunched form; `LIST` prints the name.",
        "",
        "| Token | Keyword | Kind | Crunched form | Notes |",
        "| --- | --- | --- | --- | --- |",
    ]
    for name, kind, note, token, match, display in rows:
        crunched = "same" if match == display else "`%s`" % cc.render(match)
        out.append("| `$%02X` | `%s` | %s | %s | %s |"
                   % (token, name, kind, crunched, note))
    out.append("")
    out.append("`$%02X`-`$%02X` remain free; `$FF` is pi and can never be claimed."
               % (cc.FIRST_FREE_TOKEN + len(rows), cc.LAST_FREE_TOKEN))
    out.append("")
    return "\n".join(out)


def write(path, text):
    full = os.path.join(REPO, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as fh:
        fh.write(text)
    print("wrote %s (%d bytes)" % (path, len(text)))


def main():
    rows = entries()
    check(rows)
    write("bindings/asm/uci_keywords.inc", asm_include(rows))
    write("docs/generated/basic-keywords.md", markdown(rows))


if __name__ == "__main__":
    main()
