# Software sprites under Ultimate 64 turbo: findings and design

Date: 2026-09-01. Machine: Ultimate 64 Elite, firmware 3.15, core 1.4F, NTSC,
Turbo Control = "U64 Turbo Registers". Experiment code: `experiments/bobs/`.

## Question

Can the 6510 at 48 MHz (64 MHz on the Commodore 64 Ultimate) do what the Amiga's
blitter does for bobs: masked rectangles drawn into a bitmap playfield, any
number of them, any size, restored and redrawn every frame?

## Answer

Yes, comfortably, and the speed-up is linear: no wait states on RAM.

| bob size (multicolour) | bytes blitted per bob | 1 MHz | 4 MHz | 8 MHz | 24 MHz | 48 MHz |
|---|---|---|---|---|---|---|
| 16 px x 16 lines (32x16 hires) | 80 draw + 120 restore | 6,250 us | 1,490 | 748 | 250 | 127 |
| 16 px x 32 lines (32x32 hires) | 160 draw + 200 restore | 10,950 us | 2,560 | 1,280 | 427 | 218 |

Bobs per frame at 60 fps (NTSC, 16.7 ms), badlines off, nothing else running:

| MHz | 16-line bobs | 32-line bobs |
|---|---|---|
| 1 | 2 | 1 |
| 4 | 11 | 6 |
| 8 | 22 | 13 |
| 24 | 64 | 39 |
| 48 | 128 | 76 |

PAL gets 17% more (19,656 cycles per frame against 17,092). The 64 MHz machine
should get a third more again; not measured.

The per-bob cost is one of 6,250 6510 cycles at every speed, which is the number
to design against: the machine simply supplies 48 times more of them.

## What was measured, exactly

- **CIA timers count at 1 MHz whatever the CPU speed.** A frame is 17,092 CIA
  cycles at every speed index, and render time in CIA cycles agrees with the
  frame counter against wall-clock. So CIA cycles are microseconds under turbo.
- **Badlines cost the same microseconds at every speed.** The VIC steals about
  1 ms per frame (25 badlines x 40 us) whether the CPU runs at 1 or 48 MHz. At
  48 MHz that is 48,000 cycles, 6% of the frame, and `$D031` bit 7 gives it
  back: 128 bobs fit at 60 fps with badlines off and drop to 30 fps with them
  on. A blitter should set bit 7 while it draws.
- **REU DMA is not a blitter.** Copying 4,096 bytes:

  | | 1 MHz | 48 MHz |
  |---|---|---|
  | REU stash (C64 to REU) | 4,161 us | 816 us |
  | REU fetch (REU to C64) | 4,489 us | 1,198 us |
  | CPU, unrolled `lda/sta abs,x` | 41,415 us | 823 us |

  Under turbo the REU DMA runs about five times faster than stock, and the CPU
  is as fast as a stash and faster than a fetch. Bob images belong in main RAM
  for drawing; the REU is storage, and a 4 KB fetch costs 7% of a frame.
- **I/O stays at 1 MHz.** The blit touches no I/O, so it pays nothing. A flip is
  two register writes.
- **The blit output is byte-exact.** Every build was checked in VICE against a
  Python reference blit (`experiments/bobs/vicecheck.py`), including a 128-bob
  frame, before it ran on hardware.

## How the experiment draws

- Multicolour bitmap, 160x200, four colours: `$D021` plus three fixed for the
  whole playfield (screen RAM and colour RAM are filled once and never
  touched). Bobs are three colours plus transparent. No colour clash, because
  there is no per-cell colour.
- Double-buffered across two VIC banks: screen `$5C00` and bitmap `$6000`,
  screen `$8000` and bitmap `$A000`. The flip is one write each to `$DD00` and
  `$D018` after the raster passes line 250.
- A clean copy of the background at `$E000`, under the KERNAL, with `$01 = $35`.
  Every bitmap and the clean copy share a layout, so restore is a copy at a
  constant address offset (the two high bytes differ, the low bytes match).
- Per frame, into the back buffer: restore every rectangle drawn there two
  frames ago, move, then draw. Draw is `D = (D AND mask) OR image`, the Amiga
  minterm for a bob, 25 cycles per byte with self-modified absolute,X operands.
- Images are column-major and pre-shifted four ways (one per multicolour pixel
  of X), 5 bytes wide, followed by their mask. A 16-line shape is 640 bytes for
  all four shifts, a 32-line one 1,280.
- Addressing trick that makes one index register walk image, mask and
  destination together: for a bob at (x, y), row r of column c is at
  `BUF + y + (x>>2)*8 + cellrow*312 + c*8 + r` within one cell row, so each
  cell-row segment is a contiguous run and only the base is re-patched.

Memory: code, tables and four shapes end at `$2D6F` (16-line) or `$376F`
(32-line), under the REST runner's 16 KB load limit. `$3400-$5AFF` is left for
the SDK blob, `$C000-$CFFF` and the spare RAM above screen B are free.

## Proposed SDK shape (not built yet, per instruction)

Two layers, the second built on the first, following the steer that a blitter
should also do vsprites and that vsprites should own the vblank wait.

**Blitter** (`blit_*`): RAM-resident, turbo-agnostic, useful at any speed.

- `blit_target(bitmap)`: which bitmap subsequent blits write.
- `blit_copy(src_bitmap, cell_x, cell_y, cells_w, cells_h)`: cell-aligned
  rectangle from one bitmap to another. The restore primitive.
- `blit_masked(image, x, y)`: masked draw of a pre-shifted image at any pixel
  position. The bob primitive.
- `blit_shift(image_in, image_out)`: build the four shifted copies plus masks
  from one unshifted image at init, so a program ships one copy per shape.
- Image header carries width in bytes and height in lines; the experiment's
  5x16 and 5x32 become two cases of one routine.

**Vsprites** (`vsprite_*`): the Amiga bob list.

- `vsprite_init(bank_a, bank_b, clean)`: sets up the two banks, the clean copy,
  the four-colour palette, and turns badlines off while it draws.
- `vsprite_set(id, image, x, y)`, `vsprite_hide(id)`: state only, no drawing.
- `vsprite_update()`: restore, draw in id order (id is priority), **wait for
  vblank, flip**. The caller never touches the raster. Returns the render time
  in CIA cycles so a game can budget.
- Hardware sprites are untouched and layer on top.

Constraints to state in the docs: the blitter is self-modifying and must live
in RAM (the cartridge-ROM rule that `turbo.s` follows does not apply; an
indirect-addressing variant would cost about 15%). One palette per playfield.
Y order equals draw order. At 48 MHz, 100 16-line bobs leave a fifth of the
frame for everything else.

## Colour: what the VIC allows, and what each option costs

Multicolour bitmap gives every 4x8-pixel cell four colours: bit pair 00 is
`$D021` for the whole screen, 01 and 10 are the two nibbles of that cell's
screen RAM byte, 11 is its colour RAM nibble. That is the limit; the demo
modes below (`experiments/bobs`, `bobtest.py --mode N`) show what can be done
inside it. All measured on the Elite at 48 MHz, badlines off, 32-line bobs.

| mode | what | cost | seen on hardware |
|---|---|---|---|
| 0 | one palette for the playfield: three colours, every bob the same | none | 76 bobs at 60 fps |
| 1 | per-bob 01/10 written into screen RAM cells under the bob; 11 shared (white) | ~15 cell writes and restores per bob, RAM speed, double-buffered with the bank | 48 bobs at 60 fps, 11.5 ms of 16.7 |
| 2 | mode 1 plus per-bob 11 in colour RAM, applied after the flip inside the non-display lines | up to 15 I/O writes per bob, twice (clear old, set new), single-buffered | 48 bobs at 60 fps, no visible tearing |
| 3 | mode 1 plus eight expanded hardware sprites, one exact colour each | nil to the blitter | 48 bobs + 8 sprites at 60 fps |
| 4 | dithered shapes: checkerboards of 1/2 and 2/3 give five apparent shades | none, it is image data | 40 bobs at 60 fps |
| 5 | palette animation through the SDK blob | one UCI round trip per update | not on this firmware, see below |

Mode 1 is the SDK default to propose: the background must use only 00 and 11
in cells a bob can cross (stars on black here), and where two bobs share a
cell the later one owns its colours. Classic attribute clash, and it looks
fine in motion. Mode 2 is for a handful of hero objects, not a crowd: at 128
bobs the colour RAM writes alone would exceed the non-display window.

**Palette commands are not in firmware 3.15.** The Elite answers
`21,UNKNOWN COMMAND` (`ULTIMATE_ERR_NOT_SUPPORTED`) to `CTRL_CMD_GET_PALETTE`
at every CPU speed. Mode 5 waits for the firmware PR.

## SDK transport bug, found and fixed

Entering mode 5 (`ultimate_init` then `ultimate_palette_get`) returned
`ULTIMATE_ERR_PROTOCOL` (3) at 10 MHz and above, and the firmware's honest
`21,UNKNOWN COMMAND` (4) at 8 MHz and below. Root cause, from
`command_protocol.vhd` and the firmware's `command_intf.cc`: writing the abort
bit sets status bit 2 (`ABORT_P`), which only the firmware clears, and it does
so with `HANDSHAKE_RESET`: state forced idle and the command pointer rewound.
`uci_abort()` waited only for the state to be idle, which on a fresh machine it
already is, so `uci_init()` returned before the abort was serviced and the
next command was wiped by the reset. Fix: `uci_abort()` polls until both the
state and `ABORT_P` are clear. `tests/emulator/abort-latency.suite` reproduces
the race with a slow simulated firmware (fails before, passes after);
`tests/hardware/ucitest.c` sends a known-rejected command first thing after
init, at 1 MHz and at the top turbo index. On the Elite, same source with only
the abort wait reverted: code 3 at 48 MHz three times out of three (and once
at 8 MHz); with the wait: 4 every time, mode 5 entry included.

An earlier reading that "the first command after init gets `00,OK`" was an
artifact of the probe routine in `bobs.asm` (a branch sent those probe kinds
through identify); it is corrected here and in the code comments.

## Delivered on 2026-09-02

- **`demos/vsprites/`**: the mode-0 look (grid, grey outlines, light blue
  bodies, white highlights) as an SDK demo. It uses the blob's
  `ultimate_turbo_available`, `ultimate_turbo_set(U64_SPEED_MAX)` and
  `ultimate_turbo_badlines(0)`, then adds a bob whenever the last frame used
  under three quarters of the raster period and removes one above seven
  eighths. On the Elite it settles at 60 bobs at 60 fps with the frame 76%
  full; in VICE at 1 MHz it holds one or two. Two lessons from building it:
  `ultimate_turbo_available` (and the other one-byte entry points) return with
  Z set by their trailing `ldx #0`, so test A with `cmp #0`; and the second
  buffer must not live in VIC bank 2 with its screen in `$9000-$9FFF`, where
  the VIC reads the character ROM instead of RAM. RAM readback hides that; the
  display flickers glyph colours every other frame. The demo keeps buffer A in
  bank 1 and buffer B in bank 3 (`$C000` screen, `$E000` bitmap).
- **`experiments/boing/`**: the Amiga Boing ball out of hardware sprites,
  verified in VICE and running on the Elite. Ball = 2 columns x 4 rows of
  X-expanded hires sprites, each position a white sprite and a red sprite
  overlaid, so 16 sprites a frame from 8: sprites 0-3 draw rows 0 and 2,
  sprites 4-7 rows 1 and 3, with raster IRQs at `y+22` and `y+43` moving them
  down and one at line 250 applying the next frame. 16 rotation frames over 90
  degrees rendered by `genball.py` (8 x 8 checker on a sphere, axis tilted 17
  degrees); only the white layer is stored (8 KB), red is `disc AND NOT white`
  built each frame into a double-buffered live set (12 ms at 1 MHz, so a
  stock C64 runs it). PRG 9,985 bytes. Missing: shadow (a bob for the
  blitter), sound, perspective floor. **The row multiplexer is the SDK
  candidate**: a fixed grid of sprite rows reused down the screen is a much
  smaller thing than a general Y-sorting multiplexer, and it is all this needs.

## Bench notes

- The VIC video stream (`PUT /v1/streams/video:start`) could not reach a Mac on
  Wi-Fi: unicast fails ARP on the Ultimate's interface 0, multicast and
  broadcast never arrive. Frames were read back with `machine:readmem` and
  rendered in Python instead (`experiments/bobs/render.py`).
- **REST reads during a measurement perturb the CIA count.** At 1 MHz, a
  0.6 s render polled every 50 ms reported 4,968 us per bob; unpolled it
  reported 10,935, linear with VICE. Do not poll while timing.
- `hwtest`-style control block at `$033C`; layout documented at the top of
  `bobs.asm`. `bobtest.py --sweep` reproduces every table above in about two
  minutes per build; `--mode N` switches colour mode; `--attach` keeps the
  running demo; `--png` freezes a frame (pause byte) and renders it with the
  cell colours and hardware sprites read back.
- The REST `run_prg` loads at most 16 KB and `writemem` takes at most 4 KB per
  call. The SDK blob for mode 5 is built with `BASE=3400` and uploaded in
  pieces; its variables stay at the default `$9F00`, which the demo leaves
  free.

## Not done, and why

- No ca65 port, no SDK entry points, no generated bindings: the instruction was
  to find out how, not to add functions yet.
- Per-bob colour (writing the colour cells under a bob, with clash at the
  edges) and hires single-bitplane bobs (8 shifts, half the bytes per pixel)
  are both straightforward variants of the same blit; neither was measured.
- The 64 MHz Commodore 64 Ultimate was not measured.
