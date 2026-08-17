#!/usr/bin/env python3
"""Tests for the CRUNCH model.

The wedge's whole match table is derived from this, so if the model is wrong
every keyword is wrong in the same direction and nothing downstream would
notice. The cases below are real C64 tokenisations, chosen to pin the parts of
the algorithm the wedge actually depends on rather than to cover it evenly.

Checked against the Commodore BASIC source (basic/code2.s) and against the
built 901226-01 image while this was written.
"""

import unittest

import c64_crunch as cc


def b(*values):
    return list(values)


class TestKnownTokenisations(unittest.TestCase):

    def check(self, source, expected):
        self.assertEqual(cc.crunch(source), expected,
                         "%r -> %s" % (source, cc.render(cc.crunch(source))))

    def test_a_plain_keyword(self):
        self.check("PRINT", b(0x99))

    def test_question_mark_is_print(self):
        self.check("?", b(0x99))

    def test_a_bare_identifier_is_left_alone(self):
        self.check("AB", b(0x41, 0x42))

    def test_keywords_need_no_spaces_around_them(self):
        self.check("FORI=1TO9", b(0x81, 0x49, 0xB2, 0x31, 0xA4, 0x39))

    def test_two_operators_in_a_row(self):
        # '<' then '>', because the list has '>' before '<' and matching is by
        # prefix: "<>" cannot match '>' first.
        self.check("IFA<>BTHENEND",
                   b(0x8B, 0x41, 0xB3, 0xB1, 0x42, 0xA7, 0x80))

    def test_a_string_constant_is_copied_verbatim(self):
        self.check('PRINT"HI"', b(0x99, 34, 0x48, 0x49, 34))

    def test_a_keyword_inside_a_string_is_not_tokenised(self):
        self.check('PRINT"PRINT"', b(0x99, 34, 0x50, 0x52, 0x49, 0x4E, 0x54, 34))

    def test_data_stops_tokenising(self):
        self.check("DATA PRINT",
                   b(0x83, 0x20, 0x50, 0x52, 0x49, 0x4E, 0x54))

    def test_rem_stops_tokenising(self):
        self.check("REM PRINT",
                   b(0x8F, 0x20, 0x50, 0x52, 0x49, 0x4E, 0x54))

    def test_a_colon_ends_data_and_tokenising_resumes(self):
        self.check("DATA 1:PRINT", b(0x83, 0x20, 0x31, 0x3A, 0x99))

    def test_a_colon_inside_a_string_does_not_end_data(self):
        self.check('DATA":"PRINT',
                   b(0x83, 34, 0x3A, 34, 0x50, 0x52, 0x49, 0x4E, 0x54))


class TestTheTwoFactsTheWedgeDependsOn(unittest.TestCase):

    def test_high_bytes_in_the_input_are_dropped(self):
        # The reason the wedge substitutes after CRUNCH instead of before. If
        # this ever stopped being true, pre-substitution would become the
        # simpler design and this test is where that would surface.
        self.assertEqual(cc.crunch("A\x99B"), b(0x41, 0x42))

    def test_pi_is_the_one_high_byte_that_survives(self):
        self.assertEqual(cc.crunch("A\xffB"), b(0x41, 0xFF, 0x42))

    def test_a_keyword_is_matched_inside_a_longer_word(self):
        # ULEN is not four letters by the time the wedge sees it.
        self.assertEqual(cc.crunch("ULEN"), b(0x55, 0xC3))
        self.assertEqual(cc.render(cc.crunch("ULEN")), "U[LEN]")

    def test_the_first_match_in_list_order_wins(self):
        # "GO" is last in the list and "GOTO" comes far earlier, so GOTO wins
        # even though GO also prefixes the input.
        self.assertEqual(cc.crunch("GOTO"), b(0x89))
        self.assertEqual(cc.crunch("GO TO"), b(0xCB, 0x20, 0xA4))


class TestVerbatimModeDetection(unittest.TestCase):

    def test_an_embedded_data_token_arms_verbatim_mode(self):
        self.assertTrue(cc.arms_verbatim_mode(cc.crunch("UDATA$")))

    def test_an_embedded_rem_token_arms_verbatim_mode(self):
        self.assertTrue(cc.arms_verbatim_mode(cc.crunch("UREM")))

    def test_an_ordinary_keyword_does_not(self):
        for name in ("UCI", "UERR", "ULEN", "UDAT$", "ULOAD", "USAVE"):
            self.assertFalse(cc.arms_verbatim_mode(cc.crunch(name)), name)


class TestTokenSpace(unittest.TestCase):

    def test_the_reserved_list_is_contiguous_from_80(self):
        for i, (token, _word) in enumerate(cc.RESERVED):
            self.assertEqual(token, 0x80 + i)

    def test_the_free_token_range_is_the_51_slots_the_design_counted(self):
        self.assertEqual(cc.FIRST_FREE_TOKEN, 0xCC)
        self.assertEqual(cc.LAST_FREE_TOKEN, 0xFE)
        self.assertEqual(cc.LAST_FREE_TOKEN - cc.FIRST_FREE_TOKEN + 1, 51)

    def test_pi_is_not_claimable(self):
        self.assertLess(cc.LAST_FREE_TOKEN, cc.PI)


if __name__ == "__main__":
    unittest.main()
