#!/usr/bin/env python3
"""
Report which UCI commands the test suites actually exercise.

Coverage that is tracked by hand stops being true within a week. This reads the
protocol definition - the same one the headers and includes come from - scans
what the tests really send, and writes docs/generated/command-coverage.md.

It also fails when a command the SDK claims to wrap has no test behind it. A
command with an API and no test is the case worth catching; a command with
neither is just work not started yet, and is reported without complaint.

    python3 tools/gen_coverage.py          # write the report
    python3 tools/gen_coverage.py --check  # and fail on an untested wrapper

SPDX-License-Identifier: MIT
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_protocol as protocol

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Commands the SDK exposes an API for, and the entry points that send them. Add
# to this when a service lands, and the --check gate will insist on a test to go
# with it.
#
# The entry points matter because a wrapper is the whole point of wrapping: a
# test written against the SDK calls ultimate_palette_get(), and the command
# byte never appears in its source at all. Scanning for the byte alone would
# report every wrapped command as untested for ever, which is the opposite of
# what this file is for.
# A command is listed against the entry points that *always* send it. That
# qualifier is what keeps this honest for ultimate_load, which tries the
# SoftwareIEC pair first and falls back to DOS OPEN/READ/CLOSE: it always
# attempts LOAD_SU, so it is credited with that, and it is not credited with
# READ_DATA, which a machine with an IEC drive never sees it send.
WRAPPED = {
    "UCI_CMD_IDENTIFY":           ("ultimate_identify", "ultimate_detect"),
    "CTRL_CMD_GET_HWINFO":        ("ultimate_get_model", "ultimate_legacy_get_sid_info"),
    "CTRL_CMD_GET_PALETTE":       ("ultimate_palette_get",),
    "CTRL_CMD_SET_PALETTE":       ("ultimate_palette_set",),
    "CTRL_CMD_SET_PALETTE_COLOR": ("ultimate_palette_set_color",),
    "CTRL_CMD_RESET_PALETTE":     ("ultimate_palette_reset",),
    "DOS_CMD_CHANGE_DIR":         ("ultimate_chdir",),
    "DOS_CMD_GET_PATH":           ("ultimate_getpath",),
    "DOS_CMD_OPEN_DIR":           ("ultimate_opendir",),
    "DOS_CMD_READ_DIR":           ("ultimate_readdir",),
    "DOS_CMD_OPEN_FILE":          ("ultimate_open", "ultimate_bload",
                                   "ultimate_save"),
    "DOS_CMD_CLOSE_FILE":         ("ultimate_close", "ultimate_bload",
                                   "ultimate_save"),
    "DOS_CMD_READ_DATA":          ("ultimate_read", "ultimate_bload"),
    "DOS_CMD_WRITE_DATA":         ("ultimate_write", "ultimate_save"),
    "DOS_CMD_FILE_SEEK":          ("ultimate_seek",),
    "DOS_CMD_DELETE_FILE":        ("ultimate_delete",),
    "DOS_CMD_LOAD_REU":           ("ultimate_reu_load",),
    "DOS_CMD_SAVE_REU":           ("ultimate_reu_save",),
    "NET_CMD_GET_INTERFACE_COUNT": ("ultimate_net_ifcount",),
    "NET_CMD_GET_NETADDR":        ("ultimate_net_macaddr",),
    "NET_CMD_GET_IPADDR":         ("ultimate_net_ipconfig",),
    "NET_CMD_OPEN_TCP":           ("ultimate_net_connect",),
    "NET_CMD_OPEN_UDP":           ("ultimate_net_udp",),
    "NET_CMD_CLOSE_SOCKET":       ("ultimate_net_close",),
    "NET_CMD_READ_SOCKET":        ("ultimate_net_read",),
    "NET_CMD_WRITE_SOCKET":       ("ultimate_net_write",),
    "HTTP_CMD_HEADER_CREATE":     ("ultimate_http_open", "ultimate_http_get"),
    "HTTP_CMD_HEADER_FREE":       ("ultimate_http_close", "ultimate_http_get"),
    "HTTP_CMD_HEADER_ADD":        ("ultimate_http_header",),
    "HTTP_CMD_DO_EXCHANGE_RAW":   ("ultimate_http_exchange", "ultimate_http_get"),
    "HTTP_CMD_FREE_ALL":          ("ultimate_http_free_all",),
    "SOFTIEC_CMD_LOAD_SU":        ("ultimate_load",),
    "SOFTIEC_CMD_LOAD_EX":        ("ultimate_load",),
    "DOS_CMD_FILE_STAT":          ("ultimate_stat",),
    "DOS_CMD_FILE_INFO":          ("ultimate_fstat",),
    "DOS_CMD_RENAME_FILE":        ("ultimate_rename",),
    "DOS_CMD_COPY_FILE":          ("ultimate_copy",),
    "DOS_CMD_CREATE_DIR":         ("ultimate_mkdir",),
    "DOS_CMD_COPY_HOME_PATH":     ("ultimate_home",),
    "DOS_CMD_MOUNT_DISK":         ("ultimate_mount",),
    "DOS_CMD_UMOUNT_DISK":        ("ultimate_unmount",),
    "DOS_CMD_SWAP_DISK":          ("ultimate_swap",),
    "DOS_CMD_GET_TIME":           ("ultimate_get_time",),
    "DOS_CMD_SET_TIME":           ("ultimate_set_time",),
    "NET_CMD_SET_IPADDR":         ("ultimate_net_setip",),
    "CTRL_CMD_REBOOT":            ("ultimate_reboot",),
    "CTRL_CMD_FREEZE":            ("ultimate_freeze",),
    # One entry point covers the four enable/disable commands and one the two
    # power commands: which of them goes on the wire is the drive argument.
    "CTRL_CMD_ENABLE_DRIVE_A":    ("ultimate_drive_enable",),
    "CTRL_CMD_DISABLE_DRIVE_A":   ("ultimate_drive_enable",),
    "CTRL_CMD_ENABLE_DRIVE_B":    ("ultimate_drive_enable",),
    "CTRL_CMD_DISABLE_DRIVE_B":   ("ultimate_drive_enable",),
    "CTRL_CMD_GET_DRIVE_A_POWER": ("ultimate_drive_power",),
    "CTRL_CMD_GET_DRIVE_B_POWER": ("ultimate_drive_power",),
    "CTRL_CMD_GET_DRVINFO":       ("ultimate_drive_info",),
    "CTRL_CMD_GET_RAMDISKINFO":   ("ultimate_ramdisk_info",),
    "HTTP_CMD_BODY_CREATE":       ("ultimate_http_body",),
    "HTTP_CMD_BODY_FREE":         ("ultimate_http_body_free",),
    "HTTP_CMD_BODY_CLEAR":        ("ultimate_http_body_clear",),
    "HTTP_CMD_BODY_UP":           ("ultimate_http_body_up",),
    "HTTP_CMD_BODY_ADD_INT":      ("ultimate_http_body_int",),
    "HTTP_CMD_BODY_ADD_BOOL":     ("ultimate_http_body_bool",),
    "HTTP_CMD_BODY_ADD_STRING":   ("ultimate_http_body_string",),
    "HTTP_CMD_BODY_ADD_OBJECT":   ("ultimate_http_body_object",),
    "HTTP_CMD_BODY_ADD_ARRAY":    ("ultimate_http_body_array",),
    "HTTP_CMD_BODY_ADD_BINARY":   ("ultimate_http_body_binary",),
}

# Where a test could plausibly send a command from.
TEST_FILES = [
    "tests/emulator/protocol.suite",
    "tests/emulator/sdk.suite",
    "tests/emulator/absent.suite",
    "tests/emulator/timeout.suite",
    "tests/hardware/ucitest.c",
]

# What the simulated Ultimate in sim6502 implements. Anything outside this can
# only be covered on real hardware, which is worth saying out loud rather than
# leaving as a mystery gap in the table.
SIMULATED_TARGETS = {"Ultimate DOS commands", "Control commands",
                     "Commands common to every target"}

# Commands inside an otherwise-simulated family that u64sim does not implement.
# The palette four are newer than firmware 3.15 and u64sim answers them with
# "21,UNKNOWN COMMAND" - which tests/emulator/sdk.suite pins deliberately, as
# the case an old machine presents, rather than as coverage of what they do.
HARDWARE_ONLY = {
    "CTRL_CMD_GET_PALETTE",
    "CTRL_CMD_SET_PALETTE",
    "CTRL_CMD_SET_PALETTE_COLOR",
    "CTRL_CMD_RESET_PALETTE",
    # u64sim answers these with "99,FUNCTION NOT IMPLEMENTED" on the DOS target
    # and "21,UNKNOWN COMMAND" on the control target. sdk.suite pins those
    # answers, because they are what a program meets on older firmware; what
    # the commands do when a machine has them is tests/hardware's job.
    "DOS_CMD_COPY_HOME_PATH",
    "DOS_CMD_MOUNT_DISK",
    "DOS_CMD_UMOUNT_DISK",
    "DOS_CMD_SWAP_DISK",
    "DOS_CMD_GET_TIME",
    "DOS_CMD_SET_TIME",
    "DOS_CMD_LOAD_RAMDISK",
    "DOS_CMD_SAVE_RAMDISK",
    "CTRL_CMD_READ_RTC",
    "CTRL_CMD_REBOOT",
    "CTRL_CMD_FREEZE",
    "CTRL_CMD_GET_DRVINFO",
    "CTRL_CMD_ENABLE_DRIVE_A",
    "CTRL_CMD_DISABLE_DRIVE_A",
    "CTRL_CMD_ENABLE_DRIVE_B",
    "CTRL_CMD_DISABLE_DRIVE_B",
    "CTRL_CMD_GET_DRIVE_A_POWER",
    "CTRL_CMD_GET_DRIVE_B_POWER",
    "CTRL_CMD_GET_RAMDISKINFO",
}


# Sub-command bytes are arguments, not commands: counting them would inflate
# the total and mark them covered whenever the argument value coincides.
NOT_COMMAND_GROUPS = {"Control: deprecated hardware info sub-commands"}


def command_groups():
    for title, _note, items in protocol.GROUPS:
        if "commands" in title.lower() and title not in NOT_COMMAND_GROUPS:
            yield title, items


def group_targets(title):
    """The target ids a group's commands belong to, read out of its own title.

    Command bytes repeat across targets - $05 is WRITE_DATA on Ultimate DOS and
    FREEZE on the control target - so a test that sends one must not mark the
    other covered. The group titles already name their targets, which is one
    fewer table to keep in step with the protocol definition.

    An empty set means "any target": that is how the group of commands common to
    every target reads, and it is the right answer for it.
    """
    if "target" not in title.lower():
        return set()
    return {int(v, 16) for v in re.findall(r"\$([0-9A-Fa-f]{2})", title)}


def target_values():
    """UCI_TARGET_* name -> id, from the protocol definition."""
    for title, _note, items in protocol.GROUPS:
        if title == "Targets":
            return {name: value for name, value, _c in items}
    return {}


def strip_comments(text):
    """Comments out, before anything is scanned.

    A test file that *describes* a command it does not send would otherwise be
    credited with sending it, and a coverage report that over-reports is worse
    than none. Only whole-line `;` comments go: the sim6502 DSL uses `;` and
    nothing else on the line matters, while a mid-line strip would risk eating
    code.
    """
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    return re.sub(r"(?m)^[ \t]*;[^\n]*", " ", text)


def test_corpus():
    text = ""
    for path in TEST_FILES:
        full = os.path.join(REPO, path)
        if os.path.exists(full):
            with open(full) as fh:
                text += fh.read() + "\n"
    return strip_comments(text)


# The emulator suites never write ultimate_chdir(): the sim6502 DSL cannot call
# a C function, so it jsr's a stub in tests/emulator/harness.s instead. The stub
# bodies are read rather than listed here, because a hand-kept stub-to-entry-
# point table is the same thing this file exists to abolish.
HARNESS = "tests/emulator/harness.s"

STUB_LABEL = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):")
STUB_CALL = re.compile(r"\b(?:jsr|jmp)\s+_?(ultimate_[a-z0-9_]+)")


def harness_stubs():
    """Harness stub name -> the SDK entry points its body reaches."""
    stubs = {}
    label = None
    with open(os.path.join(REPO, HARNESS)) as fh:
        for line in fh:
            found = STUB_LABEL.match(line)
            if found:
                label = found.group(1)
            call = STUB_CALL.search(line)
            if call and label:
                stubs.setdefault(label, set()).add(call.group(1))
    return stubs


def called_entry_points(corpus, stubs):
    """SDK entry points the tests reach, directly or through a harness stub.

    Bare words, not `name(`: a C test calls ultimate_load(name, addr) and a
    suite writes jsr([t_load]), and both have to count.
    """
    wanted = {name for points in WRAPPED.values() for name in points}
    words = set(re.findall(r"\b[A-Za-z_][A-Za-z0-9_]*\b", corpus))
    called = words & wanted
    for stub in words & set(stubs):
        called |= stubs[stub] & wanted
    return called


# The three ways a test names a target or a command, in the order they appear:
#
#   uci($01, $f0, ...)                  the sim6502 DSL's own client
#   [req_target] = $01                  the SDK harness, driven from the DSL
#   [req_command] = $f0
#   req.target = UCI_TARGET_DOS1;       the hardware program, in C
#   req.command = DOS_CMD_ECHO;
#
# A target assignment stays current until the next one, which is exactly how all
# three read, so scanning in order pairs each command with the target it went to.
TRAFFIC = re.compile(
    r"uci\(\s*\$(?P<dsl_target>[0-9a-fA-F]{2})\s*,\s*\$(?P<dsl_cmd>[0-9a-fA-F]{2})"
    r"|\[req_target\]\s*=\s*\$(?P<sdk_target>[0-9a-fA-F]{2})"
    r"|\[req_command\]\s*=\s*\$(?P<sdk_cmd>[0-9a-fA-F]{2})"
    r"|\.target\s*=\s*(?P<c_target>[A-Za-z0-9_]+)"
    r"|\.command\s*=\s*(?P<c_cmd>[A-Za-z0-9_]+)"
)


def _as_value(token, names):
    """A target or command token as a number, or None when it is a name."""
    if token in names:
        return names[token]
    try:
        return int(token, 0)
    except ValueError:
        return None


def sent_commands(corpus):
    """What the tests really put on the wire.

    Returns the set of command names sent by name - unambiguous, since the name
    carries its family - and the set of (target, command) pairs sent
    numerically. A target of None means the test named one this scanner could
    not resolve; those count against any family rather than being dropped.
    """
    names = target_values()
    sent_names = set()
    sent_pairs = set()
    current = None

    for m in TRAFFIC.finditer(corpus):
        if m.group("dsl_target"):
            sent_pairs.add((int(m.group("dsl_target"), 16) & 0x0F,
                            int(m.group("dsl_cmd"), 16)))
        elif m.group("sdk_target"):
            current = int(m.group("sdk_target"), 16) & 0x0F
        elif m.group("sdk_cmd"):
            sent_pairs.add((current, int(m.group("sdk_cmd"), 16)))
        elif m.group("c_target"):
            value = _as_value(m.group("c_target"), names)
            current = None if value is None else value & 0x0F
        elif m.group("c_cmd"):
            token = m.group("c_cmd")
            value = _as_value(token, names)
            if value is None:
                sent_names.add(token)       # a command constant, e.g. DOS_CMD_ECHO
            else:
                sent_pairs.add((current, value))

    return sent_names, sent_pairs


def main():
    check = "--check" in sys.argv
    corpus = test_corpus()
    sent_names, sent_pairs = sent_commands(corpus)
    called = called_entry_points(corpus, harness_stubs())

    rows = []
    totals = {"total": 0, "covered": 0, "gap": 0}
    untested_wrappers = []

    for title, items in command_groups():
        family = title.split("(")[0].strip()
        targets = group_targets(title)
        for name, value, comment in items:
            covered = name in sent_names or any(
                cmd == value and (not targets or tgt is None or tgt in targets)
                for tgt, cmd in sent_pairs) or any(
                point in called for point in WRAPPED.get(name, ()))
            totals["total"] += 1
            if covered:
                totals["covered"] += 1
                status = "tested"
            elif name in WRAPPED:
                status = "**wrapped, untested**"
                untested_wrappers.append(name)
                totals["gap"] += 1
            else:
                status = "no API yet"
            if "deprecated" in comment.lower():
                status += "; deprecated"
            where = ("simulator + hardware"
                     if family in SIMULATED_TARGETS and name not in HARDWARE_ONLY
                     else "hardware only")
            rows.append((family, name, value, status, where))

    out = [
        "<!-- Generated by tools/gen_coverage.py - DO NOT EDIT BY HAND. -->",
        "",
        "# UCI command coverage",
        "",
        "Which commands the test suites actually send. Generated from the same",
        "protocol definition as the headers, so it cannot quietly drift from",
        "reality the way a hand-kept checklist does.",
        "",
        "`no API yet` is not a failure - it is work not started. The status worth",
        "acting on is **wrapped, untested**: an SDK entry point with nothing",
        "exercising it. `tools/gen_coverage.py --check` fails the build on those.",
        "",
        "`hardware only` marks commands the simulated Ultimate in sim6502 does not",
        "implement, so they can only ever be covered by `tests/hardware`.",
        "",
        "A command byte is only credited to the target it was actually sent to.",
        "The codes repeat across targets - `$05` is `WRITE_DATA` on Ultimate DOS",
        "and `FREEZE` on the control target - so counting bytes alone would report",
        "commands as tested that no test has ever sent.",
        "",
        "| Family | Command | Code | Status | Reachable from |",
        "| --- | --- | --- | --- | --- |",
    ]
    for family, name, value, status, where in rows:
        out.append("| %s | `%s` | `$%02X` | %s | %s |" % (family, name, value, status, where))

    pct = 100 * totals["covered"] // totals["total"]
    out += [
        "",
        "## Summary",
        "",
        "| | |",
        "| --- | --- |",
        "| commands defined | %d |" % totals["total"],
        "| exercised by a test | %d (%d%%) |" % (totals["covered"], pct),
        "| wrapped but untested | %d |" % totals["gap"],
        "",
        "Commands with no API yet are the remainder. They are the ones a",
        "wrapper would misrepresent: EasyFlash sector erase, GCR track",
        "encoding and decoding, the control target's REU pair - which never",
        "returns on firmware 3.14d - the SoftwareIEC channel commands the",
        "hyperspeed kernal owns, and the four network listener commands whose",
        "numbers are not in the published specification. Every one of them is",
        "reachable through uci_exec(), which is what the generic form is for.",
        "",
    ]

    path = os.path.join(REPO, "docs/generated/command-coverage.md")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write("\n".join(out))
    print("wrote docs/generated/command-coverage.md: %d/%d commands exercised (%d%%)"
          % (totals["covered"], totals["total"], pct))

    if untested_wrappers:
        print("\nwrapped by the SDK but not exercised by any test:")
        for name in untested_wrappers:
            print("  %s" % name)
        if check:
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
