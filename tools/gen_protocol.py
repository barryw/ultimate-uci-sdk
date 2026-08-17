#!/usr/bin/env python3
"""
Single source of truth for Ultimate Command Interface (UCI) protocol constants.

Every language binding gets its constants from this file so that the register
map, target IDs, command codes and error codes can never drift apart between
the C header, the assembler include and the documentation.

Run:  python3 tools/gen_protocol.py
Emits:
    include/uci_protocol.h              (C / C++, used by cc65, Oscar64, llvm-mos, host)
    bindings/asm/uci_protocol.inc       (ca65)
    docs/generated/protocol-constants.md
    bindings/kickass/uci_protocol.asm   (KickAssembler)
    bindings/acme/uci_protocol.a        (ACME)

Sources for every value are cited in docs/uci.md.  Nothing here is guessed:
values marked INFERRED in docs/uci.md come from the Ultimate firmware / FPGA
sources rather than the published register API document.
"""

import os
import textwrap

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---------------------------------------------------------------------------
# Protocol definition.  (name, value, comment)
# ---------------------------------------------------------------------------

GROUPS = [
    ("Register map", "UCI I/O registers. The block is mapped at $DF1B-$DF1F and "
                     "overlays the last five REU registers. Mapping is optional and is "
                     "enabled in the Ultimate 'Command Interface' configuration menu.", [
        ("UCI_REG_BUSID",    0xDF1B, "R   SoftwareIEC bus ID (0 = unset)"),
        ("UCI_REG_CONTROL",  0xDF1C, "W   Control register"),
        ("UCI_REG_STATUS",   0xDF1C, "R   Status register"),
        ("UCI_REG_CMDDATA",  0xDF1D, "W   Command data (write command bytes here)"),
        ("UCI_REG_IDENT",    0xDF1D, "R   Identification register"),
        ("UCI_REG_RESPDATA", 0xDF1E, "R   Response data queue"),
        ("UCI_REG_STATDATA", 0xDF1F, "R   Status data queue"),
    ]),

    ("Identification register values", "Read from UCI_REG_IDENT.", [
        ("UCI_IDENT_IDLE",  0xC9, "No interrupt pending"),
        ("UCI_IDENT_IRQ",   0x49, "Interrupt active (bit 7 cleared). FW 3.15+"),
        ("UCI_IDENT_MASK",  0x7F, "Mask off the IRQ bit before comparing"),
        ("UCI_IDENT_VALUE", 0x49, "Expected value after masking with UCI_IDENT_MASK"),
    ]),

    ("Control register bits", "Write-only. Always write a literal mask; never "
                              "read-modify-write, because reading $DF1C returns the "
                              "status register, not the control register.", [
        ("UCI_CTRL_PUSH_CMD", 0x01, "Submit the buffered command"),
        ("UCI_CTRL_DATA_ACC", 0x02, "Acknowledge / release the current data block"),
        ("UCI_CTRL_ABORT",    0x04, "Request abort of the running command"),
        ("UCI_CTRL_CLR_ERR",  0x08, "Clear the state-error flag"),
        ("UCI_CTRL_IRQ",      0x20, "Raise IRQ on completion (FW 3.15+, latched on push)"),
        ("UCI_CTRL_TRIGGER",  0x40, "Freeze the machine on the next $FF00 write (latched on push). NOT a transfer accelerator"),
        ("UCI_CTRL_DMA",      0x80, "Freeze the machine immediately (latched on push). NOT a transfer accelerator - see docs/uci.md"),
    ]),

    ("Status register bits", "Read from $DF1C.", [
        ("UCI_STAT_CMD_BUSY", 0x01, "A command is pending in command memory"),
        ("UCI_STAT_DATA_ACC", 0x02, "Data acknowledge seen by the Ultimate"),
        ("UCI_STAT_ABORT_P",  0x04, "Abort request still pending"),
        ("UCI_STAT_ERROR",    0x08, "State error: command pushed while not idle"),
        ("UCI_STAT_STATE",    0x30, "Protocol state mask"),
        ("UCI_STAT_STAT_AV",  0x40, "Status byte available at $DF1F"),
        ("UCI_STAT_DATA_AV",  0x80, "Response byte available at $DF1E"),
    ]),

    ("Protocol states", "Value of (status & UCI_STAT_STATE).", [
        ("UCI_STATE_IDLE",      0x00, "Ready to accept a command"),
        ("UCI_STATE_BUSY",      0x10, "Command submitted, Ultimate is working"),
        ("UCI_STATE_DATA_LAST", 0x20, "Data available, this is the final block"),
        ("UCI_STATE_DATA_MORE", 0x30, "Data available, more blocks follow"),
    ]),

    ("Queue sizes", "Hard limits enforced by the hardware. The three queue "
                    "pointers all saturate on the LAST byte of their buffer rather "
                    "than one past it, which costs a byte on the way in and can hang "
                    "a naive reader on the way out - see docs/uci.md, 'Queue pointer "
                    "saturation'.", [
        ("UCI_MAX_COMMAND",  896, "Command queue size in bytes ($380)"),
        ("UCI_MAX_RESPONSE", 896, "Response data queue size in bytes ($380)"),
        ("UCI_MAX_STATUS",   256, "Status queue size in bytes ($100)"),
        ("UCI_MAX_COMMAND_USABLE", 895, "Largest command the hardware can actually receive"),
    ]),

    ("Timeouts", "Budget for a status poll loop, in units of 256 polls. The core "
                 "installs the default at bring-up, so the bounded-time guarantee "
                 "holds without the caller doing anything; raise it around a "
                 "command whose duration cannot be bounded and restore it after.", [
        ("UCI_TIMEOUT_DEFAULT", 200, "Comfortable for local commands at any CPU speed"),
        ("UCI_TIMEOUT_FOREVER",   0, "Poll until the Ultimate answers, however long that takes"),
    ]),

    ("Targets", "First byte of every command. Only bits 0-3 select the target; "
                "bit 7 is the NO_REPLY flag (INFERRED from firmware).", [
        ("UCI_TARGET_MASK",     0x0F, "Target field of the first command byte"),
        ("UCI_TARGET_NO_REPLY", 0x80, "Fire-and-forget: skip the data/status phase"),
        ("UCI_TARGET_DOS1",     0x01, "Ultimate DOS instance 1"),
        ("UCI_TARGET_DOS2",     0x02, "Ultimate DOS instance 2"),
        ("UCI_TARGET_NETWORK",  0x03, "Network (TCP/UDP sockets)"),
        ("UCI_TARGET_CONTROL",  0x04, "Machine / cartridge control"),
        ("UCI_TARGET_SOFTIEC",  0x05, "SoftwareIEC bypass"),
        ("UCI_TARGET_HTTP",     0x06, "HTTP client (FW 3.15+)"),
        ("UCI_TARGET_MAX",      0x0F, "Highest addressable target"),
    ]),

    ("Commands common to every target", "", [
        ("UCI_CMD_IDENTIFY", 0x01, "Return an identification string. Cannot fail."),
    ]),

    ("Ultimate DOS commands (targets $01/$02)", "", [
        ("DOS_CMD_IDENTIFY",       0x01, ""),
        ("DOS_CMD_OPEN_FILE",      0x02, "<attrib> <filename>"),
        ("DOS_CMD_CLOSE_FILE",     0x03, ""),
        ("DOS_CMD_READ_DATA",      0x04, "<len_lo> <len_hi>"),
        ("DOS_CMD_WRITE_DATA",     0x05, "<dummy> <dummy> <data...>"),
        ("DOS_CMD_FILE_SEEK",      0x06, "<pos32 LSB first>"),
        ("DOS_CMD_FILE_INFO",      0x07, ""),
        ("DOS_CMD_FILE_STAT",      0x08, "<filename>"),
        ("DOS_CMD_DELETE_FILE",    0x09, "<filename>"),
        ("DOS_CMD_RENAME_FILE",    0x0A, "<old> $00 <new>"),
        ("DOS_CMD_COPY_FILE",      0x0B, "<src> $00 <dst>"),
        ("DOS_CMD_CHANGE_DIR",     0x11, "<dirname>"),
        ("DOS_CMD_GET_PATH",       0x12, ""),
        ("DOS_CMD_OPEN_DIR",       0x13, ""),
        ("DOS_CMD_READ_DIR",       0x14, ""),
        ("DOS_CMD_COPY_UI_PATH",   0x15, "Deprecated since FW 3.0"),
        ("DOS_CMD_CREATE_DIR",     0x16, "<dirname>"),
        ("DOS_CMD_COPY_HOME_PATH", 0x17, ""),
        ("DOS_CMD_LOAD_REU",       0x21, "<addr32> <len32>"),
        ("DOS_CMD_SAVE_REU",       0x22, "<addr32> <len32>"),
        ("DOS_CMD_MOUNT_DISK",     0x23, "<id> <filename>"),
        ("DOS_CMD_UMOUNT_DISK",    0x24, "<id>"),
        ("DOS_CMD_SWAP_DISK",      0x25, "<id>"),
        ("DOS_CMD_GET_TIME",       0x26, "[fmt]"),
        ("DOS_CMD_SET_TIME",       0x27, "<Y-1900> <M> <D> <h> <m> <s>"),
        ("DOS_CMD_ECHO",           0xF0, "Echo the command back as data"),
    ]),

    ("DOS file open attributes", "Bit flags for DOS_CMD_OPEN_FILE.", [
        ("DOS_FA_READ",          0x01, "Open for reading"),
        ("DOS_FA_WRITE",         0x02, "Open for writing, do not truncate"),
        ("DOS_FA_CREATE_NEW",    0x04, "Create/truncate to zero bytes"),
        ("DOS_FA_CREATE_ALWAYS", 0x08, "May overwrite an existing file"),
    ]),

    ("DOS directory entry attributes", "First byte of each DOS_CMD_READ_DIR entry (FAT semantics).", [
        ("DOS_ATTR_READONLY", 0x01, ""),
        ("DOS_ATTR_HIDDEN",   0x02, ""),
        ("DOS_ATTR_SYSTEM",   0x04, ""),
        ("DOS_ATTR_VOLUME",   0x08, ""),
        ("DOS_ATTR_DIR",      0x10, ""),
        ("DOS_ATTR_ARCHIVE",  0x20, ""),
    ]),

    ("Network commands (target $03)", "", [
        ("NET_CMD_IDENTIFY",            0x01, ""),
        ("NET_CMD_GET_INTERFACE_COUNT", 0x02, ""),
        ("NET_CMD_GET_NETADDR",         0x04, "<iface> -> 6 byte MAC"),
        ("NET_CMD_GET_IPADDR",          0x05, "<iface> -> 12 bytes ip/mask/gw"),
        ("NET_CMD_SET_IPADDR",          0x06, "<iface> <12 bytes>"),
        ("NET_CMD_OPEN_TCP",            0x07, "<port16> <host>"),
        ("NET_CMD_OPEN_UDP",            0x08, "<port16> <host>"),
        ("NET_CMD_CLOSE_SOCKET",        0x09, "<handle>"),
        ("NET_CMD_READ_SOCKET",         0x10, "<handle> <len16>"),
        ("NET_CMD_WRITE_SOCKET",        0x11, "<handle> <data...>"),
        ("NET_CMD_LISTEN_START",        0x12, "INFERRED: <port16>, not in the published spec"),
        ("NET_CMD_LISTEN_STOP",         0x13, "INFERRED: not in the published spec"),
        ("NET_CMD_LISTEN_STATE",        0x14, "INFERRED: not in the published spec"),
        ("NET_CMD_LISTEN_SOCKET",       0x15, "INFERRED: not in the published spec"),
    ]),

    ("Control commands (target $04)", "", [
        ("CTRL_CMD_IDENTIFY",          0x01, ""),
        ("CTRL_CMD_READ_RTC",          0x02, "INFERRED: firmware only, not in the published spec"),
        ("CTRL_CMD_FINISH_CAPTURE",    0x03, ""),
        ("CTRL_CMD_FREEZE",            0x05, ""),
        ("CTRL_CMD_REBOOT",            0x06, "Never replies: the C64 and the UCI are reset"),
        ("CTRL_CMD_LOAD_REU",          0x08, "<filename>"),
        ("CTRL_CMD_SAVE_REU",          0x09, "<filename>"),
        ("CTRL_CMD_U64_SAVEMEM",       0x0F, "<filename>, U64 family only"),
        ("CTRL_CMD_DECODE_TRACK",      0x11, "GCR -> binary in REU"),
        ("CTRL_CMD_ENCODE_TRACK",      0x12, "INFERRED: firmware only, not in the published spec"),
        ("CTRL_CMD_EASYFLASH",         0x20, "$00 <bank> <baseaddr> - sector erase"),
        ("CTRL_CMD_GET_HWINFO",        0x28, "[sub] $00 = model name, $01 = SID config"),
        ("CTRL_CMD_GET_DRVINFO",       0x29, "<effective_addr_flag>"),
        ("CTRL_CMD_ENABLE_DRIVE_A",    0x30, ""),
        ("CTRL_CMD_DISABLE_DRIVE_A",   0x31, ""),
        ("CTRL_CMD_ENABLE_DRIVE_B",    0x32, ""),
        ("CTRL_CMD_DISABLE_DRIVE_B",   0x33, ""),
        ("CTRL_CMD_GET_DRIVE_A_POWER", 0x34, ""),
        ("CTRL_CMD_GET_DRIVE_B_POWER", 0x35, ""),
        ("CTRL_CMD_GET_RAMDISKINFO",   0x40, "GEOS MegaPatch 3 RAM disk layout"),
        ("CTRL_CMD_LOAD_CONFIG",       0x50, "INFERRED: firmware only, not in the published spec"),
        ("CTRL_CMD_GET_PALETTE",       0x51, "-> 48 RGB bytes (FW > 3.15)"),
        ("CTRL_CMD_SET_PALETTE",       0x52, "<48 RGB bytes> (FW > 3.15)"),
        ("CTRL_CMD_SET_PALETTE_COLOR", 0x53, "<index> <r> <g> <b> (FW > 3.15)"),
        ("CTRL_CMD_RESET_PALETTE",     0x54, "restore the built-in palette (FW > 3.15)"),
    ]),

    ("Control: VIC-II palette", "Runtime palette control. Affects the live palette "
                                "only; it does not touch flash configuration or VPL files.", [
        ("UCI_PALETTE_COLORS", 16, "colors in a VIC-II palette"),
        ("UCI_PALETTE_BYTES",  48, "bytes in a full palette frame (16 * RGB)"),
    ]),

    ("Control: hardware info sub-commands", "", [
        ("CTRL_HWINFO_MODEL", 0x00, "ASCII model name, e.g. 'ULTIMATE 64'"),
        ("CTRL_HWINFO_SID",   0x01, "SID configuration frames"),
    ]),

    ("Control: drive type codes", "From CTRL_CMD_GET_DRVINFO.", [
        ("CTRL_DRVTYPE_1541",     0x00, ""),
        ("CTRL_DRVTYPE_1571",     0x01, ""),
        ("CTRL_DRVTYPE_1581",     0x02, ""),
        ("CTRL_DRVTYPE_UNDECIDED", 0x03, ""),
        ("CTRL_DRVTYPE_SOFTIEC",  0x0F, ""),
        ("CTRL_DRVTYPE_PRINTER",  0x50, ""),
    ]),

    ("SoftwareIEC commands (target $05)", "", [
        ("SOFTIEC_CMD_IDENTIFY",      0x01, ""),
        ("SOFTIEC_CMD_LOAD_SU",       0x10, "<sec> <verify> <addr16> <name>"),
        ("SOFTIEC_CMD_LOAD_EX",       0x11, "<sec> <verify>"),
        ("SOFTIEC_CMD_SAVE",          0x12, "<verify> <sec> <start16> <end16> <name>"),
        ("SOFTIEC_CMD_OPEN",          0x13, "<sec> $00 <name>"),
        ("SOFTIEC_CMD_CLOSE",         0x14, "<sec>"),
        ("SOFTIEC_CMD_CHKIN",         0x15, "<sec>"),
        ("SOFTIEC_CMD_CHKOUT",        0x16, "<sec> $00 <data...>"),
        ("SOFTIEC_CMD_ADD_PARTITION", 0x20, "<index> <ident>':'<path>"),
        ("SOFTIEC_CMD_DEL_PARTITION", 0x21, "<index>"),
        ("SOFTIEC_CMD_GET_FATNAME",   0x22, "<channel> <iec name>"),
        ("SOFTIEC_CMD_GET_IECNAME",   0x23, "<fat name>"),
    ]),

    ("SoftwareIEC status bytes", "This target returns a single binary status byte, "
                                 "not an ASCII status string.", [
        ("SOFTIEC_ST_OK",                0x00, ""),
        ("SOFTIEC_ST_FILE_NOT_FOUND",    0x01, ""),
        ("SOFTIEC_ST_SAVE_ERROR",        0x02, ""),
        ("SOFTIEC_ST_NO_INPUT_CHANNEL",  0x03, ""),
        ("SOFTIEC_ST_UNKNOWN_COMMAND",   0x04, ""),
        ("SOFTIEC_ST_MODULE_NOT_LOADED", 0x05, ""),
        ("SOFTIEC_ST_INVALID_PARAMS",    0x06, ""),
        ("SOFTIEC_ST_INVALID_NAME",      0x07, ""),
        ("SOFTIEC_ST_INVALID_PARTITION", 0x08, ""),
        ("SOFTIEC_ST_INVALID_DIRECTORY", 0x09, ""),
        ("SOFTIEC_ST_VERIFY_ERROR",      0x80, "LOAD_EX verify mismatch"),
    ]),

    ("HTTP commands (target $06, FW 3.15+)", "", [
        ("HTTP_CMD_IDENTIFY",        0x01, ""),
        ("HTTP_CMD_FREE_ALL",        0x10, ""),
        ("HTTP_CMD_HEADER_CREATE",   0x11, "<verb> <url>"),
        ("HTTP_CMD_HEADER_FREE",     0x12, "<handle>"),
        ("HTTP_CMD_HEADER_ADD",      0x13, "<handle> <'key: value'>"),
        ("HTTP_CMD_HEADER_QUERY",    0x14, "<handle> <key>"),
        ("HTTP_CMD_HEADER_LIST",     0x15, "<handle> <index>"),
        ("HTTP_CMD_BODY_CREATE",     0x21, "<format>"),
        ("HTTP_CMD_BODY_FREE",       0x22, "<handle>"),
        ("HTTP_CMD_BODY_ADD_INT",    0x23, "<handle> <keylen> <key> <int>"),
        ("HTTP_CMD_BODY_ADD_BOOL",   0x24, "<handle> <keylen> <key> <bool>"),
        ("HTTP_CMD_BODY_ADD_STRING", 0x25, "<handle> <keylen> <key> <vallen> <val>"),
        ("HTTP_CMD_BODY_ADD_OBJECT", 0x26, "<handle> <keylen> <key>"),
        ("HTTP_CMD_BODY_ADD_ARRAY",  0x27, "<handle> <keylen> <key>"),
        ("HTTP_CMD_BODY_UP",         0x28, "<handle>"),
        ("HTTP_CMD_BODY_REMOVE",     0x29, "<handle> <path>"),
        ("HTTP_CMD_BODY_QUERY",      0x2A, "<handle> <path>"),
        ("HTTP_CMD_BODY_MOVE",       0x2B, "<handle> <path>"),
        ("HTTP_CMD_BODY_ADD_BINARY", 0x2C, "<handle> <data...>"),
        ("HTTP_CMD_BODY_ADD",        0x2D, "<handle> <items...>"),
        ("HTTP_CMD_BODY_CLEAR",      0x2E, "<handle>"),
        ("HTTP_CMD_DO_EXCHANGE_OBJ", 0x31, "<header> <body|$FF>"),
        ("HTTP_CMD_DO_EXCHANGE_RAW", 0x32, "<header> <body|$FF>"),
    ]),

    ("HTTP verbs", "", [
        ("HTTP_VERB_GET",     0x01, ""),
        ("HTTP_VERB_PUT",     0x02, ""),
        ("HTTP_VERB_POST",    0x03, ""),
        ("HTTP_VERB_PATCH",   0x04, ""),
        ("HTTP_VERB_DELETE",  0x05, ""),
        ("HTTP_VERB_HEAD",    0x06, ""),
        ("HTTP_VERB_OPTIONS", 0x07, ""),
        ("HTTP_VERB_CONNECT", 0x08, ""),
        ("HTTP_VERB_TRACE",   0x09, ""),
    ]),

    ("HTTP body formats", "", [
        ("HTTP_BODY_BINARY",      0x01, ""),
        ("HTTP_BODY_JSON_OBJECT", 0x02, ""),
        ("HTTP_BODY_JSON_ARRAY",  0x03, ""),
        ("HTTP_BODY_URL_ENCODED", 0x04, ""),
        ("HTTP_BODY_NONE",        0xFF, "Pass as <body> to send no body"),
    ]),

    ("HTTP / JSON value type tags", "Used by BODY_ADD and BODY_QUERY.", [
        ("HTTP_TYPE_INT",    0x01, "4 bytes, LSB first"),
        ("HTTP_TYPE_BOOL",   0x02, "1 byte"),
        ("HTTP_TYPE_STRING", 0x03, "<len> <bytes>"),
        ("HTTP_TYPE_OBJECT", 0x04, "<count> [<key> <value>]*"),
        ("HTTP_TYPE_ARRAY",  0x05, "<count> [<value>]*"),
    ]),

    ("SDK status / error codes", "Stable across firmware versions. The raw device "
                                 "status is preserved separately, see uci_last_device_code().", [
        ("ULTIMATE_OK",                  0, "Success (device may still have set a warning code)"),
        ("ULTIMATE_ERR_NO_DEVICE",       1, "No Ultimate Command Interface found"),
        ("ULTIMATE_ERR_TIMEOUT",         2, "The Ultimate did not answer in time"),
        ("ULTIMATE_ERR_PROTOCOL",        3, "Transport-level protocol violation"),
        ("ULTIMATE_ERR_NOT_SUPPORTED",   4, "Target or command not implemented by this firmware"),
        ("ULTIMATE_ERR_INVALID_ARGUMENT", 5, "Bad argument supplied by the caller"),
        ("ULTIMATE_ERR_IO",              6, "File system / network I/O failure"),
        ("ULTIMATE_ERR_DEVICE",          7, "Target reported a failure status"),
        ("ULTIMATE_ERR_TRUNCATED",       8, "Reply did not fit in the caller's buffer"),
        ("ULTIMATE_ERR_ABORTED",         9, "Command was aborted"),
    ]),

    ("Request block layout", "Byte offsets into a uci_request. The assembly core "
                             "is the authority on this layout; bindings/cc65/abi_assert.c "
                             "fails the build if the C struct ever stops matching.", [
        ("UCI_REQ_TARGET",     0,  "byte: target id, optionally | UCI_TARGET_NO_REPLY"),
        ("UCI_REQ_COMMAND",    1,  "byte: command code"),
        ("UCI_REQ_ARGS",       2,  "word: pointer to argument bytes, 0 for none"),
        ("UCI_REQ_ARGLEN",     4,  "word: number of argument bytes"),
        ("UCI_REQ_PAYLOAD",    6,  "word: pointer to payload bytes, 0 for none"),
        ("UCI_REQ_PAYLOADLEN", 8,  "word: number of payload bytes"),
        ("UCI_REQ_DATA",       10, "word: buffer for the reply, 0 to discard it"),
        ("UCI_REQ_DATAMAX",    12, "word: size of that buffer"),
        ("UCI_REQ_DATALEN",    14, "word: out, reply bytes stored"),
        ("UCI_REQ_STATUS",     16, "word: buffer for the status string, 0 to discard"),
        ("UCI_REQ_STATUSMAX",  18, "word: size of that buffer"),
        ("UCI_REQ_STATUSLEN",  20, "word: out, status bytes stored"),
        ("UCI_REQ_SIZE",       22, "total size of the block"),
    ]),

    ("SDK memory footprint", "How much RAM the core needs, and where. All of it "
                             "is placeable: see UCI_ZP and UCI_VARS in docs/asm-abi.md.", [
        ("UCI_ZP_SIZE",   4,  "zero page bytes the core needs"),
        ("UCI_VARS_SIZE", 88, "non-zero-page bytes the whole SDK needs"),
    ]),

    ("ASCII literals", "Bytes that come off the wire are always written "
                       "numerically. An assembler charmap, or a compiler's idea of the "
                       "target character set, must never reach them: cc65 turns \"NO "
                       "TARGET\" into PETSCII, which silently stops matching what the "
                       "Ultimate sends.", [
        ("UCI_ASCII_ZERO",  0x30, "'0'"),
        ("UCI_ASCII_NINE",  0x39, "'9'"),
        ("UCI_ASCII_COMMA", 0x2C, "','"),
        ("UCI_ASCII_SPACE", 0x20, "' '"),
    ]),

    ("Status string families", "Targets do not agree on how status is encoded; the "
                               "SDK picks a decoder per target.", [
        ("UCI_STATUS_FMT_DECIMAL2", 0, "'NN,TEXT' - DOS, Network, Control"),
        ("UCI_STATUS_FMT_DECIMAL3", 1, "'NNN TEXT' - HTTP"),
        ("UCI_STATUS_FMT_BINARY",   2, "single binary byte - SoftwareIEC"),
        ("UCI_STATUS_FMT_NONE",     3, "target sends no status"),
    ]),
]

# Strings that the protocol defines and that bindings must not re-spell.
STRINGS = [
    ("UCI_STR_NO_TARGET", "NO TARGET",
     "Reply of the built-in placeholder target: this target ID is not implemented."),
    ("UCI_STR_STATUS_OK", "00,OK", "Canonical success status of the decimal2 family."),
]


DECIMAL_GROUPS = ("Queue sizes", "Timeouts", "SDK status", "Status string",
                  "Control: VIC-II palette", "Request block layout",
                  "SDK memory footprint")


def _decimal_group(title):
    """Groups whose values read better in decimal than in hex."""
    for prefix in DECIMAL_GROUPS:
        if title.startswith(prefix):
            return True
    return False


def c_header():
    out = [
        "/* Generated by tools/gen_protocol.py - DO NOT EDIT BY HAND. */",
        "/* Ultimate Command Interface protocol constants. See docs/uci.md. */",
        "",
        "#ifndef ULTIMATE_UCI_PROTOCOL_H",
        "#define ULTIMATE_UCI_PROTOCOL_H",
        "",
    ]
    for title, note, items in GROUPS:
        out.append("/* ---- %s ---- */" % title)
        if note:
            for line in textwrap.wrap(note, 72):
                out.append("/* %s */" % line)
        width = max(len(n) for n, _, _ in items)
        for name, value, comment in items:
            val = "0x%02X" % value if value <= 0xFF and not _decimal_group(title) \
                else str(value)
            if value > 0xFF and value <= 0xFFFF and title == "Register map":
                val = "0x%04X" % value
            line = "#define %-*s %s" % (width, name, val)
            if comment:
                line += "  /* %s */" % comment
            out.append(line)
        out.append("")
    out.append("/* ---- Protocol strings ---- */")
    out.append("/*")
    out.append(" * Protocol strings are emitted as explicit byte lists, never as C string")
    out.append(" * literals. cc65 translates literals into the target character set, so")
    out.append(" * \"NO TARGET\" compiled for the C64 becomes PETSCII and stops matching the")
    out.append(" * ASCII the Ultimate actually sends. Use them as:")
    out.append(" *")
    out.append(" *     static const uint8_t marker[] = { UCI_STR_NO_TARGET_BYTES };")
    out.append(" */")
    for name, value, comment in STRINGS:
        out.append("/* %s = \"%s\": %s */" % (name, value, comment))
        out.append("#define %s_BYTES %s" %
                   (name, ", ".join("0x%02X" % ord(c) for c in value)))
        out.append("#define %s_LEN %d" % (name, len(value)))
    out.append("")
    out.append("#endif /* ULTIMATE_UCI_PROTOCOL_H */")
    return "\n".join(out) + "\n"


def asm_include():
    out = [
        "; Generated by tools/gen_protocol.py - DO NOT EDIT BY HAND.",
        "; Ultimate Command Interface protocol constants (ca65 syntax).",
        "; See docs/uci.md and docs/asm-abi.md.",
        "",
        ".ifndef ULTIMATE_UCI_PROTOCOL_INC",
        "ULTIMATE_UCI_PROTOCOL_INC = 1",
        "",
    ]
    for title, note, items in GROUPS:
        out.append("; ---- %s ----" % title)
        if note:
            for line in textwrap.wrap(note, 72):
                out.append("; %s" % line)
        width = max(len(n) for n, _, _ in items)
        for name, value, comment in items:
            if value > 0xFF:
                val = "$%04X" % value
            elif title in ("Queue sizes",) or title.startswith("SDK status") \
                    or title.startswith("Status string"):
                val = str(value)
            else:
                val = "$%02X" % value
            line = "%-*s = %s" % (width, name, val)
            if comment:
                line += "  ; %s" % comment
            out.append(line)
        out.append("")
    out.append("; ---- Protocol strings ----")
    out.append("; Emitted as byte lists so that no assembler charmap can rewrite them.")
    for name, value, comment in STRINGS:
        out.append("; %s = \"%s\" (%s)" % (name, value, comment))
        out.append(".macro %s_BYTES" % name)
        out.append("    .byte %s" % ", ".join("$%02X" % ord(c) for c in value))
        out.append(".endmacro")
        out.append("%s_LEN = %d" % (name, len(value)))
    out.append("")
    out.append(".endif")
    return "\n".join(out) + "\n"


def kickass_include():
    """KickAssembler: .label NAME = value, inside a file namespace."""
    out = [
        "// Generated by tools/gen_protocol.py - DO NOT EDIT BY HAND.",
        "//",
        "// Ultimate Command Interface constants for KickAssembler.",
        "//",
        "//     #import \"uci_protocol.asm\"",
        "//     lda #uci.UCI_TARGET_DOS1",
        "//",
        "// The code itself is not linkable from KickAssembler; use the",
        "// standalone binary in bindings/blob, which needs no linking at all.",
        "//",
        "// SPDX-License-Identifier: MIT",
        "",
        ".filenamespace uci",
        "",
    ]
    for title, note, items in GROUPS:
        out.append("// ---- %s ----" % title)
        if note:
            for line in textwrap.wrap(note, 72):
                out.append("// %s" % line)
        for name, value, comment in items:
            width = 2 if value < 0x100 else 4
            text = ".label %-26s = $%0*X" % (name, width, value)
            if comment:
                text += "  // %s" % comment
            out.append(text)
        out.append("")
    return "\n".join(out)


def acme_include():
    """ACME: NAME = value."""
    out = [
        "; Generated by tools/gen_protocol.py - DO NOT EDIT BY HAND.",
        ";",
        "; Ultimate Command Interface constants for ACME.",
        ";",
        ";     !source \"uci_protocol.a\"",
        ";     lda #UCI_TARGET_DOS1",
        ";",
        "; The code itself is not linkable from ACME; use the standalone",
        "; binary in bindings/blob, which needs no linking at all.",
        ";",
        "; SPDX-License-Identifier: MIT",
        "",
    ]
    for title, note, items in GROUPS:
        out.append("; ---- %s ----" % title)
        if note:
            for line in textwrap.wrap(note, 72):
                out.append("; %s" % line)
        for name, value, comment in items:
            width = 2 if value < 0x100 else 4
            text = "%-26s = $%0*X" % (name, width, value)
            if comment:
                text += "  ; %s" % comment
            out.append(text)
        out.append("")
    return "\n".join(out)


def markdown():
    out = [
        "<!-- Generated by tools/gen_protocol.py - DO NOT EDIT BY HAND. -->",
        "",
        "# UCI protocol constants",
        "",
        "Machine-generated from `tools/gen_protocol.py`, which is the single source",
        "of truth for every binding. Provenance for each value is in [uci.md](../uci.md).",
        "",
    ]
    for title, note, items in GROUPS:
        out.append("## %s" % title)
        out.append("")
        if note:
            out.append(note)
            out.append("")
        out.append("| Name | Value | Notes |")
        out.append("| --- | --- | --- |")
        for name, value, comment in items:
            if _decimal_group(title):
                val = str(value)
            elif value > 0xFF:
                val = "`$%04X`" % value
            else:
                val = "`$%02X`" % value
            out.append("| `%s` | %s | %s |" % (name, val, comment))
        out.append("")
    out.append("## Protocol strings")
    out.append("")
    out.append("| Name | Value | Notes |")
    out.append("| --- | --- | --- |")
    for name, value, comment in STRINGS:
        out.append('| `%s` | `"%s"` | %s |' % (name, value, comment))
    out.append("")
    return "\n".join(out)


def write(path, text):
    full = os.path.join(REPO, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as fh:
        fh.write(text)
    print("wrote %s (%d bytes)" % (path, len(text)))


def main():
    # Guard against typos: no duplicate names anywhere.
    seen = {}
    for title, _, items in GROUPS:
        for name, value, _ in items:
            if name in seen:
                raise SystemExit("duplicate constant %s (%s and %s)" % (name, seen[name], title))
            seen[name] = title
    write("include/uci_protocol.h", c_header())
    write("bindings/asm/uci_protocol.inc", asm_include())
    write("docs/generated/protocol-constants.md", markdown())
    write("bindings/kickass/uci_protocol.asm", kickass_include())
    write("bindings/acme/uci_protocol.a", acme_include())


if __name__ == "__main__":
    main()
