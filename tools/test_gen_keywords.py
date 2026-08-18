#!/usr/bin/env python3
"""Tests for the BASIC wedge's keyword table.

The token numbers are pinned literally. That looks like testing the obvious
until you remember a tokenised BASIC program stores the token byte and not the
name: renumbering does not break a build, it silently changes what every
already-saved program means. This test is the thing that fails when someone
inserts a keyword in the middle instead of appending.
"""

import unittest

import c64_crunch as cc
import gen_keywords as gk


class TestTokenAssignment(unittest.TestCase):
    """Append-only. Changing a number here is changing a file format."""

    EXPECTED = {
        "UCI": 0xCC, "UERR": 0xCD, "UDEV": 0xCE, "ULEN": 0xCF,
        "UST$": 0xD0, "UDAT$": 0xD1, "UBYTE(": 0xD2, "UW(": 0xD3,
        "UL(": 0xD4, "UDOS1": 0xD5, "UDOS2": 0xD6, "UNET": 0xD7,
        "UCTRL": 0xD8, "UIEC": 0xD9, "UHTTP": 0xDA,
        "UTURBO": 0xDB,
        "ULOAD": 0xDC, "UBLOAD": 0xDD, "USAVE": 0xDE, "UDIR": 0xDF,
        "USTASH": 0xE0, "UFETCH": 0xE1,
    }

    def test_tokens_have_not_moved(self):
        got = {name: token for name, _k, _n, token, _m, _d in gk.entries()}
        self.assertEqual(got, self.EXPECTED)

    def test_tokens_start_where_the_reserved_words_end(self):
        self.assertEqual(gk.entries()[0][3], cc.FIRST_FREE_TOKEN)

    def test_tokens_are_contiguous_in_table_order(self):
        tokens = [t for _n, _k, _no, t, _m, _d in gk.entries()]
        self.assertEqual(tokens, list(range(tokens[0], tokens[0] + len(tokens))))

    def test_the_set_still_fits_the_token_space(self):
        self.assertLessEqual(gk.entries()[-1][3], cc.LAST_FREE_TOKEN)


class TestCrunchConstraints(unittest.TestCase):

    def setUp(self):
        self.rows = gk.entries()

    def test_no_keyword_arms_verbatim_mode(self):
        for name, _k, _n, _t, match, _d in self.rows:
            self.assertFalse(cc.arms_verbatim_mode(match),
                             "%s crunches to %s" % (name, cc.render(match)))

    def test_the_reply_string_is_udat_because_udata_is_impossible(self):
        names = [n for n, *_ in self.rows]
        self.assertIn("UDAT$", names)
        self.assertNotIn("UDATA$", names)
        # ...and this is why, so the reason survives the next rename attempt.
        self.assertTrue(cc.arms_verbatim_mode(cc.crunch("UDATA$")))

    def test_ulen_is_matched_as_a_token_sequence_not_as_text(self):
        row = next(r for r in self.rows if r[0] == "ULEN")
        _name, _k, _n, _t, match, display = row
        self.assertEqual(match, [0x55, 0xC3])
        self.assertEqual(display, [0x55, 0x4C, 0x45, 0x4E])
        self.assertNotEqual(match, display)

    def test_the_width_forcers_take_their_paren(self):
        # Bare "W" would tokenise the variable in FOR W=1 TO 10.
        for name in ("UW(", "UL("):
            self.assertIn(name, [n for n, *_ in self.rows])
            self.assertTrue(name.endswith("("))

    def test_no_pattern_is_a_prefix_of_another(self):
        patterns = [tuple(m) for _n, _k, _no, _t, m, _d in self.rows]
        for a in patterns:
            for b in patterns:
                if a is not b and a != b:
                    self.assertNotEqual(b[:len(a)], a)


class TestCheckRejects(unittest.TestCase):

    def setUp(self):
        self.real = gk.KEYWORDS

    def tearDown(self):
        gk.KEYWORDS = self.real

    def reject(self, keywords):
        gk.KEYWORDS = keywords
        with self.assertRaises(SystemExit) as caught:
            gk.check(gk.entries())
        return str(caught.exception)

    def test_the_real_table_passes(self):
        gk.check(gk.entries())

    def test_a_keyword_that_swallows_the_line_is_refused(self):
        problem = self.reject([("UDATA$", gk.FUNCTION, "")])
        self.assertIn("verbatim mode", problem)

    def test_a_single_letter_keyword_is_refused(self):
        # It would match inside every variable name that contains it.
        problem = self.reject([("W", gk.FUNCTION, "")])
        self.assertIn("single byte", problem)

    def test_a_prefix_collision_is_refused(self):
        problem = self.reject([("UCI", gk.STATEMENT, ""),
                               ("UCIX", gk.STATEMENT, "")])
        self.assertIn("prefix", problem)

    def test_running_out_of_tokens_is_refused(self):
        many = [("UK%03d" % i, gk.FUNCTION, "") for i in range(60)]
        self.assertIn("free tokens", self.reject(many))

    def test_a_duplicate_name_is_refused(self):
        problem = self.reject([("UCI", gk.STATEMENT, ""),
                               ("UCI", gk.FUNCTION, "")])
        self.assertIn("duplicate", problem)


class TestEmittedTable(unittest.TestCase):
    """Decode the emitted bytes the way the 6502 scan will."""

    def setUp(self):
        self.rows = gk.entries()
        self.text = gk.asm_include(self.rows)

    def bytes_of(self):
        """Pull the .byte stream back out of the generated source."""
        out = []
        started = False
        for line in self.text.splitlines():
            line = line.strip()
            if line.startswith("uci_keywords:"):
                started = True
                continue
            if not started:
                continue
            if line.startswith("uci_keywords_size"):
                break
            if line.startswith(".byte"):
                body = line[len(".byte"):].split(";")[0]
                for part in body.split(","):
                    part = part.strip()
                    out.append(int(part[1:], 16) if part.startswith("$")
                               else int(part))
        return out

    def test_the_stream_walks_back_into_the_table(self):
        stream = self.bytes_of()
        i = 0
        decoded = []
        while stream[i] != 0:
            matchlen = stream[i]
            i += 1
            match = stream[i:i + matchlen]
            i += matchlen
            displaylen = stream[i]
            i += 1
            if displaylen:
                display = stream[i:i + displaylen]
                i += displaylen
            else:
                display = match
            decoded.append((match, display))
        self.assertEqual(i, len(stream) - 1, "terminator is not the last byte")

        expected = [(m, d) for _n, _k, _no, _t, m, d in self.rows]
        self.assertEqual(decoded, expected)

    def test_the_shared_case_costs_one_byte_not_a_second_copy(self):
        """Only a keyword the ROM crunched carries its display text twice.

        The four that do are the four with a reserved word inside them, and
        naming them is the point: a fifth appearing means a new keyword is
        being tokenised in a way its author probably did not intend, and a
        fourth disappearing means the ROM stopped crunching one that it does.
        """
        stream = self.bytes_of()
        differ = sorted(n for n, _k, _no, _t, m, d in self.rows if m != d)
        self.assertEqual(differ, ["UBLOAD", "ULEN", "ULOAD", "USAVE"])
        self.assertLess(len(stream), 200)


if __name__ == "__main__":
    unittest.main()
