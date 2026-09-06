# Ultimate hardware verification — 2026-09-06

Machine: Ultimate 64 Elite at `192.168.1.62`, firmware `3.15`, firmware commit
`abd0888c`, FPGA `124`, core `1.4F`, NTSC. Tested the working tree containing
the selective-linking and ca65 demo conversions, not a clean release commit.

## SDK settings matrix

```sh
python3 tests/hardware/peers.py --bind 192.168.1.112
make -B -C tests/hardware NET_PEER=192.168.1.112:6464 HTTP_PEER=192.168.1.112:8099
python3 -u tests/hardware/hwtest.py --host 192.168.1.62 --prg tests/hardware/ucitest.prg --verbose
```

First run: **6/7 scenarios passed**. The SoftIEC scenario did not finish;
drive/control calls returned SDK error 2 and the screen stopped at the TCP
peer connection. The runner continued, and audio/turbo scenarios passed.
Second complete run: **7/7 scenarios passed**. The initial intermittent failure
remains unexplained; the successful retry is not a fix.

Successful configurations included 128 KB/2 MB/16 MB REU measurement, REU
transfers, TCP send/read/close, UDP socket open/close (not datagram transfer),
HTTP responses/body construction, palette API round trips, Ultimate Audio
sample completion, and every public turbo speed index. The audio configuration
completed 186 checks: 182 passed, 4 skipped. Reboot, freeze, and IP reconfiguration
are intentionally not performed; unavailable feature paths are reported as skips.
UCI disabled deliberately produces one failed signature check and returns to
BASIC; the host verifies that as the expected unavailable-device behavior.

The runner now saves/restores **REU Size** too, derived from the settings its
scenarios actually change. Original settings are restored; no flash write.

## BASIC and demos

| Command (`U64_HOST=192.168.1.62`) | Observed result |
|---|---|
| `make basic-run` | PRG and CRT each passed all 41 checks; the old runner printed an incorrect 34-check summary, now corrected |
| `make boing-run` | 58.6 fps, seven bounces in eight seconds, turbo/REU/audio flags all set, SDK result 0 |
| `make vsprites-run` | 39 vsprites at 60.0 fps; render 13393 of 17055 measured CIA cycles |
| `make -C demos/follow-me hardware` | PCM/palette and UCI-disabled SID fallback both passed keyboard input, score 10, timeout, and exit |
| `make demo-run` | Both SID visualizer runs failed the unchanged 45 fps minimum: 41.2 fps, then 43.0 fps |
| `make -C guide hardware` | Third sweep passed all 17 automated runs, including C/native turbo detection with UCI off |
| PCM runner, temporary WAV below | Three buffer swaps, 99 visual states, no underruns; temporary remote WAV removed |

Boing's runner now requires SDK result 0 rather than merely printing it.
The PCM runner's deadline now allows the approximately 35.7 seconds required
for three 1 MiB buffers at 22.05 kHz, stereo 16-bit (previous limit: 25 seconds).

The original music WAV was absent. A 60-second stereo chirp exercised streaming
instead; this does **not** validate the original music asset or audible mix:

```sh
ffmpeg -f lavfi -i 'aevalsrc=0.15*sin(2*PI*(180*t+10*t*t))|0.15*sin(2*PI*(240*t+15*t*t)):s=22050:d=60' -c:a pcm_s16le stream.wav
make -B -C demos/pcm-visualizer WAV_PATH=/temp/sdk-pcm-check.wav
# Upload stream.wav to /Temp/sdk-pcm-check.wav (refuse to replace an existing file).
python3 demos/pcm-visualizer/hwtest.py --host 192.168.1.62 --prg demos/pcm-visualizer/pcm-visualizer.prg
# Remove only the uploaded test WAV; restore the ordinary build path:
make -B -C demos/pcm-visualizer
```

## Scope and remaining evidence

The SID visualizer needs performance investigation. Its second run again
reached the music loop and passed the preceding SID-store/render/tick checks,
but failed the frame-rate gate; later palette-motion/song-key checks were not
reached in these two runs. The threshold was not lowered to obtain a pass.

The first `make -C guide hardware U64_HOST=192.168.1.62` run passed all six
startup cases and discovery, then the C identify launch showed an unrelated
program screen instead of the expected output. This is a failed launch, not a
successful SDK example test. The second sweep stopped when the assembly hello
reported `NO ULTIMATE FOUND` in the enabled-UCI case. The third sweep passed all
17 checks; these intermittent failures remain unexplained.

The file-info assembly example handled its missing `/Usb0/big.bin` fixture
cleanly (SDK error `$07`) and printed drive information; its successful-file
path was not tested. The C file-listing example completed, but mixed-case ASCII
directory names rendered as graphics (`T...`, `F....` in the screen decoder).
The automated completion check does not establish correct filename rendering.

Logan Approach was removed from this pass at the user's request and moved intact
to `/Users/barry/Git/logan-approach`, outside the repository.

All 128 host tests and the guide reference-contract check passed after the
build/test references to Logan were removed. Compile contracts for every API
call are not equivalent to running every documented example.
HDMI palette appearance and audible sound require separate human confirmation;
memory/register checks and the network video stream cannot establish those.
