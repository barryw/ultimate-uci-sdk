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

import os
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


def decode_arg_table(rows):
    """Walk the emitted rows the way the 6502 will, back into shapes.

    Deliberately does not reuse the packing code. A test that packs with the
    same helper it unpacks with agrees with itself no matter what it emits.
    """
    names = {code: kind for kind, code in gp.ARG_CODES.items()}
    out = {}
    for target, _command, value, codes in rows:
        packed = []
        for i in range(0, len(codes), 2):
            hi = codes[i]
            lo = codes[i + 1] if i + 1 < len(codes) else gp.ARG_CODES["end"]
            packed.append((hi << 4) | lo)

        # From here on, only the bytes an assembler would emit.
        count = len(codes)
        kinds = []
        for i in range(count):
            byte = packed[i // 2]
            nibble = (byte >> 4) if i % 2 == 0 else (byte & 0x0F)
            kinds.append(names[nibble])
        out[(target, value)] = kinds
    return out


class TestArgTable(unittest.TestCase):

    def setUp(self):
        self.rows = gp.arg_table_entries()
        self.values = {n: v for _t, _n, items in gp.GROUPS for n, v, _c in items}

    def test_only_shapes_the_default_rule_cannot_marshal_are_listed(self):
        # One numeric is one byte and one string is its own bytes, so a shape of
        # nothing but byte/str/data costs the 6502 no table bytes at all.
        listed = {name for _t, name, _v, _c in self.rows}
        for command, shape in gp.ARGS.items():
            wide = any(k in ("word", "dword", "pstr", "lit") for k, _s in shape)
            self.assertEqual(command in listed, wide, command)

    def test_every_shape_round_trips_through_the_packing(self):
        decoded = decode_arg_table(self.rows)
        for target, command, value, _codes in self.rows:
            expected = [k if k != "lit" else "lit0"
                        for k, _spec in gp.ARGS[command]]
            self.assertEqual(decoded[(target, value)], expected, command)

    def test_a_packing_slip_would_be_caught(self):
        # Negative control: swap two nibbles and the round trip must notice.
        rows = [list(r) for r in self.rows]
        victim = next(r for r in rows if r[1] == "SOFTIEC_CMD_LOAD_SU")
        victim[3] = list(victim[3])
        victim[3][0], victim[3][2] = victim[3][2], victim[3][0]
        decoded = decode_arg_table([tuple(r) for r in rows])
        self.assertNotEqual(decoded[(0x05, self.values["SOFTIEC_CMD_LOAD_SU"])],
                            [k for k, _s in gp.ARGS["SOFTIEC_CMD_LOAD_SU"]])

    def test_keys_are_unique(self):
        # (target, command) is the key. DOS lives on $01 and $02 with one
        # command set, so a duplicate here would mean two shapes for one call.
        keys = [(t, v) for t, _n, v, _c in self.rows]
        self.assertEqual(len(keys), len(set(keys)))

    def test_dos_entries_are_stored_under_dos1_only(self):
        # The lookup folds $02 onto $01 rather than carrying a second copy.
        targets = {t for t, _n, _v, _c in self.rows}
        self.assertIn(0x01, targets)
        self.assertNotIn(0x02, targets)

    def test_rows_are_sorted_so_a_scan_can_stop_early(self):
        keys = [(t, v) for t, _n, v, _c in self.rows]
        self.assertEqual(keys, sorted(keys))

    def test_every_kind_code_fits_in_a_nibble(self):
        for kind, code in gp.ARG_CODES.items():
            self.assertTrue(0 <= code <= 0x0F, kind)

    def test_a_non_zero_literal_is_refused_rather_than_truncated(self):
        real = gp.ARGS
        try:
            gp.ARGS = {"DOS_CMD_CHANGE_DIR": [("lit", 0x2C), ("str", "x")]}
            with self.assertRaises(SystemExit) as caught:
                gp.arg_table_entries()
            self.assertIn("only encodes $00 literals", str(caught.exception))
        finally:
            gp.ARGS = real

    def test_a_command_with_no_derivable_target_is_refused(self):
        real = gp.ARGS
        try:
            # UCI_CMD_IDENTIFY is common to every target, so it has no single
            # one. Giving it a wide shape must fail rather than pick a target.
            gp.ARGS = {"UCI_CMD_IDENTIFY": [("word", "x")]}
            with self.assertRaises(SystemExit) as caught:
                gp.arg_table_entries()
            self.assertIn("target cannot be derived", str(caught.exception))
        finally:
            gp.ARGS = real

    def test_the_table_stays_small_enough_to_live_in_the_wedge(self):
        # 3 header bytes plus one packed byte per two arguments, plus the
        # terminator. The design budgeted about 150 bytes.
        size = 1
        for _t, _n, _v, codes in self.rows:
            size += 3 + (len(codes) + 1) // 2
        self.assertLess(size, 150, "argument table grew past its budget")


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


class TestBlobConstants(unittest.TestCase):
    """The BLOB_* constants are read out of blob.s, so a wrong one is a wrong blob.s."""

    def names(self):
        out = {}
        for _title, _note, items in gp.blob_groups():
            for name, value, _comment in items:
                out[name] = value
        return out

    def test_the_first_and_the_audio_entries(self):
        n = self.names()
        self.assertEqual(n["BLOB_UCI_INIT"], 0x04)
        self.assertEqual(n["BLOB_ULTIMATE_INIT"], 0x1C)
        self.assertEqual(n["BLOB_ULTIMATE_TURBO_AVAILABLE"], 0x43)
        self.assertEqual(n["BLOB_ULTIMATE_AUDIO_INIT"], 0x2E8)
        self.assertEqual(n["BLOB_AUDIO_CONFIGURE"], 0x2F1)

    def test_parameter_block_fields_are_from_the_blob_base(self):
        n = self.names()
        self.assertEqual(n["BLOB_PARAMS"], 0x100)
        self.assertEqual(n["BLOB_BP_RESULT"], 0x100)
        self.assertEqual(n["BLOB_BP_ADDR"], 0x103)
        self.assertEqual(n["BLOB_BP_REU"], 0x256)
        self.assertEqual(n["BLOB_BP_AUDIO"], 0x29A)

    def test_every_jump_has_a_constant(self):
        with open(os.path.join(gp.REPO, gp.BLOB_SOURCE)) as fh:
            text = fh.read()
        names = self.names()
        for target, off in gp.BLOB_JUMP.findall(text):
            self.assertEqual(names[gp.blob_name(target)], int(off, 16), target)

    def test_the_assembler_includes_carry_them_and_the_c_header_does_not(self):
        for text in (gp.asm_include(), gp.kickass_include(), gp.acme_include()):
            self.assertIn("BLOB_ULTIMATE_INIT", text)
            self.assertIn("BLOB_BP_AUDIO", text)
        self.assertNotIn("BLOB_ULTIMATE_INIT", gp.c_header())
        self.assertNotIn("BLOB_ULTIMATE_INIT", gp.markdown())


if __name__ == "__main__":
    unittest.main()
