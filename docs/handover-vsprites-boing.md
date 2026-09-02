# Handover: software sprites, the vsprites demo, the Boing ball, and an SDK fix

Written 2026-09-02 at the end of a long session. Nothing below is committed.
Bench: Ultimate 64 Elite at 192.168.1.62, firmware 3.15, core 1.4F, NTSC.

## What exists now

| Where | What | State |
|---|---|---|
| `src/uci/uci_core.s` | `uci_abort` waits for the abort flag (`UCI_STAT_ABORT_P`), new `uci_poll_aborted` | Fixed, tested on emulator and hardware |
| `tests/emulator/abort-latency.suite`, harness `t_status_reg`, Makefile `ABORT_LATENCY` | Reproduces the abort race with a slow simulated firmware | Fails before the fix, passes after; whole emulator run passes (9 suites) |
| `tests/hardware/ucitest.c` | "first-command-after-init" at 1 MHz and at max turbo | Passes; the bench has 10 unrelated pre-existing failures (below) |
| `docs/uci.md`, `docs/superpowers/specs/2026-09-01-software-sprites-design.md` | Mechanism, measurements, colour options, demo results | Written |
| `demos/vsprites/` | Bobs on a grid, blob turbo calls, auto-scaling bob count | 60 bobs at 60 fps on the Elite; VICE check passes |
| `experiments/bobs/` | The throughput experiment, six colour modes, harness, VICE byte-exact checker | Done; keep as the test bed |
| `experiments/boing/` | Amiga Boing ball: 16 sprites a frame from 8, blitter shadow, perspective floor, original sample through Ultimate Audio | Runs on the Elite, three clean launches in a row |

## The SDK bug, in one paragraph

Writing the abort bit sets status bit 2, which only the firmware clears, and
it clears it with `HANDSHAKE_RESET`: state forced idle and the command pointer
rewound. `uci_abort` waited for idle state only, which a fresh machine already
is, so `uci_init` returned before the abort was serviced and the first command
was wiped by the reset: `ULTIMATE_ERR_PROTOCOL` at 10 MHz and above on the
Elite. The fix polls state and abort flag together. Not a VHDL bug. Full
detail in `docs/uci.md` under "Recovering a wedged interface".

## Two more SDK findings, not yet fixed in the SDK

1. **Ultimate Audio reprogramming race.** `audio_stop`, `audio_configure`,
   `audio_start` back to back sometimes leaves a channel playing noise, and at
   init the engine may still be running whatever the previous launch left.
   The Boing demo works around it with `audio_settle` (1,024 reads of `$D012`,
   about a millisecond at any CPU speed) after stop and after configure, and a
   stop-and-settle before the first configure. Fold that into
   `ultimate_audio_configure` or document it. An earlier "must be called from
   interrupt context" conclusion in the same NOTES was wrong; the correction is
   there too.
2. **Blob one-byte entry points** (`ultimate_turbo_available` and friends)
   return with Z set by their trailing `ldx #0`. Callers must `cmp #0` before
   `beq`. Bit this once in the vsprites demo.

## Bench facts learned

- CIA timers count at 1 MHz under turbo; a NTSC frame is 17,092 CIA cycles at
  every speed, so CIA cycles are microseconds.
- Turbo speed-up is linear with no RAM wait states. One 16x16 multicolour bob
  costs about 6,250 6510 cycles (127 us at 48 MHz); 32-line, 218 us. Badlines
  cost about 1 ms a frame at any speed; `$D031` bit 7 recovers it.
- REU DMA under turbo is about five times faster than stock and no faster than
  the CPU; storage, not a blitter.
- REST: `run_prg` uploads at most 16 KB; `writemem` 4 KB per call. Bigger PRGs
  go to `/Temp` over anonymous FTP and run with
  `PUT /v1/runners:run_prg?file=/Temp/x.prg`. `/Temp` is wiped by a reboot.
- After a reboot the running config reverts: "Map Ultimate Audio $DF20-DFFF"
  goes back to Disabled. Both demo runners require and restore it; for
  listening leave it Enabled.
- REST reads during a timed measurement perturb the CIA count; never poll while
  timing. A double-buffered front buffer flips every frame; freeze the demo
  (pause byte) before reading a frame back.
- The VIC sees character ROM at `$1000-$1FFF` and `$9000-$9FFF` in banks 0
  and 2. Never put a screen or bitmap there; RAM readback hides it, the
  display shows glyph data as colour.
- Ultimate Audio registers are write-only; readback shows `00 10` pairs.
- The VIC UDP video stream cannot reach a Mac on Wi-Fi (ARP on interface 0,
  multicast and broadcast never arrive). Frames are read back over REST.
- VICE (`x64sc`) saves command-line options into `~/.config/vice/vicerc`
  (`-saveres`); a stale `-exitscreenshot` persists. Its monitor output goes to
  the log file named there, readable with `strings`.
- `git HEAD:src/uci/uci_core.s` does not assemble against the working tree's
  includes; "pre-fix" comparisons must revert the one `jsr` in the working
  copy, and delete `bindings/blob/build/*.o` first, or the stale object is
  silently reused.
- The hardware suite currently fails 10 checks on this bench, identical before
  and after the abort fix: the turbo work-ratio check (equal work at "1" and
  "4 MHz" inside ucitest, though `$D031` speed changes work in the demos) and
  nine `/Temp` DOS operations answering device error 7. Not investigated.

## The Boing ball, specifically

- `experiments/boing/NOTES.md` is current and detailed. Read it first.
- The sound is `boing.samples` from the Amiga Workbench Demos disk
  (`sca.ch/amiga/disks/WorkbenchDemos.adf`, unpacked with `xdftool`):
  8-byte header, then signed 8-bit PCM, played at 8,363 Hz. **Commodore-Amiga's
  file: git-ignored, never commit or ship it.** `mkpcm.py` builds `boing.pcm`
  from it (or from any WAV). It is resident in two pieces around the I/O area
  and stashed to REU `$4000`; a 16-bit copy does not fit a 64 KB machine.
- Layout matches the original: 12x12 wall grid with margins, thin four-line
  floor at 176-190, ball rests 4 px under the wall/floor line (`YMAX 96`),
  shadow 12 px right and level (`SHX 12`, `SHY 0`).
- Fixed on the way: shadow wrapping to the left at the right wall (two 8-bit
  overflows, `sh_hi` and `sh_r_c0x8h`).
- Tried and dropped: firing the sample two frames early to beat HDMI audio
  latency. Judged worse by ear, though those tests were made while the
  reprogramming race was still present, so it deserves one retry now.
- Hardware snapshots composite only one multiplexer phase (two of the four
  sprite rows); use VICE screenshots (`make check`) for whole-ball checks.
- Missing versus the original: nothing the user has asked for. Possible next:
  32 rotation frames for smoother spin, the row multiplexer as an SDK service.

## Exact resume order

1. `make -C tests/emulator run` and `make unittest` to confirm green, then
   commit in sensible pieces: the abort fix with its tests and docs; the
   vsprites demo; the experiments; the design doc and this handover. Keep
   `experiments/boing/boing.samples` and `boing*.pcm` out (already ignored).
2. Decide on the two audio/blob findings above: settle-and-stop inside
   `ultimate_audio_configure`, and a note on the Z flag of the byte-returning
   entry points.
3. Optional: retry the two-frame sound lead in the Boing demo now that the
   race is closed; try 32 rotation frames.
4. Optional: look at the 10 pre-existing hardware-suite failures on the bench.

## Commands that matter

```
make -C tests/emulator run                      # 9 suites, needs Docker
make hardware-run U64_HOST=192.168.1.62         # the on-device suite
make vsprites-run U64_HOST=192.168.1.62         # demo, prints bobs and fps
make -C experiments/boing run U64_HOST=192.168.1.62   # boing, requires audio mapping
python3 experiments/bobs/bobtest.py --host 192.168.1.62 --prg experiments/bobs/bobs32.prg --sweep
```
