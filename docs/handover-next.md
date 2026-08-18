# Handover: loose ends, and the boing ball

Written to be picked up cold, alongside [handover.md](handover.md). That file is
the state of the SDK; this one is what is left over from Phase 2 and what the
next interesting thing looks like.

Phases 1 and 2 are done and proven on hardware. `make basic-run` types at a real
C64 and passes 13/13 from the `.prg` and 13/13 from the `.crt`.

---

## 1. Loose ends

Ordered by how much they cost if ignored.

### ~~The cc65 side may print graphics glyphs~~ — confirmed, fixed

**It was a live bug. It is fixed and proven on hardware.** cc65 applies the c64
charmap to C string literals exactly as ca65 does: source `'A'-'Z'` becomes
PETSCII `$C1-$DA`, which CHROUT renders as *graphics symbols*, and source
`'a'-'z'` becomes `$41-$5A`, which renders as letters.

Confirmed in the built binary before touching anything — `"SOFTIEC"` assembled
to `d3 cf c6 d4 c9 c5 c3`, squarely in the glyph range — and then on the real
screen after the fix, which now reads `SOFTIEC : SOFTWARE IEC TARGET V1.0` in
letters.

Two files were affected, and only two: `examples/cc65/identify.c`'s six target
labels, and `ucitest.c`'s TAP `# SKIP` directive (now `# skip`; the directive is
case-insensitive and nothing parses it anyway — `hwtest.py` reads the result
block at `$033C` by DMA).

**`tools/test_charmap.py` now fails the build on any uppercase letter in a C
string literal**, across `examples/`, `tests/hardware/` and `include/`. It skips
comments — the files explain this rule in prose and the prose quotes the strings
it warns about — and allows `extern "C"`, which never reaches a character set.
Run against the pre-fix tree it names exactly the six labels and nothing else.

Two things that look like the same bug and are not:

- **`printf("%x")` is fine.** cc65's `_hextab` is the literal `"0123456789ABCDEF"`
  compiled for the target, so `A-F` really are `$C1-$C6` in the library — but
  `_printf.s` runs `_strlower` over the result for lowercase `%x`, and the CBM
  `ctype` table classifies `$C1-$DA` as upper case, so they come out `$41-$46`
  and display as letters. Do not "fix" this.
- **Wire strings are unaffected.** The Ultimate speaks ASCII; identification
  strings arrive as `$41-$5A` and display as letters already. `ascii_upper()`
  exists for the mixed-case model name and is still right.

Do not trust a decoder to check this. `tests/hardware/screen.py` deliberately
renders screen codes `$41-$5A` as `.`, which is what PETSCII `$C1-$DA` lands on,
so it is the one decoder that disagrees with the bug rather than agreeing with
it. That is what makes `hwtest.py --verbose` usable as the confirmation.

### `sdk.suite`'s comment about the charmap was half right

Already corrected in the file, but worth knowing the shape of the mistake: the
rule *"protocol bytes are emitted numerically and never touch the charmap"* is
right and still stands. The other half — *"display text goes through the charmap
and PETSCII is what you want"* — was wrong, and the suite asserted the wrong
bytes and called them correct, which is how it survived.

### The wedge is not covered by `make coverage`

`tools/gen_coverage.py` gates on SDK entry points with no test behind them. The
wedge's keywords are not in it, so a keyword could be added to
`gen_keywords.py`, tokenise, and dispatch to nothing without anything failing.
`basic.suite` covers the ones that exist today by hand.

### Carry preservation in `IGONE` has no emulator test

`wedge_gone` must hand `GONE3` the carry `CHRGET` left, because `GONE3` does
`sbc #endtk` with it. Getting this wrong dispatches every statement one token
low — `PRINT` runs as `PRINT#`. It is fixed and commented, and the only test
that would catch a regression is `make basic-run` typing `PRINT 2+3` at a real
machine, because the ROM path that exposes it ends in the direct-mode loop and
never returns to a test harness.

### Phase 3 will outgrow the `$C000` block

The resident wedge plus SDK is 3464 bytes of the 4K at `$C000`, so 632 are left. The design's §8
says Phase 3 pushes past it, at which point **the SDK alone** moves to `$A000`
under the BASIC ROM — which needs one shared trampoline, not banking discipline
throughout, because the SDK is never called by BASIC ROM. The wedge keeps
`$C000`. Relocation makes it a link-time choice.

### Two hardware facts worth keeping

- The bench Ultimate 64 Elite I **cannot be power cycled remotely**. Do not
  issue `PUT /v1/machine:reboot` casually; it takes the machine off the network
  for about 100 seconds and may need a hand. Never discover a REST API by
  looping PUTs over guessed endpoint names — `grep -rho "API_CALL(...)"` over
  `software/api/*.cc` in the firmware tree lists all 51 of them in one command.
- `Command Interface` is normally `Disabled` on that machine. Everything goes
  through `tools/u64_settings.py`, which reads first, writes only what is wrong,
  and restores only what it changed.

---

## 2. Turbo: built, and what it measured

**There is no UCI command for CPU speed** - the control target's full command
set is in `docs/generated/protocol-constants.md` and nothing in it touches
speed. Confirmed against the firmware, not inferred.

Turbo is plain memory-mapped I/O instead, documented at
<https://1541u-documentation.readthedocs.io/en/latest/config/turbo_mode.html>:

| Register | | |
|---|---|---|
| `$D031` | R/W | bits 0-3 speed index, bit 7 badlines off (0 = badlines on) |
| `$D030` | R/W | bit 0, in `Turbo Enable Bit` mode only. Write 1 to use the menu settings; read tells you whether turbo is on |
| `$D07A` / `$D07B` | W | SuperCPU-style normal / turbo speed select |
| `$D0BC` | R | SuperCPU detect, needs its own enable |

Three facts that shape the API:

- **Both registers read `$FF` when turbo is unavailable**, which makes
  availability testable rather than assumed. Availability means the Ultimate's
  `Turbo Control` setting is `U64 Turbo Registers` or `TurboEnable Bit` - a
  program cannot set that itself, so a demo shipping to other people must cope
  with turbo simply not being there.
- **The speed index is not portable above 4 MHz.** The U64's table is
  1,2,3,4,5,6,8..48 and the U64-II's is 1,2,3,4,6,8..64, so index 4 is 5 MHz on
  one machine and 6 MHz on the other. Only indices 0-3 mean the same thing on
  both.
- **Bit 7 disables badlines**, which is a real speed win for a demo and is worth
  exposing rather than hiding.

### Built, and proved on hardware

`src/uci/turbo.s`, in all three languages, plus the constants that were already
generated. The measured proof, from `make hardware-run`:

```
# work/frame: 2616 at 1mhz, 655 at 4mhz     <- 3.99x, on a fixed RAM-only loop
# work/frame: 2616 with badlines, 2452 without   <- 6.3% back from the VIC
```

The badline figure is worth keeping: 43 cycles on each of 25 character rows out
of a 17095-cycle frame predicts 6.3%, and the measurement says 6.3%, which is
two independent routes to the same number.

| | |
|---|---|
| `ultimate_turbo_available()` | 1 or 0, from `$D031` reading `$FF` |
| `ultimate_turbo_get()` | the index, or `U64_TURBO_UNAVAILABLE` — `$FF` is not a speed, the index is four bits |
| `ultimate_turbo_set(index)` | index 0-15; anything larger is refused rather than masked, and the badline bit is preserved |
| `ultimate_turbo_badlines(on)` | the other half of the register, and the speed is preserved |

BASIC gets one appended token, `$DB`, in both forms:

```basic
UTURBO 3 : IF UERR THEN PRINT "no turbo here"
PRINT UTURBO
```

and the blob gets `+$43`..`+$4C`.

Three things learned doing it, all of them things the next person would
otherwise re-derive:

- **The machine's speed table really is 1,2,3,4,5,6,8,10,12,14,16,20,24,32,40,48**
  — read off `/v1/configs/U64 Specific Settings/CPU Speed`, sixteen entries for
  sixteen indices. `Turbo Control` takes `Off`, `Manual`, `U64 Turbo Registers`
  or `TurboEnable Bit` — note that last one has no space, unlike what this file
  used to say.
- **`$D031` under sim6502 is ordinary RAM**, not a VIC returning `$FF` for its
  unimplemented registers. That is a fidelity gap, and it turns out to be the
  useful kind: the register can be put in any state from a suite, so the bit
  arithmetic — speed not clobbering badlines, badlines not clobbering speed — is
  proved exhaustively in the emulator, and only "the machine actually runs
  faster" needs hardware.
- **`src/basic/Makefile` had no dependency from its objects to the generated
  includes.** The keyword table lives in `wedge.o` and dispatch in
  `dispatch.o`; regenerating `uci_keywords.inc` rebuilt neither, so the first
  build with `UTURBO` shipped a wedge whose dispatcher knew the token and whose
  tokeniser did not. Fixed, and it would have bitten every future keyword.

### What is deliberately not built

**Badlines from BASIC.** `UTURBO` takes a speed and nothing else. The keyword
table is append-only and a token is a file format, but an *argument* is not:
`UTURBO speed, badlines` can be added later without a second token, which is
why there is no `UBADLINE` sitting in the table waiting.

**`$D030`'s TurboEnable Bit mode.** `U64_REG_TURBO_ENABLE` is generated and
nothing uses it. That mode takes its speed from the machine's own menu rather
than from a program, so there is no API to give it that the register does not
already have.

**Anything that claims to know megahertz.** The SDK passes the index through.
Above `U64_SPEED_4MHZ` the same index is a different speed on a U64 and a
U64-II, and a helper that pretended otherwise would be wrong on one of them.

## 3. The boing ball

The idea: recreate the Amiga's 1984 Boing Ball demo on a C64, using the Ultimate
for the parts a stock C64 cannot do.

**The rotation is colour cycling.** The original ball does not rotate — its
checkerboard is a fixed pattern whose palette is rotated, which reads as
spinning. That is the trick worth reproducing, and it is why the palette
commands matter.

### What the palette commands give us

Already in the protocol table, from the palette PR, marked `FW > 3.15`:

| | |
|---|---|
| `CTRL_CMD_GET_PALETTE` `$51` | read 48 bytes, 16 colours of RGB |
| `CTRL_CMD_SET_PALETTE` `$52` | write all 48 |
| `CTRL_CMD_SET_PALETTE_COLOR` `$53` | one colour: `<index> <r> <g> <b>` |
| `CTRL_CMD_RESET_PALETTE` `$54` | back to the built-in palette |

They affect the **live palette only** — not flash, not VPL files — which is
exactly right for a demo, and means a crash cannot leave the machine looking
wrong permanently.

From BASIC, today, with no new SDK code:

```basic
UCI UCTRL,$53,I,R,G,B      : REM one colour
UCI UCTRL,$54              : REM put it all back
```

### ~~The risk to measure first~~ — measured

**A UCI round trip is much cheaper than a frame.** `make time-run
U64_HOST=<ip>` builds `tests/hardware/ucitime.c`, runs it on the machine and
reads the numbers back by DMA. On the bench Ultimate 64 Elite, NTSC, CPU at
1MHz with turbo unavailable:

| Command | cycles | frames | per frame |
|---|---|---|---|
| `SET_PALETTE_COLOR` fire-and-forget | 1074 | 0.06 | 15.9 |
| `SET_PALETTE_COLOR` | 2096 | 0.12 | 8.2 |
| `SET_PALETTE`, all 16 colours, fire-and-forget | 3082 | 0.18 | 5.5 |
| `SET_PALETTE`, all 16 colours | 4105 | 0.24 | 4.2 |
| `DOS_CMD_ECHO` fire-and-forget | 1091 | 0.06 | 15.7 |
| `DOS_CMD_ECHO` | 2684 | 0.16 | 6.4 |
| `UCI_CMD_IDENTIFY` | 3780 | 0.22 | 4.5 |
| `GET_PALETTE`, 48 bytes back | 6328 | 0.37 | 2.7 |

**The one number: a whole-palette rotation costs a quarter of a frame.** Colour
cycling is not the constraint, so the first of the three outcomes below holds -
cycle directly, and the demo stays simple. Four rotations fit in a frame with
the screen on and interrupts off, which is three more than the demo needs.

Run to run the figures move by about 2%, and the third column is what to design
against, not the first.

Two things about the method, because they are what make the number trustworthy:

- **The frame length is measured, not assumed.** CIA #2's two timers chain into
  a 32-bit cycle counter, and the same counter times ten raster frames, so every
  result is a ratio of two figures off one clock - immune to PAL versus NTSC, to
  whatever the CIA is really clocked at on an Ultimate 64, and to the machine
  sitting in turbo. It reads 17091 against a textbook NTSC 17095, and the report
  prints both so a broken measurement looks broken.
- **Sync the raster *before* starting the timer.** The first version started it
  first, so the ten frames were really nine and a half: 16245 cycles, a number
  plausible enough to have been believed. The 5% gap against the textbook figure
  is what caught it.

`UCI_TARGET_NO_REPLY` is worth knowing about: it skips the data and status
phase and costs about half as much. Fine for a palette write, which has nothing
to say back.

**~~None of the palette commands is wrapped or tested.~~ All four are, now** —
`src/uci/palette.s`, and `make coverage` reports 13/101:

```c
uint8_t ultimate_palette_get(uint8_t *palette);          /* 48 bytes */
uint8_t ultimate_palette_set(const uint8_t *palette);
uint8_t ultimate_palette_set_color(uint8_t index, uint8_t r, uint8_t g, uint8_t b);
uint8_t ultimate_palette_reset(void);
```

Also on the blob's jump table at `+$37`..`+$40`, with `ult_color` at `$CF58` for
the four bytes `set_color` takes. Not in the BASIC wedge yet — that is a keyword,
and `gen_keywords.py` is append-only, so it is a deliberate decision rather than
an oversight.

Two things about how they are tested, because the split is the interesting part:

- **The simulator cannot cover them at all.** u64sim answers all four with
  `21,UNKNOWN COMMAND`. `sdk.suite` pins that on purpose — it is what a program
  meets on an older machine — plus the argument checks, which never reach the
  wire and so are fully provable there: a null buffer, colour 16, and colour 15
  still being accepted so the bound is proved off-by-one rather than
  "everything is rejected".
- **The hardware test is not decorative.** `ucitest.c` reads the live palette,
  changes one colour to a value it demonstrably did not have, reads it back,
  resets, writes the saved palette and compares — so the machine ends exactly
  as it started, and a write that silently did nothing still fails. It caught a
  real bug on its first run: `ultimate_palette_get` returned `48`, the reply
  length left in `A`, instead of `ULTIMATE_OK`. No emulator test could have
  reached that path, because u64sim never gets far enough to have a length.

**The bench machine's firmware string lies about the palette commands.** It
reports `firmware 3.15`, the palette four are annotated `FW > 3.15`, and they
work anyway — because it is running a post-tag build. The commit that added them
is `v3.15-68-g6b41404f`, and no release tag contains it. So the annotation is
right, the REST `firmware_version` field simply cannot tell a 3.15 dev build
from 3.15, and anything shipping to other people must probe rather than compare
version strings. `ucitime.c` probes with `GET_PALETTE` and skips the palette
measurements if it fails.

The measurements never change what is on screen, incidentally: the palette is
read first and written straight back, so this stays out of the destructive
bucket that `docs/handover.md` §6 puts palette writes in.

### Sprites versus hires

- **Sprite multiplexing** is the safer route: the ball is a sphere, sprites are
  cheap to move, and multiplexing is a solved problem at 1MHz. Turbo would only
  raise the sprite count.
- **Hires bitmap** needs turbo to redraw at speed. The registers are known now
  (§2), but turbo is a setting the user owns and a program cannot switch on for
  itself, so a demo that requires it is a demo that does not run everywhere.

Start with sprites. Turbo is an optimisation with a dependency on someone else's
settings menu, and the demo does not need it to exist. The bench machine reads
`$D031` as `$FF` right now, which is what turbo-unavailable looks like — see the
`make time-run` output.

### The shadow

The original has a soft shadow on the floor grid. On a C64 that is either a
second multiplexed sprite layer or a character-cell fudge. It is the detail
people remember, so it is worth the effort, but it is not what the Ultimate
buys — do it last.

---

## 4. Suggested order

1. ~~Confirm and fix the cc65 charmap bug.~~ **Done**, and `make test` now
   fails if it comes back.
2. ~~Measure a UCI round trip in frames.~~ **Done** — a whole-palette rotation
   is a quarter of a frame, so the demo's shape is the simple one. `make
   time-run U64_HOST=<ip>`.
3. ~~Wrap the palette commands and add `make coverage` entries.~~ **Done** —
   `src/uci/palette.s`, coverage 9/101 → 13/101. A `UPAL` wedge keyword is the
   obvious next sugar, and is not done.
4. ~~Build `turbo.s` and its three exposures.~~ **Done** — C, BASIC (`UTURBO`,
   token `$DB`) and the blob (`+$43`..`+$4C`), with the speed change measured
   against the raster on real hardware: 3.99x at index 3, and 6.3% back from
   turning badlines off.
5. Phase 3 proper: `dos.s`, `file.s`, the SoftwareIEC fast path, `reu.s`, and
   `ULOAD`/`USAVE`/`UDIR` in all three languages at once.

The boing ball is a good forcing function for Phase 3, incidentally: it needs to
load its own sprite data, which is exactly `ULOAD`.
