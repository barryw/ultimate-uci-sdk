# Handover: Phase 3, in progress

Written to be picked up cold, alongside [handover.md](handover.md) and
[handover-next.md](handover-next.md). That first one is the state of the SDK and
the traps that have already cost debugging time; the second is the loose ends
and the boing ball. This one is Phase 3: what is built, what is not, and the
things this session found out the hard way.

**Verify with `git log` rather than trusting the counts here.** As of writing,
HEAD is `96a20ea` and the last eight commits are the whole of this session.

---

## 1. Where Phase 3 stands

| | |
|---|---|
| `dos.s` — chdir, getpath, opendir, readdir, open, close, read, write, seek | **done**, `7c415db` |
| `file.s` — load, bload, save, last_end, with the SoftwareIEC fast path | **done**, `96a20ea` |
| the `$A000` move — SDK under BASIC ROM, wedge keeps `$C000` | **done**, `33ebb01` |
| `reu.s` — RAM to REU over `$DF00-$DF0A` | **not started** |
| BASIC keywords — `ULOAD` `UBLOAD` `USAVE` `UDIR` `USTASH` `UFETCH` | **not started** |
| network, http services | not started, and not needed: the generic form reaches them |

```
make test         GREEN   100 host unit tests + 155 across 8 suites
make hardware-run GREEN   5/5 scenarios, 27 checks in the enabled ones
make basic-run    GREEN   13/13 from the .prg and 13/13 from the .crt
make coverage     GREEN   but see §2.1 - it is green for the wrong reason now
make blob         GREEN   4560 bytes at $8000, variables at $9F00
make wedge        GREEN   wedge 2090 of the 4K at $C000, SDK 1595 of the 8K at $A000
```

## 2. What to do next, in order

### 2.1 `make coverage` has gone quietly wrong — do this first

It reports **13/101 and passes**, which was true before `dos.s` and is not true
now. `WRAPPED` in `tools/gen_coverage.py` never gained the DOS and file
commands, so `OPEN_FILE`, `READ_DATA`, `READ_DIR`, `CHANGE_DIR` and the rest
still read as *"no API yet"* when they have had an API for two commits.

This is exactly the failure that file exists to catch, inverted: a wrapper with
no test is what it gates on, and a wrapper it has never been told about is
invisible. Add them, with the entry points that send them — the mechanism is
already there from the palette work:

```python
"DOS_CMD_OPEN_FILE":  ("ultimate_open",),
"DOS_CMD_READ_DIR":   ("ultimate_readdir",),
...
```

**Expect `--check` to go red, and that is the point.** `write`, `seek` and
`save` have no test behind them, because `u64sim` implements only the read-only
half of Ultimate DOS. So they need hardware tests, and those need a writable
fixture: create a file, use it, delete it, exactly as the test data policy in
handover.md §6 requires. That is the real work item hiding behind this one.

### 2.2 The BASIC keywords

Six of them, and they are the last thing standing between Phase 3 and the
promise the whole SDK is built on — the same operation, the same call, from all
three languages.

`gen_keywords.py` is **append-only: a token is a file format.** `UTURBO` is
`$DB`, so these start at `$DC`. The machinery is all in place and `UTURBO` is
the worked example: one entry in `KEYWORDS`, a branch in `wedge_gone` for the
statement form, a branch in `wedge_eval` for a function form, and a handler.

Two things to remember, both already paid for once:

- **`ULOAD`, `UBLOAD` and `USAVE` do not arrive as the text the user typed.**
  CRUNCH matches a reserved word anywhere, so they contain `LOAD` and `SAVE` and
  reach the wedge as token sequences. The generated table carries both forms and
  the wedge matches the crunched one; `LIST` prints the name. This is handled
  for free — `gen_keywords.py` computes it — but a name that crunches to
  something containing `DATA` or `REM` is refused outright, so check the
  generator's output rather than assuming.
- **Every call into the SDK goes through `src/basic/bank.s`.** The SDK is at
  `$A000` under BASIC ROM now. Add a stub per entry point the new keywords need;
  do not `jsr ultimate_load` from `dispatch.s`.

`UDIR` is the interesting one. It prints to the screen through `CHROUT`, so it
converts each entry from ASCII as it goes, and it is the first consumer of
`ultimate_readdir` outside a test. Remember the walk is one live exchange: no
other command between calls.

### 2.3 `reu.s`

The second and last member of the closed list of services that do not go
through `uci_exec` — there is no UCI command that moves bytes between C64 RAM
and the REU, so it drives `$DF00-$DF0A` directly. `turbo.s` is the worked
example of that exemption and the design doc's §"The services that do not go
through `uci_exec`" states the test that admits one.

**Wrap the DOS REU pair (`$21`/`$22`); never wrap the control pair.**
`CTRL_CMD_LOAD_REU` never returns on firmware 3.14d and wedges the interface
until a power cycle ([#740](https://github.com/GideonZ/1541ultimate/issues/740)),
and the bench machine cannot be power cycled remotely.

### 2.4 The blob's jump table, once the services settle

`dos.s` and `file.s` are in the blob binary and reachable by symbol from a ca65
link, but they are **not on the jump table**. That is deliberate: a blob caller
cannot pass a filename in `A`/`X` alone, and the parameter block does not carry
their arguments yet. Giving them entries before it does would fix the wrong
contract for ever, and the table is append-only.

The parameter block already has `bp_name` (40 bytes at `+$29`), `bp_addr` and
`bp_len`, which is most of what `ULOAD` needs. That is the shape to finish.

---

## 3. Things this session found out, that are not obvious

### `READ_DIR` is why `uci_exec_first` / `uci_exec_next` exist

`DOS_CMD_READ_DIR` does not answer with a list. It answers with **one reply
block per entry**, each `<attrib> <name>` with no terminator and no length, and
the block boundary is the only thing separating one name from the next.
`uci_exec` stitches the chain into one buffer — right for every other command,
and for this one it destroys the answer, because an attribute byte of `$20` is a
space and a filename containing one is indistinguishable from the next entry.

Confirmed against `software/filemanager/dos.cc` *and* against the wire before
any code was written: `READ_DIR` on the fixture tree returns 13 bytes,
`$10 "data" $20 "big.bin"`, concatenated.

`uci_exec` is now `uci_exec_send` plus a loop over `uci_collect_one`, and the
stepwise pair is the same two pieces stopped at each boundary. Behaviour is
unchanged and both the emulator suites and a hardware run say so.

### The status decoder reads lookup tables out of RODATA

`uci_tens` and `uci_hundreds_*` in `uci_core.s` convert the ASCII status digits
into a number. If they are wrong, a command that ran perfectly comes back
`ULTIMATE_ERR_DEVICE` — data intact, status garbage. That is what a
mis-ordered linker segment produced during the `$A000` move, and it is a very
convincing-looking failure. If you ever see a correct reply with a device error,
look at RODATA before looking at the command.

### Three stale-build bugs, all the same shape

Each one relinked without reassembling, and each produced a binary that looked
fine:

- `src/basic/Makefile` had no dependency from its objects to the generated
  includes, so a regenerated `uci_keywords.inc` left the wedge half-knowing a
  keyword — dispatch handled the token, the tokeniser had never heard of it.
- `bindings/blob`'s `.cfg` files bake in `BASE` and `VARS` and did not depend on
  the Makefile.
- `bindings/blob`'s **objects** bake in `-D UCI_VARS` and did not depend on it
  either, so changing `VARS` gave a blob addressing its variables where they used
  to be: init and the timeout accessors passed, every command returned
  `INVALID_ARGUMENT`.

All three are fixed. The lesson is worth keeping: anything a build flag is baked
into needs that flag's file as a prerequisite.

### The sim6502 DSL writes one byte, not two

`$addr = $0000` stores the low byte and leaves the high one holding whatever was
in RAM. handover.md §4 has always said to write word fields as two byte stores;
`blob.suite` was not doing it and got away with it only while the variables
happened to sit inside the loaded image. Write every byte.

Assertions and assignments also differ: `assert(([x] + $01).b == ...)` needs the
`.b`, and `[x] + $01 = ...` must not have it.

### A filename is protocol, not display text

`tests/hardware/ucitest.c` builds `"/Usb1/data/hello.txt"` as numeric bytes.
cc65 would charmap a literal and send `'d'` as `$44`, ASCII `'D'` — which works
only because FAT lookup is case-insensitive. `tools/test_charmap.py` does not
catch this: it flags uppercase in literals, and a lowercase literal is still
charmapped. Anything that goes on the wire is bytes.

---

## 4. Decisions taken, so they are not reopened by accident

**The SDK runs at `$A000` under BASIC ROM; the wedge keeps `$C000`.** Phase 3
took the two together past 4K. `src/basic/bank.s` is twelve bytes per entry
point — not one shared trampoline, because the argument and the result both live
in `A` and sharing one would need the target address somewhere else. Only code
moved: RODATA and BSS stay at `$C000`, which is RAM whatever `$01` says. The
copy banks nothing, because a 6510 write always goes to RAM and only a read sees
ROM. Interrupts stay on: `$36` leaves the KERNAL and I/O mapped, and there is no
`sei` on purpose, because `uci_exec` can poll for a long time.

**The blob is based at `$8000`, and that is a different trade from the wedge's.**
Its caller picks the base and cannot be asked to bank, so `$8000-$9FFF` — RAM
with nothing mapped over it — is right for it and `$A000` is not. `blob.cfg.in`
sizes the code area from `VARS`, so a build that does not fit fails to link.

**`ULTIMATE_END` is a result, not an error.** `readdir` needs "no more entries"
to be distinguishable from a failure. Adding it cleared the `ULT_ERR_COUNT`
debt: the count is generated now and `strerror` asserts its table against it.

**Two services touch hardware and the list is closed**: `turbo.s`, built, and
`reu.s`, to come. The test that admits one is whether the operation exists on
the UCI at all.

---

## 5. Running things

```
make test                              everything that needs no hardware
make hardware-run U64_HOST=192.168.1.62   the SDK on the bench machine
make basic-run    U64_HOST=192.168.1.62   the wedge, typed at it, both deliveries
make time-run     U64_HOST=192.168.1.62   how long a round trip takes
```

The bench machine is an **Ultimate 64 Elite at `192.168.1.62`, firmware 3.15**
(a post-tag build: `firmware_version` cannot tell one from 3.15 itself, which is
why the palette commands work on it). **It cannot be power cycled remotely.**
Its settings are never in a consistent state — `Command Interface` and
`Turbo Control` are both normally off — so everything goes through
`tools/u64_settings.py`, which reads first, writes only what is wrong, and
restores only what it changed.

The hardware fixture lives at `/Usb1/data/hello.txt` and is pushed over FTP:

```
curl --ftp-create-dirs -T tests/emulator/fixtures/usb0/data/hello.txt \
     ftp://192.168.1.62/USB1/data/hello.txt
```

`make time-run` is not a test. It measures, and the numbers it prints decided
the boing ball's shape — a whole-palette rotation is 0.24 frames, so colour
cycling is not the constraint. See handover-next.md §2 for the full table and
for the turbo figures.
