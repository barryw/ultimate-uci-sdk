# Handover: the cleanup pass, and the order after it

Written to be picked up cold, alongside [handover.md](handover.md), which is the
state of the SDK and the traps that have already cost debugging time,
[handover-phase3.md](handover-phase3.md), which is what Phase 3 delivered, and
[handover-next.md](handover-next.md), which is the loose ends and the boing
ball. This one is the pass that came after Phase 3: what it fixed, what it
found, and what is left in the order it should be done.

**Verify with `git log` rather than trusting the counts here.** The pass is one
commit, `922ba4f`.

---

## 1. What this was

A deliberate stop before new features: make the documentation true, take out
what is dead, and give back whatever bytes were being spent twice. The brief
was a clean, consistent, complete SDK before anything is built on it.

It found one real bug, which is the usual argument for doing this at all.

## 2. The bug: `uci_abort` could not recover the case it exists for

**An abort is not serviced while the interface is holding a reply block.** The
firmware is waiting for `DATA_ACC`; until it gets one the state never leaves
*data-more*, so the abort's own wait for idle times out and nothing is cleared.

The ordinary way to get there is a directory walk given up half way — read the
first entry, decide it is the one you wanted, stop. Every command after that
returned `ULTIMATE_ERR_TIMEOUT`, **including the abort meant to rescue it**, and
docs/uci.md said abort cleared every failure mode there was.

`uci_abort` now releases whatever is held first, with `DATA_ACC`, until the
state falls below *data-last*, and only then aborts. Releasing without reading
is exactly right for a drain: `DATA_ACC` resets both queues whether or not
anything read them. The loop is bounded by the same timeout budget as every
other wait in the SDK, so a device stuck in *data-more* cannot hold the CPU.

Pinned in three places, because it was invisible in all of them:

- `sdk.suite`'s `sdk-abort-recovers-an-abandoned-walk` — one entry, then abort,
  then two more commands that have to work.
- `ucitest.c` — the same sequence against real firmware, which is where the
  state machine is the real one.
- `docs/uci.md`, "Recovering a wedged interface" — as a fourth failure mode,
  with the mechanism.

It was found by writing the blob's parameter-block test, which walked a
directory the way a program would and stopped. Nothing else had ever stopped.

## 3. What else changed

| | |
|---|---|
| `bindings/oscar64`, `examples/oscar64` | **deleted.** The makefile named three C files the assembly rewrite removed, was marked broken in its own header, and was built by nothing. The blob has been that route in since Phase 1. |
| three duplicated sequences | shared helpers: `ult_have_buf`, `ult_invalid`, `uci_get_ptr`, and `cc_ptr_at_y` in the cc65 binding |
| `tools/test_blob_table.py` | new: fails the build when `blob.s` and `bindings/blob/README.md` disagree about an offset, or when the jump table gains a gap |
| `tools/test_generated_assembles.py` | new: feeds the generated ACME and KickAssembler constant files to those assemblers, and skips when they are not installed |
| `.github/workflows/ci.yml` | **`make unittest` was never run in CI.** The generators, the CRUNCH model, the charmap rule and the register boundary went unchecked on every push. It runs now, with ACME installed beside cc65 so the check above is not a permanent skip. |
| `sdk.suite` | `$FF` sentinels in the setup, so an assertion that only passed because BSS happened to be zero fails. All 56 still pass. |
| `sdk-exec-rejects-wrapping-lengths` | proved nothing — each length is bounded before the sum, so no wrapping pair reaches the addition. Replaced by `sdk-exec-rejects-a-total-that-does-not-fit`, with two lengths that are legal apart and too much together. |
| `timeout.suite` | its header claimed to prove bounded time for every entry point; it says what it exercises now |
| README, architecture.md, api-design.md, asm-abi.md, tests/README.md, bindings/blob/README.md | measured again against the code — see §4 |

**Bytes.** 4310 bytes of code and rodata to 4269, and that is after the abort
fix added about 30. The blob binary went 5078 → 5037. Not a large number; the
point was that it was being spent on the same six instructions written out six
times.

## 4. The documentation that was wrong

Worth listing, because the pattern is what to watch for next time: every one of
these was true when it was written.

- **architecture.md described a `services/dos/`, `services/file/` directory tree
  that never existed.** The code is flat files in `src/uci/`. It also said the
  directories "will be created when there is code to put in them" — the code
  arrived and the layout turned out differently.
- **Its bindings table was three rows stale**, including an Oscar64 row marked
  broken and a BASIC row saying "out of scope here" — for a wedge that ships in
  two delivery forms with 49 tests behind it.
- **api-design.md still called `reu.s` "a future `services/reu`".**
- **The README's feature list stopped at "identify the machine"** and never
  mentioned the BASIC wedge at all. Its answer for KickAssembler, ACME, Oscar64,
  llvm-mos and KickC was "Not yet", for a blob that had served all of them since
  Phase 1.
- **`bindings/blob/README.md` documented `bp_devcode` and `bp_status` as
  outputs.** Nothing has ever written them: the device code comes from
  `uci_last_code` at `+$19`, and the status text is only kept by a request the
  caller builds. They are documented as the caller's own now, and reserved
  rather than removed, because the layout is published.
- Sizes and test counts throughout, in six files.

## 5. Two things worth knowing before the next refactor

**A blanket replace of an instruction sequence will eat the helper you just
wrote out of that same sequence.** Twice in this pass — `uci_get_ptr` and
`cc_ptr_at_y` both ended up as `jsr` to themselves, which assembles perfectly
and recurses until the stack is gone. Both were caught by running the suites
straight after the extraction, which is the habit worth keeping: after each
helper, not after all of them.

**The generated constant files for ACME and KickAssembler had never been
assembled by anything.** They were correct, as it turned out. They are checked
now, and the same gap is worth assuming for any future emitter: a file nothing
consumes is a file nothing validates.

## 6. Where the SDK stands

```
make test         GREEN   114 host unit tests + 199 across 8 suites
make hardware-run GREEN   5/5 scenarios, 40-52 checks each
make basic-run    GREEN   32/32 from the .prg and 32/32 from the .crt
make coverage     GREEN   32/101 commands, and 0 wrapped-but-untested
make blob         GREEN   5952 bytes at $8000, 392 relocations
make wedge        GREEN   wedge 2741 of the 4K at $C000, SDK 3498 of the 8K at $A000
```

Bench machine, settings, and the fixture policy: handover.md §5 and §8. Nothing
about them changed here, except that mutating hardware tests now write to
`/Temp` — see handover-phase3.md §2.3.

## 7. What is left, in the order agreed

### ~~7.1 The wedge's keywords are not gated by `make coverage`~~ — done

`tools/test_keyword_dispatch.py`, beside `tools/test_blob_table.py` and run by
the same `make unittest`. It walks `KEYWORDS` and fails the build on a token no
comparison in `dispatch.s` can ever match.

The part worth knowing before touching it: **dispatch is not one comparison per
token, so the check cannot pretend it is.** Twelve of the 22 keywords are
decided by range — the six file statements in `wedge_gone`, the six target
constants in `wedge_eval` — because a range test and a vector table are smaller
than twelve comparisons. So it reads bounds the way the 6502 does: a `cmp` with
a `beq` behind it matches one token, a `cmp` with a `bcc`/`bcs` opens a range,
and the `cmp #UCI_TOK_X + 1` that follows closes it at X. The `+ 1` is what
makes the bound inclusive on a 6502, and it is what makes it findable here.

A range brings a hole a token-by-token check would not have: widen the upper
bound for a seventh file keyword, forget the seventh `.addr`, and the dispatch
reads two bytes past `wedge_file_vec` and jumps through them. So the vector
table is counted against the range that indexes it too.

Kind is checked, not only presence: a `STATEMENT` has to be reachable from
`wedge_gone`, because one known only to `wedge_eval` is a statement that does
not run. `UW(` and `UL(` are the exception the code already is — functions in
name, legal only inside a `UCI` argument list, and dispatched entirely in
`wedge_arg`.

Eight mutations were run against it before it was trusted, and each was caught:
a statement, a function and a constant appended to `KEYWORDS` and dispatched
nowhere; the range widened without a vector; a vector dropped; `UTURBO`'s
statement comparison deleted; `UBYTE(`'s eval comparison deleted; and the
constant range narrowed from `UHTTP` to `UIEC`.

### 7.2 The network service — built, hardware run still owed

`src/uci/net.s`, nine of the fifteen commands, in assembly, C and the blob
(`+$85`..`+$9A`). **The emulator half passes; the hardware half has not been run
yet**, because the bench machine went off the network twice during this work —
see "the machine" below, which is the first thing to read.

Everything in the file was measured rather than read out of the protocol
document, which gives the argument shapes and stops exactly where the trouble
starts. The four findings that shaped the API are in docs/uci.md under
"Sockets, and what the network target really does", and repeated at the top of
`net.s`. In short:

- **A read never waits for the wire.** One issued straight after a connect
  reports "nothing yet" even though the peer greeted us on accept. Callers poll,
  and that is the right answer on a C64 — a blocking read would freeze the
  machine for as long as the far end stayed quiet.
- **The device code is the whole state machine, and `uci_exec` hides it.** Data,
  end-of-stream and would-block are codes 0, 1 and 2, and `00`/`01`/`02` are all
  success in the CBM DOS numbering the status decoder follows. The generic form
  therefore answers `ULTIMATE_OK` to all three, and a caller cannot tell a
  finished download from an idle socket. `ultimate_net_read` reads the code back
  and turns 1 into `ULTIMATE_END` — the same code `ultimate_readdir` ends a
  directory with. This is the clearest argument the service layer has ever had
  for existing.
- **A connect can take 30.8 seconds.** Measured, to an address on the same
  subnet with nothing at it, before the firmware gave up. The timeout budget is
  a byte of 256-poll units: 0.65 s at the default and about 1 s at its maximum.
  **No value of it reaches thirty seconds**, so the two open calls run on
  `UCI_TIMEOUT_FOREVER` and restore the caller's budget afterwards. They are the
  only entry points in the SDK not bounded by the SDK, and they say so.
- **Read lengths of 769..1023 are dangerous.** The firmware range-checks at 1024
  but its response queue is 896 bytes. A probe stepping through that gap took
  the machine off the network and needed a power cycle. `UCI_NET_READ_MAX` is
  512, verified with 700 bytes queued behind it, and the SDK will not ask for
  more however large a buffer it is handed. **The exact edge is deliberately not
  pinned** — finding it means wedging the machine again for a number nothing
  needs.

Answering handover-next.md §2's question directly: the figures there are all
*local* commands and do not transfer. A socket read or write is 3-21 ms, which
is frame-scale and fine; a connect is not, and cannot be made so.

**`make hardware-run` is 5/5 green**, with the network address checks running:
`net-interfaces`, `net-has-an-address` (which correctly picks interface 1 of 2
on the bench machine), `net-macaddr`, `net-macaddr-is-not-empty`,
`net-bad-interface-is-refused`, and both argument checks. **The socket round
trip is not in that run**, and the next section says why.

**The machine went down three times, and this cost real time.** docs/uci.md,
"The network stack is fragile", has the table. The short version: socket traffic
destabilises the firmware's network stack, the failure can arrive minutes after
the program that caused it has finished, and each one needs a power cycle. Two
of the three have credible causes — a read in the 769..1023 gap, and a connect
to the machine's own address — and the third has none.

**The first version of the hardware test connected to the Ultimate's own web
server**, on the reasoning that a machine can always reach itself and that this
kept the fixture policy intact. It hung in the connect; the run never finished,
and the firmware stayed busy long enough to fail the three scenarios after it.
That was a guess dressed as a fixture, and it is the mistake worth not repeating:
the rest of this work measured everything and that one assumption was not.

So the socket checks now need a peer and skip without one:

    make -C tests/hardware NET_PEER=192.168.1.242:6464

anything that accepts a connection and sends a byte. A dotted quad, not a name —
cc65 charmaps source characters and digits survive that where letters do not.
`hwtest.py` requires the address half to have run and merely *reports* whether
the socket half did, because requiring a peer would make the routine run depend
on something that may not be there.

**What is left here:**

1. The socket round trip against a real peer, through the wrappers. The
   semantics underneath it are all measured (docs/uci.md) and the local logic is
   in `sdk.suite`, but `ultimate_net_read`'s prefix-stripping and its
   ULTIMATE_END mapping have not been run end to end on hardware.
2. The four LISTEN commands stay unwrapped: `tools/gen_protocol.py` marks them
   INFERRED, their numbers are not in the published specification, and wrapping
   a guessed command number is not something this SDK does. The generic form
   reaches them.
3. No BASIC keywords. The token table is append-only and a token is a file
   format, so adding `UNET`-anything is a commitment that should follow a
   working demo rather than precede one.
4. No worked example yet; `tests/hardware/ucitest.c`'s network section is the
   only reading of the API end to end.

### 7.3 The HTTP service

23 commands, no wrapper, and the most argument-shaped family in the protocol —
JSON bodies, headers, and a status channel that carries both firmware errors and
the remote server's response code with nothing distinguishing them. The SDK
already decodes that channel; the service has to decide what a caller sees.

### 7.4 The boing ball

Last, deliberately. handover-next.md §3 has the design and the timing that
shaped it. A demo is worth building on a finished SDK and not before.

### Smaller, and not blocking

- There is no worked example of the blob route beyond the snippet in the README
  and the `blob.suite` walk. A KickAssembler example would prove it end to end,
  and would need a CI runner with a jar.
- `bp_status`'s 32 bytes are reserved and unused. If a service ever keeps the
  status text, that is where it goes.
- Ports of the core to Oscar64, llvm-mos or KickC are closed as a question, not
  as a possibility: the blob answers it with one implementation. Anything that
  reopened it would still have to pass `tests/emulator` unchanged.
