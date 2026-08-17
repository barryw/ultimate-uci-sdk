# Handover: implementing the service layers and their tests

Written to be picked up cold. It says where things stand, what is already
decided and why, the traps that have already cost debugging time, and a
concrete order of work.

The short version: **the transport is done and thoroughly tested; the command
surface is barely touched.** 11 of 101 UCI commands are exercised, because only
detection and identity have an API. Everything below is about closing that.

---

## 1. Where things stand

| | State |
|---|---|
| Layer 1 — UCI transport | complete, assembly, 1398 bytes |
| Layer 2 — bring-up, detection, identity | complete, assembly, 673 bytes |
| Layer 2 — dos, file, network, http, control | **not started** |
| Layer 3 — ca65 / cc65 bindings | working |
| Layer 3 — Oscar64, llvm-mos, KickC | **not started** (see §7) |

```
make lib              GREEN
make -C examples/asm  GREEN     2.6 KB .prg
make -C examples/cc65 GREEN     5.8 KB .prg
make hardware         GREEN
make test             GREEN     75 tests across 5 suites  (= make emulator)
make hardware-run     GREEN     13/13 across 4 config scenarios
make coverage         GREEN     0 wrapped-but-untested
```

**The host test layer is gone, and is not coming back.** The 182 checks in
`tests/unit` were written against the C core the assembly rewrite replaced.
They are now `tests/emulator/sdk.suite`, `absent.suite` and `timeout.suite`,
asserting the same behaviour against instructions a 6502 really executes.
`make test` is an alias for `make emulator`; there is nothing left that a host
compiler can run, because a host test for 6502 code has to reimplement the thing
it is testing.

Porting them found three things worth knowing about, all fixed:

- **`uci_store_status` stored one status byte and dropped the rest.** The
  16-bit "is there room" compare tested `Z` after the high-byte `sbc`, which
  only asks whether the high bytes differ. Nothing caught it because the
  internal four-byte prefix is captured separately, so every result code was
  still correct — only the caller's copy of the status string was truncated.
- **Nothing installed the timeout.** `UCI_TIMEOUT_DEFAULT` lived in `uci.h` and
  was never written to `uci_timeout`, so the shipped default was "wait forever",
  and with `UCI_VARS` it was whatever byte happened to be in the caller's RAM.
  `uci_init` sets it now, and `UCI_TIMEOUT_DEFAULT` is a generated constant so
  assembly callers can see it.
- **`bindings/oscar64` is broken** — it lists the C files that no longer exist.
  The root `Makefile` no longer builds the Oscar64 example conditionally on the
  compiler being installed, because that only hid the failure. See §7.

---

## 2. Things not to re-derive

Read [uci.md](uci.md) properly before writing a service. These are the ones that
have already cost time:

- **Queue pointers saturate on the last byte.** A reply that exactly fills the
  896-byte response queue leaves `DATA_AV` set for ever. `while (DATA_AV) read`
  hangs the machine. The core bounds every drain; a service must never
  reimplement that loop.
- **Max command is 895 bytes, not 896.** The write pointer saturates the same
  way. The core rejects oversized commands, so a service that chunks a write
  must chunk to 895 minus its own header, not 896.
- **`DOS_CMD_READ_DATA` arrives in 512-byte blocks.** Multi-block replies are
  already handled by `uci_exec`; a service asks for what it wants and gets it
  whole, up to its buffer.
- **Status encoding is decided by shape, not by target.** SoftwareIEC answers
  `IDENTIFY` in ASCII and everything else in binary. `uci_decode` sniffs. Do not
  add per-command status logic to a service.
- **Never put protocol bytes in a string literal.** cc65 translates literals to
  PETSCII. `"NO TARGET"` compiled to `$CE $CF ...` and silently stopped
  matching. Generate byte lists from `tools/gen_protocol.py`.
- **The model name is mixed case**, unlike the uppercase identification
  strings. Anything printing it needs folding or conversion.
- **Target `$05` reports present even when the drive is off**
  ([firmware #794](https://github.com/GideonZ/1541ultimate/issues/794)). A
  SoftwareIEC service must expect its first real command to fail.

---

## 3. How a service is built

Every service is `uci_exec` plus argument marshalling. No service touches
`$DF1B-$DF1F` or the handshake. If you find yourself writing `sta
UCI_REG_CONTROL` in a service, stop.

The pattern is in `src/uci/ultimate.s`, `ultimate_get_model`: clear a request
block, set target and command, point `args` at a small byte array, call
`uci_exec`. Wider parameters go in the shared variable block rather than on any
stack — see `ult_buf` / `ult_buflen` / `ult_outlen`.

Three constraints that are not negotiable, because they are what the SDK sells:

1. **Caller-owned buffers.** No allocation, no hidden statics a second call
   would stomp.
2. **Bounded time.** Every entry point completes or returns
   `ULTIMATE_ERR_TIMEOUT`. Network and HTTP services must raise the timeout
   themselves and restore it — see `uci_set_timeout`.
3. **Add your variables to the single block** in `uci_core.s`, and update
   `UCI_VARS_SIZE` in `tools/gen_protocol.py`. The `.assert` in `uci_core.s`
   fails the build if you forget. One block keeps cartridge placement to one
   knob.

When a service wraps a command, add it to `WRAPPED` in
`tools/gen_coverage.py`. `make coverage` then **fails** until a test sends it.
That is the mechanism that stops this drifting again.

---

## 4. Adding a test, at each layer

### Emulator — `tests/emulator/`

Five suites, all run by `make test` through the sim6502 container.
`tests/README.md` has the table; the two you will add to are these.

**Protocol expectation** (`protocol.suite`) — pins a firmware behaviour the SDK
depends on. Runs against the simulator *and* real hardware with the same file:

```
test("dos-open-missing", "opening a missing file is reported") {
  uci($01, $02, $01, "no-such-file.prg")
  assert(uci_status("FILE DOESN'T EXIST"), "OPEN_FILE on a missing file failed")
}
```

**SDK behaviour** (`sdk.suite`) — drives the assembled SDK through `harness.s`.
**Most of the time this needs no new assembly.** The harness exports a request
block and the buffers it points at, so a test fills the block from the DSL:

```
jsr([boot], stop_on_rts = true, fail_on_brk = true)
jsr([t_init], stop_on_rts = true, fail_on_brk = true)
jsr([t_req_reset], stop_on_rts = true, fail_on_brk = true)
[req_target] = $01
[req_command] = $04                  ; READ_DATA
[buf_args] = $10
[buf_args] + $01 = $00
[req_arglen] = $02
jsr([t_exec], stop_on_rts = true, fail_on_brk = true)
assert([result] == $00, "ULTIMATE_OK")
assert([req_datalen].w == $0010, "sixteen bytes")
assert(([buf_data] + $02).b == $48, "'H'")
```

`t_req_reset` zeroes the block, re-aims its pointers and clears the buffers, so
a test cannot pass on a byte the previous one left. Write word fields as two
byte stores — a small value assigns as one byte and would leave the high byte of
a pointer intact, which is the difference between a null pointer and a live one.

Add a harness entry point only for something the request block cannot express.
`t_decode`, `t_strerror`, `t_wedge` and `t_break_cstack` are the current
examples. When you do, export it and add its name to `HARNESS_SYMS` in the
Makefile, or the suite cannot name it.

`sdk.suite` runs twice, the second time against a build with the SDK's RAM
relocated (`sdk-placed.suite`, generated). Nothing extra to do; it happens.

Two behaviours need their own suite because they need a different device, not a
different test: `timeout.suite` runs with the simulated interface latency raised
past the SDK's budget, and `absent.suite` runs under the plain `sim` backend,
where nothing answers at `$DF1B-$DF1F` at all. Add to those when you add an
entry point whose failure path matters — which, for network and HTTP, is all of
them.

### Hardware — `tests/hardware/`

`ucitest.c` is a TAP program. Add a check with `check(name, expected, actual)`.
It publishes counters to `$033C` so the host driver reads results by DMA rather
than parsing the screen; if you add fields, keep the layout comment accurate.

`hwtest.py` reconfigures the Ultimate over REST and runs the program once per
configuration. Add a scenario when a *setting* changes what the SDK should do.

---

## 5. Risk tags: do this before writing file tests

Most of the remaining command surface mutates something.
`DELETE_FILE`, `RENAME`, `CREATE_DIR`, `SET_TIME`, `SAVE_REU`,
`EASYFLASH` erase, `SET_PALETTE`, `MOUNT_DISK`, `REBOOT`.

A default `make hardware-run` must never delete a user's files or reboot their
machine. Before the first DOS write test, introduce tags and honour them:

| Tag | Meaning | Runs by default |
|---|---|---|
| `safe` | read-only | yes |
| `mutating` | writes, but only under a fixture directory | yes |
| `destructive` | can lose data outside the fixture | **no**, opt-in |
| `manual` | cannot be automated | never |

sim6502 already supports `--filter-tag` / `--exclude-tag`, and
`example/ultimate.suite` upstream uses `hardware-wedges` for exactly this. Two
commands need `manual` today: `CTRL_CMD_FREEZE` only completes when the user
leaves the menu, and `CTRL_CMD_REBOOT` kills the session by design.

Fixtures live in `tests/emulator/fixtures/usb0`. For real hardware they have to
be pushed over FTP first — the REST API has no arbitrary file-write endpoint:

```
curl --ftp-create-dirs -T tests/emulator/fixtures/usb0/data/hello.txt \
     ftp://192.168.1.62/USB1/data/hello.txt
```

---

## 6. The simulator ceiling

`u64sim` implements Ultimate DOS (`$01`/`$02`) and part of the control target
(`$04`). Network, HTTP and SoftwareIEC are **hardware only** — about half the
command surface can never be covered in CI as things stand.
`docs/generated/command-coverage.md` marks this per command.

Two ways forward, and the choice matters:

- **Extend `u64sim`** with network/HTTP/SoftwareIEC targets. It is the same
  author as this SDK, so it is a real option, and it is the only route to CI
  coverage of those services.
- **Accept hardware-only coverage** for them, and make `make hardware-run` a
  required step before release rather than an optional one.

Whichever, say so explicitly. A permanently half-red coverage table that nobody
has decided about is worse than a smaller table everyone trusts.

---

## 7. Suggested order

1. ~~Unbreak `make test`~~ — done, see §1. The build is green end to end.
2. **Ultimate DOS**, in this order: `CHANGE_DIR`, `GET_PATH`, `OPEN_DIR`,
   `READ_DIR`, `OPEN_FILE`, `READ_DATA`, `CLOSE_FILE`. All read-only, all
   simulated by `u64sim`, so they are testable in CI from day one — and they
   are the commands most programs actually want.
3. **Risk tags** (§5), before the first write test.
4. **DOS writes**: `WRITE_DATA`, `CREATE_DIR`, `DELETE_FILE`, `RENAME`, `COPY`.
5. **Then decide the simulator question** (§6) before starting network or HTTP,
   because the answer changes how those get tested.

Do not start the Oscar64 / llvm-mos / KickC ports until the service API has
settled. Every port multiplies the cost of an API change, and there is a
toolchain image (`tools/docker`) ready to verify them when the time comes.

`bindings/oscar64/ultimate.mk` still lists the deleted C files, and the example
that used it is no longer built. It is one of those three ports now, not a
binding that needs a small repair: Oscar64 has no external assembler, so
reaching an assembly core from it means either a port held to `tests/emulator`
or a relocatable binary with a jump table.

---

## 8. Ground truth

- Hardware on the bench: Ultimate 64 Elite, `192.168.1.62`, firmware 3.15.
  Its **Command Interface setting is normally Disabled** — `hwtest.py` enables
  it per scenario and restores it, and never writes flash.
- Firmware source, worth grepping before assuming anything:
  `~/Git/1541ultimate` (v3.15-69). `roms/c64rom/kernal/uci.s` is Gideon's own
  6502 client and settles most arguments.
- Nothing in this repository has been committed yet.
