# The UCI, complete, in assembly, C and BASIC

Design for making the whole Ultimate Command Interface reachable from every
toolchain a C64 programmer might use, in the smallest and most reusable form
that can be built.

Status: agreed in design. **Phases 1 and 2 are done** — the blob, and the BASIC
wedge in both its deliveries. **Phase 3 is under way**: `dos.s` is built and
tested, and the `$A000` move §8 predicted has happened.

Where this document and the code disagree, the code won and the section says so.
Two keyword names changed in §4 for reasons that only showed up once the ROM's
tokeniser was modelled instead of reasoned about.

---

## 1. The goal, and the rule that keeps it small

**A complete, parallel implementation of the UCI in assembly, C and BASIC.**
Complete means all 101 commands and all six targets, from all three languages.
Parallel means the same operation is the same call. Small means nobody links or
loads a byte they do not use.

One rule does most of the work:

> **The complete surface is `uci_exec`. Everything else is sugar, and sugar
> earns its place only where the generic form cannot express the operation.**

`uci_exec(target, command, args, payload) -> data, status` reaches all 101
commands. It already exists, it is 1401 bytes, and it is tested. So completeness
is not a thing to build — it is a thing to expose. What remains is exposing it
everywhere, and adding convenience only where a caller genuinely cannot manage
without it.

That rule is what stops this growing into a wrapper per command, which is the
usual way an SDK like this becomes 12K.

## 2. What exists today

Measured, not estimated:

| | |
|---|---|
| `uci_core.s` transport | 1401 bytes code+rodata, 65 bytes RAM, 4 bytes zero page |
| `ultimate.s` service layer | 673 bytes, of which 168 is `strerror`'s string table |
| Tests | 75 across five suites, all passing |
| Placement | `UCI_ZP` and `UCI_VARS` already move every byte of RAM the SDK uses |

The transport is done. Bring-up, capability detection and identity are done.
Nothing below Layer 2 needs redesigning to support any of this.

## 3. Architecture

```
   BASIC              C                 assembly          any assembler
   UCI / ULOAD    ultimate_load()    jsr ultimate_load    jsr base+$0A
       |                |                    |                  |
       +--- wedge ------+                    |                  |
       |  tokens, PETSCII,                   |                  |
       |  FAC1, UERR/UST$                    |                  |
       +----------------+--------------------+------------------+
                                 |
                    Layer 2b  file.s   load / bload / save        pay per use
                    Layer 2a  dos.s    open read close chdir dir   pay per use
                    Layer 2   ultimate.s  init, detect, identify   pay per use
                                 |
                    Layer 1   uci_core.s  the transport            always
                                 |
                              $DF1B-$DF1F
```

Every layer is a separate object file. `ld65` eliminates unreferenced modules
without any build configuration, so a program that only calls `uci_exec` links
1401 bytes and nothing else. This is verified: a test program calling only
`uci_present` and `uci_exec_block` links to 1699 bytes total, with `ultimate.o`
absent from the map.

### Delivery: the blob is the product

Toolchains cannot link each other's objects. ca65 objects serve cc65 and cl65
only; KickAssembler, ACME, 64tass, Oscar64, llvm-mos and KickC each want
something else, and BASIC wants none of it. So the primary artifact is a
**binary with a jump table**, which every one of them can reach without linking
anything:

| Caller | How it calls in |
|---|---|
| ca65 / cc65 | link `ultimate.lib` for best codegen, **or** use the blob |
| KickAssembler, ACME, 64tass, DASM | `.import binary`, or load it; `jsr base+N` |
| Oscar64, llvm-mos, KickC | call an absolute address |
| BASIC, no wedge | `POKE` the parameter block, `SYS base+N` |
| BASIC, with wedge | `UCI 1,$04,8192` |

All of them execute the same bytes. There is no second implementation anywhere,
which is the property the whole SDK exists to protect.

### The blob loads anywhere

Built standalone at `$A000` and at `$A100` and diffed: 2074 bytes, **71 differ,
every one by exactly +1**. So relocation is a 71-entry table. With a ~40 byte
relocator that is roughly **150 bytes for load-anywhere**, which removes any
argument about what the SDK's "official" address is.

### Blob layout

Fixed for ever. Entries are appended, never reordered or removed.

```
base+$000   "UCI" + version byte     identification and compatibility check
base+$004   jmp uci_init             jump table. Phase 1 fills the transport
base+$007   jmp uci_exec_block       entries; later phases append, never reorder
base+$00A   jmp uci_abort
   ...     (ultimate_load / bload / save appended in phase 3)

base+$100   parameter block          page-aligned: BASIC POKE arithmetic is trivial
            +$00  result             ULTIMATE_* code
            +$01  device code (word) 85, 404, ...
            +$03  address (word)
            +$05  length (word)
            +$07  end address (word)
            +$09  status string       32 bytes
            +$29  filename buffer     40 bytes
            +$51  reply buffer       256 bytes
```

The jump table grows only at the end. A program built against version 1 keeps
working against version 5, which is what makes the blob safe to ship separately
from the programs that call it — the version byte is there so a program can
refuse politely rather than jump into the wrong entry.

**The reply buffer is 256 bytes**, which sizes `UBYTE(n)` exactly and covers what
the generic form is for: directory entries, paths, identification strings,
status. A reply larger than that sets `UERR` to `ULTIMATE_ERR_TRUNCATED` (8) —
the transport already reports this and already drains the rest cleanly, so the
interface is never left mid-transfer. Bulk transfers are what `ULOAD` and
`UBLOAD` exist for; they write to an address the caller names and never pass
through this buffer.

The page-aligned parameter block is what makes the SDK usable from BASIC with no
wedge installed at all — `POKE UCI+256+n, v` needs no address arithmetic.

Addresses for the jump table and the per-assembler constant includes are
**generated**, not hand-copied: `gen_protocol.py` gains emitters for the
assembler syntaxes, and the entry addresses come out of the ca65 link map by the
same awk filter that already produces `tests/emulator/harness.sym`. Both
mechanisms exist and are tested.

## 4. The BASIC wedge

### Two builds, one source

| | `.prg` | `.crt` |
|---|---|---|
| how it starts | `LOAD "UCI",8` then `RUN` | power on, nothing to type |
| BASIC RAM | 38911 bytes | 30719 bytes — the cartridge holds `$8000-$9FFF` |
| survives reset | no | yes |
| room | 4K at `$C000` for the wedge, 8K at `$A000` for the SDK | 8K of ROM, all three phases fit |

The cartridge is the `.prg` payload plus a `CBM80` signature and a cold-start
vector. Both are built from the same source.

**Cartridge and command interface coexist** — this is not an assumption.
`software/6502/cmd_test_rom.tas` in the firmware tree is an 8K autostart
cartridge at `$8000` that adds a BASIC command driving `$DF1C-$DF1F`: the same
architecture, from the firmware author.

That file is GPL-3.0, as is the whole firmware repository, and this SDK is MIT.
**Nothing is copied from it.** It is read for interface facts — command codes,
wire formats, the `LOAD_SU`/`LOAD_EX` sequence — the same way `handover.md` §8
already directs. Copying source would relicense the SDK and take away the thing
it exists for: a demo author linking the transport into a cartridge they sell.

### Installation

```
LOAD "UCI",8
RUN

ULTIMATE UCI BASIC WEDGE INSTALLED.
VIVA LA COMMODORE!
READY.
```

The `.prg` loads at `$0801` and contains exactly one BASIC line, `10 SYS 2061`,
followed by the installer. `RUN` reaches the installer, which:

1. copies the wedge and the SDK to `$C000`
2. installs `ICRNCH`, `IQPLOP`, `IGONE` and `IEVAL`
3. prints the banner through `CHROUT`
4. performs a `NEW`, so `$0801` is empty again
5. jumps to BASIC's warm start rather than returning, landing at `READY.`

The installer sits above `$080D` and survives its own `NEW` — `NEW` resets
pointers, it does not clear RAM — and by the time the user types over it the
wedge has already been copied out.

The `NEW` and warm-start entry points are pinned against a ROM map during
implementation. They are not quoted from memory here, and the BASIC test suite
asserts the *outcome* — `$0801` empty, vectors installed, banner on screen —
rather than trusting the addresses.

### Why `$C000` and not `$A000` under BASIC ROM

Both are free to a BASIC programmer, so the cost is identical and simplicity
decides. `IGONE` is called *by BASIC ROM*; a handler at `$A000` is unreachable
at that moment, so `$A000` needs a RAM trampoline per hook, `$01` juggling
around every call, and banking discipline inside code that must call ROM
routines to parse its own arguments. `$C000` needs none of that.

The estimate in §8 says phase 3 pushes the total just past 4K, at which point
the **SDK alone** moves to `$A000` and the wedge keeps the block. That is a
different proposition from putting the hooks there: the SDK is never called by
BASIC ROM, so it needs one shared trampoline rather than banking discipline
throughout. Relocation makes it a link-time choice.

**Done, in Phase 3.** `src/basic/bank.s` is the trampoline - twelve bytes per
entry point rather than one shared stub, because the argument and the result
both live in `A` and a shared one would need the target address somewhere else.
`ca65 -D UCI_BANKED` puts the SDK's code in a `UCICODE` segment (see
`src/uci/uci_seg.inc`), the wedge links a second flavour of the library built
with it, and both the `.prg` and the cartridge run it at `$A000`. The wedge
went from 3581 bytes of the 4K to 2078, and the SDK has 6597 free where it now
lives.

### The keyword set

Token space is `$CC`–`$FE` with `$FF` reserved for pi: **51 slots for 101
commands.** One keyword per command was never arithmetically possible, which is
why completeness comes from the generic form and keywords are ergonomics.

**Statements**

| | |
|---|---|
| `UCI t, c [, arg …]` | execute any command on any target |
| `UCI` | no arguments: abort anything pending, print the data and status left behind |
| `ULOAD name$ [, addr]` | PRG load; header address unless one is given, header always stripped |
| `UBLOAD name$, addr` | raw bytes, nothing interpreted |
| `USAVE name$, start, len` | memory to file |
| `UDIR [path$]` | print the current directory, or `path$`, to the screen |

**Functions**

| | |
|---|---|
| `UCI(t, c [, arg …])` | executes and returns the reply length |
| `UERR` | `ULTIMATE_*` result code; 0 is OK |
| `UDEV` | raw device code: 85, 404 |
| `ULEN` | reply length in bytes |
| `UST$` | status string as sent: `"00,OK"` |
| `UDAT$` | reply as a string, clipped to 255 |
| `UBYTE(n)` | byte *n* of the reply |
| `UW(x)`, `UL(x)` | force a 16- or 32-bit argument |

**Two of these names changed once CRUNCH was modelled rather than reasoned
about.** Both were found by `tools/c64_crunch.py`, which reimplements the ROM's
tokeniser, and both are enforced by `gen_keywords.py` so the next new keyword
cannot reintroduce them:

- **`UDATA$` was impossible.** CRUNCH matches a reserved word anywhere, not only
  at a word boundary, so it crunches to `U` `[DATA]` `$` — and the `DATA` token
  arms verbatim mode, which stops the rest of the statement being tokenised.
  `A$=UDATA$+"X"` would reach the interpreter with `+"X"` as raw text. `UDAT$`
  crunches clean.
- **`W(` and `L(` could not be bare letters.** A keyword matching anywhere means
  claiming `W` tokenises the `W` in `FOR W=1 TO 10`, breaking every program that
  uses it as a variable. They take the `U` prefix like everything else and their
  opening paren into the name, exactly as the ROM's own `TAB(` and `SPC(` do,
  which keeps `UW` and `UL` usable as ordinary variables.

`ULEN`, and Phase 3's `ULOAD`, `UBLOAD` and `USAVE`, are fine but are *not* the
text the user typed by the time the wedge sees them: they contain `LEN`, `LOAD`
and `SAVE`, so they arrive as token sequences. The wedge matches the crunched
form and `LIST` prints the name, which is why the generated table carries both.

`UCI` the statement and `UCI(…)` the function share one token: `IGONE` fires in
statement position and `IEVAL` in expression position, and the wedge owns both
hooks.

`UCI` with no arguments is a rescue hatch at the `READY` prompt: a command left
half-finished by a crashed program is aborted and whatever it left behind is
printed. The idea is taken from the arrow-left statement in Gideon's cartridge;
the code is our own. It costs no token, because a bare `UCI` has no other
meaning.

**`@` was considered as the statement character and rejected.** It costs no
token, but it only avoids the tokenizer if there are *no* keywords at all — keep
`UERR` and `UST$` and `ICRNCH`/`IQPLOP` are needed regardless, so it saves one
token out of 51 and nothing structural. Dropping all keywords to earn the saving
would mean `PEEK`ing the parameter block to find out what happened. And `@` is
the classic CBM DOS wedge prefix: taking it breaks a wedge many people have
resident. `UCI` collides with nothing.

The four sugar statements exist because a BASIC string cannot hold 16K, so
`ULOAD`, `UBLOAD` and `USAVE` are operations the generic form genuinely cannot
express. `UDIR` is a judgement call — five generic lines versus one keyword, for
the most-typed command at a prompt. It prints straight to the screen through
`CHROUT`, converting each entry from ASCII, and returns nothing; a program that
wants the entries as data uses `OPEN_DIR`/`READ_DIR` generically and reads them
through `UDATA$`.

### Arguments

**One numeric argument is one protocol byte, unless the command's argument shape
says otherwise.** The shapes are generated, so the natural thing works:

```basic
UCI 1,$04,8192            : REM READ_DATA, <len16>
UCI 1,$06,100000          : REM FILE_SEEK, <pos32>
UCI 1,$02,1,"GAME.PRG"    : REM OPEN_FILE, byte then string
UCI 1,$0A,"OLD","NEW"     : REM RENAME, the $00 separator is inserted
UCI 5,$99,UW(300),UL(1)   : REM a command the table has never heard of
```

`UW()` and `UL()` are not decoration: without them the generic form cannot
express a wide argument for a firmware command newer than the SDK's table, and
reaching everything is the entire point of having a generic form.

The alternative rule — under 256 is a byte, over is a word — silently sends one
byte for a length of 255 and two for 256. Rejected.

**The argument shapes had to become structured data. That is done** — `ARGS` in
`gen_protocol.py`, 67 commands, checked by `check_args()` at generation time and
by `tools/test_gen_protocol.py` under `make test`.

Each shape is a list of `(kind, spec)` pairs: `byte`, `word`, `dword`, `str`,
`pstr` (length-prefixed), `data` (trailing), `lit` (a fixed byte the caller does
not supply). NUL-separated strings turned out not to need a kind of their own —
`<old> $00 <new>` is `str`, `lit`, `str`, which is what the firmware actually
splits on.

Two rules are enforced rather than trusted, because breaking either produces
bytes that a target accepts and misreads: `str` carries no length, so it must be
last or immediately before a `lit`; `data` runs to the end, so nothing may
follow it.

**Every shape was read out of the firmware, not transcribed from the prose**,
and that caught two errors the prose had been carrying: `SOFTIEC_CMD_LOAD_SU`'s
filename starts two bytes later than it said, and `CTRL_CMD_EASYFLASH`'s base
address is one byte and not two. The prose comments are gone; the emitters
render the shape from `ARGS`, so the C header, the three assembler includes and
the reference cannot disagree about what a command takes.

**The in-memory table is generated too**, into `bindings/asm/uci_argtable.inc`.
It holds only the exceptions: a command earns an entry when its shape has a wide
numeric, a length-prefixed string, or a literal the caller never types. 21 of the
67 shaped commands do, and the other 46 cost the 6502 nothing — the default rule
already marshals them.

Entries are `target, command, count, packed kinds` with two kind nibbles to a
byte, ordered by target then command so a scan stops as soon as it passes what
it wants. **98 bytes assembled**, against the 150 budgeted here. Command codes
repeat across targets (`$04` is `DOS_CMD_READ_DATA` and `NET_CMD_GET_NETADDR`),
so the target is part of the key; DOS is one command set on two targets, so its
shapes are stored under `$01` and the lookup folds `$02` onto `$01` instead of
carrying a second copy.

Every literal in the protocol is `$00` today, so `lit0` is a kind and no byte is
spent on the value. A non-zero literal fails generation rather than truncating.

ca65 only. The wedge is the one consumer and every other toolchain reaches the
SDK through the blob, which will carry the table already assembled.

### Constants

BASIC V2 variable names are significant to **two characters only**, so
`UDOS1` and `UDOS2` collide as `UD`. Install-time variables cannot work.
Constants must be tokens, and the token budget decides how many:

```
51 free  -  5 statements  -  8 functions  =  38 for constants
```

- **Six targets now:** `UDOS1 UDOS2 UNET UCTRL UIEC UHTTP`. Every generic call
  begins with one.
- **Command constants ship with the service that wraps them.** DOS constants
  when `dos.s` lands, control constants with control. No token is spent on an
  HTTP body-builder call no BASIC programmer will hand-write.
- **~15 tokens held in reserve** so future named commands are not locked out.

A generated one-page BASIC reference covers the tail that stays hex, so nobody
has to read the C header to find a command code.

### Errors

Status variables, never a BASIC error. A failed load must not drop a running
demo to `READY.`; the program decides what to do. This mirrors `DS`/`DS$` from
the CBM DOS wedges the audience already knows.

```basic
10 ULOAD "PART2.PRG", $4000
20 IF UERR = 0 THEN SYS $4000
30 PRINT "CANT LOAD PART 2: "; UST$
```

### One table, not three

Tokenizing, `LIST` detokenizing and dispatch all walk a **single** table of
`name, handler` — the example implementation we looked at kept three parallel
tables that can drift. `gen_protocol.py` emits it, so the wedge's table, the
build-time tokenizer and the documentation share one source.

## 5. The service layer

### Primitives — `dos.s`

`chdir`, `getpath`, `opendir`, `readdir`, `open`, `read`, `close`, then the
writes. All read-only ones are simulated by `u64sim`, so they are testable in CI
from the first commit.

### Convenience — `file.s`

```c
uint8_t  ultimate_load (const char *name, uint16_t addr);              /* 0 = use header */
uint8_t  ultimate_bload(const char *name, uint16_t addr, uint16_t max);
uint8_t  ultimate_save (const char *name, uint16_t start, uint16_t len);
uint16_t ultimate_last_end(void);
```

Identical from assembly, and the thing `ULOAD` compiles down to.

### Two tiers, because one of them is much faster

```
ultimate_load()
   |- SoftwareIEC usable?  -> LOAD_SU + LOAD_EX   firmware DMAs into C64 RAM
   `- otherwise            -> DOS OPEN/READ/CLOSE  queue reads
```

Read out of the firmware, not inferred from constant names:

- `UCI_CTRL_DMA` (`$80`) and `UCI_CTRL_TRIGGER` (`$40`) do **not** accelerate
  transfers. In `fpga/io/command_interface/vhdl_source/command_protocol.vhd:152`
  both latch into `freeze_i` — the freezer line. `TRIGGER` is the classic
  "freeze on the next `$FF00` write". **The comment in `uci_protocol.inc` calling
  these "DMA mode" is misleading and must be corrected**, or the next person
  reaches for them expecting speed.
- The real fast path is `SOFTIEC_CMD_LOAD_SU` then `LOAD_EX` on target `$05`.
  `software/6502/unsorted/uci_wedge.s` is Gideon's own fast LOAD and it pushes
  with a plain `$01` — **no DMA bit**. Data never passes through `$DF1E`; the
  firmware writes straight into C64 RAM and returns the end address in status
  bytes 1–2, which the SDK's four-byte status capture already keeps.
- `LOAD_SU` takes `<sec> <verify> <addr16> <unused16> <name>`, where the
  secondary address is the same 0-or-1 that `LOAD"X",8,1` uses. So `ULOAD "X"`
  is `sec=1` and `ULOAD "X",$4000` is `sec=0, addr=$4000`. The semantics we
  chose are the firmware's own; nothing is invented.

  **The `<unused16>` is not padding we chose to add.** This line said
  `<sec> <verify> <addr16> <name>` until the argument table was built and every
  shape was read out of the firmware rather than transcribed. `cmd_load_su()`
  opens `&command->message[8]`: a load shares `SAVE`'s layout and has to send
  the end-address pair it never reads. Sending the name at offset 6 is accepted
  and then opens whatever the tail happens to be, so it would have surfaced as
  "file not found" on a file that is plainly there — during Phase 3, on the one
  path that has to be tested on real hardware. `tools/test_gen_protocol.py`
  now pins the offset.

**Fallback triggers on the first command failing, not on detection.** Target
`$05` reports present even when the IEC drive is switched off, and
[#794](https://github.com/GideonZ/1541ultimate/issues/794) settles that this is
intended and permanent: disabling the drive removes it from the IEC bus, not
from UCI, which is the path the hyperspeed kernal itself uses.

Two consequences for this phase, both good. **The fast load path does not
require the user to enable the IEC drive** — `LOAD_SU`/`LOAD_EX` are reachable
either way, so `ULOAD` has no setting to talk the user through. And detection
still cannot tell you a *file* is loadable, which is why the fallback hangs off
the command failing.

### The services that do not go through `uci_exec`

There are exactly two, and the test that admits them is the same one:
**does the operation exist on the UCI at all?** If it does, a service uses
`uci_exec` and nothing else. If it does not exist there — if the only way to
reach it is a memory-mapped register — then the rule about not reimplementing
the transport has nothing to bite on, because there is no transport involved.

**This is a deliberate and closed list, not the rule eroding.** It is written
down so that a future service author does not read it as permission. Adding to
it means showing that `docs/generated/protocol-constants.md` has no command for
the job.

#### `turbo.s` — CPU speed (built)

The control target's full command set is generated into
`docs/generated/protocol-constants.md` and nothing in it touches CPU speed.
Turbo is `$D031`: bits 0-3 a speed index into the machine's own table, bit 7
badlines off. `$D030` bit 0 belongs to the machine's other turbo mode and the
SDK does not use it.

```c
uint8_t ultimate_turbo_available(void);          /* 1 or 0 */
uint8_t ultimate_turbo_get(void);                /* index, or $FF */
uint8_t ultimate_turbo_set(uint8_t index);
uint8_t ultimate_turbo_badlines(uint8_t on);
```

```basic
UTURBO 3 : IF UERR THEN PRINT "no turbo here"
PRINT UTURBO
```

Two things shape the API and are not negotiable. **The register reads `$FF`
when turbo is unavailable**, which makes availability testable rather than
assumed — and unavailable is the common case, because it depends on a setting
only the machine's owner can change. **The index above `U64_SPEED_4MHZ` means
different speeds on the U64 and the U64-II**, so the SDK passes the index
through and never pretends to know megahertz.

#### `reu.s` — RAM to REU (Phase 3)

There is no UCI command that moves bytes between C64 RAM and the REU. That is
the REU's own DMA controller at `$DF00-$DF0A`, and the C64 drives it directly.

```c
uint8_t ultimate_reu_stash (uint16_t c64, uint16_t reu, uint8_t bank, uint16_t len);
uint8_t ultimate_reu_fetch (uint16_t c64, uint16_t reu, uint8_t bank, uint16_t len);
uint8_t ultimate_reu_swap  (uint16_t c64, uint16_t reu, uint8_t bank, uint16_t len);
uint8_t ultimate_reu_verify(uint16_t c64, uint16_t reu, uint8_t bank, uint16_t len);
uint8_t ultimate_reu_present(void);
```

```basic
USTASH $4000, 0, 0, 8192
UFETCH $4000, 0, 0, 8192
IF UREU = 0 THEN PRINT "NO REU" : END
```

Address and bank are split rather than passed as a 32-bit REU address: that is
how the hardware registers are laid out, and it keeps cc65 from pulling in
32-bit arithmetic for something stored as word-plus-byte. `swap` and `verify`
are the same routine with a different command byte — `$92` and `$93` against
`$90` stash and `$91` fetch — and `verify` earns its place letting a loader
check a bank arrived intact.

Four behaviours that are documented rather than discovered:

- **A length of `0` means 65536 bytes** to the hardware. A caller passing zero
  almost certainly has a bug, so it is rejected as
  `ULTIMATE_ERR_INVALID_ARGUMENT`, consistent with how `uci_exec` validates.
- **The REU sees the bus as currently banked.** Stashing `$A000-$BFFF` with
  BASIC ROM in stashes ROM, not the RAM beneath. This matters to the SDK
  directly, because the `.prg` build may place the SDK at `$A000`.
- **Detection is non-destructive only.** Write a pattern to `$DF02-$DF05` and
  read it back; unimplemented registers return `$FF` (`compatibility.md:61`).
  Sizing an REU requires writing across banks and watching for wrap, which is
  destructive, so it is deliberately absent.
- **Transfers execute immediately.** Command bit 4 set disables the `$FF00`
  trigger; `$90`/`$91` include it. A caller wanting `$FF00`-synchronised
  transfer programs the registers itself.

`u64sim` does not model an REU, so this module is hardware-only coverage — the
same bucket as the SoftwareIEC fast path. `hwtest.py` already has the
`uci-with-reu` scenario and already toggles the setting, and the SDK touching
only `$DF00-$DF0A` here is exactly what that scenario exists to prove.

### The REU is a feature, not plumbing

`DOS_CMD_LOAD_REU` and `SAVE_REU` move a file directly between USB and REU
memory — it never passes through C64 RAM. For a demo that is megabytes of assets
streamed off USB with the C64 uninvolved, which is the single most useful thing
the SDK can hand a demo author. Wrapped in `file.s`, with a BASIC keyword, in
phase 3.

**Paging SDK code through the REU was considered and rejected.** It would make
the core depend on optional hardware — `CTRL_CMD_LOAD_REU` answers
`84,REU NOT ENABLED` when there is none, and `u64sim` does not model an REU at
all, so a core mechanism would sit where no CI test can reach it. It also solves
a shortage that does not exist: `$A000` and the cartridge each give 8K against
~4.1K of need. A pager belongs in a demo author's own loader, and the SDK's job
is to make that loader three lines long.

## 6. Character sets

**Services convert; the transport does not.**

The Ultimate speaks ASCII. BASIC strings are PETSCII, and so are cc65 and ca65
string literals — `ca65 -t c64` installs the c64 charmap, which is why
`ultimate_strerror` returns `$CF $CB` for "OK". So every high-level caller
naturally produces PETSCII, and the convenience layer takes PETSCII and converts
on the way out, and converts directory entries and status strings on the way
back.

That single rule is why the same literal works unchanged from BASIC, C and
assembly. Callers wanting raw bytes still have `uci_exec`, unchanged.

## 7. Testing

Every layer gets the same treatment the transport already has.

| Suite | Backend | Covers |
|---|---|---|
| `protocol.suite` | `u64sim` + real hardware | firmware behaviours the SDK depends on |
| `sdk.suite` | `u64sim` | transport, services, status decoding |
| `sdk-placed.suite` | `u64sim` | the same with SDK RAM relocated |
| `timeout.suite` | `u64sim`, latency raised | bounded time |
| `absent.suite` | `sim`, nothing at `$DF1B` | failing fast with no Ultimate |
| `basic.suite` | `u64sim` + C64 ROMs | **new** — the wedge |
| `tests/hardware` | a real Ultimate | firmware reality, and the fast path |

### The BASIC suite

`sim6502` supports `rom("basic", …)` and `rom("kernal", …)` for `system(c64)`,
so real BASIC ROM and a simulated Ultimate coexist in one suite. That makes the
wedge's three jobs testable without a human:

```
; tokenize: text into the input buffer, through BASIC's own CRUNCH,
; which calls our ICRNCH hook on the way
[$0200] = $55                   ; "U"
[$0201] = $4c                   ; "L" ...
jsr($a579, stop_on_rts = true, fail_on_brk = true)
assert([$0200] == $cc, "ULOAD tokenized")
```

Detokenizing is asserted through the `IQPLOP` path and execution by setting the
text pointer and calling the handler.

**ROM-gated.** C64 ROM images cannot be committed, so the suite runs when
`C64_ROMS` points at them and skips with a message naming the fix otherwise —
the same pattern `hardware-run` uses for `U64_HOST`. CI runs the other suites.

### The hardware layer

`hwtest.py` already POSTs a `.prg` to `/runners:run_prg` and reads results back
by DMA from `$033C`. `basictest.prg` uses that rig unchanged: it is **the
shipping wedge with a tokenized BASIC test program appended**, so what is tested
is what is shipped. `decode_screen` also lets the suite assert the banner
actually printed, so the install path is covered and not just the commands.

The SoftwareIEC fast path lives here permanently — `u64sim` does not implement
target `$05`. This settles `handover.md` §6: **accept hardware-only coverage for
what the simulator cannot reach, and make `make hardware-run` required before a
release rather than optional.**

### Test data policy

Every mutating test creates its own file, uses it, and deletes it. Nothing
pre-existing on the device is ever touched. This collapses the four risk tags in
`handover.md` §5 into two that matter: `mutating` is safe by default because it
only touches what it made, and `destructive` shrinks to the genuinely
irreversible — reboot, flash, palette — which stays opt-in.

### Build-time tokenizer

Building the tokenized BASIC test needs a text-to-tokens converter that knows
our tokens. It reads the same generated table the wedge uses. It also lets `.bas`
sources live in the repo and build into runnable `.prg`s, so the BASIC examples
are built and tested rather than pasted into a README and left to rot.

## 8. Footprint

| | |
|---|---|
| transport, all 101 commands reachable | 1401 |
| wedge glue: one table, tokenize/LIST/dispatch, PETSCII, installer, banner | ~500 |
| observers `UERR UDEV ULEN UST$ UDATA$ UBYTE` | ~200 |
| argument shape table, ~25 commands | ~150 |
| target constants | ~60 |
| parameter block, including the 256-byte reply buffer | ~340 |
| **phases 1–2: full UCI in BASIC** | **~2.65K of 4K** |
| phase 3: service layer, DOS, file convenience | ~1.45K |
| **all three phases** | **~4.1K — over by about 60 bytes** |

Network and HTTP need nothing added; the generic form already reaches them. But
phase 3 does not fit, and it is better to say so now than to discover it while
implementing.

There are two escapes, and both are cheap.

**The cartridge build has no problem at all.** 8K of ROM at `$8000` holds all
three phases with 4K spare, and costs no C64 RAM for code. Phase 3 fits there
today.

**The `.prg` build moves the SDK to `$A000`. This has now happened**, in both
builds rather than only the `.prg`: keeping one layout is what lets
`tools/test_make_crt.py` keep comparing the two deliveries byte for byte.

**The original note:** Transport plus services under
BASIC ROM, wedge left at `$C000`. The banking objection from §4 does not apply
here: it was about putting the *hook handlers* under ROM, where `IGONE` cannot
reach them. The SDK is never called by BASIC ROM and calls no BASIC routine, so
reaching it needs one shared ~12-byte trampoline flipping `$01` to `$36` around
a `jsr`, with KERNAL and I/O left banked in so interrupts are unaffected. That
buys 8K and leaves the whole 4K block to the wedge, for a dozen bytes and a few
cycles per call.

Because the blob relocates, both are link-time choices rather than redesigns.
Phases 1 and 2 ship at `$C000`; phase 3 flips the `.prg` build to `$A000` when
the measurement says it must, and changes nothing about the cartridge.

Housekeeping that pays for itself: `strerror` moves to its own module (168 bytes
of string table that every caller of `ultimate_init` currently drags in, and
which BASIC does not want because `UST$` carries the device's own status text),
and `ult_probe_target` moves into the shared variable block — `ultimate.s:388`
puts it in BSS unconditionally, so the `UCI_VARS` build still emits a BSS
segment and `asm-abi.md`'s "emits no BSS at all" is false today. The blob wants
zero BSS.

## 9. Phases

Completeness first, sugar second.

| | Deliverable | Unblocks |
|---|---|---|
| 1 | **Blob**: jump table, parameter block, relocation, generated per-assembler includes | the complete UCI from every toolchain, on the transport that already exists |
| 2 | **BASIC wedge**: generic `UCI`, observers, constants, installer, banner, `basic.suite`, both `.prg` and `.crt` builds | the complete UCI from BASIC, with no service layer needed |
| 3 | **DOS service + file convenience**, with the SoftwareIEC fast path, the UCI REU commands and `reu.s` | `ULOAD`/`UBLOAD`/`USAVE`/`UDIR`/`USTASH`/`UFETCH` in all three languages at once |

Phase 1 and 2 are one deliverable in practice — the wedge is the first real
consumer of the jump table, and building them together is what proves the table
is usable rather than merely defined.

## 10. Risks

- **The fast path cannot be tested in CI.** Target `$05` is hardware-only.
  Accepted deliberately, with `make hardware-run` promoted to required.
- **The BASIC suite needs ROMs that cannot be committed.** Gated, and the
  hardware layer covers the wedge unconditionally.
- **The 4K block does not hold all three phases of the `.prg` build** — the
  estimate is ~4.1K. Two escapes, both link-time: the cartridge build has 8K and
  no problem, and the `.prg` build moves the SDK alone to `$A000` behind one
  small trampoline. Sized in §8; measure again at the end of phase 2 rather than
  trusting the estimate.
- **The cartridge costs BASIC 8K of program space** — 38911 bytes down to
  30719, measured on the bench rather than estimated; this document said 10K
  until the cartridge was actually booted. That is the price of autostart and
  surviving a reset. Shipping both builds keeps it a choice rather than a tax.
- **The argument shape table can drift from firmware.** `UW()` and `UL()` are
  the escape, which is why they are not optional.
- **Structured argument shapes are real work** across ~50 commands, and were on
  the critical path for phase 2. Done: `ARGS` in `gen_protocol.py`.
- **The firmware repository is GPL-3.0 and this SDK is MIT.** It is a reference
  for interface facts and nothing else. No source is copied from it, in any
  phase — doing so would relicense the SDK and remove the reason a game or demo
  author can link it into something they sell.
