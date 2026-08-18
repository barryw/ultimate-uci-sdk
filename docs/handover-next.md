# Handover: loose ends, and the boing ball

Written to be picked up cold, alongside [handover.md](handover.md). That file is
the state of the SDK; this one is what is left over from Phase 2 and what the
next interesting thing looks like.

Phases 1 and 2 are done and proven on hardware. `make basic-run` types at a real
C64 and passes 8/8 from the `.prg` and 8/8 from the `.crt`.

---

## 1. Loose ends

Ordered by how much they cost if ignored.

### The cc65 side may print graphics glyphs

**Almost certainly a live bug, not yet confirmed.** ca65's c64 charmap sends
source `'A'-'Z'` to PETSCII `$C1-$DA`, and CHROUT renders those as *graphics
symbols*, not letters. Source `'a'-'z'` becomes `$41-$5A` and displays as
letters.

This was fixed in `src/uci/ultimate_strerror.s` and `examples/asm/identify.s`
after a photograph of a real screen showed the wedge's banner as a row of
glyphs. **cc65 applies the same charmap to C string literals**, so
`examples/cc65/` and `tests/hardware/ucitest.c` are very likely printing the
same garbage.

- It costs nothing functionally: `ucitest.c` publishes its results to `$033C`
  and `hwtest.py` reads them by DMA, so the hardware suite passes either way.
- It costs a first impression: the examples are what someone reads first.

To check: build, run on hardware, look at the screen. Do not trust a decoder —
`tests/hardware/screen.py` deliberately renders `$41-$5A` as `.` for exactly
this reason, and any decoder that maps them back to letters agrees with the bug
instead of finding it.

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

The resident wedge plus SDK is 3159 bytes of the 4K at `$C000`. The design's §8
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

## 2. Turbo: what is actually there

**There is no UCI command for CPU speed.** The control target's full command set
is in `docs/generated/protocol-constants.md` and nothing in it touches speed.
Confirmed against the firmware, not inferred.

What exists instead:

- The U64 has turbo hardware. `software/u64/u64_config.cc` offers speeds up to
  **48× on the U64 and 64× on the U64-II**.
- It is gated by a setting, `Turbo Settings → Turbo Control`, whose options are
  `Off`, `Manual`, `U64 Turbo Registers`, `TurboEnable Bit`. Only some of those
  let a running C64 program change its own speed.
- The firmware side is `C64_TURBOREGS_EN` and `C64_SPEED_PREFER`.

**Unknown, and deliberately not guessed:** the address a C64 program writes to
set the speed when `U64 Turbo Registers` is selected. The config plumbing was
found; the C64-visible register was not. Look in the FPGA sources or the U64
manual before writing a line of demo code that depends on it.

Three ways forward, in increasing order of effort:

1. **Require the setting.** The demo documents that `Turbo Control` must be set,
   and pokes the register directly. No SDK change; the SDK's rule that services
   never touch hardware would make this demo code, not SDK code — the same
   exception `reu.s` gets in Phase 3.
2. **Add a UCI control command upstream.** Exactly the shape of the palette PR:
   a new command on target `$04` that sets speed, so a program can ask for turbo
   without the user having pre-configured anything. This is the clean answer and
   it is a firmware PR, not an SDK one.
3. **Do not use turbo.** A boing ball is comfortably achievable at 1MHz with
   sprite multiplexing. Turbo buys resolution, not feasibility.

---

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

### The risk to measure first

**Nobody has timed a UCI round trip against a frame.** Colour cycling wants a
palette write every frame or two — 50Hz. Every UCI command is a handshake:
write the bytes, push, poll for BUSY to clear, read the status. `uci_exec`
budgets `UCI_TIMEOUT_DEFAULT` (200 units of 256 polls) for that.

Measure before designing around it. `SET_PALETTE_COLOR` is six bytes on the
wire, so it is the cheapest possible command, but the round trip is the round
trip. Three outcomes:

- Fast enough per frame → cycle directly, and the demo is simple.
- Fast enough only every few frames → cycle more slowly, which the original's
  rotation speed may tolerate anyway.
- Too slow → cycle the C64's own colour registers for the ball and use the
  Ultimate's palette to shift what those registers *mean*, which is one write
  per several frames.

**None of the palette commands is wrapped or tested.** `make coverage` reports
9/101 wrapped; the palette four are reachable through the generic form only.
Wrapping them is small and would earn `ULOAD`-style sugar in the wedge.

### Sprites versus hires

- **Sprite multiplexing** is the safer route: the ball is a sphere, sprites are
  cheap to move, and multiplexing is a solved problem at 1MHz. Turbo would only
  raise the sprite count.
- **Hires bitmap** needs turbo to redraw at speed, which needs the register that
  has not been found yet.

Start with sprites. Turbo is an optimisation with an unresolved dependency, and
the demo does not need it to exist.

### The shadow

The original has a soft shadow on the floor grid. On a C64 that is either a
second multiplexed sprite layer or a character-cell fudge. It is the detail
people remember, so it is worth the effort, but it is not what the Ultimate
buys — do it last.

---

## 4. Suggested order

1. Confirm and fix the cc65 charmap bug. Small, and it is the first thing a
   newcomer sees.
2. Measure a UCI round trip in frames. One number, and it decides the demo's
   whole shape.
3. Wrap the palette commands and add `make coverage` entries.
4. Find the turbo register, or decide the demo does not need it.
5. Phase 3 proper: `dos.s`, `file.s`, the SoftwareIEC fast path, `reu.s`, and
   `ULOAD`/`USAVE`/`UDIR` in all three languages at once.

The boing ball is a good forcing function for Phase 3, incidentally: it needs to
load its own sprite data, which is exactly `ULOAD`.
