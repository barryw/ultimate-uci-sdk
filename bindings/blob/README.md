# The SDK as a standalone binary

Toolchains cannot link each other's objects. This is the same SDK, linked
standalone with a jump table at its base, so anything that can `jsr` an address
can use it — with no linking at all.

    make -C bindings/blob                 # build/ultimate-c000.bin at $C000
    make -C bindings/blob BASE=a000       # at $A000
    make -C bindings/blob BASE=8000 VARS=49152 ZP=163

The default build is 2,860 bytes: the 256-byte jump table page and the
512-byte parameter block, fixed at those sizes so every offset below holds
regardless of how little of them is used, plus the code itself.

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
| `+$28` | `ultimate_get_model` | | `A` = result |
| `+$2B` | `ultimate_strerror` | `A` = result code | `A`/`X` = PETSCII text |
| `+$2E` | `uci_req_clear` | | zeroes the request block at `uci_req` |
| `+$31` | `uci_decode` | `uci_dec_target`/`uci_dec_ptr`/`uci_dec_len` | `A` = result |
| `+$34` | `uci_status_fmt` | `A` = target | `A` = `UCI_STATUS_FMT_*` |

The signature is checked before calling anything:

```asm
        lda $C000
        cmp #$D5                ; 'U' in PETSCII - the blob is built with the
        bne no_sdk              ; c64 charmap, like everything else on screen
```

## The parameter block

At `base+$100`, page-aligned so a BASIC program needs no address arithmetic.

| Offset | | Size |
|---|---|---|
| `+$00` | result | 1 |
| `+$01` | raw device code | 2 |
| `+$03` | address argument | 2 |
| `+$05` | length argument | 2 |
| `+$07` | end address after a load | 2 |
| `+$09` | status string | 32 |
| `+$29` | filename | 40 |
| `+$51` | reply buffer | 256 |

## The SDK's variable block

`uci_decode` (`+$31`) reads its arguments from three variables in the SDK's own
RAM rather than from registers, and `uci_exec_block` (`+$07`) runs whatever is
in `uci_req`. Both live in the block laid out from `UCI_VARS` (see
`src/uci/uci_core.s`'s `.ifdef UCI_VARS` branch), not in the jump table or the
page-aligned parameter block above. For the default build (`VARS=52992`, i.e.
`UCI_VARS = $CF00`):

| Address | Name | Size |
|---|---|---|
| `$CF0E` | `uci_dec_target` | 1 |
| `$CF0F` | `uci_dec_ptr` | 2 |
| `$CF11` | `uci_dec_len` | 1 |
| `$CF42` | `uci_req` | `UCI_REQ_SIZE` (22) |

A build with `VARS=` set to something else shifts all four by the same
amount: each is `UCI_VARS` plus the fixed offset above minus `$CF00`.

## Loading it somewhere else

Build it at the address you want — that is free and has no runtime cost. If the
address is only known at run time, load `ultimate-<base>.reloc` alongside and
assemble `reloc.s` into your loader:

```asm
        lda #<$8000
        ldx #>$8000
        ldy #$C0                ; pages to add, as a byte: $80 - $C0
        jsr blob_relocate
```

The table is a little-endian count followed by that many 16-bit offsets, each
naming a byte that holds the high half of an absolute address. It is produced by
diffing two builds one page apart, so it cannot fall behind the assembler the
way a hand-written instruction table would. The default build has 89 such
offsets, a 180-byte table.

`tests/emulator/blob-relocated.suite` moves the blob and then erases the
original before calling it, which is what turns a missing relocation entry into
a failure rather than an accidental pass.
