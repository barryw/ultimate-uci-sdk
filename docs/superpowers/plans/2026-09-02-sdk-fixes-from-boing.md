# SDK Fixes From The Boing Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fold four things the Boing demo works around into the SDK: `BLOB_*` offsets generated into every assembler binding, byte results that set the flags, a settle inside `ultimate_audio_configure`, and `ultimate_audio_load_wav`, which turns a WAV file on the Ultimate into a voice ready to play.

**Architecture:** The SDK is ca65 assembly in `src/uci/*.s`, linked three ways from one module list (`src/uci/sources.mk`): a cc65 library with wrappers in `bindings/cc65/ultimate_cc65.s`, a standalone "blob" with a jump table (`bindings/blob/blob.s`), and the BASIC wedge. Protocol constants come from `tools/gen_protocol.py` into the C header and three assembler includes. Tests: Python unit tests in `tools/test_*.py` (`make unittest`), and 6502 suites run under the sim6502 Docker image against a simulated Ultimate (`make -C tests/emulator run`), driven through `tests/emulator/harness.s`. Hardware checks run against the bench.

**Tech Stack:** ca65/cl65 (cc65 2.18+), Python 3, sim6502 (Docker, `ghcr.io/barryw/sim6502:latest`), KickAssembler for the demos, VICE `x64sc`, an Ultimate 64 Elite at 192.168.1.62.

**Spec:** `docs/superpowers/specs/2026-09-02-sdk-fixes-from-boing-design.md`.

## Global Constraints

- Every SDK module opens with `uci_code` (from `uci_seg.inc`), never `.code`; rodata is `.rodata` followed by `uci_code` to return, as `src/uci/reu.s` does.
- Byte results: after Task 2, every public entry that returns a byte in `A` ends with `ldx #$00` **before** the load of `A`, so N and Z reflect the result. New code in Tasks 4 to 7 follows the rule from the start.
- The jump table is append-only: offsets `+$04..+$FD` and `+$2E8..+$2FD` never move. New entries go in the extension table at `+$300` (Task 7).
- Generated files (`include/uci_protocol.h`, `bindings/asm/uci_protocol.inc`, `bindings/kickass/uci_protocol.asm`, `bindings/acme/uci_protocol.a`, `bindings/asm/uci_argtable.inc`, `docs/generated/protocol-constants.md`) are edited only through `make protocol`, and committed.
- Strings in assembler sources are explicit byte lists (`.byte $52, $49, $46, $46`), never quoted literals, because a charmap can rewrite a literal.
- Commit messages: conventional commits, and every commit ends with the two trailer lines below.

```
Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01MWZot9Zonrj1xjkwu9tCpq
```

- Bench facts that matter here: I/O reads run at 1 MHz under turbo; the hardware suite has 10 pre-existing failures on this bench (a turbo work-ratio check and nine `/Temp` DOS checks) that must be identical before and after; "Map Ultimate Audio $DF20-DFFF" must be Enabled for any sound.

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `tools/gen_protocol.py` | reads `blob.s`, emits `BLOB_*` groups into the three assembler includes; gains `UA_RATE_CLOCK` | 1, 5 |
| `tools/test_gen_protocol.py` | pins the `BLOB_*` values | 1 |
| `tools/test_blob_table.py` | imports the two regexes from the generator; no-gaps check covers the `+$300` table | 1, 7 |
| `tools/gen_wav_fixtures.py` (new) | writes the four WAV fixtures | 5 |
| `tests/emulator/fixtures/usb0/wav/*` (new) | the fixtures, committed | 5 |
| `tests/emulator/harness.s`, `tests/emulator/Makefile` | `t_flags_*`, `t_audio_load_wav`, `voice`; `HARNESS_SYMS` | 2, 5 |
| `tests/emulator/sdk.suite`, `absent.suite`, `blob.suite` | the new cases | 2, 5, 7 |
| `src/uci/*.s` | the `ldx #$00` sweep | 2 |
| `src/uci/audio.s` | `audio_settle`, called twice inside configure | 4 |
| `src/uci/wav.s` (new) | `ultimate_audio_load_wav` | 6 |
| `src/uci/sources.mk` | lists `wav.s` | 6 |
| `bindings/asm/ultimate.inc` | declares the new entry | 5 |
| `include/ultimate.h` | configure comment; `ultimate_audio_load_wav` prototype | 4, 6 |
| `bindings/cc65/ultimate_cc65.s` | the three-argument wrapper | 7 |
| `bindings/blob/blob.s`, `blob.cfg.in`, `README.md` | extension table, shim, rows, the flags rule, the configure note | 4, 7 |
| `docs/asm-abi.md` | the flags rule; audio rows | 2, 6 |
| `demos/vsprites/vsprites.asm` | `uci.BLOB_*` names, no `cmp #0` | 3 |
| `experiments/boing/boing.asm` | drops `audio_settle` and the init stop (verification of Task 4 only; the migration is Spec B) | 4 |

---

### Task 1: `BLOB_*` constants generated from `blob.s` (A3)

**Files:**
- Modify: `tools/gen_protocol.py` (imports at top; new block after `GROUPS`; the three assembler emitters; nothing in `c_header` or `markdown`)
- Modify: `tools/test_gen_protocol.py` (new test class at the end)
- Modify: `tools/test_blob_table.py:36-40` (regexes become imports)
- Regenerate: `bindings/asm/uci_protocol.inc`, `bindings/kickass/uci_protocol.asm`, `bindings/acme/uci_protocol.a`

**Interfaces:**
- Produces: `gp.BLOB_SOURCE`, `gp.BLOB_PARAMS`, `gp.BLOB_JUMP`, `gp.BLOB_FIELD`, `gp.blob_name(target)`, `gp.blob_groups()`; constants `BLOB_<ENTRY>` (jump offsets from the blob base) and `BLOB_PARAMS`, `BLOB_BP_<FIELD>` (parameter block fields, from the blob base) in the three assembler includes, under the KickAssembler `uci` namespace.

- [ ] **Step 1: Write the failing tests**

Append to `tools/test_gen_protocol.py` (add `import os` next to `import unittest` at the top):

```python
class TestBlobConstants(unittest.TestCase):
    """The BLOB_* constants are read out of blob.s, so a wrong one is a wrong blob.s."""

    def names(self):
        out = {}
        for _title, _note, items in gp.blob_groups():
            for name, value, _comment in items:
                out[name] = value
        return out

    def test_the_first_and_the_audio_entries(self):
        n = self.names()
        self.assertEqual(n["BLOB_UCI_INIT"], 0x04)
        self.assertEqual(n["BLOB_ULTIMATE_INIT"], 0x1C)
        self.assertEqual(n["BLOB_ULTIMATE_TURBO_AVAILABLE"], 0x43)
        self.assertEqual(n["BLOB_ULTIMATE_AUDIO_INIT"], 0x2E8)
        self.assertEqual(n["BLOB_AUDIO_CONFIGURE"], 0x2F1)

    def test_parameter_block_fields_are_from_the_blob_base(self):
        n = self.names()
        self.assertEqual(n["BLOB_PARAMS"], 0x100)
        self.assertEqual(n["BLOB_BP_RESULT"], 0x100)
        self.assertEqual(n["BLOB_BP_ADDR"], 0x103)
        self.assertEqual(n["BLOB_BP_REU"], 0x256)
        self.assertEqual(n["BLOB_BP_AUDIO"], 0x29A)

    def test_every_jump_has_a_constant(self):
        text = open(os.path.join(gp.REPO, gp.BLOB_SOURCE)).read()
        names = self.names()
        for target, off in gp.BLOB_JUMP.findall(text):
            self.assertEqual(names[gp.blob_name(target)], int(off, 16), target)

    def test_the_assembler_includes_carry_them_and_the_c_header_does_not(self):
        for text in (gp.asm_include(), gp.kickass_include(), gp.acme_include()):
            self.assertIn("BLOB_ULTIMATE_INIT", text)
            self.assertIn("BLOB_BP_AUDIO", text)
        self.assertNotIn("BLOB_ULTIMATE_INIT", gp.c_header())
        self.assertNotIn("BLOB_ULTIMATE_INIT", gp.markdown())
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest tools.test_gen_protocol.TestBlobConstants -v 2>&1 | tail -5` from the repo root (or `cd tools && python3 -m unittest test_gen_protocol.TestBlobConstants -v`).
Expected: 4 errors, `AttributeError: module 'gen_protocol' has no attribute 'blob_groups'`.

- [ ] **Step 3: Add the reader and the groups to the generator**

In `tools/gen_protocol.py`, add `import re` after `import os`. After the `GROUPS = [ ... ]` list ends (before the `STRINGS` definition), add:

```python
# ---------------------------------------------------------------------------
# The standalone blob's jump table and parameter block, read from blob.s at
# generation time so the constants can never disagree with the code they name.
# Not in the C header: a C program links the library and has no table to jsr.
# ---------------------------------------------------------------------------

BLOB_SOURCE = "bindings/blob/blob.s"
BLOB_PARAMS = 0x100   # the parameter block's offset from the blob's base

# `        jmp ultimate_init               ; +$1C`
BLOB_JUMP = re.compile(r"^\s+jmp\s+(\w+)\s*;\s*\+\$([0-9A-F]+)", re.M)
# `bp_attrib:  .res 1                  ; +$151 open's DOS_FA_* mask in,`
BLOB_FIELD = re.compile(r"^(bp_\w+):\s+\.res\s+(\S+)\s*;\s*\+\$([0-9A-F]+)", re.M)


def blob_name(target):
    """`blob_audio_configure` -> BLOB_AUDIO_CONFIGURE; `ultimate_init` -> BLOB_ULTIMATE_INIT.

    The shims in blob.s are named for the file they live in; the constant names
    the operation, which is what the README table already does.
    """
    if target.startswith("blob_"):
        target = target[5:]
    return "BLOB_" + target.upper()


def blob_groups():
    """Two groups in GROUPS' (title, note, items) shape, for the assembler emitters."""
    with open(os.path.join(REPO, BLOB_SOURCE)) as fh:
        text = fh.read()
    jumps = [(blob_name(name), int(off, 16), "")
             for name, off in BLOB_JUMP.findall(text)]
    fields = [("BLOB_PARAMS", BLOB_PARAMS, "the parameter block itself")]
    fields += [("BLOB_" + name.upper(), BLOB_PARAMS + int(off, 16), "")
               for name, _size, off in BLOB_FIELD.findall(text)]
    return [
        ("Blob jump table", "Offsets from the base address of the standalone blob "
         "(bindings/blob), whatever base it was built for: jsr BLOB + "
         "BLOB_ULTIMATE_INIT. Entries are appended, never moved. Read from "
         "blob.s when this file was generated.", jumps),
        ("Blob parameter block", "Fields of the blob's parameter block, also from "
         "the blob's base: sta BLOB + BLOB_BP_ADDR. The block starts at "
         "BLOB_PARAMS.", fields),
    ]
```

Then in each of `asm_include()`, `kickass_include()` and `acme_include()`, change the loop header

```python
    for title, note, items in GROUPS:
```

to

```python
    for title, note, items in GROUPS + blob_groups():
```

(three places; `c_header()`, `markdown()` and `arg_table_include()` stay on `GROUPS`).

- [ ] **Step 4: Point the blob-table test at the shared regexes**

In `tools/test_blob_table.py`, replace the two compiled patterns

```python
# `        jmp ultimate_init               ; +$1C`
JUMP = re.compile(r"^\s+jmp\s+(\w+)\s*;\s*\+\$([0-9A-F]+)", re.M)
```

and

```python
# `bp_attrib:  .res 1                  ; +$151 open's ...`
FIELD = re.compile(r"^(bp_\w+):\s+\.res\s+(\S+)\s*;\s*\+\$([0-9A-F]+)", re.M)
```

with

```python
# The two patterns the generator reads blob.s with: one parser, so the
# constants it emits and the table this file checks cannot read differently.
from gen_protocol import BLOB_JUMP as JUMP, BLOB_FIELD as FIELD
```

placed after the other imports. `DOC_ROW` and `PARAM_HEADING` stay.

- [ ] **Step 5: Regenerate and run every unit test**

Run: `make protocol && make unittest 2>&1 | tail -4`
Expected: `wrote bindings/kickass/uci_protocol.asm (...)` among the six `wrote` lines; then `OK` from unittest with no failures. Then `grep -c 'BLOB_' bindings/kickass/uci_protocol.asm` prints a number of at least 120 (92 jumps, 25 fields, `BLOB_PARAMS`, plus the two group headings), and `grep -n 'BLOB_AUDIO_CONFIGURE\|BLOB_BP_AUDIO' bindings/kickass/uci_protocol.asm` shows `$02F1` and `$029A`.

- [ ] **Step 6: Commit**

```bash
git add tools/gen_protocol.py tools/test_gen_protocol.py tools/test_blob_table.py \
        bindings/asm/uci_protocol.inc bindings/kickass/uci_protocol.asm bindings/acme/uci_protocol.a
git commit -m "feat(bindings): BLOB_* jump table and parameter block offsets, generated

Every assembler binding now carries the standalone blob's offsets, read
out of blob.s by gen_protocol.py, so a KickAssembler or ACME program
writes jsr BLOB + uci.BLOB_ULTIMATE_INIT instead of copying \$1C out of
the README. The blob-table test shares the generator's two parsers.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01MWZot9Zonrj1xjkwu9tCpq"
```

---

### Task 2: Byte results set the flags (A2)

**Files:**
- Modify: `tests/emulator/harness.s` (exports near line 118; routines after `t_reu_save`)
- Modify: `tests/emulator/Makefile:56` (`HARNESS_SYMS`)
- Modify: `tests/emulator/sdk.suite` (two cases after the REU tests), `tests/emulator/absent.suite` (one case)
- Modify: `src/uci/*.s`, `bindings/asm/ultimate_asm.s` (the sweep)
- Modify: `docs/asm-abi.md:100-108` (the register contract table), `bindings/blob/README.md` (one paragraph above the jump table)

**Interfaces:**
- Produces: harness routines `t_flags_init`, `t_flags_reu_avail`, `t_flags_audio_avail`, each storing the Z bit (`$02` set, `$00` clear) of the status register as the SDK call returned it into `result`.
- Guarantee every later task relies on: a byte result in `A` leaves N and Z set from `A`.

- [ ] **Step 1: Add the harness routines**

In `tests/emulator/harness.s`, add to the export block (after the line `.export t_reu_load, t_reu_save, reu_at, reu_len`):

```
        .export t_flags_init, t_flags_reu_avail, t_flags_audio_avail
```

After `set_reu_args` (which ends with `rts` after `sta ult_addr + 1`), add:

```
; --- byte results set the flags ---
;
; The ABI promises that a byte result in A leaves Z set from A, so that a
; caller can write `jsr entry` / `beq ok`. Each of these stores the Z bit of
; the status register exactly as the call left it: $02 when the result was
; zero, $00 when it was not.
t_flags_init:
        jsr ultimate_init
        jmp store_z

t_flags_reu_avail:
        jsr ultimate_reu_available
        jmp store_z

t_flags_audio_avail:
        jsr ultimate_audio_available
        jmp store_z

store_z:
        php
        pla
        and #$02
        sta result
        rts
```

In `tests/emulator/Makefile`, in `HARNESS_SYMS`, change the line

```
                t_reu_avail t_reu_stash t_reu_fetch t_reu_load t_reu_save \
```

to

```
                t_reu_avail t_reu_stash t_reu_fetch t_reu_load t_reu_save \
                t_flags_init t_flags_reu_avail t_flags_audio_avail \
```

- [ ] **Step 2: Add the suite cases**

In `tests/emulator/sdk.suite`, after the test `sdk-reu-load-takes-the-open-file` (it ends with `assert([result] == $00, "and the file closed")` and a closing `}`), add:

```
    ; --- byte results set the flags ---
    ;
    ; docs/asm-abi.md promises that a byte result in A leaves Z set from A, so
    ; `jsr` / `beq` tests the result. Every entry used to end in `ldx #$00`,
    ; which left Z set whatever A was. $02 is the Z bit of the status byte the
    ; harness stores.

    test("sdk-flags-ok-sets-z", "ultimate_init returning ULTIMATE_OK leaves Z set") {
      jsr([boot], stop_on_rts = true, fail_on_brk = true)
      [result] = $ff
      jsr([t_flags_init], stop_on_rts = true, fail_on_brk = true)
      assert([result] == $02, "Z set: the result is zero")
    }

    test("sdk-flags-one-clears-z", "ultimate_reu_available returning 1 leaves Z clear") {
      jsr([boot], stop_on_rts = true, fail_on_brk = true)
      jsr([t_init], stop_on_rts = true, fail_on_brk = true)
      $df00 = $40               ; REU_STAT_DONE, so the probe sees an expansion
      [result] = $ff
      jsr([t_flags_reu_avail], stop_on_rts = true, fail_on_brk = true)
      assert([result] == $00, "Z clear: the result is 1")
    }

    test("sdk-flags-zero-byte-sets-z", "ultimate_audio_available returning 0 before init leaves Z set") {
      jsr([boot], stop_on_rts = true, fail_on_brk = true)
      [result] = $ff
      jsr([t_flags_audio_avail], stop_on_rts = true, fail_on_brk = true)
      assert([result] == $02, "Z set: the result is zero")
    }
```

In `tests/emulator/absent.suite`, after the test `absent-init`, add:

```
    test("absent-flags-error-clears-z", "ultimate_init returning NO_DEVICE leaves Z clear") {
      jsr([boot], stop_on_rts = true, fail_on_brk = true)
      [result] = $ff
      jsr([t_flags_init], stop_on_rts = true, fail_on_brk = true)
      assert([result] == $00, "Z clear: the result is 1")
    }
```

The spec names `blob.suite` as well; it gets no case, deliberately. The blob is
the same object code linked at a fixed address, so the library cases cover
it, and the blob suite has no harness in which to execute a `php` after a
`jsr`. The README paragraph in Step 7 is the blob caller's contract.

- [ ] **Step 3: Run the emulator suites to verify the new cases fail**

Run: `make -C tests/emulator run 2>&1 | grep -E 'flags|passed|failed' | head -20`
Expected: `sdk-flags-one-clears-z` and `absent-flags-error-clears-z` FAIL (result is `$02`, Z always set today); `sdk-flags-ok-sets-z` and `sdk-flags-zero-byte-sets-z` pass by accident. Everything else passes.

- [ ] **Step 4: Run the sweep script (once; not committed)**

Save this as `/tmp/zflag_sweep.py` (or the scratchpad) and run it from the repo root:

```python
#!/usr/bin/env python3
"""One-off: put `ldx #$00` before the load of A at every byte return.

Matches `<label?> lda <operand>` / `ldx #$00` / `rts` and swaps the first two
lines, keeping comments and a label on the branch target. Skips operands that
index by X, which cannot be loaded after X is cleared.
"""
import pathlib
import re

PAT = re.compile(
    r"^(?P<lbl>(?:@?\w+:)?[ \t]+)(?P<lda>lda [^\n;]*?)(?P<c1>[ \t]*;[^\n]*)?\n"
    r"(?P<ind>[ \t]+)ldx #\$00(?P<c2>[ \t]*;[^\n]*)?\n"
    r"(?=[ \t]+rts\b)", re.M)


def swap(m):
    lda = m.group("lda").rstrip()
    if ",x" in lda.lower():
        return m.group(0)
    c1 = m.group("c1") or ""
    c2 = m.group("c2") or ""
    return "%sldx #$00%s\n%s%s%s\n" % (m.group("lbl"), c2, m.group("ind"), lda, c1)


files = sorted(pathlib.Path("src/uci").glob("*.s")) + [pathlib.Path("bindings/asm/ultimate_asm.s")]
for p in files:
    s = p.read_text()
    t, n = PAT.subn(swap, s)
    if n:
        p.write_text(t)
        print("%s: %d" % (p, n))
```

Run: `python3 /tmp/zflag_sweep.py`
Expected: a line per file with a count; about 100 swaps in total. `git diff --stat` shows only `src/uci/*.s` (and possibly `bindings/asm/ultimate_asm.s`).

- [ ] **Step 5: Find and fix the sites the script could not**

Run this checker; it prints every `rts` preceded by `ldx #$00` whose preceding line still computes `A`:

```bash
awk 'FNR==1{p1="";p2=""} { if ($0 ~ /^[ \t]+rts/ && p1 ~ /ldx #\$00/ && p2 ~ /^[^;]*[ \t](lda|pla|txa|tya|and|ora|eor|adc|sbc|jsr|asl|lsr|rol|ror|inc|dec)([ \t]|$)/) print FILENAME":"FNR-2": "p2; p2=p1; p1=$0 }' src/uci/*.s bindings/asm/ultimate_asm.s
```

Fix each line it prints by shape, then re-run until it prints nothing:

| Shape before | After |
|---|---|
| `pla` / `ldx #$00` / `rts` | `ldx #$00` / `pla` / `rts` (`pla` sets N and Z) |
| `txa` / `ldx #$00` / `rts` | `txa` / `ldx #$00` / `ora #$00` / `rts` |
| `jsr tail` / `ldx #$00` / `rts` | delete the `ldx #$00` if `tail` ends in the `ldx #$00` / load / `rts` pattern; otherwise `jsr tail` / `ldx #$00` / `ora #$00` / `rts` |
| `and #mask` / `ldx #$00` / `rts` (and `ora`, `eor`) | move the `ldx #$00` above the `lda` that precedes the `and` |
| `lda foo,x` / `ldx #$00` / `rts` | `lda foo,x` / `ldx #$00` / `ora #$00` / `rts` |

Two sites the checker cannot see, fix by hand:

`src/uci/audio.s`, `audio_require` (the `sec` sits between the `ldx` and the `rts`):

```
audio_require:
        lda ult_audio_up
        cmp #$01
        beq @yes
        ldx #$00
        lda #ULTIMATE_ERR_NOT_SUPPORTED
        sec
        rts
@yes:   clc
        rts
```

`src/uci/audio.s`, `ultimate_audio_irq_status` (its `@none` tail is `lda #$00` / `tax` / `rts`, which is already right: `tax` does not disturb Z from `lda #$00`; leave it).

Then run the checker again. Expected: no output.

- [ ] **Step 6: Run the emulator suites**

Run: `make -C tests/emulator run 2>&1 | grep -E 'passed|failed|FAIL' | head -20`
Expected: every suite passes, including the four flags cases; no other case changed.

- [ ] **Step 7: Document the rule**

In `docs/asm-abi.md`, in the "Register contract" table, change the row

```
| Return | result code in `A` |
```

to

```
| Return | result code in `A`, with N and Z set from it: `jsr entry` / `beq ok` tests the result. A result that occupies `A` and `X` (a 16-bit value such as `ultimate_reu_size`) carries no such promise; test both bytes. |
```

In `bindings/blob/README.md`, directly above the line `## The jump table`, add:

```
**A byte result sets the flags.** Every entry that answers with a byte in `A`
leaves N and Z set from it, so `jsr BLOB + $1C` / `beq ok` tests the result
without a `cmp #0`. Entries that answer in `A` and `X` together (`reu_size`,
`strerror`) make no such promise.
```

- [ ] **Step 8: Commit**

```bash
git add src/uci bindings/asm/ultimate_asm.s tests/emulator/harness.s tests/emulator/Makefile \
        tests/emulator/sdk.suite tests/emulator/absent.suite docs/asm-abi.md bindings/blob/README.md
git commit -m "fix(abi): a byte result in A leaves the flags set from A

Every entry ended in ldx #\$00, so Z was always set and a caller's
jsr/beq tested X. The clear now precedes the load, and the ABI says so.
Three harness routines pin it in both simulator builds.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01MWZot9Zonrj1xjkwu9tCpq"
```

---

### Task 3: The vsprites demo consumes Tasks 1 and 2

**Files:**
- Modify: `demos/vsprites/vsprites.asm:24-27` (the constants) and `:137-138` (the `cmp #0`)

- [ ] **Step 1: Confirm the binding is imported**

Run: `grep -n '#import' demos/vsprites/vsprites.asm`
Expected: a line importing `../../bindings/kickass/uci_protocol.asm`. If there is none, add `#import "../../bindings/kickass/uci_protocol.asm"` above the `.const` block.

- [ ] **Step 2: Use the generated names and drop the workaround**

Replace lines 24 to 27

```
.const BLOB                = $7000            // bindings/blob, default build
.const ULT_TURBO_AVAILABLE = BLOB + $43
.const ULT_TURBO_SET       = BLOB + $49
.const ULT_TURBO_BADLINES  = BLOB + $4c
```

with

```
.const BLOB                = $7000            // bindings/blob, default build
.const ULT_TURBO_AVAILABLE = BLOB + uci.BLOB_ULTIMATE_TURBO_AVAILABLE
.const ULT_TURBO_SET       = BLOB + uci.BLOB_ULTIMATE_TURBO_SET
.const ULT_TURBO_BADLINES  = BLOB + uci.BLOB_ULTIMATE_TURBO_BADLINES
```

Then find the `cmp #0` after `jsr ULT_TURBO_AVAILABLE` (line 138: `cmp #0              // test A: the entry point returns with Z from its trailing ldx`) and delete that one line. The `beq`/`bne` that follows now tests the SDK's own flags.

- [ ] **Step 3: Build and run in VICE**

Run: `make -C demos/vsprites && make -C demos/vsprites check`
Expected: `vsprites.prg` assembles with no errors, and `vsprites-vice.png` is written (the check prints its `ls -la` line).

- [ ] **Step 4: Commit**

```bash
git add demos/vsprites/vsprites.asm
git commit -m "refactor(vsprites): generated BLOB_* offsets, no cmp #0

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01MWZot9Zonrj1xjkwu9tCpq"
```

---

### Task 4: `ultimate_audio_configure` settles (A1)

**Files:**
- Modify: `src/uci/audio.s` (module comment; `audio_settle` after `audio_ok`; two calls inside configure)
- Modify: `include/ultimate.h` (the comment above `ultimate_audio_configure`)
- Modify: `bindings/blob/README.md` (the `audio_configure` row)
- Modify: `experiments/boing/boing.asm` (delete `audio_settle` and its callers; delete the init `AUDIO_STOP`) for the hardware check only

**Interfaces:**
- Consumes: nothing new.
- Produces: `ultimate_audio_configure` now takes about 2 ms under turbo and is the safe re-arm path: stop, configure, start.

- [ ] **Step 1: Add the settle and call it twice**

In `src/uci/audio.s`, after the `audio_ok` tail (`lda #ULTIMATE_OK` / `ldx #$00` / `rts`, in whichever order Task 2 left it), add:

```
; About a millisecond at any CPU speed: I/O reads run at 1 MHz under Ultimate
; 64 turbo, so 1,024 of them take a millisecond at 48 MHz and nine at stock
; speed. Reprogramming a running channel without a pause leaves it playing
; noise (an Elite, firmware 3.15: intermittent from one launch to the next
; until the pause went in). Preserves X, which configure keeps the channel
; offset in.
audio_settle:
        txa
        pha
        ldx #$00
        ldy #$04
@loop:  lda $D012
        inx
        bne @loop
        dey
        bne @loop
        pla
        tax
        rts
```

In `ultimate_audio_configure`, change

```
        ; Stop first, then replace every write-only register.
        lda #$00
        sta UA_REG_BASE + UA_REG_CONTROL,x
```

to

```
        ; Stop first and let the engine actually stop, then replace every
        ; write-only register, then let it take those before the caller can
        ; open the gate.
        lda #$00
        sta UA_REG_BASE + UA_REG_CONTROL,x
        jsr audio_settle
```

and, at the end of the same routine, change

```
        lda #$01
        sta UA_REG_BASE + UA_REG_IRQ_CLEAR,x
        ldy #UA_VOICE_FLAGS
        lda (uci_ptr),y
        sta UA_REG_BASE + UA_REG_CONTROL,x
        jmp audio_ok
```

to

```
        lda #$01
        sta UA_REG_BASE + UA_REG_IRQ_CLEAR,x
        jsr audio_settle
        ldy #UA_VOICE_FLAGS
        lda (uci_ptr),y
        sta UA_REG_BASE + UA_REG_CONTROL,x
        jmp audio_ok
```

In the module comment at the top of `audio.s`, after the sentence ending `by the application.`, add:

```
; Configure pauses about a millisecond after stopping the channel and again
; after programming it: the engine reprogrammed on the fly plays noise.
```

- [ ] **Step 2: Document it**

In `include/ultimate.h`, replace

```c
/* Validate and write every voice register, leaving its gate closed. */
uint8_t ultimate_audio_configure(const ultimate_audio_voice *voice);
```

with

```c
/*
 * Validate and write every voice register, leaving its gate closed. Stops the
 * channel first and pauses about a millisecond after the stop and again after
 * the writes (about 2 ms under turbo, 20 ms at 1 MHz): a running channel
 * reprogrammed without a pause plays noise. This is the safe way to re-arm a
 * voice: stop, configure, start. stop() and start() themselves are immediate.
 */
uint8_t ultimate_audio_configure(const ultimate_audio_voice *voice);
```

In `bindings/blob/README.md`, change the row

```
| `+$2F1` | `audio_configure` | `bp_audio` | `bp_result` |
```

to

```
| `+$2F1` | `audio_configure` | `bp_audio` | `bp_result`; stops the channel first, about 2 ms |
```

- [ ] **Step 3: Emulator suites unchanged**

Run: `make -C tests/emulator run 2>&1 | grep -E 'passed|failed|FAIL' | head -12`
Expected: every suite passes. (The simulator has no audio block; configure returns `NOT_SUPPORTED` before the settle.)

- [ ] **Step 4: Hardware suite**

Run: `make hardware-run U64_HOST=192.168.1.62 2>&1 | tail -25`
Expected: the audio scenario passes (configure, start, stop, and the end-of-sample bit), and exactly the 10 pre-existing failures remain: the turbo work-ratio check and nine `/Temp` DOS checks answering device error 7. Any other failure is a regression from this task; stop and fix.

- [ ] **Step 5: Boing without its own settle**

In `experiments/boing/boing.asm`:
- in `play_boing`, delete the two `jsr audio_settle` lines (the routine becomes `AUDIO_STOP`, `AUDIO_CONF`, `AUDIO_START`, then the result store);
- delete the `audio_settle` routine and its comment (`// About a millisecond at any CPU speed ...` through its `rts`);
- in `sdk_init`, delete the line `jsr AUDIO_STOP      // whatever a previous run or the init probe left running` and the `jsr audio_settle` after it, so `AUDIO_INIT` success goes straight to `jsr voice_setup`.

Run, three times, listening each time: `make -C experiments/boing run U64_HOST=192.168.1.62`
Expected, every run: the script reports flags 7, 60 fps, bounces climbing, last result 0; a clean boing on every bounce and no static between bounces. A launch with static means the settle is not long enough for this bench; double `ldy #$04` to `#$08` in `audio_settle` and repeat.

- [ ] **Step 6: Commit**

```bash
git add src/uci/audio.s include/ultimate.h bindings/blob/README.md experiments/boing/boing.asm
git commit -m "fix(audio): configure settles after the stop and after the writes

A running Ultimate Audio channel reprogrammed without a pause plays
noise, intermittently, from one launch to the next. Configure now waits
about a millisecond (1,024 I/O reads, the same at any CPU speed) after
stopping the channel and again after programming it. The Boing demo
drops the bracket it carried for this.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01MWZot9Zonrj1xjkwu9tCpq"
```

---

### Task 5: `UA_RATE_CLOCK`, the WAV fixtures, and the failing suite cases (A4, red)

**Files:**
- Modify: `tools/gen_protocol.py` (one constant in the "Ultimate Audio registers (NOT UCI)" group)
- Create: `tools/gen_wav_fixtures.py`
- Create: `tests/emulator/fixtures/usb0/wav/mono16.wav`, `stereo16.wav`, `mono8.wav`, `notwav.bin` (generated, committed)
- Modify: `bindings/asm/ultimate.inc` (declare the entry), `tests/emulator/harness.s` (routine, `voice`), `tests/emulator/Makefile` (`HARNESS_SYMS`), `tests/emulator/sdk.suite` (five cases)
- Regenerate: the six generated files

**Interfaces:**
- Produces: `UA_RATE_CLOCK = 6250000` in every binding; harness routine `t_audio_load_wav` (name in `reply`, REU address in `reu_at`, voice in `voice`, result in `result`); the fixtures with the exact values below.
- Consumes (Task 6): `ultimate_audio_load_wav` with `ult_buf` = name, `ult_reu` = REU address, `A`/`X` = voice pointer, `A` = result.

- [ ] **Step 1: The constant**

In `tools/gen_protocol.py`, in the group titled `"Ultimate Audio registers (NOT UCI)"`, after the line

```python
        ("UA_REG_RATE",           0x0E,   "W    divider from 6.25 MHz, big endian"),
```

add

```python
        ("UA_RATE_CLOCK",         6250000, "the sampler's reference in Hz; a voice's rate is UA_RATE_CLOCK / sample rate"),
```

Run: `make protocol && make unittest 2>&1 | tail -3 && grep -n 'UA_RATE_CLOCK' include/uci_protocol.h bindings/asm/uci_protocol.inc bindings/kickass/uci_protocol.asm`
Expected: unittest `OK`; the header line shows `6250000`, the ca65 and KickAssembler lines show `$5F5E10`.

- [ ] **Step 2: The fixture generator**

Create `tools/gen_wav_fixtures.py`:

```python
#!/usr/bin/env python3
"""The WAV files tests/emulator/sdk.suite feeds ultimate_audio_load_wav.

They are committed with the other fixtures under tests/emulator/fixtures/usb0;
run this to regenerate them. The values the suite asserts:

    mono16.wav    16-bit mono, 8,000 Hz, 128 data bytes, a 13-byte LIST chunk
                  (odd, so padded) in front of fmt: divider 781, flags $10
    stereo16.wav  16-bit stereo, 11,025 Hz, 128 data bytes: divider 566, flags $50
    mono8.wav     8-bit mono, 8,363 Hz, 100 data bytes: divider 747, flags $00
    notwav.bin    64 bytes that are not RIFF at all
"""
import os
import struct

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "tests/emulator/fixtures/usb0/wav")


def chunk(tag, body):
    pad = b"\x00" if len(body) & 1 else b""
    return tag + struct.pack("<I", len(body)) + body + pad


def fmt(channels, rate, bits):
    block = channels * bits // 8
    return chunk(b"fmt ", struct.pack("<HHIIHH", 1, channels, rate, rate * block, block, bits))


def wav(chunks):
    body = b"WAVE" + b"".join(chunks)
    return b"RIFF" + struct.pack("<I", len(body)) + body


FILES = {
    "mono16.wav": wav([chunk(b"LIST", b"INFOISFT\x01\x00\x00\x00s"),
                       fmt(1, 8000, 16),
                       chunk(b"data", struct.pack("<64h", *range(64)))]),
    "stereo16.wav": wav([fmt(2, 11025, 16),
                         chunk(b"data", struct.pack("<64h", *range(64)))]),
    "mono8.wav": wav([fmt(1, 8363, 8),
                      chunk(b"data", bytes(range(100)))]),
    "notwav.bin": b"NOPE" * 16,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, data in FILES.items():
        with open(os.path.join(OUT, name), "wb") as fh:
            fh.write(data)
        print("%s: %d bytes" % (name, len(data)))


if __name__ == "__main__":
    main()
```

Run: `python3 tools/gen_wav_fixtures.py && ls -l tests/emulator/fixtures/usb0/wav && git check-ignore -v tests/emulator/fixtures/usb0/wav/mono16.wav; echo "ignored=$?"`
Expected: four files (`mono16.wav` 194 bytes, `stereo16.wav` 172, `mono8.wav` 144, `notwav.bin` 64) and `ignored=1` (not ignored).

- [ ] **Step 3: Declare the entry and add the harness routine**

In `bindings/asm/ultimate.inc`, after the line `.global ultimate_audio_irq_clear ; A = channel -> A = result`, add:

```
.global ultimate_audio_load_wav  ; ult_buf = name, ult_reu = REU address,
                                 ; A/X = ultimate_audio_voice -> A = result
```

In `tests/emulator/harness.s`:
- export block: after `.export t_flags_init, t_flags_reu_avail, t_flags_audio_avail` add `.export t_audio_load_wav, voice`
- `.bss` block: after `reu_len:      .res 4      ; and how many bytes it moves` add `voice:        .res UA_VOICE_SIZE  ; the ultimate_audio_voice t_audio_load_wav fills`
- after `store_z` add:

```
; A WAV into the REU: the name is in `reply`, the REU address in reu_at, and
; the voice comes back in `voice`.
t_audio_load_wav:
        lda #<reply
        sta ult_buf
        lda #>reply
        sta ult_buf + 1
        ldx #$03
@copy:  lda reu_at,x
        sta ult_reu,x
        dex
        bpl @copy
        lda #<voice
        ldx #>voice
        jsr ultimate_audio_load_wav
        sta result
        rts
```

In `tests/emulator/Makefile`, `HARNESS_SYMS`: change `t_flags_init t_flags_reu_avail t_flags_audio_avail \` to `t_flags_init t_flags_reu_avail t_flags_audio_avail t_audio_load_wav voice \`.

- [ ] **Step 4: The suite cases**

In `tests/emulator/sdk.suite`, after the three `sdk-flags-*` tests, add:

```
    ; --- a WAV file into the REU and a voice ---
    ;
    ; The simulated firmware implements no REU load, so a good file ends where
    ; its data chunk would be loaded: NOT_SUPPORTED from reu_load, with the
    ; header already parsed into the voice. That pins the parser and the
    ; divider; the load itself is the reu_load the hardware suite runs, and
    ; the Boing demo plays the whole path. tools/gen_wav_fixtures.py wrote the
    ; files and documents their values. Voice offsets: flags +1, reu_address
    ; +4, length +8, rate +20.

    test("sdk-wav-mono16", "16-bit mono at 8,000 Hz: address, length, divider 781, the 16-bit flag") {
      jsr([boot], stop_on_rts = true, fail_on_brk = true)
      jsr([t_init], stop_on_rts = true, fail_on_brk = true)
      [ident_buflen] = $40
      [ident_buflen] + $01 = $00
      [reply0] = $2f            ; "/Usb0/wav"
      [reply1] = $55
      [reply2] = $73
      [reply3] = $62
      [reply0] + $04 = $30
      [reply0] + $05 = $2f
      [reply0] + $06 = $77
      [reply0] + $07 = $61
      [reply0] + $08 = $76
      [reply0] + $09 = $00
      jsr([t_chdir], stop_on_rts = true, fail_on_brk = true)
      assert([result] == $00, "in the fixture directory")

      [reply0] = $6d            ; "mono16.wav"
      [reply1] = $6f
      [reply2] = $6e
      [reply3] = $6f
      [reply0] + $04 = $31
      [reply0] + $05 = $36
      [reply0] + $06 = $2e
      [reply0] + $07 = $77
      [reply0] + $08 = $61
      [reply0] + $09 = $76
      [reply0] + $0a = $00
      [reu_at] = $00            ; REU $004000
      [reu_at] + $01 = $40
      [reu_at] + $02 = $00
      [reu_at] + $03 = $00
      memfill([voice], 22, $ee)
      [result] = $ff
      jsr([t_audio_load_wav], stop_on_rts = true, fail_on_brk = true)
      assert([result] == $04, "ULTIMATE_ERR_NOT_SUPPORTED: no REU load in this firmware, so the header was accepted")
      assert(([voice] + $04).b == $00, "reu_address low")
      assert(([voice] + $05).b == $40, "reu_address middle")
      assert(([voice] + $06).b == $00, "reu_address high")
      assert(([voice] + $08).b == $80, "length 128, low")
      assert(([voice] + $09).b == $00, "length, middle")
      assert(([voice] + $0a).b == $00, "length, high")
      assert(([voice] + $14).b == $0d, "divider 781 = $030D, low")
      assert(([voice] + $15).b == $03, "divider, high")
      assert(([voice] + $01).b == $10, "UA_CTRL_16BIT, and mono so no interleave")
      assert(([voice] + $00).b == $ee, "channel untouched")
      assert(([voice] + $02).b == $ee, "volume untouched")
      assert(([voice] + $03).b == $ee, "pan untouched")

      ; The file was closed on the way out: a close now is 85,NO FILE OPEN.
      [result] = $ff
      jsr([t_close], stop_on_rts = true, fail_on_brk = true)
      assert([result] == $07, "ULTIMATE_ERR_DEVICE: nothing was left open")
    }

    test("sdk-wav-stereo16", "16-bit stereo at 11,025 Hz: divider 566, interleave set") {
      jsr([boot], stop_on_rts = true, fail_on_brk = true)
      jsr([t_init], stop_on_rts = true, fail_on_brk = true)
      [ident_buflen] = $40
      [ident_buflen] + $01 = $00
      [reply0] = $2f            ; "/Usb0/wav"
      [reply1] = $55
      [reply2] = $73
      [reply3] = $62
      [reply0] + $04 = $30
      [reply0] + $05 = $2f
      [reply0] + $06 = $77
      [reply0] + $07 = $61
      [reply0] + $08 = $76
      [reply0] + $09 = $00
      jsr([t_chdir], stop_on_rts = true, fail_on_brk = true)
      assert([result] == $00, "in the fixture directory")
      [reply0] = $73            ; "stereo16.wav"
      [reply1] = $74
      [reply2] = $65
      [reply3] = $72
      [reply0] + $04 = $65
      [reply0] + $05 = $6f
      [reply0] + $06 = $31
      [reply0] + $07 = $36
      [reply0] + $08 = $2e
      [reply0] + $09 = $77
      [reply0] + $0a = $61
      [reply0] + $0b = $76
      [reply0] + $0c = $00
      [reu_at] = $00
      [reu_at] + $01 = $00
      [reu_at] + $02 = $01      ; REU $010000
      [reu_at] + $03 = $00
      memfill([voice], 22, $ee)
      [result] = $ff
      jsr([t_audio_load_wav], stop_on_rts = true, fail_on_brk = true)
      assert([result] == $04, "ULTIMATE_ERR_NOT_SUPPORTED from reu_load, header accepted")
      assert(([voice] + $06).b == $01, "reu_address high")
      assert(([voice] + $08).b == $80, "length 128")
      assert(([voice] + $14).b == $36, "divider 566 = $0236, low")
      assert(([voice] + $15).b == $02, "divider, high")
      assert(([voice] + $01).b == $50, "UA_CTRL_16BIT | UA_CTRL_INTERLEAVE")
    }

    test("sdk-wav-mono8", "8-bit mono at 8,363 Hz: divider 747, no format flags, length not rounded") {
      jsr([boot], stop_on_rts = true, fail_on_brk = true)
      jsr([t_init], stop_on_rts = true, fail_on_brk = true)
      [ident_buflen] = $40
      [ident_buflen] + $01 = $00
      [reply0] = $2f            ; "/Usb0/wav"
      [reply1] = $55
      [reply2] = $73
      [reply3] = $62
      [reply0] + $04 = $30
      [reply0] + $05 = $2f
      [reply0] + $06 = $77
      [reply0] + $07 = $61
      [reply0] + $08 = $76
      [reply0] + $09 = $00
      jsr([t_chdir], stop_on_rts = true, fail_on_brk = true)
      assert([result] == $00, "in the fixture directory")
      [reply0] = $6d            ; "mono8.wav"
      [reply1] = $6f
      [reply2] = $6e
      [reply3] = $6f
      [reply0] + $04 = $38
      [reply0] + $05 = $2e
      [reply0] + $06 = $77
      [reply0] + $07 = $61
      [reply0] + $08 = $76
      [reply0] + $09 = $00
      [reu_at] = $00
      [reu_at] + $01 = $40
      [reu_at] + $02 = $00
      [reu_at] + $03 = $00
      memfill([voice], 22, $ee)
      [result] = $ff
      jsr([t_audio_load_wav], stop_on_rts = true, fail_on_brk = true)
      assert([result] == $04, "ULTIMATE_ERR_NOT_SUPPORTED from reu_load, header accepted")
      assert(([voice] + $08).b == $64, "length 100: 8-bit mono is not rounded to even")
      assert(([voice] + $14).b == $eb, "divider 747 = $02EB, low")
      assert(([voice] + $15).b == $02, "divider, high")
      assert(([voice] + $01).b == $00, "8-bit mono: no format flags")
    }

    test("sdk-wav-not-riff", "a file that is not a WAV is a protocol error, and is closed") {
      jsr([boot], stop_on_rts = true, fail_on_brk = true)
      jsr([t_init], stop_on_rts = true, fail_on_brk = true)
      [ident_buflen] = $40
      [ident_buflen] + $01 = $00
      [reply0] = $2f            ; "/Usb0/wav"
      [reply1] = $55
      [reply2] = $73
      [reply3] = $62
      [reply0] + $04 = $30
      [reply0] + $05 = $2f
      [reply0] + $06 = $77
      [reply0] + $07 = $61
      [reply0] + $08 = $76
      [reply0] + $09 = $00
      jsr([t_chdir], stop_on_rts = true, fail_on_brk = true)
      assert([result] == $00, "in the fixture directory")
      [reply0] = $6e            ; "notwav.bin"
      [reply1] = $6f
      [reply2] = $74
      [reply3] = $77
      [reply0] + $04 = $61
      [reply0] + $05 = $76
      [reply0] + $06 = $2e
      [reply0] + $07 = $62
      [reply0] + $08 = $69
      [reply0] + $09 = $6e
      [reply0] + $0a = $00
      [reu_at] = $00
      [reu_at] + $01 = $40
      [reu_at] + $02 = $00
      [reu_at] + $03 = $00
      [result] = $ff
      jsr([t_audio_load_wav], stop_on_rts = true, fail_on_brk = true)
      assert([result] == $03, "ULTIMATE_ERR_PROTOCOL: not RIFF")
      [result] = $ff
      jsr([t_close], stop_on_rts = true, fail_on_brk = true)
      assert([result] == $07, "ULTIMATE_ERR_DEVICE: the file was closed before returning")
    }

    test("sdk-wav-missing-file", "a missing file is the DOS error, untouched") {
      jsr([boot], stop_on_rts = true, fail_on_brk = true)
      jsr([t_init], stop_on_rts = true, fail_on_brk = true)
      [reply0] = $6e            ; "nope.wav"
      [reply1] = $6f
      [reply2] = $70
      [reply3] = $65
      [reply0] + $04 = $2e
      [reply0] + $05 = $77
      [reply0] + $06 = $61
      [reply0] + $07 = $76
      [reply0] + $08 = $00
      [reu_at] = $00
      [reu_at] + $01 = $40
      [reu_at] + $02 = $00
      [reu_at] + $03 = $00
      [result] = $ff
      jsr([t_audio_load_wav], stop_on_rts = true, fail_on_brk = true)
      assert([result] == $07, "ULTIMATE_ERR_DEVICE: FILE DOESN'T EXIST, as ultimate_open reports it")
    }
```

- [ ] **Step 5: Verify the build fails for the right reason**

Run: `make -C tests/emulator 2>&1 | grep -iE 'unresolved|error' | head -3`
Expected: `Unresolved external 'ultimate_audio_load_wav'` from the harness link. (The suites cannot run until Task 6 provides the symbol; that is the red step.)

- [ ] **Step 6: Commit the fixtures and the constant only**

The harness, suite and `ultimate.inc` edits stay uncommitted: a commit whose
test harness does not link is a commit with failing tests, which this repo
does not allow. Task 6 commits them together with the module that makes them
pass.

```bash
git add tools/gen_protocol.py tools/gen_wav_fixtures.py tests/emulator/fixtures/usb0/wav \
        include/uci_protocol.h bindings/asm/uci_protocol.inc bindings/kickass/uci_protocol.asm \
        bindings/acme/uci_protocol.a docs/generated/protocol-constants.md bindings/asm/uci_argtable.inc
git commit -m "test(wav): fixtures for ultimate_audio_load_wav, and UA_RATE_CLOCK

Four small files under the simulator's filesystem, written by
tools/gen_wav_fixtures.py, with the values the suite will assert.
UA_RATE_CLOCK joins the protocol constants.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01MWZot9Zonrj1xjkwu9tCpq"
```

---

### Task 6: `src/uci/wav.s` (A4, green)

**Files:**
- Create: `src/uci/wav.s`
- Modify: `src/uci/sources.mk` (add the module after `src/uci/audio.s`)
- Modify: `src/uci/audio.s` (module comment: point file loading here)
- Modify: `include/ultimate.h` (prototype after `ultimate_audio_irq_clear`)
- Modify: `docs/asm-abi.md` (audio rows in the symbol table)
- Modify: `docs/superpowers/specs/2026-09-02-sdk-fixes-from-boing-design.md` (one sentence)

**Interfaces:**
- Consumes: `ultimate_open` (`A` = `DOS_FA_READ`, `ult_buf` = name), `ultimate_read` (`ult_buf`, `ult_buflen`, `ult_outlen` = where the count lands), `ultimate_seek` (`ult_num` = 32-bit position), `ultimate_close`, `ultimate_reu_load` (`ult_reu`, `ult_reulen`, the open file), `ultimate_reu_fetch`/`ultimate_reu_stash` (`ult_addr`, `ult_reu`, `ult_reulen`, low word); all return `A` = result. SDK RAM: `ult_scratch` (16 bytes), `ult_stage` (40), `ult_arg2` (2); zero page `uci_ptr`.
- Produces: `ultimate_audio_load_wav`: `ult_buf` = name, `ult_reu` = REU address, `A`/`X` = voice → `A` = result, `X` = 0, flags from `A`. Fills the voice's `reu_address`, `length`, `rate`, `flags`; leaves `ult_reu` as it found it on success.

- [ ] **Step 1: Write the module**

Create `src/uci/wav.s`:

```
; wav.s - a WAV file into the REU, and a voice ready to play it.
;
; ultimate_audio_load_wav opens the file, walks the RIFF header, loads the data
; chunk straight into the REU with ultimate_reu_load, closes the file, and
; fills the voice's address, length, rate divider and format flags. The engine
; plays signed PCM at any rate the divider can express, so the only thing a
; WAV ever needs converting is the 8-bit sign: WAV stores 8-bit samples
; unsigned. Those get one more pass, in place inside the REU, WAV_SLICE bytes
; at a time through the staging area. 16-bit data is played as it is.
;
; audio.s is the register layer and knows nothing about files; this is the
; composition every demo used to write for itself.
;
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"
        .include "uci_seg.inc"
        .include "uci_zp.inc"

        .import ultimate_open, ultimate_close, ultimate_read, ultimate_seek
        .import ultimate_reu_load, ultimate_reu_fetch, ultimate_reu_stash
        .import ult_buf, ult_buflen, ult_outlen, ult_num
        .import ult_addr, ult_reu, ult_reulen
        .import ult_scratch, ult_stage, ult_arg2

        .export ultimate_audio_load_wav

; State: ult_scratch (16 bytes) and the tail of ult_stage (40 bytes, of which
; the first WAV_SLICE are the read buffer and the sign pass's slice).
WAV_POS    = ult_scratch + 0    ; 4  file offset of the chunk header in hand;
                                ;    then the REU address the sign pass started at
WAV_SIZE   = ult_scratch + 4    ; 4  that chunk's size
WAV_LEN    = ult_scratch + 8    ; 4  the division's dividend, then the data byte
                                ;    count, which the sign pass counts down
WAV_RATE   = ult_scratch + 12   ; 2  sample rate in Hz, then the divider
WAV_BITS   = ult_scratch + 14   ; 1  8 or 16
WAV_CHANS  = ult_scratch + 15   ; 1  1 or 2
WAV_GOT    = ult_stage + 32     ; 2  how many bytes the last read returned
WAV_REM    = ult_stage + 34     ; 3  the division's remainder; a read's expected count
WAV_FMT    = ult_stage + 37     ; 1  1 once the fmt chunk has been seen
WAV_SLICE  = 32                 ; bytes per sign-pass DMA

RATE_MIN   = 96                 ; below this the divider does not fit 16 bits

        uci_code

; ---------------------------------------------------------------------------
; ultimate_audio_load_wav   ult_buf = name, ult_reu = REU address,
;                           A/X = ultimate_audio_voice  ->  A = result
;
; On success reu_address, length, rate and flags describe the loaded sample and
; channel, volume, pan and the repeat points are as the caller left them. On
; failure the voice may be partly written and means nothing. The file is
; closed on every path after a successful open.
; ---------------------------------------------------------------------------
ultimate_audio_load_wav:
        sta ult_arg2
        stx ult_arg2 + 1
        ora ult_arg2 + 1
        beq @invalid

        lda #DOS_FA_READ
        jsr ultimate_open
        cmp #ULTIMATE_OK
        beq :+
        rts                     ; the DOS result; nothing is open
:
        jsr wav_parse
        bcs @fail
        jsr wav_fill
        jsr wav_load
        bcs @fail
        jmp ultimate_close      ; its result is the result

@fail:  pha
        jsr ultimate_close
        ldx #$00
        pla
        rts

@invalid:
        ldx #$00
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        rts

; ---------------------------------------------------------------------------
; The header. Leaves the file positioned at the first data byte and WAV_LEN,
; WAV_RATE (as a divider), WAV_BITS and WAV_CHANS filled. Carry set and A = the
; result on failure.
; ---------------------------------------------------------------------------
wav_parse:
        lda #$00
        sta WAV_FMT

        lda #8                  ; "RIFF" and the file size
        jsr wav_read_stage
        bcs @out
        lda #<riff_tag
        ldx #>riff_tag
        jsr wav_tag_is
        bne @protocol
        lda #4                  ; "WAVE"
        jsr wav_read_stage
        bcs @out
        lda #<wave_tag
        ldx #>wave_tag
        jsr wav_tag_is
        bne @protocol

        lda #12                 ; the first chunk header
        sta WAV_POS
        lda #$00
        sta WAV_POS + 1
        sta WAV_POS + 2
        sta WAV_POS + 3

@chunk: jsr wav_seek_pos
        bcs @out
        lda #8                  ; tag and size
        jsr wav_read_stage
        bcs @out
        ldx #$03
@size:  lda ult_stage + 4,x
        sta WAV_SIZE,x
        dex
        bpl @size

        lda #<fmt_tag
        ldx #>fmt_tag
        jsr wav_tag_is
        bne @notfmt
        jsr wav_fmt_chunk
        bcs @out
        jmp @advance
@notfmt:
        lda #<data_tag
        ldx #>data_tag
        jsr wav_tag_is
        bne @advance
        jmp wav_data_chunk      ; the end of the walk, carry says how it went
@advance:
        jsr wav_next
        bcs @out
        jmp @chunk

@protocol:
        lda #ULTIMATE_ERR_PROTOCOL
        sec
@out:   rts

; A/X = a four-byte tag. Z set when ult_stage starts with it.
wav_tag_is:
        sta uci_ptr
        stx uci_ptr + 1
        ldy #$03
@cmp:   lda (uci_ptr),y
        cmp ult_stage,y
        bne @no
        dey
        bpl @cmp
        lda #$00
@no:    rts

; A = how many bytes to read into ult_stage. Fewer is a truncated file, which
; is a broken header rather than an I/O failure. Carry set on failure.
wav_read_stage:
        sta ult_buflen
        sta WAV_REM
        lda #$00
        sta ult_buflen + 1
        lda #<ult_stage
        sta ult_buf
        lda #>ult_stage
        sta ult_buf + 1
        lda #<WAV_GOT
        sta ult_outlen
        lda #>WAV_GOT
        sta ult_outlen + 1
        jsr ultimate_read
        cmp #ULTIMATE_OK
        bne @err
        lda WAV_GOT + 1
        bne @short
        lda WAV_GOT
        cmp WAV_REM
        bne @short
        clc
        rts
@short: lda #ULTIMATE_ERR_PROTOCOL
@err:   sec
        rts

; Seek to WAV_POS. Carry set on failure.
wav_seek_pos:
        ldx #$03
@copy:  lda WAV_POS,x
        sta ult_num,x
        dex
        bpl @copy
        jsr ultimate_seek
        ; falls into wav_check

; A = a result. Carry set when it is not ULTIMATE_OK; A is kept either way.
wav_check:
        cmp #ULTIMATE_OK
        beq @ok
        sec
        rts
@ok:    clc
        rts

; WAV_POS = WAV_POS + 8 + WAV_SIZE, rounded up to even, as RIFF pads an odd
; chunk. A sum that wraps past 32 bits is a corrupt header.
wav_next:
        lda WAV_SIZE
        and #$01
        clc
        adc #8
        adc WAV_SIZE
        sta WAV_REM
        lda WAV_SIZE + 1
        adc #$00
        sta WAV_REM + 1
        lda WAV_SIZE + 2
        adc #$00
        sta WAV_REM + 2
        lda WAV_SIZE + 3
        adc #$00
        bcs @wrap
        pha
        clc
        lda WAV_POS
        adc WAV_REM
        sta WAV_POS
        lda WAV_POS + 1
        adc WAV_REM + 1
        sta WAV_POS + 1
        lda WAV_POS + 2
        adc WAV_REM + 2
        sta WAV_POS + 2
        pla
        adc WAV_POS + 3
        sta WAV_POS + 3
        bcs @wrap
        clc
        rts
@wrap:  lda #ULTIMATE_ERR_PROTOCOL
        sec
        rts

; The fmt chunk: PCM, 1 or 2 channels, 8 or 16 bits, a rate that fits sixteen
; bits and is at least RATE_MIN. The file is positioned just past the chunk
; header, so the body is the next read.
wav_fmt_chunk:
        lda WAV_SIZE + 1
        ora WAV_SIZE + 2
        ora WAV_SIZE + 3
        bne @big
        lda WAV_SIZE
        cmp #16
        bcc @protocol
@big:   lda #16
        jsr wav_read_stage
        bcs @out

        lda ult_stage + 0       ; format 1 = PCM
        cmp #$01
        bne @unsupported
        lda ult_stage + 1
        bne @unsupported

        lda ult_stage + 3       ; channels 1 or 2
        bne @unsupported
        lda ult_stage + 2
        beq @unsupported
        cmp #$03
        bcs @unsupported
        sta WAV_CHANS

        lda ult_stage + 6       ; rate: 16 bits, at least RATE_MIN
        ora ult_stage + 7
        bne @unsupported
        lda ult_stage + 5
        bne @rate_ok
        lda ult_stage + 4
        cmp #RATE_MIN
        bcc @unsupported
@rate_ok:
        lda ult_stage + 4
        sta WAV_RATE
        lda ult_stage + 5
        sta WAV_RATE + 1

        lda ult_stage + 15      ; bits 8 or 16
        bne @unsupported
        lda ult_stage + 14
        cmp #8
        beq @bits_ok
        cmp #16
        bne @unsupported
@bits_ok:
        sta WAV_BITS
        jsr wav_divider
        lda #$01
        sta WAV_FMT
        clc
        rts

@protocol:
        lda #ULTIMATE_ERR_PROTOCOL
        sec
        rts
@unsupported:
        lda #ULTIMATE_ERR_NOT_SUPPORTED
        sec
@out:   rts

; WAV_RATE = UA_RATE_CLOCK / WAV_RATE, truncated. A 24-bit dividend over a
; 16-bit divisor by restoring division; the quotient fits sixteen bits because
; the rate is at least RATE_MIN. The dividend sits in WAV_LEN, free until the
; data chunk; the remainder in WAV_REM.
wav_divider:
        lda #<UA_RATE_CLOCK
        sta WAV_LEN
        lda #>UA_RATE_CLOCK
        sta WAV_LEN + 1
        lda #^UA_RATE_CLOCK
        sta WAV_LEN + 2
        lda #$00
        sta WAV_REM
        sta WAV_REM + 1
        sta WAV_REM + 2
        ldx #24
@bit:   asl WAV_LEN
        rol WAV_LEN + 1
        rol WAV_LEN + 2
        rol WAV_REM
        rol WAV_REM + 1
        rol WAV_REM + 2
        lda WAV_REM + 2
        bne @sub
        lda WAV_REM + 1
        cmp WAV_RATE + 1
        bcc @next
        bne @sub
        lda WAV_REM
        cmp WAV_RATE
        bcc @next
@sub:   lda WAV_REM
        sec
        sbc WAV_RATE
        sta WAV_REM
        lda WAV_REM + 1
        sbc WAV_RATE + 1
        sta WAV_REM + 1
        lda WAV_REM + 2
        sbc #$00
        sta WAV_REM + 2
        inc WAV_LEN             ; the quotient bit; asl left bit 0 clear
@next:  dex
        bne @bit
        lda WAV_LEN
        sta WAV_RATE
        lda WAV_LEN + 1
        sta WAV_RATE + 1
        rts

; The data chunk: needs a fmt before it; its size, rounded down to even for
; 16-bit or stereo data, is the length; and the engine addresses 16 MB.
; Carry set with A = the result on failure, clear when the walk is done.
wav_data_chunk:
        lda WAV_FMT
        beq @protocol
        ldx #$03
@copy:  lda WAV_SIZE,x
        sta WAV_LEN,x
        dex
        bpl @copy
        lda WAV_LEN + 3
        bne @unsupported
        lda WAV_BITS
        cmp #16
        beq @even
        lda WAV_CHANS
        cmp #2
        bne @sized
@even:  lda WAV_LEN
        and #$FE
        sta WAV_LEN
@sized: lda WAV_LEN
        ora WAV_LEN + 1
        ora WAV_LEN + 2
        beq @protocol
        clc
        rts
@protocol:
        lda #ULTIMATE_ERR_PROTOCOL
        sec
        rts
@unsupported:
        lda #ULTIMATE_ERR_NOT_SUPPORTED
        sec
        rts

; ---------------------------------------------------------------------------
; The voice: reu_address from ult_reu, length, rate, and the format flags.
; ---------------------------------------------------------------------------
wav_fill:
        lda ult_arg2
        sta uci_ptr
        lda ult_arg2 + 1
        sta uci_ptr + 1
        ldx #$00
@dword: txa
        clc
        adc #UA_VOICE_REU
        tay
        lda ult_reu,x
        sta (uci_ptr),y
        txa
        clc
        adc #UA_VOICE_LENGTH
        tay
        lda WAV_LEN,x
        sta (uci_ptr),y
        inx
        cpx #$04
        bne @dword
        ldy #UA_VOICE_RATE
        lda WAV_RATE
        sta (uci_ptr),y
        iny
        lda WAV_RATE + 1
        sta (uci_ptr),y
        lda #$00
        ldx WAV_BITS
        cpx #16
        bne :+
        ora #UA_CTRL_16BIT
:       ldx WAV_CHANS
        cpx #2
        bne :+
        ora #UA_CTRL_INTERLEAVE
:       ldy #UA_VOICE_FLAGS
        sta (uci_ptr),y
        rts

; ---------------------------------------------------------------------------
; The data chunk into the REU, then the sign pass for 8-bit data. The file is
; positioned at the first data byte, which is where reu_load reads from.
; Carry set with A = the result on failure.
; ---------------------------------------------------------------------------
wav_load:
        ldx #$03
@copy:  lda WAV_LEN,x
        sta ult_reulen,x
        dex
        bpl @copy
        jsr ultimate_reu_load
        jsr wav_check
        bcs @out
        lda WAV_BITS
        cmp #8
        beq wav_sign_pass
        clc
@out:   rts

; 8-bit WAV samples are unsigned and the engine plays signed: flip bit 7 of
; every byte in place, WAV_SLICE bytes at a time, through ult_stage. Leaves
; ult_reu where it started.
wav_sign_pass:
        ldx #$03
@save:  lda ult_reu,x
        sta WAV_POS,x
        dex
        bpl @save
        lda #<ult_stage
        sta ult_addr
        lda #>ult_stage
        sta ult_addr + 1
        lda #$00
        sta ult_reulen + 1
        sta ult_reulen + 2
        sta ult_reulen + 3

@slice: lda WAV_LEN + 1
        ora WAV_LEN + 2
        bne @full
        lda WAV_LEN
        beq @done
        cmp #WAV_SLICE
        bcc @part
@full:  lda #WAV_SLICE
@part:  sta ult_reulen
        jsr ultimate_reu_fetch
        jsr wav_check
        bcs @out
        ldx ult_reulen
@flip:  lda ult_stage - 1,x
        eor #$80
        sta ult_stage - 1,x
        dex
        bne @flip
        jsr ultimate_reu_stash
        jsr wav_check
        bcs @out

        lda ult_reu             ; next slice
        clc
        adc ult_reulen
        sta ult_reu
        bcc :+
        inc ult_reu + 1
        bne :+
        inc ult_reu + 2
:       lda WAV_LEN             ; and that much less to do
        sec
        sbc ult_reulen
        sta WAV_LEN
        bcs @slice
        dec WAV_LEN + 1
        lda WAV_LEN + 1
        cmp #$FF
        bne @slice
        dec WAV_LEN + 2
        jmp @slice

@done:  ldx #$03
@rest:  lda WAV_POS,x
        sta ult_reu,x
        dex
        bpl @rest
        clc
@out:   rts

        .rodata
riff_tag: .byte $52, $49, $46, $46      ; "RIFF"
wave_tag: .byte $57, $41, $56, $45      ; "WAVE"
fmt_tag:  .byte $66, $6D, $74, $20      ; "fmt "
data_tag: .byte $64, $61, $74, $61      ; "data"

        uci_code
```

In `src/uci/sources.mk`, after the line `           src/uci/audio.s \` add `           src/uci/wav.s \`.

In `src/uci/audio.s`, in the module comment, replace the sentence

```
; ... This module is the small,
; checked register layer; file streaming is composed from it and the existing
; DOS/REU services by the application.
```

with

```
; ... This module is the small,
; checked register layer. wav.s composes it with the DOS and REU services to
; load a sample file; streaming beyond one file is the application's.
```

(keep the surrounding words exactly as they are; only the clause after "register layer" changes).

- [ ] **Step 2: Build and run the emulator suites**

Run: `make -C tests/emulator run 2>&1 | grep -E 'wav|passed|failed|FAIL' | head -20`
Expected: the five `sdk-wav-*` cases pass in both `sdk.suite` and `sdk-placed.suite`; every other suite passes. If `sdk-wav-mono16` fails on a divider byte, check `wav_divider` first: 6,250,000 / 8,000 = 781 = `$030D`.

- [ ] **Step 3: The C prototype and the ABI rows**

In `include/ultimate.h`, after

```c
/* Clear one channel's end-of-sample bit. */
uint8_t ultimate_audio_irq_clear(uint8_t channel);
```

add

```c
/*
 * A WAV file into the REU and into this voice. Opens `name`, walks the RIFF
 * header, loads the data chunk to `reuaddr` with no byte passing through the
 * C64, closes the file, and fills reu_address, length, rate and flags.
 * channel, volume, pan and the repeat points are left as they were: set
 * them, OR UA_CTRL_REPEAT or UA_CTRL_IRQ into flags if wanted, then
 * ultimate_audio_configure() and ultimate_audio_start().
 *
 * Any PCM WAV: 8 or 16 bit, mono or stereo, any rate from 96 Hz. 16-bit data
 * is played as it is. 8-bit data is stored unsigned in a WAV and played
 * signed by the engine, so it is fixed in place inside the REU after the
 * load, 32 bytes at a time: about a tenth of a second for a 24 KB sample at
 * any CPU speed. Stereo: the voice describes the left channel with
 * UA_CTRL_INTERLEAVE set; the right channel is the same voice with
 * reu_address + 2 and length - 2 (16-bit), or + 1 and - 1 (8-bit).
 *
 * Results: the DOS error when the file will not open; ULTIMATE_ERR_PROTOCOL
 * for a file that is not RIFF/WAVE or has a broken chunk list;
 * ULTIMATE_ERR_NOT_SUPPORTED for compressed or 24-bit data, more than two
 * channels, a rate under 96 Hz, or a data chunk past 16 MB; the REU result
 * when the load or the sign fix fails. The file is closed on every path. On
 * failure the voice may be partly written and means nothing.
 */
uint8_t ultimate_audio_load_wav(const char *name, uint32_t reuaddr,
                                ultimate_audio_voice *voice);
```

In `docs/asm-abi.md`, in the symbol table, after the row for `ultimate_reu_size`, add:

```
| `ultimate_audio_init` | — | `A` = result code |
| `ultimate_audio_available` | — | `A` = 1 after a successful init |
| `ultimate_audio_version` | — | `A` = the module version byte |
| `ultimate_audio_configure` | `A`/`X` = `ultimate_audio_voice` | `A` = result code; stops the channel, about 2 ms |
| `ultimate_audio_start` | `A` = channel, `X` = `UA_CTRL_*` flags | `A` = result code |
| `ultimate_audio_stop` | `A` = channel | `A` = result code |
| `ultimate_audio_irq_status` | — | `A` = end-of-sample channel mask |
| `ultimate_audio_irq_clear` | `A` = channel | `A` = result code |
| `ultimate_audio_load_wav` | `ult_buf` = name, `ult_reu` = REU address, `A`/`X` = `ultimate_audio_voice` | `A` = result code; the voice's address, length, rate and flags filled |
```

- [ ] **Step 4: One sentence in the spec**

In `docs/superpowers/specs/2026-09-02-sdk-fixes-from-boing-design.md`, under "A4 ... Results", change

```
The file is closed on every path. `voice` is written only on success.
```

to

```
The file is closed on every path. On failure the voice may be partly written
and means nothing; that is what lets the simulator, which has no REU load,
assert the parsed header.
```

- [ ] **Step 5: Build everything that links the library**

Run: `make lib blob examples 2>&1 | grep -iE 'error|warning' ; echo "exit=$?"`
Expected: no error lines (`exit=1` from grep finding nothing). The cc65 library, the blob and the examples all link with the new module.

- [ ] **Step 6: Commit**

```bash
git add src/uci/wav.s src/uci/sources.mk src/uci/audio.s include/ultimate.h docs/asm-abi.md \
        bindings/asm/ultimate.inc tests/emulator/harness.s tests/emulator/Makefile tests/emulator/sdk.suite \
        docs/superpowers/specs/2026-09-02-sdk-fixes-from-boing-design.md
git commit -m "feat(audio): ultimate_audio_load_wav, a WAV file into the REU and a voice

Open, walk the RIFF header, reu_load the data chunk, close, fill the
voice's address, length, divider and format flags. 8-bit data, which a
WAV stores unsigned, is fixed in place inside the REU 32 bytes at a time
through the staging area. No host conversion, no caller buffer. Five
simulator cases pin the parser and the divider.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01MWZot9Zonrj1xjkwu9tCpq"
```

---

### Task 7: The cc65 wrapper and the blob's extension table (A4 bindings)

**Files:**
- Modify: `bindings/cc65/ultimate_cc65.s` (imports/exports near lines 69 and 91; wrapper after `_ultimate_audio_start`)
- Modify: `bindings/blob/blob.cfg.in` (one segment line), `bindings/blob/blob.s` (import; extension table; shim), `bindings/blob/README.md` (paragraph and row)
- Modify: `tools/test_blob_table.py` (`test_the_table_has_no_gaps`)
- Modify: `tests/emulator/blob.suite` (one case)
- Regenerate: the assembler includes (`BLOB_AUDIO_LOAD_WAV` appears)

**Interfaces:**
- Produces: C `uint8_t ultimate_audio_load_wav(const char *name, uint32_t reuaddr, ultimate_audio_voice *voice)`; blob entry `+$300` `audio_load_wav` (`bp_name`, `bp_reu` in; `bp_audio` filled, `bp_result`); constant `BLOB_AUDIO_LOAD_WAV = $300`.

- [ ] **Step 1: The blob-table test first**

In `tools/test_blob_table.py`, replace `test_the_table_has_no_gaps` with:

```python
    def test_the_tables_have_no_gaps(self):
        # Three tables: the header page from +$04, the audio table in the
        # tail of the parameter block from +$2E8, and the extension table from
        # +$300. Within each, entries are three bytes apart with nothing
        # missing; a gap is a mistyped comment or a missing jmp.
        offsets = [off for off, _ in code_entries()]
        expected = []
        for start, limit in ((0x04, 0x100), (0x2E8, 0x300), (0x300, 0x1000)):
            count = len([off for off in offsets if start <= off < limit])
            expected += list(range(start, start + 3 * count, 3))
        self.assertEqual(offsets, expected,
                         "a jump table has a mistyped comment or a missing jmp")
```

And add, in the same class:

```python
    def test_the_extension_table_starts_the_code_area(self):
        # The parameter block is full; entries added after the audio table
        # live at +$300 and must be documented there.
        self.assertIn(0x300, [off for off, _ in code_entries()])
        self.assertIn(0x300, dict(doc_entries()))
```

Run: `python3 -m unittest tools.test_blob_table -v 2>&1 | tail -4`
Expected: `test_the_extension_table_starts_the_code_area` FAILS (no `+$300` yet); the rest pass.

- [ ] **Step 2: The extension table and the shim**

In `bindings/blob/blob.cfg.in`, change the `SEGMENTS` block to

```
SEGMENTS {
    BLOBHDR:  load = HDR,  type = ro;
    BLOBPARM: load = PARM, type = rw, define = yes;
    BLOBEXT:  load = MAIN, type = ro;
    CODE:     load = MAIN, type = ro;
    RODATA:   load = MAIN, type = ro;
}
```

(`BLOBEXT` before `CODE`, so it is the first thing in `MAIN` at `+$300`.)

In `bindings/blob/blob.s`:
- in the import block, after `.import ultimate_audio_configure, ultimate_audio_start` add `.import ultimate_audio_load_wav`
- after the `.assert (* - blob_params) = $200, error, "audio table must end with the parameter block"` line and before `; ---...--- The shims.`, add:

```
; The parameter block is full and the audio table with it. Entries from here
; on live in a third table at +$300, the first thing in the code area: it can
; grow without moving anything published before it, and nothing below it is
; published by offset.
        .segment "BLOBEXT"
blob_ext_table:                     ; +$300 from the blob base
        jmp blob_audio_load_wav         ; +$300
```

- after `blob_audio_irq_clear` (which ends `jmp blob_done`), add:

```
; The WAV's name in bp_name, the REU address in bp_reu; bp_audio comes back
; with the address, length, divider and flags filled.
blob_audio_load_wav:
        jsr blob_set_name
        jsr blob_set_reu
        lda #<bp_audio
        ldx #>bp_audio
        jsr ultimate_audio_load_wav
        jmp blob_done
```

In `bindings/blob/README.md`, after the `+$2FD` row (`| `+$2FD` | `audio_irq_clear` | ...`), add:

```

The parameter block is full and the audio table with it, so entries after
`+$2FD` live in a third table at `+$300`, the first thing in the code area.
It grows downwards into code that is not published by offset, so it never
moves anything above it.

| Offset | Entry | In | Out |
|---|---|---|---|
| `+$300` | `audio_load_wav` | `bp_name` = the WAV, `bp_reu` = REU address | `bp_audio` address, length, rate and flags filled; `bp_result` |
```

- [ ] **Step 3: The cc65 wrapper**

In `bindings/cc65/ultimate_cc65.s`:
- in the block of audio imports (`.import ultimate_audio_start` near line 69) add `.import ultimate_audio_load_wav`
- in the export block (`.export _ultimate_audio_start` near line 91) add `.export _ultimate_audio_load_wav`
- after `_ultimate_audio_start` (which ends `jmp ultimate_audio_start`) add:

```
; uint8_t ultimate_audio_load_wav(const char *name, uint32_t reuaddr,
;                                 ultimate_audio_voice *voice);
;
; A/X holds voice; the C stack holds reuaddr at 0..3 and name at 4..5.
_ultimate_audio_load_wav:
        pha
        txa
        pha
        ldy #$00
        lda (sp),y
        sta ult_reu
        iny
        lda (sp),y
        sta ult_reu + 1
        iny
        lda (sp),y
        sta ult_reu + 2
        iny
        lda (sp),y
        sta ult_reu + 3
        iny
        jsr cc_ptr_at_y                 ; name -> ult_buf
        jsr incsp6
        pla
        tax
        pla
        jmp ultimate_audio_load_wav
```

(`cc_ptr_at_y` copies the two bytes at `(sp),y` into `ult_buf`; `ult_buf` and `incsp6` are already imported at the top of the file.)

- [ ] **Step 4: The blob suite case**

In `tests/emulator/blob.suite`, after the last test in the suite (before the closing `}` of `suite(...)`), add:

```
    ; The extension table: +$300 is the first entry past the full parameter
    ; block. A missing file is enough to prove the shim reaches the SDK and
    ; the SDK's result reaches bp_result.
    test("blob-audio-load-wav-missing-file", "audio_load_wav through +$300 reports the DOS error") {
      jsr($701c, stop_on_rts = true, fail_on_brk = true)   ; +$1C ultimate_init
      $7129 = $6e            ; bp_name at +$29: "nope.wav"
      $712a = $6f
      $712b = $70
      $712c = $65
      $712d = $2e
      $712e = $77
      $712f = $61
      $7130 = $76
      $7131 = $00
      $7256 = $00            ; bp_reu at +$156: 0
      $7257 = $00
      $7258 = $00
      $7259 = $00
      $7100 = $ff
      jsr($7300, stop_on_rts = true, fail_on_brk = true)   ; +$300 audio_load_wav
      assert($7100 == $07, "ULTIMATE_ERR_DEVICE: FILE DOESN'T EXIST")
    }
```

- [ ] **Step 5: Regenerate, and run every test**

Run: `make protocol && make unittest 2>&1 | tail -3 && grep -n 'BLOB_AUDIO_LOAD_WAV' bindings/kickass/uci_protocol.asm && make -C tests/emulator run 2>&1 | grep -E 'load-wav|passed|failed|FAIL' | head -20`
Expected: unittest `OK` (the blob-table tests included); `.label BLOB_AUDIO_LOAD_WAV       = $0300`; `blob-audio-load-wav-missing-file` passes; every suite passes.

- [ ] **Step 6: Commit**

```bash
git add bindings/cc65/ultimate_cc65.s bindings/blob/blob.cfg.in bindings/blob/blob.s bindings/blob/README.md \
        tools/test_blob_table.py tests/emulator/blob.suite \
        bindings/asm/uci_protocol.inc bindings/kickass/uci_protocol.asm bindings/acme/uci_protocol.a
git commit -m "feat(bindings): audio_load_wav for C and the blob, in an extension table at +\$300

The parameter block was full, so a third jump table starts the code
area; it grows without moving a published offset. The cc65 wrapper
unpacks name and REU address from the C stack.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01MWZot9Zonrj1xjkwu9tCpq"
```

---

### Task 8: Whole-tree verification

**Files:** none changed unless something fails.

- [ ] **Step 1: Everything the repo can check without hardware**

Run: `make test 2>&1 | tail -15`
Expected: `make unittest` reports `OK`; every emulator suite passes (protocol, sdk, sdk-placed, absent, timeout, abort-latency, blob, blob-relocated, and the wedge/basic suite).

- [ ] **Step 2: The hardware suite, once more**

Run: `make hardware-run U64_HOST=192.168.1.62 2>&1 | tail -20`
Expected: identical to Task 4 Step 4: the audio scenario passes and the same 10 pre-existing failures remain.

- [ ] **Step 3: What this plan leaves open**

Nothing in this plan plays a WAV through `ultimate_audio_load_wav` on hardware; the simulator has no REU load. The spec assigns that to the Boing migration in `2026-09-02-vsprite-multiplexer-design.md`, which loads the committed `boing.wav` at run time. That plan's hardware step is the end-to-end check for A4, and it should be the next thing done.
