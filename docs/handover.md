# Handover

Written to be picked up cold. Where things stand, what is already decided and
why, the traps that have already cost debugging time, and what to do next.

**Short version:** the transport is done and heavily tested, and it now ships in
a second form — a standalone relocatable binary with a jump table — so every
toolchain that cannot link a ca65 object can reach it. The service layer is
still just bring-up, detection and identity. The BASIC wedge is next.

**Verify with `git log` rather than trusting this file's counts.** As of writing:
15 commits, `main`, clean tree, HEAD `3e2bd71`.

---

## 1. Where things stand

| | State |
|---|---|
| Layer 1 — UCI transport | complete, assembly |
| Layer 2 — bring-up, detection, identity | complete, assembly |
| Layer 2 — dos, file, network, http, control, reu | **not started** — Phase 3 |
| Layer 3 — ca65 / cc65 bindings | working |
| Layer 3 — the blob (any toolchain, no linking) | **working** — Phase 1, done |
| Layer 3 — BASIC wedge | **not started** — Phase 2, next |
| Layer 3 — Oscar64, llvm-mos, KickC | not started; the blob is now their route in |

```
make lib              GREEN
make blob             GREEN     2860 bytes, 89 relocations
make -C examples/asm  GREEN
make -C examples/cc65 GREEN
make hardware         GREEN
make test             GREEN     38 host unit tests + 82 tests across 7 suites
make hardware-run     GREEN     4/4 scenarios, 13 checks each, on real hardware
make coverage         GREEN     0 wrapped-but-untested
```

### What Phase 1 added

The same object files, linked standalone at a chosen base with a jump table at
the first bytes and a page-aligned parameter block at `base+$100`. Anything that
can `jsr` an address can use the SDK with no linking at all — KickAssembler,
ACME, 64tass, Oscar64, llvm-mos, KickC, and BASIC via `POKE`/`SYS`.

**There is still exactly one implementation of the protocol.** The blob is not a
port; it is the library's own object files linked differently. Keep it that way.

- `bindings/blob/README.md` is the caller-facing contract: jump table offsets,
  parameter block layout, how to relocate.
- The jump table is **append-only**. Entries are never reordered or removed.
  Phase 2 and Phase 3 append to it.
- Relocation is a table of the 86-ish bytes holding the high half of an absolute
  address, produced by diffing two builds one page apart
  (`tools/gen_reloc.py`). Nothing in that generator knows about 6502 addressing
  modes, which is what stops it falling behind the assembler.
- Protocol constants are now generated for ca65, KickAssembler and ACME as well
  as C, all from `tools/gen_protocol.py`.

---

## 2. Things not to re-derive

Read [uci.md](uci.md) properly before writing a service. These have already cost
time:

- **Queue pointers saturate on the last byte.** A reply that exactly fills the
  896-byte response queue leaves `DATA_AV` set for ever. `while (DATA_AV) read`
  hangs the machine. The core bounds every drain; a service must never
  reimplement that loop.
- **Max command is 895 bytes, not 896.** The write pointer saturates the same
  way. A service that chunks a write must chunk to 895 minus its own header.
- **`DOS_CMD_READ_DATA` arrives in 512-byte blocks.** `uci_exec` already walks
  the chain; a service asks for what it wants and gets it whole.
- **Status encoding is decided by shape, not by target.** SoftwareIEC answers
  `IDENTIFY` in ASCII and everything else in binary. `uci_decode` sniffs. Do not
  add per-command status logic to a service.
- **Never put protocol bytes in a string literal.** `ca65 -t c64` installs the
  c64 charmap, so `.byte "OK"` assembles to PETSCII `$CF $CB`. Generate byte
  lists from `tools/gen_protocol.py`. Two deliberate exceptions, both tested and
  documented: the error strings in `ultimate_strerror.s` (printed via `CHROUT`,
  where PETSCII is what you want) and the blob's `"UCI"` signature (compared
  only against itself).
- **Argument shapes come from `ARGS` in `tools/gen_protocol.py`, never from a
  comment.** The comments used to carry the shapes in four notations and two of
  them were wrong. Every entry in `ARGS` was read out of the firmware source;
  `check_args()` rejects a shape that cannot be marshalled, and
  `tools/test_gen_protocol.py` pins the wire offsets that were wrong.
- **`SOFTIEC_CMD_LOAD_SU` sends an end-address pair it never reads.** The
  filename starts at offset 8, because a load shares `SAVE`'s layout. Send the
  name at 6 and the firmware opens whatever follows, which looks like "file not
  found" on a file that is plainly there.
- **The model name is mixed case**, unlike the uppercase identification strings.
- **Target `$05` reports present even when the drive is off, and that is
  intended** ([#794](https://github.com/GideonZ/1541ultimate/issues/794), answered
  by Gideon). Disabling the drive takes it off the IEC bus, not off UCI — UCI is
  how the hyperspeed kernal reaches it. So SoftwareIEC over UCI needs no setting
  from the user, and Phase 3's fast load has nothing to talk them through. A
  SoftwareIEC service still falls back on its first real command failing rather
  than on detection, because detection cannot see a mounted image or a valid
  path either way.
- **`UCI_CTRL_DMA` and `UCI_CTRL_TRIGGER` are not a fast path.** Both latch into
  `freeze_i` in the FPGA source — the freezer line. See uci.md's closing
  section. The real fast load is `SOFTIEC_CMD_LOAD_SU` then `LOAD_EX` on target
  `$05`, which pushes with a plain `$01` and no freeze bit; the firmware writes
  straight into C64 RAM and returns the end address in status bytes 1-2.

---

## 3. How a service is built

Every service is `uci_exec` plus argument marshalling. No service touches
`$DF1B-$DF1F` or the handshake. If you find yourself writing `sta
UCI_REG_CONTROL` in a service, stop.

The pattern is in `src/uci/ultimate.s`, `ultimate_get_model`. Wider parameters go
in the shared variable block rather than on any stack.

Three constraints that are not negotiable, because they are what the SDK sells:

1. **Caller-owned buffers.** No allocation, no hidden statics.
2. **Bounded time.** Every entry point completes or returns
   `ULTIMATE_ERR_TIMEOUT`. `uci_init` installs `UCI_TIMEOUT_DEFAULT`; services
   that wait on the network raise it themselves and restore it.
3. **Add your variables to the single block** in `uci_core.s`, and update
   `UCI_VARS_SIZE` in `tools/gen_protocol.py`. The `.assert` in `uci_core.s`
   fails the build if you forget. **Both branches** of that block — the
   `.ifdef UCI_VARS` equates and the `.else` BSS — must stay in step, or one of
   the two builds silently diverges.

**With `UCI_VARS` defined the SDK emits no BSS at all.** That is now true and
the blob depends on it. A new module with a `.bss` section breaks the standalone
link.

When a service wraps a command, add it to `WRAPPED` in `tools/gen_coverage.py`.
`make coverage` then **fails** until a test sends it.

**The one exception to "services never touch hardware"** will be `reu.s` in
Phase 3: there is no UCI command that moves bytes between C64 RAM and the REU,
so that module drives `$DF00-$DF0A` directly. It is an exception, not the rule
eroding — see the design doc.

---

## 4. Adding a test

Seven suites, all run by `make test` through the sim6502 container.

| Suite | Backend | Covers |
|---|---|---|
| `protocol.suite` | `u64sim`, and real hardware | firmware behaviours the SDK depends on |
| `sdk.suite` | `u64sim` | transport, services, status decoding |
| `sdk-placed.suite` | `u64sim` | the same with SDK RAM relocated (generated) |
| `timeout.suite` | `u64sim`, latency raised | bounded time |
| `absent.suite` | `sim` — nothing at `$DF1B` | failing fast with no Ultimate |
| `blob.suite` | `u64sim` | the blob through its jump table, no symbols |
| `blob-relocated.suite` | `u64sim` | the blob moved at run time |

**Most tests need no new assembly.** `harness.s` exports a request block and the
buffers it points at, so a suite fills the block from the DSL and calls
`t_exec`. `t_req_reset` zeroes it, re-aims its pointers and clears the buffers.
Add a harness entry point only for something the request block cannot express.

Traps in the DSL, each of which has already cost a debugging cycle:

- **sim6502 hard-fails any test whose body never executes anything.** A test of
  pure `assert()` against loaded memory will not run. Every test needs a `jsr`.
- **sim6502 does not reset CPU registers between tests.** `assert(a == $00)`
  after a call proves nothing unless you set `a = $ff` first. Two tests shipped
  vacuous this way before it was caught.
- **Write word fields as two byte stores.** A small value assigns as one byte
  and leaves the high byte of a pointer intact — the difference between a null
  pointer and a live one.
- **A behavioural test of relocated or generated code proves only the path it
  executes.** Where a linker-built reference exists, compare against it with
  `memcmp` instead. That is what `blob-relocated.suite` does now.

### Hardware

`ucitest.c` is a TAP program; add a check with `check(name, expected, actual)`.
It publishes counters to `$033C` so `hwtest.py` reads results by DMA.

`hwtest.py` reconfigures the Ultimate over REST and runs the program once per
configuration, restoring every setting afterwards and never writing flash.

---

## 5. Known debt, carried forward

These came out of the Phase 1 reviews. Each is real and each has a location.
Ordered by when they need doing.

**Before Phase 3:**

- `tests/emulator/blob-relocated.suite` hardcodes `memcmp(..., 2860)` and
  `relocharness.s` copies a fixed 12 pages (3072 bytes). Phase 3 grows the blob
  past that and **both relocation tests silently start under-verifying.** Derive
  both from the built size, or fail the build when the binary outgrows the copy.

**Whenever the relevant file is next touched:**

- `bindings/cc65/Makefile` and `bindings/blob/Makefile` keep two hand-maintained
  lists of the same modules. A fifth module added to the library would silently
  never reach the blob. Share one `sources.mk`.
- `ULT_ERR_COUNT = 10` in `ultimate_strerror.s` is hand-written beside ten
  generated `ULTIMATE_ERR_*` codes. An eleventh code silently prints "UNKNOWN
  ERROR". Emit the count, or `.assert` the table length.
- `tools/gen_coverage.py`'s untested-entry-point gate was never extended to the
  blob's jump table entries; most are never called by any test.
- `bindings/blob/README.md`'s jump table is hand-written. The design asked for it
  to be generated from the ca65 link map.
- **~20 harness assertions are non-vacuous only by accident.** `harness.prg`'s
  BSS overlaps cc65's ONCE segment by 38 bytes, so `result` and `caps_*` get
  non-zero bytes before each test. If that overlap ever changes, a whole class of
  `assert(... == $00)` goes vacuous with nothing failing. Use `memfill(..., $ff)`
  sentinels, as `sdk-absent-softiec` already does correctly.
- `sdk.suite`'s `sdk-exec-rejects-wrapping-lengths` is vacuous: `arglen` is
  rejected against the maximum before the sum is computed, and with both bounds
  in place a 16-bit wrap is unreachable. Delete it or say plainly that the sum
  check is unreachable defence-in-depth.
- `timeout.suite`'s header claims to prove bounded time for every entry point.
  It exercises one path, and asserts init *succeeds* under that latency. Narrow
  the claim or add the cases.
- `docs/architecture.md` says `uci_core.s` assembles to 1398 bytes; measured is
  1401. Predates Phase 1.

---

## 6. The simulator ceiling — decided

`u64sim` implements Ultimate DOS (`$01`/`$02`) and part of the control target
(`$04`). Network, HTTP, SoftwareIEC and the REU are **hardware only**.

**The decision, taken: accept hardware-only coverage for what the simulator
cannot reach, and treat `make hardware-run` as required before a release rather
than optional.** The SoftwareIEC fast load path in Phase 3 lives permanently in
`tests/hardware` for this reason. Extending `u64sim` stays open but is not on
the critical path.

Fixtures live in `tests/emulator/fixtures/usb0`. For real hardware they are
pushed over FTP — the REST API has no arbitrary file-write endpoint:

```
curl --ftp-create-dirs -T tests/emulator/fixtures/usb0/data/hello.txt \
     ftp://192.168.1.62/USB1/data/hello.txt
```

**Test data policy:** every mutating test creates its own file, uses it, and
deletes it. Nothing pre-existing on the device is ever touched. That collapses
the old four risk tags into two that matter — `mutating` is safe by default
because it only touches what it made, and `destructive` shrinks to the genuinely
irreversible (reboot, flash, palette), which stays opt-in.

`CTRL_CMD_LOAD_REU` (`$04 $08`) never returns on firmware 3.14d and wedges the
interface until a power cycle
([#740](https://github.com/GideonZ/1541ultimate/issues/740)). **Wrap the DOS REU
pair (`$21`/`$22`); never wrap the control pair.** It stays reachable through the
generic form only, so issuing it is always deliberate.

---

## 7. What to do next

The design is written and agreed: **[docs/superpowers/specs/2026-08-17-uci-everywhere-design.md](superpowers/specs/2026-08-17-uci-everywhere-design.md)**.
Read it before starting. Phase 1's plan, for the shape a plan should take, is
[docs/superpowers/plans/2026-08-17-phase1-blob.md](superpowers/plans/2026-08-17-phase1-blob.md).

The goal in one line: **a complete, parallel implementation of the UCI in
assembly, C and BASIC, in the smallest and most reusable form that can be
built.** Completeness comes from the generic `uci_exec`; sugar earns its place
only where the generic form cannot express the operation.

| | Phase | Notes |
|---|---|---|
| 1 | the blob | **done** |
| 2 | **BASIC wedge** — next | generic `UCI` statement and function, observers (`UERR`, `UST$`, `UDATA$`, `UBYTE`, `ULEN`, `UDEV`), target constants, `W()`/`L()`, installer with banner, `.prg` and `.crt` builds, `basic.suite` |
| 3 | DOS service, file convenience, SoftwareIEC fast path, `reu.s` | `ULOAD`/`UBLOAD`/`USAVE`/`UDIR`/`USTASH`/`UFETCH` in all three languages at once |

**Phase 2's stated blocker is cleared.** The argument shapes are structured data
now: `ARGS` in `tools/gen_protocol.py`, 67 commands, `(kind, spec)` pairs over
`byte`, `word`, `dword`, `str`, `pstr`, `data` and `lit`. `check_args()` fails
generation on a shape that cannot be marshalled, the reference gained an
argument column, and the emitters render the shape instead of repeating it in
prose. What the wedge still needs is the ~150-byte in-memory table it dispatches
on, generated from `ARGS` — nothing else has to be decided first.

Every shape was read out of the firmware source rather than transcribed, which
is worth keeping up as the table grows: it caught two errors the prose had been
carrying, one of them on Phase 3's critical path. See §2.

Do not start the Oscar64 / llvm-mos / KickC ports until the service API has
settled. The blob is now their route in, so none of them needs a port at all.
`bindings/oscar64/ultimate.mk` still lists the deleted C core and does not
build; it is marked broken.

---

## 8. Ground truth

- Hardware on the bench: **Ultimate 64 Elite, `192.168.1.62`, firmware 3.15**
  (fpga 123, core 1.4E). Real hardware reports `targets=$007e` — all six —
  against `$0016` under the simulator.
- **Its settings are never in a consistent state**, because new firmware is
  tested often and settings get reset. `Command Interface` is normally
  `Disabled`.

  **Never assume a baseline. `tools/u64_settings.py` is the shared guard** — it
  reads each required setting, writes only the ones that are wrong, runs the
  command, and restores only what it actually changed, on success, on failure
  and on Ctrl-C alike. A setting already correct is never written and never
  "restored" to a value it never left. It passes the wrapped command's exit
  status through, so `make` still fails when tests fail.

  ```
  python3 tools/u64_settings.py --host 192.168.1.62 \
      --require "C64 and Cartridge Settings:Command Interface=Enabled" \
      -- <command and its arguments>
  ```

  Both `hwtest.py` and `tests/emulator/Makefile`'s `hardware:` target go through
  it; `tools/test_u64_settings.py` covers the logic against a fake REST client,
  and runs under `make test` without needing hardware or Docker. Any new test
  that needs a setting wraps itself the same way rather than growing a second
  copy of this.

  The symptom when a caller forgets: sim6502's `u64` backend fails every test
  with `status $1D`, "the Ultimate's error latch rejected this command push",
  which looks like a broken SDK and is not.
- Firmware source, worth grepping before assuming anything: `~/Git/1541ultimate`
  (v3.15-69). **It is GPL-3.0 and this SDK is MIT — it is a reference for
  interface facts only, never a source to copy from.** Copying would relicense
  the SDK and remove the reason a demo author can link it into something they
  sell. `roms/c64rom/kernal/uci.s` is Gideon's own 6502 client and settles most
  arguments; `software/6502/cmd_test_rom.tas` is an 8K autostart cartridge that
  adds a BASIC command driving the UCI — the closest prior art to Phase 2.
- KickAssembler is at `/Users/barry/Development/Kickassembler/kickass`. ACME is
  installed. Both parse the generated constant files.
