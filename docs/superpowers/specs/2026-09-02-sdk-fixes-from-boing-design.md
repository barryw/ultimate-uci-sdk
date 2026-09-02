# Four SDK fixes the Boing demo asked for

Date: 2026-09-02. Bench: Ultimate 64 Elite at 192.168.1.62, firmware 3.15,
core 1.4F, NTSC. Origin: `docs/handover-vsprites-boing.md`, "Two more SDK
findings", and the demo's own hand-copied blob offsets.

## Why

The Boing demo (`experiments/boing/`) works around four things the SDK
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
4. Its sample is assembled into the PRG in two pieces (`$aa00`, and `$e000`
   under the KERNAL) because 17 KB fits nowhere contiguous, then copied to
   the REU at start. `demos/pcm-visualizer` does the honest thing, `open`
   and `reu_load` straight into the REU, and pays for it with its own RIFF
   parser in C. Nothing in the SDK turns a sample file into a voice.

All four are the SDK's job. This spec fixes them in the SDK; the demos then
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

## A4. `ultimate_audio_load_wav`

### Contract

```
uint8_t ultimate_audio_load_wav(const char *name, uint32_t reuaddr,
                                ultimate_audio_voice *voice);
```

Opens `name`, walks the RIFF header, loads the `data` chunk into the REU at
`reuaddr` with `ultimate_reu_load` (no byte passes through the C64), closes
the file, and fills four fields of `voice`: `reu_address` = `reuaddr`,
`length` = the data chunk's byte count rounded down to even, `rate` =
`UA_RATE_CLOCK / sample rate` truncated, `flags` = `UA_CTRL_16BIT`, plus
`UA_CTRL_INTERLEAVE` for stereo. Every other field (`channel`, `volume`,
`pan`, `repeat_a`, `repeat_b`) is left as the caller had it; the caller ORs
`UA_CTRL_REPEAT` or `UA_CTRL_IRQ` into `flags` afterwards if it wants them,
then calls `ultimate_audio_configure` and `ultimate_audio_start`.

Stereo: the voice describes the left channel. The right channel is the same
voice with `reu_address + 2` and `length - 2`, one line the header documents,
which is what pcm-visualizer already does by hand.

`UA_RATE_CLOCK = 6250000` joins the protocol constants so the number lives
in one place.

### Accepted input

RIFF/WAVE, `fmt ` chunk with format 1 (PCM), 1 or 2 channels, 16 bits per
sample, any sample rate from 96 Hz up (below that the divider overflows 16
bits). Chunks before `data` other than `fmt ` are skipped; odd chunk sizes
are padded as RIFF requires; `data` without a preceding `fmt ` is an error.

8-bit WAV is refused. WAV stores 8-bit samples unsigned and the engine plays
them signed; correcting that means a pass through C64 RAM, which the whole
point of this function is to avoid. Host tooling writes 16-bit.

### Results

| Case | Result |
|---|---|
| `open` fails | the DOS result, as `ultimate_open` returned it |
| not RIFF/WAVE, chunk walk runs off the end, `data` before `fmt ` | `ULTIMATE_ERR_PROTOCOL` |
| format not 1, bits not 16, channels not 1 or 2, rate under 96 | `ULTIMATE_ERR_NOT_SUPPORTED` |
| `reu_load` fails (including no REU) | its result |
| success | `ULTIMATE_OK` |

The file is closed on every path. `voice` is written only on success.

### Placement

New module `src/uci/wav.s`, listed in `sources.mk`: `audio.s` stays the
register layer, and its header comment ("file streaming is composed from it
and the DOS/REU services by the application") is updated to point here. The
header parse uses the SDK's 40-byte staging area (`ult_stage`), reading the
12-byte RIFF header, then 8-byte chunk headers, then 16 bytes of `fmt `, so
no caller buffer. One 24-by-16-bit division routine for the divider.

Blob: entry `audio_load_wav` appended, `bp_name` = path, `bp_reu` = REU
address, fills `bp_audio`, result in `bp_result`. cc65: wrapper with three
arguments on the cc65 stack, as `ultimate_reu_stash` already does.

### Tests

- Emulator: `tests/emulator/fixtures/usb0` gains four small files written by
  a script under `tools/` (not committed as binaries by hand): a 16-bit mono
  WAV at 8,000 Hz, a 16-bit stereo WAV, an 8-bit WAV, and a file that is
  not RIFF. `sdk.suite` and `blob.suite` cases assert the voice fields
  (`rate` = 781 for 8,000 Hz, `length`, `flags`) and the result codes for
  each, and that a missing file returns the DOS error. `reu_load` already
  runs in the emulator.
- Hardware: the Boing demo plays its `boing.wav`; `ucitest.c` gains no case,
  the demo is the hardware test for this.

### Consumers

Boing, in its migration. `demos/pcm-visualizer` keeps its parser for now: it
streams 1 MiB windows of one file with `seek` and `reu_load`, which this
function does not do. Retiring that parser is a later pass, out of scope.

## Order of work

A3 first (it changes generated files every later step assembles against),
then A2, then A1 with its hardware verification, then A4. Each is one
commit. The vsprites demo edit rides with A3 and A2; the Boing edits belong
to the multiplexer spec's migration step.
