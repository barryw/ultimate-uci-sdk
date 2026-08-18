#!/usr/bin/env python3
"""The charmap rule, enforced on the C sources.

cc65 and ca65 both install the c64 charmap when the target is c64, and both
apply it to string literals. Source 'A'-'Z' becomes PETSCII $C1-$DA, which
CHROUT renders as *graphics symbols*; source 'a'-'z' becomes $41-$5A, which
renders as letters. So a display string written the obvious way prints as a row
of glyphs, and nothing in a build, a unit test or an emulator suite notices -
the bytes are the bytes, and only a real screen tells you.

That has now cost three separate fixes: ultimate_strerror.s, examples/asm's
banner, and the wedge's. This is the check that would have caught all three on
the C side.

**Do not "fix" a failure by decoding differently.** tests/hardware/screen.py
renders $41-$5A as '.' on purpose, for exactly this reason: a decoder that maps
them back to letters agrees with the bug instead of finding it.

Protocol bytes are a separate rule and are not affected: they are never string
literals at all, they are byte lists out of tools/gen_protocol.py. See
docs/handover.md section 2.
"""

import glob
import os
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Everything that is compiled for the C64 and prints to its screen. Headers are
# in because a literal hidden in a macro compiles just the same.
PATTERNS = (
    "examples/*/*.c",
    "tests/hardware/*.c",
    "include/*.h",
)


def string_literals(src):
    """Every double-quoted literal in C source, as (line, text).

    Comments are skipped, which is the whole reason this is a scanner and not a
    regex: the files explain this rule in prose, and the prose quotes the
    strings it is warning about.
    """
    out = []
    i, line, n = 0, 1, len(src)
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
        elif src.startswith("/*", i):
            end = src.find("*/", i + 2)
            end = n if end < 0 else end + 2
            line += src.count("\n", i, end)
            i = end
        elif src.startswith("//", i):
            i = src.find("\n", i)
            i = n if i < 0 else i
        elif c == "'":
            i += 1
            while i < n and src[i] != "'":
                i += 2 if src[i] == "\\" else 1
            i += 1
        elif c == '"':
            quote = i
            start, i = line, i + 1
            text = []
            while i < n and src[i] != '"':
                if src[i] == "\\":
                    i += 2
                    continue
                if src[i] == "\n":
                    line += 1
                text.append(src[i])
                i += 1
            i += 1
            # `extern "C"` is a linkage specification, not text: it never
            # reaches a character set, and the compiler insists on the capital.
            if not src[:quote].rstrip().endswith("extern"):
                out.append((start, "".join(text)))
        else:
            i += 1
    return out


class CharmapTest(unittest.TestCase):

    def test_no_uppercase_in_string_literals(self):
        """A display string with an uppercase letter prints as glyphs."""
        bad = []
        for pattern in PATTERNS:
            for path in sorted(glob.glob(os.path.join(REPO, pattern))):
                with open(path) as fh:
                    src = fh.read()
                for line, text in string_literals(src):
                    if any("A" <= ch <= "Z" for ch in text):
                        rel = os.path.relpath(path, REPO)
                        bad.append("%s:%d: %r" % (rel, line, text))
        self.assertEqual(bad, [], "write these lowercase; the c64 charmap "
                         "turns source 'A'-'Z' into PETSCII graphics symbols:"
                         "\n  " + "\n  ".join(bad))

    def test_scanner_skips_comments_char_constants_and_extern(self):
        """The scanner has to be right, or the test above is decoration."""
        src = ('/* a "COMMENT" with a quote */\n'
               '// another "COMMENT"\n'
               'extern "C" {\n'
               'char q = \'"\';\n'
               'const char *s = "live \\"quoted\\" text";\n')
        self.assertEqual(string_literals(src), [(5, "live quoted text")])

    def test_scanner_finds_the_bug_it_exists_for(self):
        found = string_literals('printf("SOFTIEC");')
        self.assertEqual(found, [(1, "SOFTIEC")])


if __name__ == "__main__":
    unittest.main()
