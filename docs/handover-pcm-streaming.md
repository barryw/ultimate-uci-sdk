# Love note: resume the disk PCM demo here

Local work resumed 2026-08-22. Barry confirmed the bench is ready.

## Most important observation

The likely underrun fix is now implemented: inactive buffers refill in slices,
at most one per video frame, and are configured only after the final
slice arrives. Status byte 14 counts an end flag that arrives before the next
pair is ready. The hardware smoke test now requires three buffer crossings with
that counter still zero. Status bytes 15 and 16 identify the active in-loop
operation and refill slice if another error occurs.

Hardware tuning found that direct disk-to-REU transfers produced audible
scratches and pops regardless of slice size. Refills now read 16 KiB into C64
RAM, then use a short REU DMA into the inactive buffer. That clean path cannot
sustain 44.1 kHz stereo (about 126 KiB/s measured versus 176.4 KiB/s required),
so the current WAV is 22.05 kHz, signed 16-bit stereo. It has crossed seven
buffers with zero underruns and is left running for listening.

## Proven on the real Ultimate

- Ultimate: `Ultimate 64 Elite`, firmware `3.15`, FPGA `123`, core `1.4E`.
- The new Ultimate Audio API passed the full hardware matrix earlier: seven
  scenarios passed, including a real silent sample reaching its end IRQ.
- The original WAV remains on the USB disk at `/USB1/HALL.WAV`, 29,926,444
  bytes. The current 22.05 kHz WAV is `/USB1/HALL22.WAV`, 14,963,278 bytes.
- WAV SHA-256:
  `b896129e0fe784976f0a476cb030a7b8880c9b502336c7eabe8b4cd150b52dee`.
- The demo reached status `PVIZ`, state `2`, completed two reported 1 MiB swaps,
  and produced live six-band levels `12, 7, 9, 11, 9, 9` before shutdown.
- The sliced build later completed a ten-buffer, 479-visual-state soak with no
  underrun or protocol error. A preceding run had stopped after two swaps with
  protocol error 3 and loud buzzing; shutdown now stops both stereo pairs.
- The bars now analyze small windows fetched from the active PCM buffer; the
  precomputed 10 KiB visualization table was removed.
- The current PRG is 15,383 bytes and ends below the REST runner's observed
  `$47FF` load ceiling. The previously recorded `$57FF` ceiling was wrong;
  direct memory comparison showed the runner's bytes diverging at `$4800`.
- The lowercase cc65 source literals display as readable uppercase PETSCII on
  hardware.

## SDK work in the tree

- `src/uci/audio.s` adds checked Ultimate Audio discovery/config/start/stop/IRQ
  support. The probe and IRQ behavior were verified on hardware.
- `include/ultimate.h` exposes `ultimate_audio_voice` and the public PCM API.
- Protocol constants and every generated binding contain the audio registers,
  control bits, and structure offsets.
- Blob jump-table entries and cc65 wrappers are present.
- Hardware tests cover mapped and unmapped audio; the mapped scenario passed.
- `src/uci/reu.s` now runs disk-to-REU load/save with
  `UCI_TIMEOUT_FOREVER`, restoring the caller's timeout afterward. A 1 MiB load
  had returned `ULTIMATE_ERR_TIMEOUT` at maximum turbo before this shared fix.
- `tests/emulator/sdk.suite` now asserts that REU load restores the caller's
  timeout budget; the emulator suite passes.
- The interleaved PCM validator now requires even byte lengths, not multiples
  of four. That is required for a stereo right channel starting at `base+2`
  with `length=total-2`, and follows the official Ultimate Audio manual.

## Demo and asset state

- New untracked directory: `demos/pcm-visualizer/`.
- `visualizer.c` parses RIFF/WAVE itself, requires PCM 22,050 Hz, 16-bit,
  stereo, streams from `/USB1/HALL22.WAV`, and uses two 1 MiB REU buffers.
- `HallOfTheMountainKing.mid` is Mutopia Project item 1888, public domain.
- The WAV was rendered with FluidSynth and MuseScore General (MIT) from
  `/private/tmp/MuseScore_General.sf3`.
- Local source copies are `/private/tmp/hall-44100.wav` and
  `/private/tmp/hall-22050.wav`.
- `ASSET-LICENSES.md` and the demo README record provenance.
- `make protocol`, `make unittest`, `make emulator`, `make hardware`, and the
  demo build all pass after the sliced-refill change.
- The release/Woodpecker generation and packaging changes have not been added
  yet. After playback is stable, make release CI render the WAV with
  FluidSynth, include WAV + PRG in release artifacts, and keep the ordinary
  `make demos` build offline.
- A zero-byte `/USB1/HALL.VIS` from the abandoned sidecar attempt may remain;
  remove it later if desired. It is not used.

## USB cleanup already authorized and completed

Forty `/USB1/update_*.u64` development firmware images were deleted. The one
requested keeper, `/USB1/update_v3.14d.u64`, remains. Non-firmware files were
left alone.

## Current bench state

- Command Interface: `Enabled`
- RAM Expansion Unit: `Enabled`
- REU Size: `16 MB`
- Map Ultimate Audio `$DF20-DFFF`: `Enabled`
- Turbo Control: `U64 Turbo Registers`
- The 22.05 kHz visualizer is intentionally left running.

## Exact resume order

1. Get Barry's listening verdict on the running 22.05 kHz bounced-refill build.
2. Only after clean playback is confirmed, finish release asset generation,
   guide examples, coverage,
   commit, and push.

All shell commands in this repo must be prefixed with `rtk` per
`/Users/barry/.codex/RTK.md`. Ponytail mode is active: fix the underrun with the
smallest measured change; do not build a generic streaming framework.
