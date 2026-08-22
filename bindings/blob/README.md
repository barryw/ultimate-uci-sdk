# The SDK as a standalone binary

Toolchains cannot link each other's objects. This is the same SDK, linked
standalone with a jump table at its base, so anything that can `jsr` an address
can use it — with no linking at all.

    make -C bindings/blob                 # build/ultimate-7000.bin at $7000
    make -C bindings/blob BASE=6000       # at $6000
    make -C bindings/blob BASE=6000 VARS=36864 ZP=163

The default build is 8,694 bytes: the 256-byte jump table page and the
512-byte parameter block, fixed at those sizes so every offset below holds
regardless of how little of them is used, plus the code itself.

**The default is `$7000`.** It was `$C000` until `file.s` landed and the code
overflowed the 4K there by 350 bytes, and `$8000` until the DOS, disk, clock,
machine and HTTP body services landed and overflowed the 8K by 758.

The blob has to sit below `$A000` and above the BASIC program area, because
`$A000-$BFFF` is BASIC ROM. A caller reaches every byte of a blob at `$7000`
with the machine exactly as it found it, and would have to bank for one that ran
past `$A000`. That is the difference between the blob and the BASIC wedge, whose
SDK does sit at `$A000` under BASIC ROM and pays a stub per call for it. A wedge
can bank because it is the only thing calling; a blob's caller cannot be asked
to.

`blob.cfg.in` sizes the code area from `VARS`, so a build that does not fit
**fails to link** rather than producing a binary whose first command overwrites
its own request block.

## The jump table

Offsets from the base address. **They never change.** Entries are appended,
never reordered or removed, so a program built against version 1 keeps working
against version 5.

| Offset | Entry | In | Out |
|---|---|---|---|
| `+$00` | `"UCI"` + version byte | | four bytes of signature |
| `+$04` | `uci_init` | | `A` = result |
| `+$07` | `uci_exec_block` | the request block | `A` = result |
| `+$0A` | `uci_abort` | | `A` = result |
| `+$0D` | `uci_present` | | `A` = 1 when the interface is there |
| `+$10` | `uci_ident` | | `A` = the identification register |
| `+$13` | `uci_set_timeout_a` | `A` = budget | |
| `+$16` | `uci_get_timeout_a` | | `A` = budget |
| `+$19` | `uci_last_code` | | `A`/`X` = raw device code |
| `+$1C` | `ultimate_init` | | `A` = result |
| `+$1F` | `ultimate_available` | | `A` = 1 when up |
| `+$22` | `ultimate_detect` | `A`/`X` = capability block | `A` = result |
| `+$25` | `ultimate_identify` | `A` = target | `A` = result |
| `+$28` | `ultimate_get_model` | | `A` = result; deprecated HWINFO compatibility |
| `+$2B` | `ultimate_strerror` | `A` = result code | `A`/`X` = PETSCII text |
| `+$2E` | `uci_req_clear` | | zeroes the request block at `uci_req` |
| `+$31` | `uci_decode` | `uci_dec_target`/`uci_dec_ptr`/`uci_dec_len` | `A` = result |
| `+$34` | `uci_status_fmt` | `A` = target | `A` = `UCI_STATUS_FMT_*` |
| `+$37` | `ultimate_palette_get` | `A`/`X` = 48-byte buffer | `A` = result |
| `+$3A` | `ultimate_palette_set` | `A`/`X` = 48 bytes of RGB | `A` = result |
| `+$3D` | `ultimate_palette_set_color` | `ult_color` = index, r, g, b | `A` = result |
| `+$40` | `ultimate_palette_reset` | | `A` = result |
| `+$43` | `ultimate_turbo_available` | | `A` = 1 when turbo answers |
| `+$46` | `ultimate_turbo_get` | | `A` = speed index, or `$FF` |
| `+$49` | `ultimate_turbo_set` | `A` = speed index 0-15 | `A` = result |
| `+$4C` | `ultimate_turbo_badlines` | `A` = 0 for none, non-zero for normal | `A` = result |

The entries below take their arguments from the parameter block instead of from
registers, because a caller cannot pass a filename in `A`/`X` — and because the
block is the only calling convention a BASIC program driving the blob with
`POKE` and `SYS` can express at all. Each one puts the result in `bp_result` as
well as returning it in `A`.

| Offset | Entry | In | Out |
|---|---|---|---|
| `+$4F` | `chdir` | `bp_name` | `bp_result` |
| `+$52` | `getpath` | | `bp_reply`, `bp_result` |
| `+$55` | `opendir` | | `bp_result` |
| `+$58` | `readdir` | | `bp_reply` = name, `bp_attrib`, `bp_result` |
| `+$5B` | `open` | `bp_name`, `bp_attrib` = `DOS_FA_*` | `bp_result` |
| `+$5E` | `close` | | `bp_result` |
| `+$61` | `read` | `bp_addr` = buffer, `bp_len` = wanted | `bp_len` = arrived, `bp_result` |
| `+$64` | `write` | `bp_addr`, `bp_len` | `bp_result` |
| `+$67` | `seek` | `bp_pos` | `bp_result` |
| `+$6A` | `delete` | `bp_name` | `bp_result` |
| `+$6D` | `load` | `bp_name`, `bp_addr` (0 = the file's own) | `bp_end`, `bp_result` |
| `+$70` | `bload` | `bp_name`, `bp_addr`, `bp_len` | `bp_end`, `bp_result` |
| `+$73` | `save` | `bp_name`, `bp_addr`, `bp_len` | `bp_result` |
| `+$76` | `reu_available` | | `A` = 1 when the expansion answers |
| `+$79` | `reu_stash` | `bp_addr`, `bp_reu`, `bp_reulen` | `bp_result` |
| `+$7C` | `reu_fetch` | the same, the other way | `bp_result` |
| `+$7F` | `reu_load` | `bp_reu`, `bp_reulen`, and an open file | `bp_result` |
| `+$82` | `reu_save` | the same, out of the expansion | `bp_result` |
| `+$85` | `net_ifcount` | | `bp_iface` = interfaces, `bp_result` |
| `+$88` | `net_macaddr` | `bp_iface` | `bp_reply` = 6 bytes, `bp_result` |
| `+$8B` | `net_ipconfig` | `bp_iface` | `bp_reply` = 12 bytes, `bp_result` |
| `+$8E` | `net_connect` | `bp_name` = host, `bp_port` | `bp_sock`, `bp_result` |
| `+$91` | `net_udp` | the same, for a UDP socket | `bp_sock`, `bp_result` |
| `+$94` | `net_close` | `bp_sock` | `bp_result` |
| `+$97` | `net_read` | `bp_sock`, `bp_addr` = buffer, `bp_len` = its size | `bp_len` = arrived, `bp_result` |
| `+$9A` | `net_write` | `bp_sock`, `bp_addr`, `bp_len` | `bp_len` = accepted, `bp_result` |
| `+$9D` | `http_get` | `bp_name` = url, `bp_addr` = buffer, `bp_len` = its size | `bp_len` = arrived, `bp_devcode`, `bp_result` |
| `+$A0` | `http_open` | `bp_name` = url, `bp_verb` | `bp_http`, `bp_result` |
| `+$A3` | `http_header` | `bp_http`, `bp_name` = `key: value` | `bp_result` |
| `+$A6` | `http_exchange` | `bp_http`, `bp_body`, `bp_addr`, `bp_len` | `bp_len` = arrived, `bp_result` |
| `+$A9` | `http_close` | `bp_http` | `bp_result` |
| `+$AC` | `http_free_all` | | `bp_result` |
| `+$AF` | `reu_size` | | `bp_len` = size in 64K banks, 0 = none |
| `+$B2` | `legacy_sid_info` | | deprecated HWINFO; `bp_reply` = count and SID records, `bp_result` |
| `+$B5` | `stat` | `bp_name` | `bp_reply` = the file information block, `bp_result` |
| `+$B8` | `fstat` | the open file | `bp_reply` = the file information block, `bp_result` |
| `+$BB` | `rename` | `bp_name`, `bp_name2` | `bp_result` |
| `+$BE` | `copy` | `bp_name` = source, `bp_name2` = destination | `bp_result` |
| `+$C1` | `mkdir` | `bp_name` | `bp_result` |
| `+$C4` | `home` | | `bp_result` |
| `+$C7` | `mount` | `bp_drive` = IEC device number, `bp_name` = image | `bp_result` |
| `+$CA` | `unmount` | `bp_drive` | `bp_result` |
| `+$CD` | `swap` | `bp_drive` | `bp_result` |
| `+$D0` | `get_time` | `bp_format` — 0, or 1 for the weekday | `bp_reply` = the time as text, `bp_result` |
| `+$D3` | `set_time` | `bp_time` = year less 1900, month, day, h, m, s | `bp_result` |
| `+$D6` | `reboot` | | nothing after this call runs |
| `+$D9` | `freeze` | | `bp_result`, when the machine is let go again |
| `+$DC` | `drive_enable` | `bp_drive` = 0 or 1, `bp_flag` = 0 to switch off | `bp_result` |
| `+$DF` | `drive_power` | `bp_drive` = 0 or 1 | `bp_flag` = 1 when running, `bp_result` |
| `+$E2` | `drive_info` | | `bp_reply` = count and drive records, `bp_result` |
| `+$E5` | `ramdisk_info` | | `bp_reply` = 8 bytes, `bp_result` |
| `+$E8` | `net_setip` | `bp_iface`, `bp_reply` = 12 bytes | `bp_result` |
| `+$EB` | `http_body` | `bp_format` = `HTTP_BODY_*` | `bp_body`, `bp_result` |
| `+$EE` | `http_body_free` | `bp_body` | `bp_result` |
| `+$F1` | `http_body_clear` | `bp_body` | `bp_result` |
| `+$F4` | `http_body_int` | `bp_body`, `bp_name` = key, `bp_val` | `bp_result` |
| `+$F7` | `http_body_bool` | `bp_body`, `bp_name` = key, `bp_flag` | `bp_result` |
| `+$FA` | `http_body_string` | `bp_body`, `bp_name` = key, `bp_name2` = value | `bp_result` |
| `+$FD` | `http_body_binary` | `bp_body`, `bp_addr`, `bp_len` | `bp_result` |

**`+$FD` is the last entry the table has room for.** The jump table is the
256-byte page at the base address and the parameter block begins at `base+$100`,
so the three entry points the SDK has beyond this list —
`ultimate_http_body_object`, `ultimate_http_body_array` and
`ultimate_http_body_up`, which build and leave nested JSON containers — are
reached through `uci_exec_block` at `+$07` instead. Anything added to the SDK
after them needs somewhere else for the table to continue.

`+$D6` resets the C64, so the program that called it stops existing part way
through the call. `+$D9` is the freeze button: the machine stops until whoever
is at the keyboard leaves the Ultimate's menu, and then the call returns.

`mount`, `unmount` and `swap` name the drive by the IEC device number it answers
as — 8, 9, and so on — with `bp_drive` of 0 meaning the drive that was mounted
into last. `drive_enable` and `drive_power` name it as drive A (0) or drive B
(1), because the firmware has a separate command per drive. `+$E2` reports both
numbers for every drive the machine has.

A directory walk is one live exchange: `+$55` then `+$58` until it answers
`ULTIMATE_END` (`10`), with no other command in between. `+$7F` and `+$82` work
on whatever `+$5B` left open and carry no filename of their own.

`legacy_sid_info` is named explicitly: firmware still implements its
`CTRL_CMD_GET_HWINFO` selector, but the firmware documentation marks that
command deprecated and publishes no C64-side UCI replacement. Handle
`ULTIMATE_ERR_NOT_SUPPORTED` in case it is removed.

**A socket read never waits for the wire.** `+$97` answers straight away
whether or not anything has arrived, so a caller polls: `bp_result` of
`ULTIMATE_OK` with `bp_len` non-zero is data, `ULTIMATE_OK` with `bp_len` zero
means nothing yet, and `ULTIMATE_END` (`10`) means the peer hung up — after
which the handle is gone and `+$94` would answer an error rather than close
anything. `bp_len` going in is the size of the buffer, and at most two fewer
bytes than that are stored, because the firmware sends its own count in front
of the data and the SDK strips it.

**`bp_result` of `ULTIMATE_OK` from `+$9D` means the server answered below
400.** A 404 is `ULTIMATE_ERR_DEVICE` with 404 in `bp_devcode` and the error
page in the buffer, because the request itself worked. A reply bigger than
`bp_len` is `ULTIMATE_ERR_TRUNCATED` and the rest cannot be asked for — the
protocol has no continuation. `+$9D` frees the firmware's slot whether the
exchange worked or not, which `+$A0` does not: a program that opens in a loop
and forgets `+$A9` runs the Ultimate out of header slots.

**`+$8E` can take thirty seconds.** A connect to an address with nothing at it
was measured at 30.8 s before the firmware gave up, and no timeout budget
reaches that, so this one waits without a limit of its own. Everything else
here answered in 75 ms or less.

The signature is checked before calling anything:

```asm
        lda $7000
        cmp #$D5                ; 'U' in PETSCII - the blob is built with the
        bne no_sdk              ; c64 charmap, like everything else on screen
```

## The parameter block

At `base+$100`, page-aligned so a BASIC program needs no address arithmetic.

| Offset | | Size |
|---|---|---|
| `+$00` | `bp_result` — the last entry's result code | 1 |
| `+$01` | `bp_devcode` — **yours**: the SDK never writes it, see below | 2 |
| `+$03` | `bp_addr` — address argument | 2 |
| `+$05` | `bp_len` — length argument, and what a read reports back | 2 |
| `+$07` | `bp_end` — the address after the last byte a load wrote | 2 |
| `+$09` | `bp_status` — **yours**: 32 bytes to point a hand-built request at | 32 |
| `+$29` | `bp_name` — filename, NUL terminated | 40 |
| `+$51` | `bp_reply` — where getpath and readdir put their answer | 256 |
| `+$151` | `bp_attrib` — open's `DOS_FA_*` mask in, readdir's attributes out | 1 |
| `+$152` | `bp_pos` — seek's 32-bit position | 4 |
| `+$156` | `bp_reu` — address in the RAM expansion | 4 |
| `+$15A` | `bp_reulen` — how many bytes it moves | 4 |
| `+$15E` | `bp_sock` — socket handle, in and out; `$FF` after a failed open | 1 |
| `+$15F` | `bp_iface` — interface index in, interface count out | 1 |
| `+$160` | `bp_port` — TCP or UDP port | 2 |
| `+$162` | `bp_http` — HTTP header handle, in and out | 1 |
| `+$163` | `bp_body` — HTTP body handle, or `HTTP_BODY_NONE` | 1 |
| `+$164` | `bp_verb` — `HTTP_VERB_*` for `http_open` | 1 |
| `+$165` | `bp_name2` — second name, or a string value, NUL terminated | 40 |
| `+$18D` | `bp_drive` — IEC device number, or drive A (0) or B (1) | 1 |
| `+$18E` | `bp_format` — HTTP body format, or the time format | 1 |
| `+$18F` | `bp_flag` — on or off, in and out | 1 |
| `+$190` | `bp_val` — a 32-bit value, little-endian | 4 |
| `+$194` | `bp_time` — year less 1900, month, day, hour, minute, second | 6 |

Offsets are from the block, so `bp_reu` in a `$7000` build is at `$7256`. The
block is a fixed 512 bytes whatever is used of it, which is why every field
below `bp_reply` could be appended without moving anything.

`bp_name2` exists because three entries take two caller strings where the rest
take at most one: `rename`, `copy`, and a JSON string value.

**Two of these fields are the caller's, not the SDK's.** `bp_devcode` and
`bp_status` are never written by any entry above: the raw device code comes from
`uci_last_code` at `+$19`, and the status *text* is only kept when a caller
builds a request themselves and points `UCI_REQ_STATUS` at a buffer — which is
what those 32 bytes are for. They are reserved rather than removed because the
layout is published, and reserved space costs a fixed block nothing.

## The SDK's variable block

`uci_decode` (`+$31`) reads its arguments from three variables in the SDK's own
RAM rather than from registers, and `uci_exec_block` (`+$07`) runs whatever is
in `uci_req`. Both live in the block laid out from `UCI_VARS` (see
`src/uci/uci_core.s`'s `.ifdef UCI_VARS` branch), not in the jump table or the
page-aligned parameter block above.

For the default build (`VARS=40704`, i.e. `UCI_VARS = $9F00`):

| Address | Name | Size |
|---|---|---|
| `$9F1A` | `uci_dec_target` | 1 |
| `$9F1B` | `uci_dec_ptr` | 2 |
| `$9F1D` | `uci_dec_len` | 1 |
| `$9F4E` | `uci_req` | `UCI_REQ_SIZE` (22) |
| `$9F64` | `ult_color` | 4 — index, r, g, b for `+$3D` |

A build with `VARS=` set to something else shifts all five by the same
amount: each is `UCI_VARS` plus the fixed offset above minus `$9F00`.

The DOS, file and REU entries need none of this: they read the parameter block
and move it into these variables themselves, which is the whole reason they take
a block rather than an address.

New variables are appended to the end of the block, never inserted, so the
addresses above do not move when the SDK grows.

## Loading it somewhere else

Build it at the address you want — that is free and has no runtime cost. If the
address is only known at run time, load `ultimate-<base>.reloc` alongside and
assemble `reloc.s` into your loader:

```asm
        lda #<$8000
        ldx #>$8000
        ldy #$10                ; pages to add, as a byte: $80 - $70
        jsr blob_relocate
```

The table is a little-endian count followed by that many 16-bit offsets, each
naming a byte that holds the high half of an absolute address. It is produced by
diffing two builds one page apart, so it cannot fall behind the assembler the
way a hand-written instruction table would. The default build has 704 such
offsets, a 1,410-byte table.

`tests/emulator/blob-relocated.suite` moves the blob to another address and then
compares the result byte for byte against a blob the linker built for that
address directly. A missing entry leaves a byte pointing back at where the blob
came from, and an entry that should not be there moves a byte that had to stay
put - a hardware register address, for instance. Either way the two builds stop
matching.
