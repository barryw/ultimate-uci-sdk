# Boing ball out of multiplexed hardware sprites

The Amiga Boing ball on a C64: a red-and-white checkered sphere rolling and
bouncing over a perspective grid, its shadow tracking it, a boing on every
bounce. The ball is hardware sprites, the shadow a blitter bob in the bitmap,
the sound PCM through the Ultimate's audio engine.

## What it is

- **Ball** = 2 sprite columns x 4 sprite rows, X-expanded: 96 x 84 hires
  pixels. Every position is two overlapping hires sprites, one white (colour
  $01) with the white tiles, one red ($02) with the red tiles. Red is drawn as
  `disc AND NOT white`, so it never lands where white is and sprite priority
  does not matter.
- **Multiplex**: 16 sprites a frame from 8. Sprites 0-3 draw rows 0 and 2,
  sprites 4-7 rows 1 and 3, with three raster IRQs a frame: line 250 applies
  the frame's positions and pointers for rows 0/1 and arms line y+22; y+22
  drops sprites 0-3 to row 2 and arms y+43; y+43 drops sprites 4-7 to row 3.
- **Rotation**: `genball.py` renders a sphere with an 8 x 8 checker (45-degree
  longitude bands, 22.5-degree latitude), axis tilted 17 degrees, 16 frames
  over 90 degrees so the loop is seamless. Only the white layer is stored
  (`ball.bin`, 8 KB) plus one silhouette (`disc.bin`, 512 bytes); the red layer
  is built at run time into one of two live sprite sets, flipped at vblank.
- **Background**: a hires bitmap (`genbg.py` -> `bg.bin`, `bgscr.bin`), grey
  field with a purple wall grid above the horizon and a perspective floor of
  lines converging on a vanishing point below it.
- **Shadow**: an ellipse the ball's size, offset (+30, +20) into the bitmap, its
  cells recoloured dark grey, drawn behind the ball (sprites are over the
  bitmap). `genbg.py` writes the silhouette (`shadow.bin`, 12 x 84); it is
  shifted to the pixel each frame and ORed in. There is one bitmap, so the
  previous shadow is restored first, from a clean copy of the background held
  in the REU (`reu_fetch` of just the covered cell rows) and a clean copy of
  the screen cells in RAM. Restore-then-draw runs right after the vblank sync;
  the ball floats over any brief disturbance.
- **Sound**: `genboing.py` -> `boing.pcm`, signed 8-bit mono at 11,025 Hz, a
  sine falling 420 -> 160 Hz with an exponential decay. Stashed to the REU at
  start and played one-shot on channel 0 through the audio engine on every
  bounce.

## The SDK's part

Through the standalone blob at `$8000` (built into `bindings/blob/build-boing/`
with `BASE=8000 VARS=43328`, so its RAM at `$a940` is clear of the code and of
both VIC areas): `ultimate_turbo_available/set/badlines` for the top speed with
badlines off, `reu_available/stash/fetch` for the background copy, the sample
and the shadow restore, and `ultimate_audio_init/configure/start/stop` for the
boing. UCI and max turbo are required; without either the program returns to
BASIC. No REU means no shadow and no sound.

## Memory map

| | |
|---|---|
| `$0801-$32ff` | code, tables, ball frames (`ball.bin` 8 KB, `disc.bin`) |
| `$4000-$43e7` | screen RAM, the background's cell colours (`bgscr.bin`) |
| `$4400-$4bff` | the two live sprite sets |
| `$4c00-$4fef` | the shadow silhouette |
| `$5000-$54ff` | the shifted-ellipse scratch |
| `$5500-$58e7` | a clean copy of the screen cells |
| `$6000-$7f3f` | the hires bitmap (`bg.bin`) |
| `$8000-$a91e` | the SDK blob, its RAM at `$a940-$a9fe` |
| `$aa00-$b911` | the boing sample (`boing.pcm`), stashed to the REU at start |

VIC bank 1 throughout; `$D018 = $08`. There is no room on a 64 KB machine for
an 8 KB clean copy of the bitmap in RAM once the blob, the frames and the
sprite sets are placed, which is why the shadow's restore comes from the REU.

## Verified in VICE

`make check` first verifies that the program refuses to start without UCI, then
bypasses that startup guard inside VICE and runs five screenshots across a
bounce. Every frame: the ball is
88 x 84 with about 2,960 white and 2,950 red pixels, the wall and floor grid
are intact, the shadow appears in flight and leaves no trail, the frame counter
advances, y bounces, and a wall bounce is counted. VICE has the REU but no
Ultimate Audio, so there is no sound there. Real turbo and audio are covered by
the Ultimate hardware test.

## Build once, run anywhere on an Ultimate

From the repository root:

```sh
make boing
```

`demos/boing/boing.prg` contains the program, graphics, SDK blob and sound.
Copy that one file to a USB stick or the Ultimate's internal storage, select it
in the Ultimate file browser and run it. A D64 adds no benefit.

Enable *Command Interface* and *Turbo Control → U64 Turbo Registers*; the demo
refuses to start without both. Enable *RAM Expansion Unit* and *Map Ultimate
Audio $DF20-DFFF* for the shadow and sound.

If `boing-orig8.pcm` is present locally, the build uses it at 8,363 Hz;
otherwise it builds the synthesised fallback. The original Amiga sample is
not distributable with the SDK.

## Run and verify over the network

`make run U64_HOST=<ip>` (or `python3 hwtest.py --host <ip>`): the PRG is over
the REST runner's 16 KB body limit, so it goes to the Ultimate's `/Temp` RAM
disk over FTP and runs with `runners:run_prg?file=`. The script reads the
status block back: with turbo on and Ultimate Audio mapped the flags should
read 7 (turbo, REU, audio), the frame rate 60, and the bounce counter should
climb with a boing each time. The shadow needs the REU enabled; the sound needs
"Map Ultimate Audio $DF20-DFFF" on and a firmware with the audio engine.

## Left for hardware

The audio path is not exercised in VICE (no Ultimate Audio there); it copies
the calling pattern of `demos/follow-me/lib/sound.asm`, which is known to work
on the bench, so the parent should confirm the boing actually sounds and pick
the volume. Everything visual is confirmed.


## Sound: the original sample (2026-09-02)

- The synthesised boing was replaced by the original: `boing.samples` from the
  Amiga *Workbench Demos* disk (`animations/boing.samples`, 24,706 bytes: an
  8-byte header, then signed 8-bit PCM). It is Commodore-Amiga's; it is
  git-ignored here and must not be committed or shipped. `mkpcm.py` builds
  `boing.pcm` from it: `python3 mkpcm.py boing-orig8.pcm 8363` (skip the
  header first: `tail -c +9 boing.samples > boing-orig8.pcm`), or from any WAV
  with `python3 mkpcm.py file.wav`. Without an argument it falls back to the
  synthesised sound.
- 8,363 Hz (divider 747) sounds right by ear. The sample is resident in two
  pieces because the C64 has no 24 KB run free: 9,728 bytes at `$aa00` and up
  to 7,424 at `$e000`, both stashed to REU `$4000` at start; the near-silent
  tail past 17,152 bytes is dropped. A 16-bit copy does not fit at all.
- Verified: REU `$4000` reads back equal to the file (host probe byte at
  `$033C+15`), the engine reports available (flags 7), result 0.
- Tried and rejected: firing the sample two frames before the bounce to beat
  HDMI audio latency. It sounded distorted and no earlier by ear, so the sound
  fires on the bounce itself, as first built. Trigger counter at `$033C+16`
  equals the bounce counter.
- Bench: "Map Ultimate Audio $DF20-DFFF" must be Enabled; `hwtest.py`
  requires and restores it.

## Layout to the original, and a shadow wrap bug (2026-09-02)

- Background regenerated to the original's proportions: 12 x 12 wall grid with
  margins, four-line perspective floor at 176-190, ball rests 4 px below the
  wall/floor line (`YMAX 96`), shadow right and level (`SHX 34, SHY 0`).
- Bug: at the right wall the shadow wrapped to the left edge. Two 8-bit
  overflows: x + SHX past 255, and the start column times 8 past 255. Both
  carry a ninth bit now (`sh_hi`, `sh_r_c0x8h`); the column count is clipped
  at 40 as before. Checked by reading the bitmap's left columns back while the
  ball is at the right wall.

## The static, finally (2026-09-02)

The synthesised sample was bad, but the returning static after it was
replaced had a second cause: `play_boing` (audio_stop, audio_configure,
audio_start through the blob) called from the main loop with interrupts
enabled. A raster IRQ landing inside that register sequence left the engine
playing noise, every bounce. Called from the vblank IRQ path (`irq_done`,
guarded by the `snd` flag physics sets on a bounce) it is clean. The lead-time
experiments were judged "distorted" for the same reason: both fired from the
main loop. Lesson for the SDK: the audio entry points are not interrupt-safe;
either call them with interrupts disabled or make `audio_*` bracket their
register writes with sei/cli.

## Correction: the static was a start-up race, not interrupt context (2026-09-02)

The "call it from the IRQ" conclusion above was wrong: the same binary went
static on one launch and played on the next. The real fix is in `play_boing`
and the init: `audio_stop`, then about a millisecond (`audio_settle`, 1,024
I/O reads, so the same wall time at any CPU speed), then `audio_configure`,
settle again, then `audio_start`; and at init a stop-and-settle before the
first configure, since the engine may still be running whatever a previous
run or the init probe left behind. Reprogramming a running channel without a
pause left it playing noise. Three consecutive fresh launches were clean
after this. SDK to-do: put that stop-and-settle into `ultimate_audio_configure`
or document it.
