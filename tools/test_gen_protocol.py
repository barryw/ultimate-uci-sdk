#!/usr/bin/env python3
"""Tests for the generated protocol tables.

Two jobs. The first is to prove ARGS cannot express something a marshaller
would silently get wrong - check_args() has to reject it rather than let
gen_protocol.py emit it.

The second matters more. The wire offsets below were read out of the firmware
source, and one of them had been wrong in this repo's prose for as long as the
prose existed: SOFTIEC_CMD_LOAD_SU's filename starts at message[8], not
message[6], because a load shares SAVE's layout and has to send the end-address
pair it never reads. Sending the name two bytes early is accepted by the
firmware, which then opens whatever the tail happens to be, so the failure looks
like a missing file rather than a malformed command. Pinning the offsets
arithmetically means deleting a padding field fails here instead.

Runs under `make test` with no hardware and no Docker.
"""

import unittest

import gen_protocol as gp


def prefix_width(command, upto):
    """Bytes on the wire before argument `upto`, counting the target and command.

    Returns None if anything before `upto` is variable width, which would make
    the offset meaningless.
    """
    total = 2  # target byte, command byte
    for kind, spec in gp.ARGS[command]:
        if kind != "lit" and spec == upto:
            return total
        width = gp.ARG_WIDTHS[kind]
        if width is None:
            return None
        total += width
    raise AssertionError("%s has no argument %r" % (command, upto))


class TestArgOffsets(unittest.TestCase):
    """Offsets read from the 1541ultimate firmware source, pinned here."""

    def test_softiec_load_su_name_is_at_offset_8(self):
        # softiec_target.cc, cmd_load_su(): ext_open_file(&command->message[8]).
        # 2 sec, 3 verify, 4-5 load address, 6-7 end address, 8- name.
        self.assertEqual(prefix_width("SOFTIEC_CMD_LOAD_SU", "name"), 8)

    def test_softiec_save_name_is_at_offset_8(self):
        # softiec_target.cc, cmd_save(): same layout, and this one reads 6,7.
        self.assertEqual(prefix_width("SOFTIEC_CMD_SAVE", "name"), 8)

    def test_softiec_open_name_is_at_offset_4(self):
        # softiec_target.cc, cmd_open(): 2 secondary address, 3 unused, 4- name.
        self.assertEqual(prefix_width("SOFTIEC_CMD_OPEN", "name"), 4)

    def test_softiec_chkout_data_is_at_offset_4(self):
        # softiec_target.cc, cmd_chkout(): pushes from message[4].
        self.assertEqual(prefix_width("SOFTIEC_CMD_CHKOUT", "data"), 4)

    def test_dos_write_data_starts_at_offset_4(self):
        # dos.cc: file->write(&command->message[4], length - 4).
        self.assertEqual(prefix_width("DOS_CMD_WRITE_DATA", "data"), 4)

    def test_dos_file_seek_is_a_32_bit_position(self):
        # dos.cc assembles message[2..5] little-endian.
        self.assertEqual(gp.ARGS["DOS_CMD_FILE_SEEK"], [("dword", "pos")])

    def test_easyflash_base_address_is_one_byte(self):
        # control_target.cc reads message[4] as a single byte; only bit $20 and
        # the bank bits are used. The prose "<baseaddr>" read like an address.
        self.assertEqual(
            gp.ARGS["CTRL_CMD_EASYFLASH"],
            [("lit", 0x00), ("byte", "bank"), ("byte", "baseaddr")])

    def test_net_set_ipaddr_config_is_twelve_bytes(self):
        # network_target.cc rejects any length but 15: target, command, iface, 12.
        self.assertEqual(gp.ARGS["NET_CMD_SET_IPADDR"][0], ("byte", "iface"))
        constants = {n: v for _t, _n, items in gp.GROUPS for n, v, _c in items}
        self.assertEqual(constants["UCI_NET_IPCONFIG_BYTES"], 12)

    def test_http_body_add_int_key_is_length_prefixed(self):
        # http_target.cc: keylen at message[3], key from 4, value after it.
        self.assertEqual(
            gp.ARGS["HTTP_CMD_BODY_ADD_INT"],
            [("byte", "handle"), ("pstr", "key"), ("dword", "value")])


class TestCheckArgs(unittest.TestCase):

    def setUp(self):
        self.real = gp.ARGS

    def tearDown(self):
        gp.ARGS = self.real

    def reject(self, table):
        gp.ARGS = table
        with self.assertRaises(SystemExit) as caught:
            gp.check_args()
        return str(caught.exception)

    def test_the_real_table_passes(self):
        gp.check_args()

    def test_unknown_command_is_rejected(self):
        self.assertIn("no such constant",
                      self.reject({"DOS_CMD_NOT_A_THING": [("byte", "x")]}))

    def test_unknown_kind_is_rejected(self):
        self.assertIn("unknown kind",
                      self.reject({"DOS_CMD_CHANGE_DIR": [("qword", "x")]}))

    def test_empty_shape_is_rejected(self):
        # An empty list reads as "takes nothing", which the absence of an entry
        # already says. Two ways to say one thing is how they drift apart.
        self.assertIn("empty shape",
                      self.reject({"DOS_CMD_CHANGE_DIR": []}))

    def test_unbounded_string_before_another_argument_is_rejected(self):
        # <name> <sec> cannot be marshalled: nothing says where the name ends.
        problem = self.reject({"DOS_CMD_CHANGE_DIR":
                               [("str", "name"), ("byte", "sec")]})
        self.assertIn("must be last or followed by", problem)

    def test_unbounded_string_before_a_literal_is_allowed(self):
        gp.ARGS = {"DOS_CMD_RENAME_FILE":
                   [("str", "old"), ("lit", 0x00), ("str", "new")]}
        gp.check_args()

    def test_trailing_data_must_be_last(self):
        problem = self.reject({"DOS_CMD_ECHO":
                               [("data", "d"), ("byte", "x")]})
        self.assertIn("nothing may follow it", problem)

    def test_literal_must_be_a_byte(self):
        self.assertIn("lit takes a byte value",
                      self.reject({"DOS_CMD_CHANGE_DIR": [("lit", 0x100)]}))
        self.assertIn("lit takes a byte value",
                      self.reject({"DOS_CMD_CHANGE_DIR": [("lit", "zero")]}))

    def test_duplicate_argument_names_are_rejected(self):
        # Two arguments called the same thing cannot both be addressed by name.
        self.assertIn("duplicate name",
                      self.reject({"DOS_CMD_SET_TIME":
                                   [("byte", "h"), ("byte", "h")]}))

    def test_named_argument_needs_a_name(self):
        self.assertIn("needs a name",
                      self.reject({"DOS_CMD_CHANGE_DIR": [("byte", 3)]}))

    def test_every_problem_is_reported_not_just_the_first(self):
        problem = self.reject({
            "DOS_CMD_NOT_A_THING": [("byte", "x")],
            "DOS_CMD_CHANGE_DIR": [("qword", "y")],
        })
        self.assertIn("no such constant", problem)
        self.assertIn("unknown kind", problem)


class TestArgSummary(unittest.TestCase):

    def test_each_kind_renders(self):
        gp_args = gp.ARGS
        try:
            gp.ARGS = {"DOS_CMD_ECHO": [
                ("byte", "b"), ("word", "w"), ("dword", "d"),
                ("pstr", "p"), ("lit", 0xFF), ("str", "s"),
            ]}
            self.assertEqual(gp.arg_summary("DOS_CMD_ECHO"),
                             "<b> <w:16> <d:32> <p:len> <p> $FF <s>")
        finally:
            gp.ARGS = gp_args

    def test_a_command_with_no_arguments_renders_empty(self):
        self.assertEqual(gp.arg_summary("DOS_CMD_IDENTIFY"), "")

    def test_note_puts_the_shape_before_the_prose(self):
        note = gp.arg_note("DOS_CMD_SWAP_DISK", "some prose")
        self.assertEqual(note, "<id> - some prose")

    def test_note_of_an_argumentless_command_is_just_the_prose(self):
        self.assertEqual(gp.arg_note("DOS_CMD_IDENTIFY", "prose"), "prose")


class TestTableHygiene(unittest.TestCase):

    def test_every_shaped_command_looks_like_a_command(self):
        # ARGS is keyed by command constant. A register or a status code getting
        # in would generate an argument column for something that has none.
        for name in gp.ARGS:
            self.assertRegex(name, r"_CMD_", name)

    def test_widths_cover_every_kind_used(self):
        for shape in gp.ARGS.values():
            for kind, _spec in shape:
                self.assertIn(kind, gp.ARG_WIDTHS)


if __name__ == "__main__":
    unittest.main()
