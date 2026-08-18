# Handover

Written to be picked up cold. Where things stand, what is already decided and
why, the traps that have already cost debugging time, and what to do next.

**Short version:** the transport is done and heavily tested, and it now ships in
a second form — a standalone relocatable binary with a jump table — so every
toolchain that cannot link a ca65 object can reach it. The service layer is
bring-up, detection and identity, plus two services that needed no Phase 3
work to be useful: the palette, and turbo. The BASIC wedge is complete.

**Verify with `git log` rather than trusting this file's counts.** As of writing:
15 commits, `main`, clean tree, HEAD `3e2bd71`.

---

## 1. Where things stand

| | State |
|---|---|
| Layer 1 — UCI transport | complete, assembly |
| Layer 2 — bring-up, detection, identity | complete, assembly |
| Layer 2 — the palette, on the control target | complete, assembly — `src/uci/palette.s` |
| Layer 2 — turbo, on `$D031` | complete, assembly — `src/uci/turbo.s`, in all three languages |
| Layer 2 — dos: files and directories | complete, assembly — `src/uci/dos.s` |
| Layer 2 — file: load, bload, save | complete, assembly — `src/uci/file.s`, two-tier |
| Layer 2 — reu: stash, fetch, and the DOS REU pair | complete, assembly — `src/uci/reu.s` |
| Layer 2 — network, http | **not started** — Phase 4 |
| Layer 3 — ca65 / cc65 bindings | working |
| Layer 3 — the blob (any toolchain, no linking) | **working** — Phase 1, done |
| Layer 3 — BASIC wedge | **Phase 3 complete** — `.prg` and `.crt`, 49 tests, 22 keywords |
| Layer 3 — Oscar64, llvm-mos, KickC | not started; the blob is now their route in |

```
make lib              GREEN
make blob             GREEN     5037 bytes, 305 relocations, based at $8000
                                with its variables at $9F00: file.s overflowed
                                the old 4K at $C000 by 350 bytes and the link
                                said so
make -C examples/asm  GREEN
make -C examples/cc65 GREEN
make hardware         GREEN
make wedge            GREEN     uci.prg 5948 bytes, uci.crt 8272. The wedge
                                holds 2741 of the 4K at $C000, and the SDK runs
                                at $A000 under BASIC ROM: 3498 of 8K, reached
                                through the stubs in src/basic/bank.s
make test             GREEN     110 host unit tests + 187 tests across 8 suites
make basic-run        GREEN     32/32 from the .prg and 32/32 from the .crt, the
                                same checks typed at a real C64. The cartridge
                                costs BASIC 8K: 38911 bytes free becomes 30719
make hardware-run     GREEN     5/5 scenarios on real hardware: 40 checks in
                                the plain one, 52 with the RAM expansion
                                switched on and 47 with turbo. The only skips
                                left are turbo and the REU where their setting
                                is off, which is what those scenarios exist to
                                turn on. uci-disabled asserts one clean failure
                                and reports failed=1 on purpose
make coverage         GREEN     0 wrapped-but-untested
make time-run         n/a       not a test: it times a UCI round trip on the
                                machine and prints the numbers. A whole-palette
                                rotation is 0.24 frames
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
- **Display strings are written lowercase in the source, in C as well as in
  assembly.** ca65's c64 charmap sends source `'A'-'Z'` to PETSCII `$C1-$DA`, and
  CHROUT renders those as *graphics symbols*. Source `'a'-'z'` becomes PETSCII
  `$41-$5A` and displays as letters. **cc65 applies the same charmap to C string
  literals**, so the rule is one rule. `ultimate_strerror.s`,
  `examples/asm/identify.s`, the wedge banner and then `examples/cc65/identify.c`
  were all written the obvious way and all printed glyphs on a real machine, for
  as long as they had existed. The handover used to say PETSCII was "what you
  want" here; that was half a rule, and the half about protocol bytes never
  touching the charmap is the half that was right.

  `tools/test_charmap.py` is the guard on the C side: it fails `make test` on an
  uppercase letter in any string literal under `examples/`, `tests/hardware/` or
  `include/`. `printf("%x")` is exempt and correct — see handover-next.md.
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

**`src/uci/palette.s` is the worked example to copy from** — it is the newest and
smallest complete service: four commands, its own module because cc65 links whole
object files and folding it into `ultimate.s` would charge every program for
palette code it never calls, and it reuses `ult_req_clear` from `ultimate.s`
rather than growing a second copy. Add the module to `src/uci/sources.mk` and
both bindings pick it up.

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

**The SDK runs at `$A000`, under BASIC ROM, in both wedge builds.** Phase 3 took
the wedge and the SDK together past the 4K at `$C000`, so the wedge kept the
block and the SDK moved. It costs one twelve-byte stub per entry point -
`src/basic/bank.s` - because the SDK is never called by BASIC ROM and calls no
BASIC routine, which is the whole difference between moving it and moving the
hook handlers. It buys 2018 free bytes at `$C000` and 6597 at `$A000`, and it
costs BASIC nothing either way: both regions are outside BASIC's RAM.

Three things about that arrangement worth knowing before touching it:

- **Only the code moved.** RODATA and BSS stay at `$C000`, because `$C000` is
  RAM whatever `$01` says and data is read rather than executed. One copy loop
  became two, not three.
- **The copy banks nothing.** A 6510 write always goes to RAM; only a read sees
  ROM. So `wedge_copy` writes the SDK into `$A000-$BFFF` with the machine
  exactly as BASIC left it.
- **Interrupts stay on.** `$36` leaves the KERNAL and I/O mapped, so `$EA31` is
  still there and still works. There is no `sei` in the stubs on purpose: a
  `uci_exec` can poll for a long time, and stopping the jiffy clock for it would
  be the worse bargain.

Segment order in the linker configs is load-bearing: `wedge_copy` moves CODE and
RODATA as one span, so anything placed between them is copied instead of the
RODATA. `UCICODE` was, briefly, and the symptom was a command that ran
perfectly and came back `ULTIMATE_ERR_DEVICE` - the status decoder reading its
digit-weight tables out of whatever had landed on them. `install.s` asserts the
adjacency now.

**Two services do not go through `uci_exec`, and the list is closed.** The test
that admits one is the same both times: does the operation exist on the UCI at
all? If it does, use `uci_exec`. If the only way to reach it is a memory-mapped
register, the rule about not reimplementing the transport has nothing to bite
on, because there is no transport.

- `src/uci/turbo.s`, built: nothing in the control target's command set touches
  CPU speed, so it drives `$D031` directly.
- `reu.s`, Phase 3: no UCI command moves bytes between C64 RAM and the REU, so
  it will drive `$DF00-$DF0A` directly.

Adding a third means showing that `docs/generated/protocol-constants.md` has no
command for the job. See the design doc.

---

## 4. Adding a test

Eight suites, all run by `make test` through the sim6502 container. The last one
is ROM-gated: Commodore's images cannot be committed, so `make basic` skips with
a message naming the fix unless `tests/emulator/roms` holds `basic.bin` and
`kernal.bin`, or `C64_ROMS` points somewhere that does. CI runs the other seven.

| Suite | Backend | Covers |
|---|---|---|
| `protocol.suite` | `u64sim`, and real hardware | firmware behaviours the SDK depends on |
| `sdk.suite` | `u64sim` | transport, services, status decoding |
| `sdk-placed.suite` | `u64sim` | the same with SDK RAM relocated (generated) |
| `timeout.suite` | `u64sim`, latency raised | bounded time |
| `absent.suite` | `sim` — nothing at `$DF1B` | failing fast with no Ultimate |
| `blob.suite` | `u64sim` | the blob through its jump table, no symbols |
| `blob-relocated.suite` | `u64sim` | the blob moved at run time |
| `basic.suite` | `u64sim` **+ real BASIC ROM** | the wedge: tokenising, LIST lookup, and commands running against a simulated Ultimate |

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

`ucitime.c` is the other on-device program and is **not** a test: it measures
how long a UCI round trip takes and prints the answer, which changes with the
firmware and with the machine. It shares `ucitest.c`'s shape — a result block in
the cassette buffer, read back by DMA — and chains CIA #2's timers into a 32-bit
cycle counter, timing ten raster frames on that same counter so every figure is
a ratio and nothing has to assume PAL, NTSC or a CPU speed. Numbers and method
are in [handover-next.md](handover-next.md) §3.

---

## 5. Known debt, carried forward

These came out of the Phase 1 reviews. Each is real and each has a location.
Ordered by when they need doing.

**Two of them are now cleared,** both by the palette service, which is what made
them bite:

- The blob's size is no longer written down anywhere by hand.
  `tests/emulator/Makefile` generates `blobsize.inc` and `blob-relocated.suite`
  from the binary it just built, so `relocharness.s` copies as many pages as
  there are and the suite compares as many bytes as exist. The old hand-written
  2860 was twelve bytes from going wrong: adding the palette took the blob to
  3060 against a 3072-byte copy.
- `bindings/cc65` and `bindings/blob` share one module list,
  `src/uci/sources.mk`. `palette.s` was the fifth module the old note warned
  about.
- `ULT_ERR_COUNT` is generated with the codes themselves and
  `ultimate_strerror.s` asserts its table against it. `ULTIMATE_END` was the
  eleventh code the old note predicted would silently print "UNKNOWN ERROR".

**Cleared in the cleanup pass after Phase 3:**
- The blob's jump table entries are exercised: `blob.suite` walks the DOS, file
  and REU services through the parameter block with no symbols at all, and
  `tools/test_blob_table.py` fails the build when `blob.s` and the README
  disagree about an offset - which is the cheaper half of generating the table
  from the link map.
- **The harness sentinels are in.** `sdk.suite`'s setup fills `result`,
  `devcode`, `reply_len` and the capability block with `$FF` before every test,
  so an assertion that only passed because BSS happened to be zero now fails.
  All 56 still pass, which is the answer to whether they were vacuous.
- `sdk-exec-rejects-wrapping-lengths` proved nothing: each length is bounded
  before the sum, so no wrapping pair reaches the addition. It is
  `sdk-exec-rejects-a-total-that-does-not-fit` now, with two lengths that are
  legal apart and too much together - which only the sum check can catch.
- `timeout.suite`'s header says what it exercises: one path, the one every
  entry point reaches the hardware through.
- `docs/architecture.md`'s size figure is measured again, from the link map.

**Whenever the relevant file is next touched:**
- `tools/gen_coverage.py` gates SDK entry points, not the wedge's keywords. A
  keyword could be added to `gen_keywords.py`, tokenise, and dispatch to nothing
  without anything failing; `basic.suite` covers today's by hand.

---

## 6. The simulator ceiling — decided

`u64sim` implements Ultimate DOS (`$01`/`$02`) — **both halves of it: writes,
seeks and deletes work against the fixture tree, not only reads** — and part of
the control target (`$04`). Network, HTTP, SoftwareIEC, the REU's own registers
and the DOS REU pair are **hardware only**.

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
deletes it. Nothing pre-existing on the device is ever touched. **On hardware
they write to `/Temp`**, the FAT filesystem the firmware formats in RAM at boot
(`software/filesystem/ramdisk.cc`): it cannot fill anybody's medium, cannot wear
flash, and does not survive a power cycle even if a test dies halfway through.
The read-only fixture stays on the USB stick. That collapses
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

**Three files, and they do different jobs.** This one is the state of the SDK
and the traps that have already cost debugging time.
[handover-phase3.md](handover-phase3.md) is what Phase 3 delivered and what it
found out — start there. [handover-next.md](handover-next.md) is the loose ends, the
turbo measurements and the boing ball.


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
| 2 | BASIC wedge | **done** — tokens, all four vectors, the generic `UCI`, observers, `UW(`/`UL(`, argument shapes, `.prg` and `.crt` |
| 3 | DOS service, file convenience, SoftwareIEC fast path, `reu.s` | **done** — `ULOAD`/`UBLOAD`/`USAVE`/`UDIR`/`USTASH`/`UFETCH` in all three languages at once, and the same services on the blob's jump table |
| 4 | network and HTTP services | not started; the generic form reaches both today |

**Phase 2's stated blocker is cleared.** The argument shapes are structured data
now: `ARGS` in `tools/gen_protocol.py`, 67 commands, `(kind, spec)` pairs over
`byte`, `word`, `dword`, `str`, `pstr`, `data` and `lit`. `check_args()` fails
generation on a shape that cannot be marshalled, the reference gained an
argument column, and the emitters render the shape instead of repeating it in
prose.

The in-memory table the wedge dispatches on is generated from it, into
`bindings/asm/uci_argtable.inc`: **98 bytes**, 21 entries, only the commands the
default rule cannot marshal. It has no consumer until the wedge exists, so CI
assembles it on its own to stop it rotting quietly.

**The wedge tokenises and lists.** `src/basic/` builds `uci.prg`: 580 bytes, of
which the resident wedge at `$C000` is 346. `LOAD "UCI",8` then `RUN` installs
it. `ICRNCH` and `IQPLOP` are owned; `IGONE` and `IEVAL` are not, so the tokens
exist but nothing runs yet — typing `UCI 1,4` tokenises and then reaches BASIC's
own dispatcher, which does not know the token.

**Two traps the wedge had to be built around, both from modelling the ROM's
CRUNCH in `tools/c64_crunch.py` rather than reasoning about it:**

- **CRUNCH drops input bytes `>= $80`**, pi excepted. So the wedge cannot write
  its tokens into the input buffer and let the ROM crunch afterwards. It calls
  the ROM first and substitutes into the result, compacting in place.
- **A reserved word is matched anywhere, not only at a word boundary.** `ULEN`
  reaches the wedge as `'U' $C3` because CRUNCH found `LEN` inside it. The match
  patterns are the crunched forms, which is why they are generated. This also
  killed `UDATA$` (its embedded `DATA` token stops the rest of the statement
  being tokenised) and bare `W`/`L` (they would tokenise the `W` in
  `FOR W=1 TO 10`). See `docs/generated/basic-keywords.md`.

**The wedge claims no zero page.** It runs from RAM, so its state sits beside
its code. The SDK already has `UCI_ZP`, defaulting to `$FB`, and two things
quietly sharing the free bytes is a bug nobody finds for months.

Every shape was read out of the firmware source rather than transcribed, which
is worth keeping up as the table grows: it caught two errors the prose had been
carrying, one of them on Phase 3's critical path. See §2.

**The Oscar64 / llvm-mos / KickC ports are not wanted, and the question is
closed.** The blob is their route in: the same object files linked at a base
address, with a jump table and a parameter block, which every one of them can
`jsr` without linking anything. `bindings/oscar64` was a source list naming the
C core the assembly rewrite deleted, marked broken by its own header and built
by nothing; it and its example are gone. A real port would still have to pass
`tests/emulator` unchanged if anyone ever wanted one.

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
