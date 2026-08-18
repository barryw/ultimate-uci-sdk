# Tests

Two layers. Each catches a class of bug the other structurally cannot.

| Layer | Needs | Runs | Finds |
|---|---|---|---|
| [`emulator/`](emulator) | cc65, Docker | `make test` | the assembled SDK against a device that makes it wait |
| [`hardware/`](hardware) | an Ultimate | build, copy, run | firmware reality on whatever version the machine runs |

A third set lives outside this directory: `tools/test_*.py`, run by
`make unittest`. Those test the *generators* — the protocol tables, the keyword
table, the CRUNCH model, the charmap rule, the register boundary, the blob's
published offsets — on a host, because that is where they run.

There is no host layer for the SDK itself. There was one, written against the C
core the assembly rewrite replaced; its 182 assertions live in `emulator/` now, where they run
against the instructions a C64 will really execute rather than against a
host compiler's idea of them. A host test for 6502 code has to reimplement the
thing it is testing, and the reimplementation is what drifts.

## Emulator tests

`make -C tests/emulator run`

Suites for [sim6502](https://github.com/barryw/sim6502), run from its published
container so CI and a laptop use the identical tool:

| Suite | Backend | What it pins down |
|---|---|---|
| `protocol.suite` | `u64sim`, and a real Ultimate | the firmware behaviours the SDK is built on |
| `sdk.suite` | `u64sim` | the SDK itself: bring-up, framing, replies, status decoding |
| `sdk-placed.suite` | `u64sim` | the same, with the SDK's RAM relocated (generated from `sdk.suite`) |
| `timeout.suite` | `u64sim`, latency raised past the budget | that a device which stops answering is given up on |
| `absent.suite` | `sim` — nothing at `$DF1B-$DF1F` | that a machine with no Ultimate fails fast instead of hanging |
| `blob.suite` | `u64sim` | the standalone binary through its jump table and parameter block, with no symbols at all |
| `blob-relocated.suite` | `u64sim` | the blob moved to another address, then called with the original erased |
| `basic.suite` | `u64sim`, real BASIC and KERNAL ROMs | the wedge: tokenising, `LIST`, and every keyword's dispatch |

`basic.suite` is ROM-gated. Commodore's ROM images cannot be committed, so it
skips with a message naming the fix rather than failing; put `basic.bin` and
`kernal.bin` in `tests/emulator/roms`, or pass `C64_ROMS=`.

`protocol.suite` also runs against real hardware, with the same file:

    make -C tests/emulator hardware U64_HOST=192.168.1.62

That path carries UCI traffic over the firmware's REST API, so it can check the
protocol but cannot run a loaded program — which is what `hardware/` is for.

`sdk.suite` is the layer that found the bug worth remembering: cc65 translates
string literals into PETSCII, so the `"NO TARGET"` marker that capability
detection depends on matched perfectly in the host tests and never matched on a
C64. See [../docs/api-design.md](../docs/api-design.md#protocol-bytes-are-never-string-literals).

### The harness

`harness.s` exists because sim6502 loads a program rather than booting it, so
the cc65 runtime start-up never runs; `boot` sets up the C stack pointer the C
entry points need. `harness.sym` is generated from cl65's label file and
filtered down to `HARNESS_SYMS` in the Makefile — add a symbol there when you
export a new one, or the suite will not be able to name it. The `.sym` rules
depend on the Makefile, so editing that list rebuilds them; without that, a new
symbol silently stayed missing and the suite called address zero, which reads
like a bug in the code under test rather than in the build.

Most tests need no new assembly. The harness exports a request block and the
buffers it points at, so a suite fills the block from the DSL and calls
`t_exec`:

```
jsr([t_req_reset], stop_on_rts = true, fail_on_brk = true)
[req_target] = $01
[req_command] = $f0                  ; ECHO
[buf_args] = $de
[req_arglen] = $01
jsr([t_exec], stop_on_rts = true, fail_on_brk = true)
assert([result] == $00, "ULTIMATE_OK")
assert(([buf_data] + $02).b == $de, "the argument came back")
```

`t_req_reset` zeroes the block, re-aims its four pointers at the harness
buffers and clears them, so a test cannot pass on a byte the previous one left
behind. Add a new entry point only for something the request block cannot
express — `t_decode`, `t_strerror` and `t_wedge` are the current examples.

## Hardware tests

`make -C tests/hardware`, then copy `ucitest.prg` to your Ultimate and run it.

Output is [TAP](https://testanything.org/), which reads fine on a C64 screen and
parses without guessing:

```
# ultimate-sdk hardware tests
# ident=$c9 targets=$007e
# model=ULTIMATE 64 ELITE
# dos=ULTIMATE-II DOS V1.2
ok 1 - signature-present
ok 2 - init
...
ok 22 - turbo-speed-changes # SKIP turbo control is off in the ultimate settings
1..50
# 49 passed, 0 failed, 1 skipped
```

Firmware-dependent checks are skipped rather than failed, so the same binary
gives a meaningful result on a 1541 Ultimate-II and on a Commodore 64 Ultimate.

Last run: **Ultimate 64 Elite, firmware 3.15 — 5/5 scenarios, 0 failed**, with
40 checks in the plain scenario, 52 with the RAM expansion switched on and 47
with turbo. Mutating checks write to `/Temp`, the FAT filesystem the firmware
formats in RAM at boot, so nothing they do can fill a medium or outlive a power
cycle.

### Driving it from a host

`make -C tests/hardware run U64_HOST=192.168.1.62`

`hwtest.py` reconfigures the Ultimate over its REST API, runs the program once
per configuration, and checks the SDK behaved correctly in each — including the
configurations where behaving correctly means failing cleanly. The program
publishes a machine-readable result block into the cassette buffer (`$033C`), so
the driver reads counters by DMA instead of parsing the screen; the screen is
still decoded and printed when something fails.

| Scenario | What it pins down |
|---|---|
| `uci-disabled` | with the interface switched off the SDK reports no device and returns, rather than hanging or misreading open bus |
| `uci-enabled` | the baseline, every check the machine's settings allow |
| `uci-with-reu` | the interface overlays the last five REU registers, so an enabled REU must not disturb it |
| `softiec-survives-drive-disabled` | target `$05` stays reachable over UCI with the IEC drive switched off, so the SDK's SoftwareIEC path needs no setting from the user |
| `turbo-registers` | with "Turbo Control" on, the speed really changes: a fixed loop timed against the raster |

Every setting it touches is read first and restored afterwards, including on
Ctrl-C. Nothing is written to the Ultimate's flash.

### The wedge, typed at a real machine

`make -C tests/hardware basic-run U64_HOST=192.168.1.62`

`basictest.py` types lines at the machine over the REST API and reads the screen
back, because the wedge's tokeniser only runs when a line is *typed*: `ICRNCH`
is reached from the screen editor and no program can call it. Four bugs hid
exactly there, every one of them found on this script's first run. It covers
both deliveries — the `.prg` and the cartridge — and 32 checks each.

This is the layer that found the SoftwareIEC status-encoding bug: the target
answers `IDENTIFY` in ASCII and everything else in binary, so decoding by target
ID alone made capability probing report a working target as absent. It also
turned up [GideonZ/1541ultimate#794](https://github.com/GideonZ/1541ultimate/issues/794),
which came back as intended behaviour rather than a bug — and is now a contract
the SDK can rely on rather than a quirk to route around.
