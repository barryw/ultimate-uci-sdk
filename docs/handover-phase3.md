# Handover: Phase 3, complete

Written to be picked up cold, alongside [handover.md](handover.md) and
[handover-next.md](handover-next.md). That first one is the state of the SDK and
the traps that have already cost debugging time; the second is the loose ends
and the boing ball. This one is Phase 3: what it delivered, what it found out,
and what the next person should not have to rediscover.

**A cleanup pass came after it**, and it is in
[handover-cleanup.md](handover-cleanup.md): a bug in `uci_abort`, the
documentation the figures below live in, and the order of what is next.

**Verify with `git log` rather than trusting the counts here.**

---

## 1. Where Phase 3 stands: done

| | |
|---|---|
| `dos.s` — chdir, getpath, opendir, readdir, open, close, read, write, seek, delete | **done** |
| `file.s` — load, bload, save, last_end, with the SoftwareIEC fast path | **done** |
| the `$A000` move — SDK under BASIC ROM, wedge keeps `$C000` | **done** |
| `reu.s` — RAM to REU over `$DF00-$DF0A`, and the DOS REU pair | **done** |
| BASIC keywords — `ULOAD` `UBLOAD` `USAVE` `UDIR` `USTASH` `UFETCH` | **done** |
| the blob's jump table — the same services, from a parameter block | **done** |
| network, http services | not started, and not needed: the generic form reaches them |

```
make test         GREEN   110 host unit tests + 187 across 8 suites
make hardware-run GREEN   5/5 scenarios, 40-52 checks each, 1-2 skips
make basic-run    GREEN   32/32 from the .prg and 32/32 from the .crt
make coverage     GREEN   24/101 commands, and 0 wrapped-but-untested
make blob         GREEN   5037 bytes at $8000, 305 relocations
make wedge        GREEN   wedge 2741 of the 4K at $C000, SDK 3498 of the 8K at $A000
```

**The promise the SDK was built to prove now holds end to end.** The same
operation reaches the Ultimate from assembly, from C and from BASIC, over the
same code:

```basic
ULOAD "/USB1/DATA/HELLO.TXT",51968 : IF UERR THEN PRINT "no file"
UDIR
USTASH 51968,0,16 : POKE 51968,0 : UFETCH 51968,0,16
```

Every line of that has been typed at a real Ultimate 64 by `make basic-run`,
from the `.prg` and from the cartridge alike.

## 2. What to do next

Phase 3 has no work left in it. The order below is what the next session should
weigh, not a plan already agreed.

### 2.1 The network and HTTP services

The last two families with no wrapper. The generic form reaches them today, and
`tools/gen_coverage.py` will insist on a test for each wrapper the moment one
lands — which for these means hardware, since `u64sim` implements neither.

Read [handover-next.md](handover-next.md) first: it has the measured round-trip
figures that decide whether an HTTP wrapper can be synchronous at all.

### 2.2 The boing ball

Still the best demonstration the SDK has, and still unbuilt. handover-next.md
§2 has the timing that shaped it.

### 2.3 Nothing — but read this before writing another hardware test

**Mutating hardware tests write to `/Temp`, which is a FAT filesystem the
firmware formats in RAM at boot** (`software/filesystem/ramdisk.cc`, about 3 MB
on a U64). It cannot fill somebody's medium, it cannot wear flash, and it is
gone on the next power cycle whatever a test does to it. `ucitest.c` creates
`/Temp/wr.tmp`, and `basictest.py` types `USAVE "/TEMP/SV.TMP"`.

That is how `write-data`, `seek`, `delete`, `reu-save-to-a-file` and `USAVE`
came to run rather than skip. They were skipping because **the USB stick in the
bench machine is full** — an FTP `STOR` of 64 bytes fails with `452` and the
firmware answers `WRITE_DATA` with `DISK IS FULL` — which is its owner's
business and not something a test should need fixed. The read-only fixture stays
at `/Usb1/data/hello.txt`; only writes moved.

The skip paths are still there and still say why, because a firmware without a
RAM disk is a machine this SDK should run on.

## 3. Things this session found out, that are not obvious

### A filesystem error arrives in words, not in a code

**This is the one to remember.** Ultimate DOS answers every failure that came
out of the *filesystem* rather than out of DOS itself with the bare FatFS text
and nothing in front of it — `DISK IS FULL`, `FILE DOESN'T EXIST`,
`WRITE PROTECTED`, `ACCESS DENIED`. Only its own canned statuses carry a `NN,`
code. In `software/filemanager/dos.cc` the commands that can answer this way are
`OPEN_FILE`, `WRITE_DATA`, `FILE_SEEK`, `DELETE_FILE`, `RENAME_FILE`,
`COPY_FILE` and `CREATE_DIR` — which is most of what a program does with files.

The SDK's decoder read that shape as a transport violation and returned
`ULTIMATE_ERR_PROTOCOL`, so **a program opening a file that was not there was
told the SDK was broken**. It is `ULTIMATE_ERR_DEVICE` now, with no device code,
and the words are in the caller's status buffer where they always were.

Found on the wire before it was found in the source: the new write tests failed
against the bench machine with a protocol error, and a raw probe showed
`DISK IS FULL`. `tests/emulator/protocol.suite` pins it now, and it reproduces
under `u64sim` as well as on hardware.

### `u64sim` implements the write half of Ultimate DOS

handover.md said it was read-only. It is not: `WRITE_DATA`, `FILE_SEEK`,
`DELETE_FILE`, `CREATE_DIR`, `RENAME_FILE` and `COPY_FILE` all work against the
real directory tree in `tests/emulator/fixtures/usb0`. So create/write/seek/read
back/delete runs in CI, and the hardware tests are a second opinion rather than
the only one.

It does **not** implement the DOS REU pair; `sdk.suite` pins the
`ULTIMATE_ERR_NOT_SUPPORTED` that comes back, and the hardware test is where
`LOAD_REU` actually moves bytes.

### Three traps in the test harness, all of which read as product bugs

- **A `.sym` file is filtered by a list in `tests/emulator/Makefile` and did not
  depend on it.** Adding a symbol left the `.sym` untouched, so the suite called
  address zero and the failure looked like a wedge bug. Every `.sym` rule
  depends on the Makefile now. This is the same shape as the three stale-build
  bugs from the previous session: anything a list or a flag is baked into needs
  that file as a prerequisite.
- **BASIC's own loop unwinds the stack between statements, and a suite calling
  handlers directly has no loop.** The third string argument in a test failed on
  stack rather than on anything the wedge did. `jsr($a67a)` — the ROM's own
  stack reset — goes before each statement, which is what the suite's setup
  already did once for the same reason.
- **`$FF81` does not return under this backend.** Bringing the screen editor up
  to read `UDIR`'s output off the screen hangs the simulator, so the test points
  `IBSOUT` (`$0326`) at a six-instruction stub in the cassette buffer and reads
  what the wedge emitted, in PETSCII, before anything draws it. **The stub has
  to `clc`**: BASIC's `OUTDO` goes through `$E10C`, which treats carry as an I/O
  error.

### The REU is testable in the simulator, but not the way you would hope

`$DF00-$DF0A` is ordinary read/write memory under `sim6502`, which is enough to
assert that every register got the right byte and that stash and fetch differ by
exactly the mode bit — and not enough to move anything. It also means the
availability probe, which writes two patterns and reads them back, reports a REU
that is not there. That is inherent to probing by readback and it is the right
trade for real hardware, where a missing expansion does not remember what it was
told. It is stated in `reu.s` where someone will read it.

## 4. Decisions taken, so they are not reopened by accident

**A status in words is a device error.** Two bytes or more, beginning with a
non-digit, on a target whose status is meant to be decimal: the target reported
a failure in words. One byte stays `ULTIMATE_ERR_PROTOCOL`, because one byte is
the binary shape and a decimal target has no binary vocabulary to read it with.

**The SDK touches `$DF1B-$DF1F`, and `$DF00-$DF0A` in `reu.s` alone.**
`tools/test_registers.py` makes the promise in docs/compatibility.md executable:
no `$DFxx` literal exists anywhere in the SDK, and the REU register names appear
in `reu.s` and in no other file. The list of modules allowed to drive hardware
directly is closed at two — `turbo.s` and `reu.s` — and the test that admits one
is whether the operation exists on the UCI at all.

**Never wrap the control target's REU pair.** `CTRL_CMD_LOAD_REU` never returns
on firmware 3.14d and wedges the interface until a power cycle
([#740](https://github.com/GideonZ/1541ultimate/issues/740)). The DOS pair
(`$21`/`$22`) does the same job and is wrapped; the control pair stays reachable
through the generic form, so issuing it is always deliberate.

**The blob's new entries take a parameter block, not registers.** Eighteen of
them at `+$4F` through `+$82`. A caller cannot pass a filename in `A`/`X`, and
the block is the only calling convention a BASIC program driving the blob with
`POKE` and `SYS` can express at all. Four fields were appended —
`bp_attrib`, `bp_pos`, `bp_reu`, `bp_reulen` — inside a block that has always
been a fixed 512 bytes, so nothing moved. **The table is still append-only.**

**`UDIR` folds ASCII lowercase up on its way to `CHROUT`.** `$41-$5A` draws as
letters and `$61-$7A` draws as graphics symbols, so every name reads as
lowercase on a stock screen. That is the same rule `tools/test_charmap.py`
enforces on the SDK's own strings.

**A BASIC keyword's arguments are evaluated with the ROM's own routines.**
`FRMNUM`/`GETADR` for 16 bits, `FRMNUM`/`QINT` for the REU's 24-bit address —
which is why `USTASH 51968,74565,256` works and why a `GETADR`-only
implementation would silently address the wrong megabyte.

## 5. Running things

```
make test                              everything that needs no hardware
make hardware-run U64_HOST=192.168.1.62   the SDK on the bench machine
make basic-run    U64_HOST=192.168.1.62   the wedge, typed at it, both deliveries
make time-run     U64_HOST=192.168.1.62   how long a round trip takes
```

The bench machine is an **Ultimate 64 Elite at `192.168.1.62`, firmware 3.15**.
**It cannot be power cycled remotely.** Its settings are never in a consistent
state, so everything goes through `tools/u64_settings.py`, which reads first,
writes only what is wrong, and restores only what it changed — including the
`RAM Expansion Unit` setting the REU tests need.

The hardware fixture lives at `/Usb1/data/hello.txt` and is pushed over FTP:

```
curl --ftp-create-dirs -T tests/emulator/fixtures/usb0/data/hello.txt \
     ftp://192.168.1.62/USB1/data/hello.txt
```

A one-off question about what the firmware really does is answered fastest by a
scratch suite and the `u64` backend, which is how `DISK IS FULL` and the DOS REU
pair's argument layout were both settled:

```
python3 tools/u64_settings.py --host 192.168.1.62 \
  --require "C64 and Cartridge Settings:Command Interface=Enabled" \
  -- docker run --rm -v $PWD:/code ghcr.io/barryw/sim6502:latest \
     -s /code/tests/emulator/probe.suite --backend u64 --u64-host 192.168.1.62
```

Delete the scratch suite afterwards. Nothing in `tests/emulator` is meant to be
temporary.
