# Tests

Two layers. Each catches a class of bug the other structurally cannot.

| Layer | Needs | Runs | Finds |
|---|---|---|---|
| [`emulator/`](emulator) | cc65, Docker | `make test` | the assembled SDK against a device that makes it wait |
| [`hardware/`](hardware) | an Ultimate | build, copy, run | firmware reality on whatever version the machine runs |

There is no host layer. There was one, written against the C core the assembly
rewrite replaced; its 182 assertions live in `emulator/` now, where they run
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
export a new one, or the suite will not be able to name it.

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
# ident=$c9 targets=$001e
# model=ULTIMATE 64
# dos=ULTIMATE-II DOS V1.2
ok 1 - signature-present
ok 2 - init
...
ok 13 - identify-control # SKIP no control target on this firmware
1..13
# 13 passed, 0 failed, 0 skipped
```

Firmware-dependent checks are skipped rather than failed, so the same binary
gives a meaningful result on a 1541 Ultimate-II and on a Commodore 64 Ultimate.

Last run: **Ultimate 64 Elite, firmware 3.15 — 13 passed, 0 failed, 0 skipped**,
reporting `ident=$c9 targets=$005e model=ULTIMATE 64 ELITE dos=ULTIMATE-II DOS V1.2`.

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
| `uci-enabled` | the baseline, all 13 checks |
| `uci-with-reu` | the interface overlays the last five REU registers, so an enabled REU must not disturb it |
| `softiec-survives-drive-disabled` | target `$05` stays reachable over UCI with the IEC drive switched off, so the SDK's SoftwareIEC path needs no setting from the user |

Every setting it touches is read first and restored afterwards, including on
Ctrl-C. Nothing is written to the Ultimate's flash.

This is the layer that found the SoftwareIEC status-encoding bug: the target
answers `IDENTIFY` in ASCII and everything else in binary, so decoding by target
ID alone made capability probing report a working target as absent. It also
turned up [GideonZ/1541ultimate#794](https://github.com/GideonZ/1541ultimate/issues/794),
which came back as intended behaviour rather than a bug — and is now a contract
the SDK can rely on rather than a quirk to route around.
