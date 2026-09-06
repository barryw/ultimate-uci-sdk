# vsprites

Software sprites on an Ultimate 64: balls, diamonds and rings, 32 x 32 pixels
each, drawn as masked vsprites into a double-buffered multicolour bitmap every
frame. They are similar to Amiga blitter objects, but without a blitter: the
6510 restores the background, moves each one, draws it with
`D = (D AND mask) OR image`, waits for the raster, and flips the buffer.

The demo adds a vsprite whenever the last frame took under three quarters of the
raster period and takes one away when it took more than seven eighths, so it
fills whatever machine it is on: one vsprite on a stock C64 and 39 on
the tested 48 MHz Elite. The grey band at the top of the border is the render
time; the black below it is what is left.

## What the SDK does here

Four calls, linked directly from `ultimate.lib`:
`ultimate_turbo_available()` says whether the machine's Turbo Control setting
gives the program the speed register; `ultimate_turbo_set(U64_SPEED_MAX)` asks
for the top speed; `ultimate_turbo_badlines(0)` stops the VIC stealing cycles,
which is worth six per cent of every frame at any speed; and
`ultimate_vsprite_draw()` restores and masked-composites each vsprite. The draw
routine is plain 6510 code and also runs, slowly, on a stock C64.

Before the ca65 port, measured on an Elite (firmware 3.15, NTSC), the adaptive loop settled at 39
32x32 vsprites at 59.9 fps, using 13,312 of the frame's 17,055 CIA cycles for
movement, restore and draw.

## Building

Requires cc65 (ca65/ld65) and Python 3. The build links only the SDK's turbo
and vsprite modules; it needs neither the UCI transport nor a C runtime.
`gen_shapes.py` generates the pre-shifted image/mask data.

```
make            # vsprites.prg, with only the required SDK modules
make check      # check moving vsprites in VICE (1 MHz)
make run U64_HOST=192.168.1.62
```

`make run` uploads the PRG to the Ultimate's `/Temp` RAM disk over FTP, runs
it from there, reads the frame counter back and reports vsprites and frames
per second. Hardware screenshots additionally need Pillow.

On the machine itself: copy `vsprites.prg` anywhere and run it from the
Ultimate's file browser. Set *Turbo Control* to *U64 Turbo Registers* to see
it at speed; with any other setting it runs at 1 MHz, honestly.

## Memory

| | |
|---|---|
| `$0801-$26dc` | program, three shapes pre-shifted four ways, linked SDK code (current build) |
| `$4000-$5f3f` | bitmap A (VIC bank 1), screen A at `$6000` |
| `$a000-$bf3f` | the clean background, RAM under BASIC (`$01 = $35`) |
| `$c000-$c3ff` | screen B (VIC bank 3), bitmap B at `$e000-$ff3f` under the KERNAL |

Bank 2 is avoided for the second buffer on purpose: the VIC sees the character
ROM, not RAM, at `$9000-$9fff` of banks 0 and 2, and a screen there shows
glyph data as colour.
