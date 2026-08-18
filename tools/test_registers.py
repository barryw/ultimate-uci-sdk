#!/usr/bin/env python3
"""Which hardware registers the SDK is allowed to touch, enforced on the source.

docs/compatibility.md tells a program that the SDK touches `$DF1B-$DF1F` and
nothing else in the I/O expansion area, because the command interface overlays
the last five REU registers and a program that pokes the whole `$DF00-$DF1F`
range as one device will disturb it. That promise is worth exactly as much as
the check behind it.

Two rules, and the second is the one that keeps the first honest:

  - **No `$DFxx` literal anywhere in the SDK.** Every register is reached
    through a name out of tools/gen_protocol.py, so there is one place that says
    what an address means.

  - **REU registers appear in reu.s and nowhere else.** The REU is the second of
    exactly two modules allowed to drive hardware directly (turbo.s is the
    other), and a module that quietly starts writing `$DF00` would erode that
    without anything failing.

Run with the rest: python3 -m unittest discover -s tools -p 'test_*.py'
"""

import glob
import os
import re
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The SDK itself and everything that ships with it: the core, the bindings, the
# BASIC wedge. Not the tests - a test may name a raw address on purpose, and
# tests/emulator/absent.suite does.
PATTERNS = (
    "src/uci/*.s",
    "src/basic/*.s",
    "bindings/asm/*.s",
    "bindings/cc65/*.s",
    "bindings/blob/*.s",
)

REU_ONLY = "src/uci/reu.s"

LITERAL = re.compile(r"\$[Dd][Ff][0-9A-Fa-f]{2}")
REU_NAME = re.compile(r"\bREU_REG_[A-Z_0-9]+\b")


def sources():
    for pattern in PATTERNS:
        for path in sorted(glob.glob(os.path.join(REPO, pattern))):
            yield os.path.relpath(path, REPO)


def code_lines(path):
    """(number, text) for lines that are not wholly a comment.

    The files explain these rules in their own prose and name the addresses
    while doing it, so a scan that counted comments would fail on the
    documentation of the thing it is checking.
    """
    with open(os.path.join(REPO, path)) as fh:
        for number, line in enumerate(fh, 1):
            stripped = line.strip()
            if stripped.startswith(";") or stripped.startswith("//"):
                continue
            code = line.split(";")[0]
            if code.strip():
                yield number, code


class RegisterRules(unittest.TestCase):

    def test_no_io_address_literals(self):
        found = []
        for path in sources():
            for number, code in code_lines(path):
                for hit in LITERAL.findall(code):
                    found.append("%s:%d: %s" % (path, number, hit))
        self.assertEqual([], found,
                         "$DFxx written as a literal. Use the generated name, "
                         "so there is one place that says what it is:\n  "
                         + "\n  ".join(found))

    def test_reu_registers_only_in_reu(self):
        found = []
        for path in sources():
            if path == REU_ONLY:
                continue
            for number, code in code_lines(path):
                for hit in REU_NAME.findall(code):
                    found.append("%s:%d: %s" % (path, number, hit))
        self.assertEqual([], found,
                         "the REU registers belong to src/uci/reu.s alone:\n  "
                         + "\n  ".join(found))

    def test_the_scan_reaches_the_sources(self):
        """A rule that scans nothing passes for the wrong reason."""
        self.assertGreater(len(list(sources())), 10)
        self.assertIn(REU_ONLY, list(sources()))

    def test_reu_really_does_use_them(self):
        """The check above passes trivially if reu.s stops driving the REU."""
        with open(os.path.join(REPO, REU_ONLY)) as fh:
            body = fh.read()
        for name in ("REU_REG_COMMAND", "REU_REG_STATUS", "REU_REG_C64_LO"):
            self.assertIn(name, body)


if __name__ == "__main__":
    unittest.main()
