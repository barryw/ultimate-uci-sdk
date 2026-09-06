# Palette video experiment

Offline encoding of video into real C64 multicolor bitmap frames, with a
fixed-palette comparison and a custom 16-entry RGB palette per frame or shot.
This directory also contains the earlier on-device palette/DMA timing probes.

## Generate a comparison

Requires Python 3, NumPy, Pillow, FFmpeg, and ffprobe. From the repository root:

```sh
python3 experiments/fmv/convert.py input.mp4 \
  experiments/fmv/build/comparison --start 10 --seconds 12 --fps 24
python3 -m unittest discover -s experiments/fmv -p 'test_*.py'
```

The output directory must not exist. `--crop w:h:x:y` optionally crops the
source before scaling. The picture is fitted inside a 4:3 display and sampled
at 160×200 multicolor pixels; widescreen sources are letterboxed. Previews use
320×240 display scaling. No dithering is applied.

`--palette-mode shot --shot-starts 0,56,96,...` fits one palette per shot.
Starts are explicit zero-based frame numbers in the extracted clip, beginning
at zero; the last shot ends at the end of the clip. With no starts supplied,
shot mode treats the entire clip as one shot. Up to 32 evenly spaced frames,
including both endpoints, contribute to each shot palette. Palette bytes stay
identical within each shot; per-cell color selection still runs per frame.
Cuts are supplied explicitly because animation flashes can fool cut detection.

`--preprocess gentle` applies a spatial bilateral filter at the target pixel
resolution (`sigmaS=1`, `sigmaR=0.06`, all RGB planes), then rounds channel values
to steps of 8, retaining endpoints 0/255. It feeds the same cleaned frames to
palette fitting and cell encoding. No frames are blended together. The source
preview and error measurements still refer to the original extracted frames;
`cleaned/` contains the processed input and the manifest records the exact filter.
This is an experimental cleanup preset, not temporal stabilization of cell colors.

Each cell of 4×8 multicolor pixels (8×8 VIC dots) gets three local color indices,
plus the shared black background at index zero. The custom palette reserves
black and uses median cut for fifteen other RGB entries. The same greedy
color fitting and local refinement run on both palettes. The fixed palette
comes from the SDK's existing `experiments/bobs/render.py`, and is recorded in
the manifest. There is no single universal RGB representation of C64 colors.

Outputs:

- `comparison.mp4`: source at target resolution, fixed palette, custom palette;
  original source audio is included when available.
- `comparison.png`: six sampled comparison frames.
- `fixed.frames`, `custom.frames`: packed frames, without a PRG load address
  or file header; 10,049 bytes per frame.
- `audio-16000hz-mono.s8`: separate signed 8-bit mono PCM at 16 kHz, when the
  source has audio. This is prepared audio, not a tested playback track.
- `manifest.json`: frame count/rate, source hash, palette, byte layout, and
  RGB reconstruction error. `input/` and `preview/` contain individual PNGs.

## Packed frame layout

| Offset | Bytes | Meaning |
| ---: | ---: | --- |
| 0 | 8,000 | Bitmap in VIC cell/scanline order |
| 8,000 | 1,000 | Screen RAM: selectors `01` / `10` in high / low nibble |
| 9,000 | 1,000 | Color RAM: selector `11`, low nibble |
| 10,000 | 1 | `$D021` background index, selector `00` |
| 10,001 | 48 | Sixteen RGB triples for UCI `$52` |

Frame `n` starts at `n * 10049`. A player must DMA the three memory regions,
set the background, and submit the RGB bytes through UCI. These are prepared
assets; `player.c` below is a first playback experiment. At 24 fps a 12-second clip has 288 frames:
2,894,112 bytes of video plus 192,000 bytes of mono PCM.

## Dragon's Lair sample

The local sample uses seconds 10–22 of the trailer from
[Digital Leisure's Steam listing](https://store.steampowered.com/app/227380/Dragons_Lair/),
sampled at 24 fps. It is a widescreen promotional trailer, not an exact capture
of the original arcade attract sequence. Downloaded footage and generated
assets live under the git-ignored `build/` directory.

[Dragon's Lair FMV v01](https://csdb.dk/release/?id=263962&show=summary), released
26 August 2026 by daddlerTL and Mac, is the motivating comparison. Our fixed
column is **our encoder's baseline**, not footage of that release or a
reproduction of its encoding algorithm.

The shot-palette variant uses reviewed boundaries at frames
`0,56,96,136,168,192,196,216,248`. Frame 56 groups the expanding iris transition
with the incoming shot, switching during the bright flare. Generate it with:

```sh
python3 experiments/fmv/convert.py \
  experiments/fmv/build/source/dragons-lair-steam.mp4 \
  experiments/fmv/build/dragons-lair-shots --start 10 --seconds 12 --fps 24 \
  --palette-mode shot --shot-starts 0,56,96,136,168,192,196,216,248 \
  --source-url https://store.steampowered.com/app/227380/Dragons_Lair/
```

For the spatial-cleanup comparison, use a new output directory
`experiments/fmv/build/dragons-lair-cleaned` and add `--preprocess gentle` to
that command. Upload that directory using `play.py --assets` after stopping
the previous run.

## What this proves

Preview pixels are decoded from the packed bitmap/screen/color/palette data.
Tests compare the encoder with the existing independent bitmap renderer and
check exact-color cell patterns, single-color frames, and malformed inputs.

The previews show spatial color/detail limits. They do not simulate analog
video, palette programming transitions, raster tearing, missed presentation
deadlines, or audio synchronization. Per-frame quantization can also cause
color flicker; brightness sorting is not temporal palette stabilization.

Earlier hardware measurements put three DMA operations plus a no-reply palette
call at roughly 15.5K cycles against a 17.1K-cycle NTSC raster frame. That is a
work-interval measurement, not proof of 60 fps presentation: the probe's frame
counter counts loop iterations and does not detect skipped raster frames.
Its timer also excludes some bookkeeping and it does not display new movie
frames. The experimental 24 fps player below now provides concurrent PCM and
coarse deadline tracking; visual validation remains necessary. Standard color RAM is not double-buffered, and
UCI palette writes must be scheduled alongside the displayed frame.

## Play the local sample on an Ultimate

```sh
make -C experiments/fmv player.prg
python3 experiments/fmv/play.py --host 192.168.1.62
# Later, stop playback and restore the original device settings:
python3 experiments/fmv/play.py --host 192.168.1.62 --stop
```

After stopping the previous run, select the shot version with
`python3 experiments/fmv/play.py --host 192.168.1.62 --assets experiments/fmv/build/dragons-lair-shots`.

The initial player expects exactly the sample above: 288 frames at 24 fps,
plus 192,000 bytes of 16 kHz mono signed PCM. The launcher checks the asset
sizes and linker map, enables UCI/16 MB REU/Ultimate Audio, uploads to `/Temp`,
and leaves the clip looping. It saves the changed settings locally under
`build/player-settings.json`; the stop command restores them. Nothing is
saved to the device's configuration flash.

RUN/STOP exits the C64 program, stops audio, and restores the palette and
display registers. Use the host `--stop` command afterward to restore device
settings too. The player uses REU offsets 0 through the video payload and
`$300000` onward for audio and saved color RAM; previous contents there are
overwritten. The uploaded files remain in `/Temp`.

Bitmap buffers are at `$6000` and `$A000`, with screen RAM at `$4400` and
`$8400`. Frame deadlines use CIA2 timers at nominal PAL/NTSC clock rates and
presentation waits for raster line 250. The shared color RAM and RGB palette
are updated there. UCI palette writes are skipped when the next frame's RGB
bytes match the active palette. Audio restarts each loop; this prototype does not provide
seamless looping or calibrated long-term A/V synchronization. HDMI inspection
is required for palette tearing. OBS C64 Stream does not reflect UCI palettes.

The cassette buffer at `$033C` contains `FMVP`, state at +4 (1 loading,
2 playing, 3 stopped, `$80` error), SDK error at +5, host stop byte at +6,
loop counter at +7, last presented frame (little endian) at +8, and a coarse
late-preparation counter at +10. That counter increments when preparation
finishes more than a full video-frame period past its deadline; it is not
a scanout or sub-frame jitter detector. Byte +12 counts playback palette writes
modulo 256; stage +13 identifies load failures.
