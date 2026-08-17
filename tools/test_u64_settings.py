#!/usr/bin/env python3
"""
Unit tests for the settings guard in tools/u64_settings.py.

This is ordinary host Python controlling REST calls, not 6502 code, so it is
tested the normal way: against a fake REST client, with no network and no
hardware involved. Run directly or via discovery:

    python3 tools/test_u64_settings.py
    python3 -m unittest discover -s tools -p 'test_*.py'

SPDX-License-Identifier: MIT
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import u64_settings as guard


class FakeUltimate:
    """In-memory stand-in for guard.Ultimate. No network involved.

    Records every write in order, so a test can assert not just the final
    value but whether a write happened at all - the whole point of the
    guard is that a setting already correct is never written.
    """

    def __init__(self, initial):
        self.values = dict(initial)     # {(category, item): value}
        self.writes = []                 # [(category, item, value), ...]

    def get_setting(self, category, item):
        return self.values[(category, item)]

    def set_setting(self, category, item, value):
        self.writes.append((category, item, value))
        self.values[(category, item)] = value


CMD_IF = ("C64 and Cartridge Settings", "Command Interface")


class RequireSettingsTests(unittest.TestCase):
    def test_setting_already_correct_is_not_written(self):
        u = FakeUltimate({CMD_IF: "Enabled"})
        changed = guard.require_settings(u, {CMD_IF: "Enabled"})
        self.assertEqual(changed, {})
        self.assertEqual(u.writes, [])

    def test_setting_wrong_is_written_once(self):
        u = FakeUltimate({CMD_IF: "Disabled"})
        changed = guard.require_settings(u, {CMD_IF: "Enabled"})
        self.assertEqual(changed, {CMD_IF: "Disabled"})
        self.assertEqual(u.writes, [("C64 and Cartridge Settings",
                                      "Command Interface", "Enabled")])
        self.assertEqual(u.values[CMD_IF], "Enabled")

    def test_only_the_wrong_settings_are_written(self):
        reu = ("C64 and Cartridge Settings", "RAM Expansion Unit")
        u = FakeUltimate({CMD_IF: "Disabled", reu: "Disabled"})
        changed = guard.require_settings(
            u, {CMD_IF: "Enabled", reu: "Disabled"})
        self.assertEqual(changed, {CMD_IF: "Disabled"})
        self.assertEqual(len(u.writes), 1)


class RestoreSettingsTests(unittest.TestCase):
    def test_restores_exactly_what_it_is_given(self):
        u = FakeUltimate({CMD_IF: "Enabled"})
        guard.restore_settings(u, {CMD_IF: "Disabled"})
        self.assertEqual(u.values[CMD_IF], "Disabled")
        self.assertEqual(u.writes, [("C64 and Cartridge Settings",
                                      "Command Interface", "Disabled")])

    def test_a_failure_is_reported_and_does_not_stop_the_rest(self):
        reu = ("C64 and Cartridge Settings", "RAM Expansion Unit")

        class FlakyUltimate(FakeUltimate):
            def set_setting(self, category, item, value):
                if (category, item) == CMD_IF:
                    raise RuntimeError("network dropped")
                super().set_setting(category, item, value)

        u = FlakyUltimate({CMD_IF: "Enabled", reu: "Enabled"})
        warnings = []
        guard.restore_settings(
            u, {CMD_IF: "Disabled", reu: "Disabled"}, warn=warnings.append)
        self.assertEqual(len(warnings), 1)
        self.assertIn("Command Interface", warnings[0])
        self.assertEqual(u.values[reu], "Disabled")   # the other one still ran


class RunAndRestoreTests(unittest.TestCase):
    """The orchestration main() uses: run the command, always restore."""

    def test_command_succeeds_settings_restored(self):
        u = FakeUltimate({CMD_IF: "Disabled"})
        changed = guard.require_settings(u, {CMD_IF: "Enabled"})
        status = guard.run_and_restore(
            u, changed, runner=lambda cmd: 0, command=["true"])
        self.assertEqual(status, 0)
        self.assertEqual(u.values[CMD_IF], "Disabled")

    def test_command_fails_still_restored_status_propagated(self):
        u = FakeUltimate({CMD_IF: "Disabled"})
        changed = guard.require_settings(u, {CMD_IF: "Enabled"})
        status = guard.run_and_restore(
            u, changed, runner=lambda cmd: 7, command=["false"])
        self.assertEqual(status, 7)
        self.assertEqual(u.values[CMD_IF], "Disabled")

    def test_exception_mid_run_still_restored(self):
        u = FakeUltimate({CMD_IF: "Disabled"})
        changed = guard.require_settings(u, {CMD_IF: "Enabled"})

        def blows_up(_cmd):
            raise RuntimeError("boom")

        with self.assertRaises(RuntimeError):
            guard.run_and_restore(u, changed, runner=blows_up, command=["x"])
        self.assertEqual(u.values[CMD_IF], "Disabled")

    def test_nothing_changed_means_nothing_is_restored(self):
        u = FakeUltimate({CMD_IF: "Enabled"})
        changed = guard.require_settings(u, {CMD_IF: "Enabled"})
        self.assertEqual(changed, {})
        guard.run_and_restore(u, changed, runner=lambda cmd: 0, command=["true"])
        self.assertEqual(u.writes, [])   # never written, so never restored either


class ParseSettingSpecTests(unittest.TestCase):
    def test_parses_category_item_value(self):
        key, value = guard.parse_setting_spec(
            "C64 and Cartridge Settings:Command Interface=Enabled")
        self.assertEqual(key, ("C64 and Cartridge Settings", "Command Interface"))
        self.assertEqual(value, "Enabled")

    def test_missing_colon_is_rejected(self):
        with self.assertRaises(ValueError):
            guard.parse_setting_spec("Command Interface=Enabled")

    def test_missing_equals_is_rejected(self):
        with self.assertRaises(ValueError):
            guard.parse_setting_spec("C64 and Cartridge Settings:Command Interface")


if __name__ == "__main__":
    unittest.main()
