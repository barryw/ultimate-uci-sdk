#!/usr/bin/env python3
"""Tests for the cartridge container, and for the claim the cartridge makes.

The claim is the one that matters: the .crt is a delivery mechanism and not a
second implementation. Both builds carry the same CODE and RODATA and copy them
to the same address, so the bytes can be compared directly - and if someone
ever "just tweaks" one build, this is what notices.
"""

import os
import unittest

import make_crt

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASIC = os.path.join(REPO, "src", "basic")

PRG = os.path.join(BASIC, "uci.prg")
CART = os.path.join(BASIC, "uci-cart.bin")
CRT = os.path.join(BASIC, "uci.crt")
PRG_LBL = os.path.join(BASIC, "uci.lbl")
CART_LBL = os.path.join(BASIC, "uci-cart.lbl")
VERSION_INC = os.path.join(BASIC, "version.inc")

BUILT = all(os.path.exists(p) for p in
            (PRG, CART, PRG_LBL, CART_LBL, VERSION_INC))


def labels(path):
    """VICE label file -> {name: address}."""
    out = {}
    with open(path) as fh:
        for line in fh:
            parts = line.split()
            if len(parts) >= 3 and parts[0] == "al":
                out[parts[2].lstrip(".")] = int(parts[1], 16)
    return out


def payload(image, lbl, base, header):
    """The relocated bytes: CODE and RODATA at $C000, then UCICODE at $A000.

    Three segments, two destinations, one claim: the cartridge carries the same
    bytes as the .prg. UCICODE is the SDK, which runs under BASIC ROM - it has
    to be compared too, or half the shipped code would sit outside the one test
    that says the two deliveries are the same thing.
    """
    start = lbl["__CODE_LOAD__"]
    size = lbl["__CODE_SIZE__"] + lbl["__RODATA_SIZE__"]
    offset = header + (start - base)
    wedge = image[offset:offset + size]

    start = lbl["__UCICODE_LOAD__"]
    size = lbl["__UCICODE_SIZE__"]
    offset = header + (start - base)
    return wedge + image[offset:offset + size]


class TestContainer(unittest.TestCase):

    def image(self, size=make_crt.IMAGE_SIZE):
        return bytes(range(256)) * (size // 256)

    def test_a_wrong_sized_image_is_refused(self):
        # A short image would leave the cartridge reading whatever followed it,
        # and the CHIP packet would be lying about its own length.
        with self.assertRaises(SystemExit) as caught:
            make_crt.build(b"\x00" * 100, "SHORT")
        self.assertIn("expected exactly", str(caught.exception))

    def test_the_signature_and_lengths(self):
        out = make_crt.build(self.image(), "NAME")
        self.assertEqual(out[0:16], b"C64 CARTRIDGE   ")
        self.assertEqual(int.from_bytes(out[0x10:0x14], "big"), 0x40)
        self.assertEqual(int.from_bytes(out[0x14:0x16], "big"), 0x0100)
        self.assertEqual(len(out), 0x40 + 16 + make_crt.IMAGE_SIZE)

    def test_the_lines_are_the_8k_configuration(self):
        # EXROM low and GAME high. Getting these the wrong way round produces a
        # cartridge that either does not appear or takes the whole machine.
        out = make_crt.build(self.image(), "NAME")
        self.assertEqual(out[0x18], 0, "EXROM must be asserted")
        self.assertEqual(out[0x19], 1, "GAME must be left alone")

    def test_the_chip_packet_describes_the_image(self):
        out = make_crt.build(self.image(), "NAME")
        chip = out[0x40:0x50]
        self.assertEqual(chip[0:4], b"CHIP")
        self.assertEqual(int.from_bytes(chip[4:8], "big"), 16 + make_crt.IMAGE_SIZE)
        self.assertEqual(int.from_bytes(chip[8:10], "big"), 0, "chip type ROM")
        self.assertEqual(int.from_bytes(chip[12:14], "big"), 0x8000)
        self.assertEqual(int.from_bytes(chip[14:16], "big"), make_crt.IMAGE_SIZE)

    def test_the_name_is_padded_not_truncated_short(self):
        out = make_crt.build(self.image(), "UCI")
        self.assertEqual(out[0x20:0x40], b"UCI".ljust(32, b"\0"))

    def test_an_over_long_name_is_cut_rather_than_overrunning(self):
        out = make_crt.build(self.image(), "X" * 100)
        self.assertEqual(out[0x20:0x40], b"X" * 32)
        self.assertEqual(len(out), 0x40 + 16 + make_crt.IMAGE_SIZE)


@unittest.skipUnless(BUILT, "run `make -C src/basic` first")
class TestTheTwoBuildsCarryTheSameWedge(unittest.TestCase):

    def setUp(self):
        with open(PRG, "rb") as fh:
            self.prg = fh.read()
        with open(CART, "rb") as fh:
            self.cart = fh.read()
        self.prg_lbl = labels(PRG_LBL)
        self.cart_lbl = labels(CART_LBL)

    def test_both_run_the_wedge_at_the_same_address(self):
        self.assertEqual(self.prg_lbl["__CODE_RUN__"],
                         self.cart_lbl["__CODE_RUN__"])
        self.assertEqual(self.prg_lbl["wedge_install"],
                         self.cart_lbl["wedge_install"])

    def test_the_relocated_bytes_are_identical(self):
        # The whole claim of the cartridge, in one assertion.
        a = payload(self.prg, self.prg_lbl, 0x0801, 2)
        b = payload(self.cart, self.cart_lbl, 0x8000, 0)
        self.assertTrue(a, "no payload found in the .prg")
        self.assertEqual(len(a), len(b))
        self.assertEqual(a, b, "the two builds no longer carry the same wedge")

    def test_the_cartridge_image_is_exactly_8k(self):
        self.assertEqual(len(self.cart), make_crt.IMAGE_SIZE)

    def test_the_cartridge_autostarts(self):
        # $8000/$8002 are the cold and warm vectors, then the CBM80 signature.
        # Without it the machine ignores the cartridge entirely.
        cold = int.from_bytes(self.cart[0:2], "little")
        warm = int.from_bytes(self.cart[2:4], "little")
        self.assertEqual(cold, self.cart_lbl["cart_cold"])
        self.assertEqual(warm, self.cart_lbl["cart_cold"])
        self.assertEqual(self.cart[4:9], bytes([0xC3, 0xC2, 0xCD, 0x38, 0x30]))

    def test_the_prg_starts_with_a_runnable_basic_line(self):
        # $0801, then a one-line program: SYS 2061, which is where boot sits.
        self.assertEqual(self.prg[0:2], bytes([0x01, 0x08]))
        self.assertEqual(self.prg[6], 0x9E, "SYS")
        self.assertEqual(self.prg[7:11], b"2061")
        self.assertEqual(self.prg_lbl["boot"], 2061)

    def test_the_banner_contains_the_build_version(self):
        with open(VERSION_INC) as fh:
            version = fh.read().split('"')[1]
        banner = ("SDK " + version).upper().encode("ascii")
        self.assertIn(banner, self.prg)
        self.assertIn(banner, self.cart)


if __name__ == "__main__":
    unittest.main()
