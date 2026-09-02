# Three SDK fixes the Boing demo asked for

Date: 2026-09-02. Bench: Ultimate 64 Elite at 192.168.1.62, firmware 3.15,
core 1.4F, NTSC. Origin: `docs/handover-vsprites-boing.md`, "Two more SDK
findings", and the demo's own hand-copied blob offsets.

## Why

The Boing demo (`experiments/boing/`) works around three things the SDK
should do for it:

1. It brackets `audio_configure` with a millisecond of settling on each
   side, and stops the engine before the first configure, because
   reprogramming a running Ultimate Audio channel without a pause leaves it
   playing noise. Three fresh launches in a row are clean with the bracket
   and intermittently static without it.
2. It writes `cmp #0` after every blob call that returns a byte, because the
   entry points end in `ldx #$00` and `beq` would test X.
3. It hand-copies jump table offsets (`BLOB + $2e8`) and parameter block
   offsets (`BP + $19a`) out of `bindings/blob/README.md`. So does
   `demos/vsprites`. A typo there is a wrong address nothing checks.

All three are the SDK's job. This spec fixes them in the SDK; the demos then
delete their workarounds.

## A1. `ultimate_audio_configure` settles

### Behaviour

After validation passes and the engine is known to be up, configure does, in
order:

1. control register = 0 (stop the channel, as now);
2. settle;
3. write volume, pan, start, length, rate, repeat A, repeat B, IRQ clear (as
   now);
4. settle;
5. control register = the caller's flags with the gate clear (as now).

`ultimate_audio_start` and `ultimate_audio_stop` stay immediate. Configure is
the documented safe path to re-arm a channel: stop, then configure, then start.

### Settle

1,024 reads of `$D012`, the loop the demo proved on the bench:

```
        ldx #$00
        ldy #$04
@loop:  lda $D012
        inx
        bne @loop
        dey
        bne @loop
```

I/O reads run at 1 MHz under Ultimate 64 turbo, so the loop takes about one
millisecond at 48 MHz and about nine at stock speed. Either is enough; the
requirement is "at least a millisecond". The loop lives in `audio.s` as a
local routine, not a public entry.

### Cost and callers

Configure now takes about two milliseconds under turbo. Every caller in the
tree was checked:

- `demos/pcm-visualizer` configures the two voices of a pair once per 1 MiB
  buffer swap; four milliseconds per swap is nothing against the buffer.
- `tests/hardware/ucitest.c` configures twice in the audio scenario.
- The Boing demo configures once per bounce, from the vblank interrupt, and
  today pays the same two settles itself.

### Documentation

`include/ultimate.h`, the `ultimate_audio_configure` comment: state the two
settles, why (a running channel reprogrammed without a pause plays noise), and
that stop and start are immediate. `bindings/blob/README.md`, the
`audio_configure` row: "about 2 ms; stops the channel first". `docs/uci.md`
has no audio section and gets none; the header is the audio contract.

### Verification

- `make -C tests/emulator run`: unchanged, the emulator has no audio block and
  configure returns `NOT_SUPPORTED` before the settle.
- `make hardware-run U64_HOST=192.168.1.62`: the audio scenario passes; the
  ten pre-existing failures on this bench are unchanged.
- Boing: `audio_settle` deleted, the init `AUDIO_STOP` deleted, three fresh
  launches with sound clean on every bounce.

## A2. Byte results set the flags

### The rule

New line in `docs/asm-abi.md`, in the calling convention table: **a byte
result in `A` leaves N and Z set from `A`**, so `jsr entry` followed by
`beq`/`bne`/`bmi` tests the result. Results that occupy `A` and `X` (16-bit
values such as `ultimate_reu_size`) carry no such promise: test both bytes.
The blob README repeats the rule once, above its jump table, because blob
callers are the ones who cannot read the source.

### The change

Every return in `src/uci/*.s` that ends `<load A>` / `ldx #$00` / `rts`
becomes `ldx #$00` / `<load A>` / `rts`. About 130 sites; roughly 100 are
`lda #constant` or `lda variable` and are swapped by a script that is run once
and not kept, the rest by hand:

- `pla` / `ldx #$00` / `rts` becomes `ldx #$00` / `pla` / `rts` (`pla` sets
  N and Z).
- `txa` / `ldx #$00` / `rts` becomes `txa` / `ldx #$00` / `ora #$00` / `rts`
  (X cannot be loaded first without destroying the value).
- `jsr tail` / `ldx #$00` / `rts`: the tail already ends in the pattern, so
  the trailing `ldx #$00` after the `jsr` is deleted where the tail sets X,
  otherwise the `ora #$00` form.
- `and #mask` / `ldx #$00` / `rts` becomes `ldx #$00` / `and #mask` / `rts`
  when the operand does not use X; otherwise the `ora #$00` form.

`ldx #$00` stays: cc65 wants X clear for a promoted byte, and the blob table
documents `A`/`X` pairs.

### Test

`tests/emulator/harness.s` gets one routine, `t_flags`, that calls an entry
whose address the suite poked, then `php` / `pla` and stores the status byte.
`sdk.suite` and `blob.suite` each get cases asserting the Z bit for:

- `ultimate_reu_available` returning 0 (absent suite) and 1;
- `ultimate_audio_available` returning 0;
- `ultimate_init` returning `ULTIMATE_OK` (Z set) and, in `absent.suite`,
  `ULTIMATE_ERR_NO_DEVICE` (Z clear).

Both harness builds (`harness` and `harness-placed`) run them, as every suite.

### Demos

`experiments/boing/boing.asm` and `demos/vsprites/vsprites.asm` drop the
`cmp #0` after `TURBO_AVAIL` and `AUDIO_INIT`. The Boing migration in the
multiplexer spec does the Boing edit; the vsprites edit is part of this spec.

## A3. Generated blob offsets

### What is generated

`tools/gen_protocol.py` gains a reader for `bindings/blob/blob.s` and two new
constant groups, emitted into the three assembler includes only
(`bindings/asm/uci_protocol.inc`, `bindings/kickass/uci_protocol.asm`,
`bindings/acme/uci_protocol.a`). C programs link the library and have no use
for the table, so `include/uci_protocol.h` and the generated Markdown are
unchanged.

**Group "Blob jump table".** One constant per `jmp target ; +$NN` line in the
blob header, offset from the blob's base:

```
BLOB_UCI_INIT            = $04
BLOB_ULTIMATE_INIT       = $1C
BLOB_TURBO_AVAILABLE     = $43
BLOB_AUDIO_CONFIGURE     = $2F1
```

Name rule: the `jmp` target with a leading `blob_` removed, upper-cased,
prefixed `BLOB_`. `blob_audio_configure` becomes `BLOB_AUDIO_CONFIGURE`;
`ultimate_audio_init` becomes `BLOB_ULTIMATE_AUDIO_INIT`. The rule matches
the names the README table already uses, so a reader can move between the
two.

**Group "Blob parameter block".** `BLOB_PARAMS = $100`, then one constant per
`bp_*` field, offset from the blob's base (the parameter page folded in, so a
KickAssembler program writes `sta BLOB + uci.BLOB_BP_AUDIO`):

```
BLOB_PARAMS              = $100
BLOB_BP_RESULT           = $100
BLOB_BP_ADDR             = $103
BLOB_BP_AUDIO            = $29A
```

### Source of truth

`blob.s` is the truth for both groups, read at generation time with the same
two regular expressions `tools/test_blob_table.py` uses today. The
expressions move into `gen_protocol.py` and the test imports them, so there
is one parser. The README table stays hand-written and the existing test
keeps it in step with `blob.s`; the generated constants cannot drift from
`blob.s` because they are read from it.

`make protocol` regenerates. `tools/test_gen_protocol.py` gets a case that
generates the KickAssembler include and asserts `BLOB_ULTIMATE_INIT = $1C`,
`BLOB_BP_RESULT = $100`, and that every `jmp` in `blob.s` has a constant.

### Consumers

`experiments/boing/boing.asm` (in its migration) and `demos/vsprites/
vsprites.asm` (here) replace their `.const` blocks with `uci.BLOB_*` names;
each keeps one `.const BLOB = $8000` (or `$7000`) for the base.

## Order of work

A3 first (it changes generated files every later step assembles against),
then A2, then A1 with its hardware verification. Each is one commit. The
vsprites demo edit rides with A3 and A2; the Boing edits belong to the
multiplexer spec's migration step.
