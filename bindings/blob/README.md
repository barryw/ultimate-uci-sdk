# The SDK as a standalone binary

Toolchains cannot link each other's objects. This is the same SDK, linked
standalone with a jump table at its base, so anything that can `jsr` an address
can use it — with no linking at all.

    make -C bindings/blob                 # build/ultimate-8000.bin at $8000
    make -C bindings/blob BASE=c000       # at $C000 - no longer big enough
    make -C bindings/blob BASE=6000 VARS=32512 ZP=163

The default build is 4,560 bytes: the 256-byte jump table page and the
512-byte parameter block, fixed at those sizes so every offset below holds
regardless of how little of them is used, plus the code itself.

**The default is the 8K at `$8000`, not the 4K at `$C000`.** It was `$C000`
until `file.s` landed and the code overflowed the block by 350 bytes.
`$8000-$9FFF` is RAM with nothing mapped over it, so a caller reaches every byte
with the machine exactly as it found it - which is the difference between the
blob and the BASIC wedge, whose SDK sits at `$A000` under BASIC ROM and pays a
stub per call for it. A wedge can bank because it is the only thing calling; a
blob's caller cannot be asked to.

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
| `+$28` | `ultimate_get_model` | | `A` = result |
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

The DOS and file services are in the binary and reachable by symbol from a ca65
link, but are **not on the jump table yet** — a blob caller cannot pass a
filename in `A`/`X` alone, and giving them table entries before the parameter
block carries their arguments would fix the wrong contract for ever.

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
page-aligned parameter block above.

For the default build (`VARS=40704`, i.e. `UCI_VARS = $9F00`):

| Address | Name | Size |
|---|---|---|
| `$9F0E` | `uci_dec_target` | 1 |
| `$9F0F` | `uci_dec_ptr` | 2 |
| `$9F11` | `uci_dec_len` | 1 |
| `$9F42` | `uci_req` | `UCI_REQ_SIZE` (22) |
| `$9F58` | `ult_color` | 4 — index, r, g, b for `+$3D` |

A build with `VARS=` set to something else shifts all five by the same
amount: each is `UCI_VARS` plus the fixed offset above minus `$9F00`.

New variables are appended to the end of the block, never inserted, so the
addresses above do not move when the SDK grows.

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
way a hand-written instruction table would. The default build has 190 such
offsets, a 382-byte table.

`tests/emulator/blob-relocated.suite` moves the blob and then erases the
original before calling it, which is what turns a missing relocation entry into
a failure rather than an accidental pass.
