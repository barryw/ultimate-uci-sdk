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
make test         GREEN   110 host unit tests + 187 across 8 suites
make hardware-run GREEN   5/5 scenarios, 40-52 checks each
make basic-run    GREEN   32/32 from the .prg and 32/32 from the .crt
make coverage     GREEN   24/101 commands, and 0 wrapped-but-untested
make blob         GREEN   5037 bytes at $8000, 305 relocations
make wedge        GREEN   wedge 2741 of the 4K at $C000, SDK 3498 of the 8K at $A000
```

Bench machine, settings, and the fixture policy: handover.md §5 and §8. Nothing
about them changed here, except that mutating hardware tests now write to
`/Temp` — see handover-phase3.md §2.3.

## 7. What is left, in the order agreed

### 7.1 The wedge's keywords are not gated by `make coverage`

`tools/gen_coverage.py` fails the build when an SDK entry point has no test.
The wedge's keywords are outside it, so a keyword could be added to
`gen_keywords.py`, tokenise, list, dispatch to nothing, and ship. `basic.suite`
covers today's 22 by hand, which is not the same as being unable to forget.

Smallest honest shape: a test that walks `KEYWORDS`, finds each token in
`dispatch.s`'s statement dispatch or `wedge_eval`, and fails on one that is
handled nowhere. That is a table-versus-code check like
`tools/test_blob_table.py`, and it belongs beside it.

### 7.2 The network service

14 commands, no wrapper. `u64sim` implements none of them, so every test is
hardware — and the bench machine is on a network, so they can be real tests
rather than "the command was accepted".

Read handover-next.md §2 for the measured round-trip figures first: they decide
whether anything here can be synchronous.

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
