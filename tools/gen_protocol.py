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
    bindings/asm/uci_argtable.inc       (ca65, runtime argument shapes)

Sources for every value are cited in docs/uci.md.  Nothing here is guessed:
values marked INFERRED in docs/uci.md come from the Ultimate firmware / FPGA
sources rather than the published register API document.
"""

import os
import re
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
        ("DOS_CMD_OPEN_FILE",      0x02, "attrib is a DOS_FA_* mask"),
        ("DOS_CMD_CLOSE_FILE",     0x03, ""),
        ("DOS_CMD_READ_DATA",      0x04, "arrives as 512-byte blocks; uci_exec walks the chain"),
        ("DOS_CMD_WRITE_DATA",     0x05, "the two fixed bytes are skipped, not stored"),
        ("DOS_CMD_FILE_SEEK",      0x06, ""),
        ("DOS_CMD_FILE_INFO",      0x07, ""),
        ("DOS_CMD_FILE_STAT",      0x08, ""),
        ("DOS_CMD_DELETE_FILE",    0x09, ""),
        ("DOS_CMD_RENAME_FILE",    0x0A, ""),
        ("DOS_CMD_COPY_FILE",      0x0B, ""),
        ("DOS_CMD_CHANGE_DIR",     0x11, ""),
        ("DOS_CMD_GET_PATH",       0x12, ""),
        ("DOS_CMD_OPEN_DIR",       0x13, ""),
        ("DOS_CMD_READ_DIR",       0x14, ""),
        ("DOS_CMD_COPY_UI_PATH",   0x15, "Deprecated since FW 3.0"),
        ("DOS_CMD_CREATE_DIR",     0x16, ""),
        ("DOS_CMD_COPY_HOME_PATH", 0x17, ""),
        ("DOS_CMD_LOAD_REU",       0x21, "the safe REU pair; never wrap the control pair, see #740"),
        ("DOS_CMD_SAVE_REU",       0x22, "the safe REU pair; never wrap the control pair, see #740"),
        ("DOS_CMD_MOUNT_DISK",     0x23, ""),
        ("DOS_CMD_UMOUNT_DISK",    0x24, ""),
        ("DOS_CMD_SWAP_DISK",      0x25, ""),
        ("DOS_CMD_GET_TIME",       0x26, "fmt may be omitted; the target defaults it to $00"),
        ("DOS_CMD_SET_TIME",       0x27, "year is the year minus 1900"),
        ("DOS_CMD_LOAD_RAMDISK",   0x41, "GEOS MegaPatch RAM disk; the firmware header spells it CTRL_CMD_LOAD_INTO_RAMDISK and puts it on this target"),
        ("DOS_CMD_SAVE_RAMDISK",   0x42, "GEOS MegaPatch RAM disk; the firmware header spells it CTRL_CMD_SAVE_RAMDISK and puts it on this target"),
        ("DOS_CMD_ECHO",           0xF0, "Echo the command back as data"),
    ]),

    ("DOS file open attributes", "Bit flags for DOS_CMD_OPEN_FILE.", [
        ("DOS_FA_READ",          0x01, "Open for reading"),
        ("DOS_FA_WRITE",         0x02, "Open for writing, do not truncate"),
        ("DOS_FA_CREATE_NEW",    0x04, "Create only when the name does not exist"),
        ("DOS_FA_CREATE_ALWAYS", 0x08, "Create or truncate an existing file"),
    ]),

    ("DOS file information reply", "Byte offsets into the reply of DOS_CMD_FILE_STAT "
                                  "and DOS_CMD_FILE_INFO. The name is last, has no "
                                  "terminator, and its length is the reply length "
                                  "less DOS_INFO_NAME. Read from t_dos_info in "
                                  "software/filemanager/dos.h.", [
        ("DOS_INFO_SIZE",      0,  "file size, 32-bit little-endian"),
        ("DOS_INFO_DATE",      4,  "FAT date, 16-bit little-endian"),
        ("DOS_INFO_TIME",      6,  "FAT time, 16-bit little-endian"),
        ("DOS_INFO_EXTENSION", 8,  "three bytes, space padded, not terminated"),
        ("DOS_INFO_ATTRIB",   11,  "DOS_ATTR_* bits"),
        ("DOS_INFO_NAME",     12,  "the name begins here"),
        ("DOS_INFO_NAME_MAX", 63,  "longest name the firmware copies"),
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
        ("NET_CMD_SET_INTERFACE",       0x03, "RESERVED: the firmware's case is commented out, "
                                              "so this answers 21,UNKNOWN COMMAND"),
        ("NET_CMD_GET_NETADDR",         0x04, "replies with UCI_NET_MACADDR_BYTES"),
        ("NET_CMD_GET_IPADDR",          0x05, "replies with UCI_NET_IPCONFIG_BYTES, ip/mask/gw"),
        ("NET_CMD_SET_IPADDR",          0x06, "ipconfig must be exactly UCI_NET_IPCONFIG_BYTES"),
        ("NET_CMD_OPEN_TCP",            0x07, ""),
        ("NET_CMD_OPEN_UDP",            0x08, ""),
        ("NET_CMD_CLOSE_SOCKET",        0x09, ""),
        ("NET_CMD_READ_SOCKET",         0x10, ""),
        ("NET_CMD_WRITE_SOCKET",        0x11, ""),
        ("NET_CMD_LISTEN_START",        0x12, "INFERRED: not in the published spec"),
        ("NET_CMD_LISTEN_STOP",         0x13, "INFERRED: not in the published spec"),
        ("NET_CMD_LISTEN_STATE",        0x14, "INFERRED: not in the published spec"),
        ("NET_CMD_LISTEN_SOCKET",       0x15, "INFERRED: not in the published spec"),
    ]),

    ("Network address sizes", "Fixed-width blobs the network target exchanges.", [
        ("UCI_NET_MACADDR_BYTES",  6,  "bytes in a MAC address"),
        ("UCI_NET_IPCONFIG_BYTES", 12, "bytes in an ip/mask/gateway triple"),
        ("UCI_NET_READ_PREFIX",    2,  "16-bit count the firmware puts in front of socket data"),
        ("UCI_NET_READ_MAX",     512,  "largest READ_SOCKET this SDK will ask for - see docs/uci.md"),
        ("UCI_NET_NO_DATA",   0xFFFF,  "that count, when nothing was available to read"),
        ("UCI_NET_DEV_OK",         0,  "network device code: the reply carries data"),
        ("UCI_NET_DEV_CLOSED",     1,  "network device code: the peer hung up, reported once"),
        ("UCI_NET_DEV_NO_DATA",    2,  "network device code: nothing pending, try again"),
    ]),

    ("Control commands (target $04)", "", [
        ("CTRL_CMD_IDENTIFY",          0x01, ""),
        ("CTRL_CMD_READ_RTC",          0x02, "INFERRED: firmware only, not in the published spec"),
        ("CTRL_CMD_FINISH_CAPTURE",    0x03, ""),
        ("CTRL_CMD_FREEZE",            0x05, ""),
        ("CTRL_CMD_REBOOT",            0x06, "Never replies: the C64 and the UCI are reset"),
        ("CTRL_CMD_LOAD_REU",          0x08, "never returns on FW 3.14d and wedges the interface, see #740"),
        ("CTRL_CMD_SAVE_REU",          0x09, ""),
        ("CTRL_CMD_U64_SAVEMEM",       0x0F, "U64 family only"),
        ("CTRL_CMD_DECODE_TRACK",      0x11, "GCR -> binary in REU"),
        ("CTRL_CMD_ENCODE_TRACK",      0x12, "INFERRED: firmware only, not in the published spec"),
        ("CTRL_CMD_EASYFLASH",         0x20, "sector erase; baseaddr bit $20 selects the high ROM"),
        ("CTRL_CMD_GET_HWINFO",        0x28, "deprecated; sub may be omitted; defaults to CTRL_HWINFO_MODEL"),
        ("CTRL_CMD_GET_DRVINFO",       0x29, ""),
        ("CTRL_CMD_ENABLE_DRIVE_A",    0x30, ""),
        ("CTRL_CMD_DISABLE_DRIVE_A",   0x31, ""),
        ("CTRL_CMD_ENABLE_DRIVE_B",    0x32, ""),
        ("CTRL_CMD_DISABLE_DRIVE_B",   0x33, ""),
        ("CTRL_CMD_GET_DRIVE_A_POWER", 0x34, ""),
        ("CTRL_CMD_GET_DRIVE_B_POWER", 0x35, ""),
        ("CTRL_CMD_GET_RAMDISKINFO",   0x40, "GEOS MegaPatch 3 RAM disk layout"),
        ("CTRL_CMD_LOAD_CONFIG",       0x50, "INFERRED: firmware only, not in the published spec"),
        ("CTRL_CMD_GET_PALETTE",       0x51, "-> 48 RGB bytes (FW > 3.15)"),
        ("CTRL_CMD_SET_PALETTE",       0x52, "palette is exactly UCI_PALETTE_BYTES (FW > 3.15)"),
        ("CTRL_CMD_SET_PALETTE_COLOR", 0x53, "(FW > 3.15)"),
        ("CTRL_CMD_RESET_PALETTE",     0x54, "restore the built-in palette (FW > 3.15)"),
    ]),

    ("Control: VIC-II palette", "Runtime palette control. Affects the live palette "
                                "only; it does not touch flash configuration or VPL files.", [
        ("UCI_PALETTE_COLORS", 16, "colors in a VIC-II palette"),
        ("UCI_PALETTE_BYTES",  48, "bytes in a full palette frame (16 * RGB)"),
    ]),

    ("Control: deprecated hardware info sub-commands", "", [
        ("CTRL_HWINFO_MODEL", 0x00, "ASCII model name, e.g. 'ULTIMATE 64'"),
        ("CTRL_HWINFO_SID",   0x01, "deprecated SID configuration frames"),
    ]),

    ("Control: drive type codes", "From CTRL_CMD_GET_DRVINFO.", [
        ("CTRL_DRVTYPE_1541",     0x00, ""),
        ("CTRL_DRVTYPE_1571",     0x01, ""),
        ("CTRL_DRVTYPE_1581",     0x02, ""),
        ("CTRL_DRVTYPE_UNDECIDED", 0x03, ""),
        ("CTRL_DRVTYPE_SOFTIEC",  0x0F, ""),
        ("CTRL_DRVTYPE_PRINTER",  0x50, ""),
    ]),

    ("Control: the physical drives", "Drives A and B. CTRL_CMD_ENABLE_DRIVE_A "
                                     "through CTRL_CMD_GET_DRIVE_B_POWER are one "
                                     "command per drive, so this is how many "
                                     "drives those commands can name. It is not "
                                     "how many records CTRL_CMD_GET_DRVINFO can "
                                     "return - see CTRL_DRVINFO_MAX.", [
        ("CTRL_DRIVE_SLOTS", 2, "drives the enable and power commands address"),
    ]),

    ("Control: drive information reply", "Layout of the CTRL_CMD_GET_DRVINFO reply: a "
                                         "count, then one record per drive the machine "
                                         "has. control_target.cc emits drives A and B, "
                                         "then IecInterface::info in iec_interface.cc "
                                         "adds one record per occupied IEC bus slot.", [
        ("CTRL_DRVINFO_COUNT",   0, "offset of the drive count"),
        ("CTRL_DRVINFO_FIRST",   1, "offset of the first record"),
        ("CTRL_DRVINFO_RECORD",  3, "bytes per record: type, IEC address, power"),
        ("CTRL_DRVINFO_SLAVES",  4, "IEC bus slots, MAX_SLOTS in iec_interface.h"),
        ("CTRL_DRVINFO_MAX",     6, "records the count can reach: two drives and four slots"),
        ("CTRL_DRVINFO_BYTES",  19, "longest reply: the count and six records"),
    ]),

    ("Control: RAM disk information reply", "Layout of the CTRL_CMD_GET_RAMDISKINFO "
                                            "reply: four two-byte records, each a drive "
                                            "type code and the size in 64K units.", [
        ("CTRL_RAMDISK_DRIVES", 4, "records in the reply"),
        ("CTRL_RAMDISK_BYTES",  8, "bytes in the reply"),
    ]),

    ("Control: drive power reply", "CTRL_CMD_GET_DRIVE_A_POWER and its B counterpart "
                                   "answer with three ASCII bytes rather than a flag.", [
        ("CTRL_POWER_BYTES", 3, "bytes in the reply: 'on ' or 'off'"),
    ]),

    ("SoftwareIEC commands (target $05)", "", [
        ("SOFTIEC_CMD_IDENTIFY",      0x01, "answers in ASCII; every other command on this target answers in binary"),
        ("SOFTIEC_CMD_LOAD_SU",       0x10, "sec 1 uses the file's own load address, 0 uses addr; unused is never read but must be sent"),
        ("SOFTIEC_CMD_LOAD_EX",       0x11, "returns the end address in status bytes 1-2"),
        ("SOFTIEC_CMD_SAVE",          0x12, ""),
        ("SOFTIEC_CMD_OPEN",          0x13, ""),
        ("SOFTIEC_CMD_CLOSE",         0x14, ""),
        ("SOFTIEC_CMD_CHKIN",         0x15, ""),
        ("SOFTIEC_CMD_CHKOUT",        0x16, "sec & $F0 of $F0 opens and $E0 closes; anything else pushes data"),
        ("SOFTIEC_CMD_ADD_PARTITION", 0x20, "the string is 'IDENT:/path'"),
        ("SOFTIEC_CMD_DEL_PARTITION", 0x21, ""),
        ("SOFTIEC_CMD_GET_FATNAME",   0x22, "resolves an IEC name to a host path"),
        ("SOFTIEC_CMD_GET_IECNAME",   0x23, ""),
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
        ("HTTP_CMD_HEADER_CREATE",   0x11, "verb is an HTTP_VERB_* code"),
        ("HTTP_CMD_HEADER_FREE",     0x12, ""),
        ("HTTP_CMD_HEADER_ADD",      0x13, "the string is 'key: value'"),
        ("HTTP_CMD_HEADER_QUERY",    0x14, ""),
        ("HTTP_CMD_HEADER_LIST",     0x15, ""),
        ("HTTP_CMD_BODY_CREATE",     0x21, "format is an HTTP_BODY_* code"),
        ("HTTP_CMD_BODY_FREE",       0x22, ""),
        ("HTTP_CMD_BODY_ADD_INT",    0x23, "1 to 4 value bytes are accepted, sign-extended from the last; send four"),
        ("HTTP_CMD_BODY_ADD_BOOL",   0x24, "any non-zero value is true"),
        ("HTTP_CMD_BODY_ADD_STRING", 0x25, ""),
        ("HTTP_CMD_BODY_ADD_OBJECT", 0x26, ""),
        ("HTTP_CMD_BODY_ADD_ARRAY",  0x27, ""),
        ("HTTP_CMD_BODY_UP",         0x28, ""),
        ("HTTP_CMD_BODY_REMOVE",     0x29, ""),
        ("HTTP_CMD_BODY_QUERY",      0x2A, ""),
        ("HTTP_CMD_BODY_MOVE",       0x2B, ""),
        ("HTTP_CMD_BODY_ADD_BINARY", 0x2C, ""),
        ("HTTP_CMD_BODY_ADD",        0x2D, ""),
        ("HTTP_CMD_BODY_CLEAR",      0x2E, ""),
        ("HTTP_CMD_DO_EXCHANGE_OBJ", 0x31, "pass HTTP_BODY_NONE as body to send none"),
        ("HTTP_CMD_DO_EXCHANGE_RAW", 0x32, "pass HTTP_BODY_NONE as body to send none"),
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

    ("Ultimate 64 turbo control (NOT UCI)", "The one part of the machine the "
     "SDK reaches without the command interface, because there is no UCI "
     "command for CPU speed. Plain memory-mapped registers, documented at "
     "1541u-documentation.readthedocs.io. They answer $FF unless the Ultimate's "
     "'Turbo Control' setting is 'U64 Turbo Registers' or 'Turbo Enable Bit', "
     "which is what makes availability testable rather than assumed.", [
        ("U64_REG_TURBO",         0xD031, "R/W  bits 0-3 speed index, bit 7 badlines off"),
        ("U64_REG_TURBO_ENABLE",  0xD030, "R/W  bit 0, in 'Turbo Enable Bit' mode only"),
        ("U64_TURBO_SPEED_MASK",  0x0F,   "speed index field of U64_REG_TURBO"),
        ("U64_TURBO_NO_BADLINES", 0x80,   "set to stop the VIC stealing cycles"),
        ("U64_TURBO_UNAVAILABLE", 0xFF,   "what both registers read when turbo is off in config"),
    ]),

    ("REU registers (NOT UCI)", "Another part of the SDK that works without "
     "the command interface, for the same reason as turbo: no UCI "
     "command moves bytes between C64 RAM and the REU. The register set is the "
     "1750's, implemented in fpga/cart_slot/vhdl_source/reu.vhd, and the "
     "command interface overlays $DF1B-$DF1F above it - the REU decodes "
     "$DF00-$DF17 only, so the two coexist. A transfer runs under DMA with the "
     "CPU halted, so it is finished by the time the next instruction runs.", [
        ("REU_REG_STATUS",   0xDF00, "R    bit 7 IRQ, 6 done, 5 verify error, 4 size; reading clears 6 and 5"),
        ("REU_REG_COMMAND",  0xDF01, "R/W  bit 7 execute, 5 autoload, 4 start now, bits 1-0 mode"),
        ("REU_REG_C64_LO",   0xDF02, "R/W  C64 base address, low"),
        ("REU_REG_C64_HI",   0xDF03, "R/W  C64 base address, high"),
        ("REU_REG_ADDR_LO",  0xDF04, "R/W  REU base address, low"),
        ("REU_REG_ADDR_MID", 0xDF05, "R/W  REU base address, middle"),
        ("REU_REG_ADDR_HI",  0xDF06, "R/W  REU base address, high"),
        ("REU_REG_LEN_LO",   0xDF07, "R/W  transfer length, low"),
        ("REU_REG_LEN_HI",   0xDF08, "R/W  transfer length, high; 0 means 65536"),
        ("REU_REG_IRQMASK",  0xDF09, "R/W  bit 7 enable, 6 on done, 5 on verify error"),
        ("REU_REG_CONTROL",  0xDF0A, "R/W  bit 7 fix C64 address, bit 6 fix REU address"),
    ]),

    ("REU command and status bits", "Written to REU_REG_COMMAND and read back "
     "from REU_REG_STATUS. REU_CMD_NOW is not optional for a program driving "
     "the REU itself: with it clear the transfer waits for a write to $FF00, "
     "which is the trick a cartridge uses and a nuisance everywhere else.", [
        ("REU_CMD_EXECUTE",  0x80, "start the transfer"),
        ("REU_CMD_AUTOLOAD", 0x20, "reload address and length after it finishes"),
        ("REU_CMD_NOW",      0x10, "start now rather than on a write to $FF00"),
        ("REU_MODE_STASH",   0x00, "C64 -> REU"),
        ("REU_MODE_FETCH",   0x01, "REU -> C64"),
        ("REU_MODE_SWAP",    0x02, "exchange both ways"),
        ("REU_MODE_VERIFY",  0x03, "compare without writing anything"),
        ("REU_STAT_DONE",    0x40, "the transfer finished; cleared by reading the register"),
        ("REU_STAT_VERIFY_ERROR", 0x20, "a verify found a difference"),
        ("REU_STAT_SIZE",    0x10, "set on 256K and larger"),
    ]),

    ("Ultimate Audio registers (NOT UCI)", "Seven hardware PCM voices mapped "
     "at $DF20-$DFFF when the machine's 'Map Ultimate Audio' setting is "
     "enabled. Multi-byte fields are written most-significant byte first. "
     "Sample addresses are offsets into the 16 MB REU window; the hardware "
     "adds the SDRAM base byte $01.", [
        ("UA_REG_BASE",          0xDF20, "channel 0 base; each channel occupies 32 bytes"),
        ("UA_REG_IRQ_STATUS",    0xDF20, "R    one end-of-sample bit per channel"),
        ("UA_REG_VERSION",       0xDF21, "R    module version; $10 is version 1.0"),
        ("UA_CHANNEL_STRIDE",    0x20,   "bytes between channel register blocks"),
        ("UA_CHANNELS",          7,      "software-visible channels 0-6"),
        ("UA_VERSION_1_0",       0x10,   "known register API version"),
        ("UA_REG_CONTROL",       0x00,   "W    gate, repeat, IRQ, format and interleave"),
        ("UA_REG_VOLUME",        0x01,   "W    0-63"),
        ("UA_REG_PAN",           0x02,   "W    0 left, 7/8 centre, 15 right"),
        ("UA_REG_START",         0x04,   "W    32-bit SDRAM address, big endian"),
        ("UA_REG_LENGTH",        0x09,   "W    24-bit byte count, big endian"),
        ("UA_REG_RATE",          0x0E,   "W    divider from 6.25 MHz, big endian"),
        ("UA_RATE_CLOCK",         6250000, "the sampler's reference in Hz; a voice's rate is UA_RATE_CLOCK / sample rate"),
        ("UA_REG_REPEAT_A",      0x11,   "W    24-bit loop start offset, big endian"),
        ("UA_REG_REPEAT_B",      0x15,   "W    24-bit loop end offset, big endian"),
        ("UA_REG_IRQ_CLEAR",     0x1F,   "W    1 clears this channel; $FF clears all"),
        ("UA_REU_SDRAM_BANK",    0x01,   "upper byte of an address in the REU window"),
    ]),

    ("Ultimate Audio control bits", "Written to a channel's UA_REG_CONTROL.", [
        ("UA_CTRL_GATE",       0x01, "start the channel"),
        ("UA_CTRL_REPEAT",     0x02, "loop between repeat points A and B"),
        ("UA_CTRL_IRQ",        0x04, "raise IRQ at the end of the sample"),
        ("UA_CTRL_16BIT",      0x10, "16-bit little-endian PCM; clear for 8-bit PCM"),
        ("UA_CTRL_INTERLEAVE", 0x40, "skip the other channel in interleaved stereo data"),
        ("UA_CTRL_FLAGS",      0x56, "all caller-selectable bits, excluding gate"),
        ("UA_VOLUME_MAX",      63,   "largest valid per-channel volume"),
        ("UA_PAN_LEFT",        0,    "hard left"),
        ("UA_PAN_CENTER",      7,    "centre (8 is also centred)"),
        ("UA_PAN_RIGHT",       15,   "hard right"),
    ]),

    ("Ultimate Audio voice layout", "Byte offsets in ultimate_audio_voice. "
     "The C ABI build asserts the structure still matches these.", [
        ("UA_VOICE_CHANNEL",    0,  "byte"),
        ("UA_VOICE_FLAGS",      1,  "byte"),
        ("UA_VOICE_VOLUME",     2,  "byte"),
        ("UA_VOICE_PAN",        3,  "byte"),
        ("UA_VOICE_REU",        4,  "dword, little endian"),
        ("UA_VOICE_LENGTH",     8,  "dword, little endian"),
        ("UA_VOICE_REPEAT_A",  12,  "dword, little endian"),
        ("UA_VOICE_REPEAT_B",  16,  "dword, little endian"),
        ("UA_VOICE_RATE",      20,  "word, little endian"),
        ("UA_VOICE_SIZE",      22,  "bytes"),
    ]),

    ("Software vsprite draw layout", "Byte offsets in ultimate_vsprite. "
     "The C ABI build asserts the structure still matches these.", [
        ("VSPRITE_BITMAP",       0, "word: destination bitmap base"),
        ("VSPRITE_SOURCE",       2, "word: column-major image or source bitmap base"),
        ("VSPRITE_MASK",         4, "word: column-major mask for VSPRITE_F_MASKED"),
        ("VSPRITE_SCREEN",       6, "word: optional screen base for VSPRITE_F_COLOR"),
        ("VSPRITE_X",            8, "byte: destination cell column, 0-39"),
        ("VSPRITE_Y",            9, "byte: destination raster line, 0-199"),
        ("VSPRITE_WIDTH",       10, "byte: width in bitmap byte columns"),
        ("VSPRITE_HEIGHT",      11, "byte: height in raster lines"),
        ("VSPRITE_COLOR",       12, "byte: screen value for touched cells"),
        ("VSPRITE_FLAGS",       13, "byte: VSPRITE_F_* operation flags"),
        ("VSPRITE_SIZE",        14, "bytes"),
        ("VSPRITE_F_MASKED",  0x01, "draw (destination AND mask) OR source"),
        ("VSPRITE_F_COPY",    0x02, "copy the same rectangle from a source bitmap"),
        ("VSPRITE_F_COLOR",   0x04, "write color to screen cells touched by nonzero source"),
        ("VSPRITE_F_ALL",     0x07, "all supported flag bits"),
    ]),

    ("Ultimate 64 speed indices", "Index into the machine's speed table. **Only "
     "these four mean the same thing on both machines.** The U64 runs "
     "1,2,3,4,5,6,8..48 MHz and the U64-II runs 1,2,3,4,6,8..64, so index 4 is "
     "5 MHz on one and 6 MHz on the other. Above 4 MHz, ask for an index and "
     "you get whatever that machine's table says.", [
        ("U64_SPEED_1MHZ", 0, "stock C64 speed, and what turbo_off restores"),
        ("U64_SPEED_2MHZ", 1, ""),
        ("U64_SPEED_3MHZ", 2, ""),
        ("U64_SPEED_4MHZ", 3, "the fastest index that means the same on both"),
        ("U64_SPEED_MAX",  15, "whatever the machine's top speed is: 48 or 64 MHz"),
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
        ("ULTIMATE_END",                10, "No more entries: the end of a directory, not a failure"),
        ("ULTIMATE_ERR_COUNT",          11, "Number of codes above, for a table that maps them"),
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
        ("UCI_VARS_SIZE", 191, "non-zero-page bytes the whole SDK needs"),
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

# ---------------------------------------------------------------------------
# The standalone blob's jump table and parameter block, read from blob.s at
# generation time so the constants can never disagree with the code they name.
# Not in the C header: a C program links the library and has no table to jsr.
# ---------------------------------------------------------------------------

BLOB_SOURCE = "bindings/blob/blob.s"
BLOB_PARAMS = 0x100   # the parameter block's offset from the blob's base

# `        jmp ultimate_init               ; +$1C`
BLOB_JUMP = re.compile(r"^\s+jmp\s+(\w+)\s*;\s*\+\$([0-9A-F]+)", re.M)
# `bp_attrib:  .res 1                  ; +$151 open's DOS_FA_* mask in,`
BLOB_FIELD = re.compile(r"^(bp_\w+):\s+\.res\s+(\S+)\s*;\s*\+\$([0-9A-F]+)", re.M)


def blob_name(target):
    """`blob_audio_configure` -> BLOB_AUDIO_CONFIGURE; `ultimate_init` -> BLOB_ULTIMATE_INIT.

    The shims in blob.s are named for the file they live in; the constant names
    the operation, which is what the README table already does.
    """
    if target.startswith("blob_"):
        target = target[5:]
    return "BLOB_" + target.upper()


def blob_groups():
    """Two groups in GROUPS' (title, note, items) shape, for the assembler emitters."""
    with open(os.path.join(REPO, BLOB_SOURCE)) as fh:
        text = fh.read()
    jumps = [(blob_name(name), int(off, 16), "")
             for name, off in BLOB_JUMP.findall(text)]
    fields = [("BLOB_PARAMS", BLOB_PARAMS, "the parameter block itself")]
    fields += [("BLOB_" + name.upper(), BLOB_PARAMS + int(off, 16), "")
               for name, _size, off in BLOB_FIELD.findall(text)]
    return [
        ("Blob jump table", "Offsets from the base address of the standalone blob "
         "(bindings/blob), whatever base it was built for: jsr BLOB + "
         "BLOB_ULTIMATE_INIT. Entries are appended, never moved. Read from "
         "blob.s when this file was generated.", jumps),
        ("Blob parameter block", "Fields of the blob's parameter block, also from "
         "the blob's base: sta BLOB + BLOB_BP_ADDR. The block starts at "
         "BLOB_PARAMS.", fields),
    ]


# Strings that the protocol defines and that bindings must not re-spell.
STRINGS = [
    ("UCI_STR_NO_TARGET", "NO TARGET",
     "Reply of the built-in placeholder target: this target ID is not implemented."),
    ("UCI_STR_STATUS_OK", "00,OK", "Canonical success status of the decimal2 family."),
]


# ---------------------------------------------------------------------------
# Argument shapes.
#
# The comment beside each command says what it takes in prose, in whichever
# notation read well at the time.  Prose cannot be marshalled from, so the same
# information lives here as data: what a caller supplies, in order, and how wide
# each piece is on the wire.  The BASIC wedge needs this to turn `UCI 1,$06,X`
# into four bytes rather than one; the generated reference needs it for its
# argument column.
#
# An entry describes the bytes that follow the target and command bytes.  Each
# is a (kind, spec) pair:
#
#   ("byte",  name)   one byte
#   ("word",  name)   two bytes, LSB first
#   ("dword", name)   four bytes, LSB first
#   ("str",   name)   raw bytes with no length and no terminator
#   ("pstr",  name)   one length byte, then that many bytes
#   ("data",  name)   caller-supplied trailing bytes, however many
#   ("lit",   value)  a fixed byte the caller does not supply
#
# "str" carries no length, so it can only be told from what follows it by the
# firmware splitting on a literal.  It is therefore valid last, or immediately
# before a "lit".  "data" is valid last only.  ARG_RULES enforces both.
#
# Trailing arguments may be omitted.  That is not a convenience the SDK invents:
# DOS_CMD_GET_TIME and CTRL_CMD_GET_HWINFO both test the received length and
# default the last argument to zero when it is absent, so a table of widths is
# all a marshaller needs.  Supplying too few arguments to a command that wanted
# them sends a short command and the target answers with its own invalid-params
# status, which is the right failure and needs no check here.
#
# Every shape below was read out of the firmware source rather than inferred
# from the prose.  Where the two disagreed the firmware won - see
# SOFTIEC_CMD_LOAD_SU, whose filename starts two bytes later than the prose
# implied, and CTRL_CMD_EASYFLASH, whose base address is one byte and not two.
# Commands whose arguments the firmware does not document and that the SDK has
# never sent are absent rather than guessed at.
# ---------------------------------------------------------------------------

ARGS = {
    # Ultimate DOS (targets $01/$02) -- software/filemanager/dos.cc
    "DOS_CMD_OPEN_FILE":     [("byte", "attrib"), ("str", "filename")],
    "DOS_CMD_READ_DATA":     [("word", "len")],
    # dos.cc writes from message[4], so two bytes are skipped and never read.
    "DOS_CMD_WRITE_DATA":    [("lit", 0x00), ("lit", 0x00), ("data", "data")],
    "DOS_CMD_FILE_SEEK":     [("dword", "pos")],
    "DOS_CMD_FILE_STAT":     [("str", "filename")],
    "DOS_CMD_DELETE_FILE":   [("str", "filename")],
    "DOS_CMD_RENAME_FILE":   [("str", "old"), ("lit", 0x00), ("str", "new")],
    "DOS_CMD_COPY_FILE":     [("str", "src"), ("lit", 0x00), ("str", "dst")],
    "DOS_CMD_CHANGE_DIR":    [("str", "dirname")],
    "DOS_CMD_CREATE_DIR":    [("str", "dirname")],
    "DOS_CMD_LOAD_REU":      [("dword", "addr"), ("dword", "len")],
    "DOS_CMD_SAVE_REU":      [("dword", "addr"), ("dword", "len")],
    "DOS_CMD_MOUNT_DISK":    [("byte", "id"), ("str", "filename")],
    "DOS_CMD_UMOUNT_DISK":   [("byte", "id")],
    "DOS_CMD_SWAP_DISK":     [("byte", "id")],
    "DOS_CMD_GET_TIME":      [("byte", "fmt")],          # optional, defaults to 0
    "DOS_CMD_SET_TIME":      [("byte", "year_1900"), ("byte", "month"),
                              ("byte", "day"), ("byte", "hour"),
                              ("byte", "minute"), ("byte", "second")],
    # <drive> is 0..3; bit $80 on LOAD_RAMDISK asks the firmware to check the
    # image and report without writing anything.
    "DOS_CMD_LOAD_RAMDISK":  [("byte", "drive"), ("str", "filename")],
    "DOS_CMD_SAVE_RAMDISK":  [("byte", "drive"), ("str", "filename")],
    "DOS_CMD_ECHO":          [("data", "data")],

    # Network (target $03) -- software/io/network/network_target.cc
    "NET_CMD_GET_NETADDR":   [("byte", "iface")],
    "NET_CMD_GET_IPADDR":    [("byte", "iface")],
    "NET_CMD_SET_IPADDR":    [("byte", "iface"), ("data", "ipconfig")],
    "NET_CMD_OPEN_TCP":      [("word", "port"), ("str", "host")],
    "NET_CMD_OPEN_UDP":      [("word", "port"), ("str", "host")],
    "NET_CMD_CLOSE_SOCKET":  [("byte", "handle")],
    "NET_CMD_READ_SOCKET":   [("byte", "handle"), ("word", "len")],
    "NET_CMD_WRITE_SOCKET":  [("byte", "handle"), ("data", "data")],
    "NET_CMD_LISTEN_START":  [("word", "port")],         # INFERRED, as the comment says

    # Control (target $04) -- software/io/command_interface/control_target.cc
    "CTRL_CMD_LOAD_REU":     [("str", "filename")],
    "CTRL_CMD_SAVE_REU":     [("str", "filename")],
    "CTRL_CMD_U64_SAVEMEM":  [("str", "filename")],
    # message[4] is a single byte: bit $20 selects the high ROM, the rest is
    # ignored. The prose "<baseaddr>" read like a 16-bit address; it is not.
    "CTRL_CMD_EASYFLASH":    [("lit", 0x00), ("byte", "bank"), ("byte", "baseaddr")],
    "CTRL_CMD_GET_HWINFO":   [("byte", "sub")],          # optional, defaults to 0
    "CTRL_CMD_GET_DRVINFO":  [("byte", "effective_addr")],
    "CTRL_CMD_SET_PALETTE":  [("data", "palette")],      # UCI_PALETTE_BYTES bytes
    "CTRL_CMD_SET_PALETTE_COLOR": [("byte", "index"), ("byte", "r"),
                                   ("byte", "g"), ("byte", "b")],

    # SoftwareIEC (target $05) -- software/io/command_interface/softiec_target.cc
    # LOAD_SU shares SAVE's layout: the name starts at message[8], so the end
    # address pair at 6,7 must be sent even though a load never reads it. Send
    # the name two bytes early and the firmware opens whatever the tail happens
    # to be. This is the one shape the prose had wrong.
    "SOFTIEC_CMD_LOAD_SU":   [("byte", "sec"), ("byte", "verify"),
                              ("word", "addr"), ("word", "unused"),
                              ("str", "name")],
    "SOFTIEC_CMD_LOAD_EX":   [("byte", "sec"), ("byte", "verify")],
    "SOFTIEC_CMD_SAVE":      [("byte", "verify"), ("byte", "sec"),
                              ("word", "start"), ("word", "end"),
                              ("str", "name")],
    "SOFTIEC_CMD_OPEN":      [("byte", "sec"), ("lit", 0x00), ("str", "name")],
    "SOFTIEC_CMD_CLOSE":     [("byte", "sec")],
    "SOFTIEC_CMD_CHKIN":     [("byte", "sec")],
    "SOFTIEC_CMD_CHKOUT":    [("byte", "sec"), ("lit", 0x00), ("data", "data")],
    "SOFTIEC_CMD_ADD_PARTITION": [("byte", "index"), ("str", "ident_colon_path")],
    "SOFTIEC_CMD_DEL_PARTITION": [("byte", "index")],
    "SOFTIEC_CMD_GET_FATNAME":   [("byte", "channel"), ("str", "iec_name")],
    "SOFTIEC_CMD_GET_IECNAME":   [("str", "fat_name")],

    # HTTP (target $06) -- software/io/command_interface/http_target.cc
    "HTTP_CMD_HEADER_CREATE": [("byte", "verb"), ("str", "url")],
    "HTTP_CMD_HEADER_FREE":   [("byte", "handle")],
    "HTTP_CMD_HEADER_ADD":    [("byte", "handle"), ("str", "key_colon_value")],
    "HTTP_CMD_HEADER_QUERY":  [("byte", "handle"), ("str", "key")],
    "HTTP_CMD_HEADER_LIST":   [("byte", "handle"), ("byte", "index")],
    "HTTP_CMD_BODY_CREATE":   [("byte", "format")],
    "HTTP_CMD_BODY_FREE":     [("byte", "handle")],
    # cmd_body_add_primitive() takes 1 to 4 value bytes and sign-extends from
    # the last one supplied, so a full four always means what it says.
    "HTTP_CMD_BODY_ADD_INT":    [("byte", "handle"), ("pstr", "key"),
                                 ("dword", "value")],
    "HTTP_CMD_BODY_ADD_BOOL":   [("byte", "handle"), ("pstr", "key"),
                                 ("byte", "value")],
    "HTTP_CMD_BODY_ADD_STRING": [("byte", "handle"), ("pstr", "key"),
                                 ("pstr", "value")],
    "HTTP_CMD_BODY_ADD_OBJECT": [("byte", "handle"), ("pstr", "key")],
    "HTTP_CMD_BODY_ADD_ARRAY":  [("byte", "handle"), ("pstr", "key")],
    "HTTP_CMD_BODY_UP":         [("byte", "handle")],
    "HTTP_CMD_BODY_REMOVE":     [("byte", "handle"), ("str", "path")],
    "HTTP_CMD_BODY_QUERY":      [("byte", "handle"), ("str", "path")],
    "HTTP_CMD_BODY_MOVE":       [("byte", "handle"), ("str", "path")],
    "HTTP_CMD_BODY_ADD_BINARY": [("byte", "handle"), ("data", "data")],
    "HTTP_CMD_BODY_ADD":        [("byte", "handle"), ("data", "items")],
    "HTTP_CMD_BODY_CLEAR":      [("byte", "handle")],
    "HTTP_CMD_DO_EXCHANGE_OBJ": [("byte", "header"), ("byte", "body")],
    "HTTP_CMD_DO_EXCHANGE_RAW": [("byte", "header"), ("byte", "body")],
}

# Wire width of each kind, in bytes. None means "as many as the caller gives".
ARG_WIDTHS = {
    "byte": 1, "word": 2, "dword": 4, "lit": 1,
    "str": None, "pstr": None, "data": None,
}


def check_args():
    """Fail generation rather than emit an argument table that cannot marshal.

    Every rule here corresponds to a way the table could silently produce wrong
    bytes on the wire, which is the failure mode that is expensive to find: the
    command is accepted, the firmware reads the wrong field, and the error comes
    back as something unrelated.
    """
    known = {}
    for title, _note, items in GROUPS:
        for name, value, _comment in items:
            known[name] = title

    problems = []
    for command, shape in sorted(ARGS.items()):
        where = "ARGS[%s]" % command
        if command not in known:
            problems.append("%s: no such constant in GROUPS" % where)
            continue
        if not shape:
            problems.append("%s: empty shape - omit the entry instead" % where)
            continue

        seen = set()
        for i, arg in enumerate(shape):
            if not isinstance(arg, tuple) or len(arg) != 2:
                problems.append("%s[%d]: not a (kind, spec) pair" % (where, i))
                continue
            kind, spec = arg
            if kind not in ARG_WIDTHS:
                problems.append("%s[%d]: unknown kind %r" % (where, i, kind))
                continue
            last = (i == len(shape) - 1)
            nxt = None if last else shape[i + 1][0]

            if kind == "lit":
                if not isinstance(spec, int) or not 0 <= spec <= 0xFF:
                    problems.append("%s[%d]: lit takes a byte value, got %r"
                                    % (where, i, spec))
                continue

            if not isinstance(spec, str) or not spec:
                problems.append("%s[%d]: %s needs a name, got %r"
                                % (where, i, kind, spec))
                continue
            if spec in seen:
                problems.append("%s[%d]: duplicate name %r" % (where, i, spec))
            seen.add(spec)

            if kind == "str" and not last and nxt != "lit":
                problems.append(
                    "%s[%d]: 'str' carries no length, so it must be last or "
                    "followed by the literal the firmware splits on; it is "
                    "followed by %r" % (where, i, nxt))
            if kind == "data" and not last:
                problems.append("%s[%d]: 'data' runs to the end of the command, "
                                "so nothing may follow it" % (where, i))

    if problems:
        raise SystemExit("gen_protocol.py: argument table is inconsistent:\n  "
                         + "\n  ".join(problems))


def arg_note(command, comment):
    """Comment text for an emitter that has no separate argument column.

    The shape is rendered from ARGS rather than left in the hand-written
    comment, so the C header, the three assembler includes and the reference
    can never disagree about what a command takes.
    """
    shape = arg_summary(command)
    if shape and comment:
        return "%s - %s" % (shape, comment)
    return shape or comment


def arg_summary(command):
    """One-line human rendering of a command's argument shape, or ''."""
    shape = ARGS.get(command)
    if not shape:
        return ""
    parts = []
    for kind, spec in shape:
        if kind == "lit":
            parts.append("$%02X" % spec)
        elif kind == "byte":
            parts.append("<%s>" % spec)
        elif kind == "word":
            parts.append("<%s:16>" % spec)
        elif kind == "dword":
            parts.append("<%s:32>" % spec)
        elif kind == "pstr":
            parts.append("<%s:len> <%s>" % (spec, spec))
        elif kind == "data":
            parts.append("<%s...>" % spec)
        else:
            parts.append("<%s>" % spec)
    return " ".join(parts)


# ---------------------------------------------------------------------------
# The runtime argument table.
#
# The BASIC wedge marshals one numeric argument as one byte and one string as
# its own bytes, because that is what nearly every command wants.  The table
# below is only the exceptions: a command earns an entry when its shape contains
# a wide numeric, a length-prefixed string, or a literal the caller never types.
# 21 of the 67 shaped commands do; the other 46 need no bytes on the 6502 at all.
#
# Entries are keyed by (target, command).  Command codes are only unique within
# a target - $04 is DOS_CMD_READ_DATA and also NET_CMD_GET_NETADDR - so the
# target has to be part of the key.  DOS is two targets running one command set,
# so its entries are stored under UCI_TARGET_DOS1 and the lookup folds $02 onto
# $01 before scanning rather than carrying a second copy of every DOS shape.
# ---------------------------------------------------------------------------

# Kind codes as the 6502 sees them. Packed two to a byte, so they must stay
# inside a nibble. UCI_ARG_END doubles as the "no more arguments" marker in the
# unused low nibble of an odd-length shape.
ARG_CODES = {
    "end":   0x0,
    "byte":  0x1,
    "word":  0x2,
    "dword": 0x3,
    "str":   0x4,
    "pstr":  0x5,
    "data":  0x6,
    "lit0":  0x7,
}

# Prefix of a command constant -> the target it belongs to. DOS commands are
# reachable on $01 and $02; $01 is the canonical one.
ARG_TARGET_PREFIX = [
    ("DOS_CMD_",     0x01),
    ("NET_CMD_",     0x03),
    ("CTRL_CMD_",    0x04),
    ("SOFTIEC_CMD_", 0x05),
    ("HTTP_CMD_",    0x06),
]

# Kinds the wedge's default rule already handles.
ARG_DEFAULT_KINDS = ("byte", "str", "data")


def arg_target(command):
    """Target a command constant belongs to, or None."""
    for prefix, target in ARG_TARGET_PREFIX:
        if command.startswith(prefix):
            return target
    return None


def needs_arg_entry(shape):
    """True when the wedge's default rule cannot marshal this shape."""
    return any(kind not in ARG_DEFAULT_KINDS for kind, _spec in shape)


def arg_table_entries():
    """(target, command_name, command_value, [kind codes]) for the exceptions.

    Sorted by target then command value so the emitted table is stable and a
    scan can give up early once it passes the command it wants.
    """
    values = {}
    for _title, _note, items in GROUPS:
        for name, value, _comment in items:
            values[name] = value

    rows = []
    for command, shape in ARGS.items():
        if not needs_arg_entry(shape):
            continue
        target = arg_target(command)
        if target is None:
            raise SystemExit("gen_protocol.py: %s needs an argument table entry "
                             "but its target cannot be derived from its name; "
                             "add a prefix to ARG_TARGET_PREFIX" % command)
        codes = []
        for kind, spec in shape:
            if kind == "lit":
                # Every literal in the protocol is $00 today, so the table
                # stores "emit a zero" as a kind and spends no byte on the
                # value. A non-zero literal would need the encoding widened,
                # which is why this fails loudly instead of truncating.
                if spec != 0x00:
                    raise SystemExit(
                        "gen_protocol.py: %s has the literal $%02X, but the "
                        "argument table only encodes $00 literals. Widen the "
                        "encoding rather than dropping the value." % (command, spec))
                codes.append(ARG_CODES["lit0"])
            else:
                codes.append(ARG_CODES[kind])
        rows.append((target, command, values[command], codes))

    rows.sort(key=lambda r: (r[0], r[2]))
    return rows


def arg_table_include():
    """ca65 source for the runtime table.

    ca65 only: the wedge is the one consumer, and every other toolchain reaches
    the SDK through the blob, which will carry this table already assembled.
    """
    rows = arg_table_entries()
    out = [
        "; Generated by tools/gen_protocol.py - DO NOT EDIT BY HAND.",
        ";",
        "; Argument shapes the BASIC wedge cannot derive from its default rule",
        "; (one numeric argument is one byte, one string is its own bytes).",
        ";",
        "; Layout, repeated until a target byte of $00:",
        ";",
        ";     .byte target          ; DOS entries are stored under $01 only;",
        ";                           ; fold $02 onto $01 before scanning",
        ";     .byte command",
        ";     .byte count           ; arguments in the shape",
        ";     .byte packed...       ; two kind nibbles per byte, high first,",
        ";                           ; low nibble of the last byte is UCI_ARG_END",
        ";                           ; when count is odd",
        ";",
        "; Entries are ordered by target then command, so a scan can stop as soon",
        "; as it passes the command it is looking for.",
        ";",
        "; A command absent from this table is not a command without arguments -",
        "; it is one the default rule already handles. uci_argtable_size is the",
        "; assembled length so a caller can copy or checksum it.",
        ";",
        "; SPDX-License-Identifier: MIT",
        "",
    ]
    for kind, code in sorted(ARG_CODES.items(), key=lambda kv: kv[1]):
        out.append("UCI_ARG_%-6s = $%X" % (kind.upper(), code))
    out.append("")
    out.append("uci_argtable:")

    target_names = {0x01: "DOS1", 0x03: "NETWORK", 0x04: "CONTROL",
                    0x05: "SOFTIEC", 0x06: "HTTP"}
    last_target = None
    for target, command, value, codes in rows:
        if target != last_target:
            out.append("        ; ---- %s ($%02X) ----" % (target_names[target], target))
            last_target = target
        packed = []
        for i in range(0, len(codes), 2):
            hi = codes[i]
            lo = codes[i + 1] if i + 1 < len(codes) else ARG_CODES["end"]
            packed.append((hi << 4) | lo)
        out.append("        ; %s  %s" % (command, arg_summary(command)))
        out.append("        .byte $%02X, $%02X, %d, %s"
                   % (target, value, len(codes),
                      ", ".join("$%02X" % b for b in packed)))
    out.append("        .byte $00               ; end of table")
    out.append("")
    out.append("uci_argtable_size = * - uci_argtable")
    out.append("")
    return "\n".join(out)


DECIMAL_GROUPS = ("Queue sizes", "Timeouts", "SDK status", "Status string",
                  "Control: VIC-II palette", "Request block layout",
                  "SDK memory footprint", "Network address sizes",
                  "Ultimate 64 speed indices")


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
            note = arg_note(name, comment)
            if note:
                line += "  /* %s */" % note
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
    for title, note, items in GROUPS + blob_groups():
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
            note = arg_note(name, comment)
            if note:
                line += "  ; %s" % note
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
    for title, note, items in GROUPS + blob_groups():
        out.append("// ---- %s ----" % title)
        if note:
            for line in textwrap.wrap(note, 72):
                out.append("// %s" % line)
        for name, value, comment in items:
            width = 2 if value < 0x100 else 4
            text = ".label %-26s = $%0*X" % (name, width, value)
            note = arg_note(name, comment)
            if note:
                text += "  // %s" % note
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
    for title, note, items in GROUPS + blob_groups():
        out.append("; ---- %s ----" % title)
        if note:
            for line in textwrap.wrap(note, 72):
                out.append("; %s" % line)
        for name, value, comment in items:
            width = 2 if value < 0x100 else 4
            text = "%-26s = $%0*X" % (name, width, value)
            note = arg_note(name, comment)
            if note:
                text += "  ; %s" % note
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
        "Command groups carry an **Arguments** column: the bytes a caller sends after",
        "the target and command bytes, in order.",
        "",
        "| Notation | Means |",
        "| --- | --- |",
        "| `<x>` | one byte |",
        "| `<x:16>` | two bytes, LSB first |",
        "| `<x:32>` | four bytes, LSB first |",
        "| `<x:len> <x>` | one length byte, then that many bytes |",
        "| `<x...>` | trailing bytes, however many are sent |",
        "| `$NN` | a fixed byte the caller does not choose |",
        "",
        "A bare `<x>` next to a string-shaped name is raw bytes with no length and no",
        "terminator; it is always either last or followed by the `$NN` the firmware",
        "splits on. Trailing arguments may be omitted where the target defaults them —",
        "`DOS_CMD_GET_TIME` and deprecated `CTRL_CMD_GET_HWINFO` both do.",
        "",
        "An empty cell means the command takes no arguments, or that the firmware does",
        "not document what it takes and the SDK has never sent it. The distinction is",
        "in the Notes column.",
        "",
    ]
    for title, note, items in GROUPS:
        out.append("## %s" % title)
        out.append("")
        if note:
            out.append(note)
            out.append("")
        # Only command groups get an argument column, and only when at least one
        # of their commands takes arguments.
        shaped = any(name in ARGS for name, _, _ in items)
        if shaped:
            out.append("| Name | Value | Arguments | Notes |")
            out.append("| --- | --- | --- | --- |")
        else:
            out.append("| Name | Value | Notes |")
            out.append("| --- | --- | --- |")
        for name, value, comment in items:
            if _decimal_group(title):
                val = str(value)
            elif value > 0xFF:
                val = "`$%04X`" % value
            else:
                val = "`$%02X`" % value
            if shaped:
                shape = arg_summary(name)
                out.append("| `%s` | %s | %s | %s |"
                           % (name, val, "`%s`" % shape if shape else "", comment))
            else:
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
    check_args()
    write("include/uci_protocol.h", c_header())
    write("bindings/asm/uci_protocol.inc", asm_include())
    write("docs/generated/protocol-constants.md", markdown())
    write("bindings/kickass/uci_protocol.asm", kickass_include())
    write("bindings/acme/uci_protocol.a", acme_include())
    write("bindings/asm/uci_argtable.inc", arg_table_include())


if __name__ == "__main__":
    main()
