# Assembly ABI

Everything an assembly program needs to call the SDK.

## What it needs from you

**Nothing.** The core and the service layer are 6502 assembly. They use four
bytes of zero page, `UCI_VARS_SIZE` bytes of RAM, the 6502 stack, and nothing
else — no C runtime, no software stack, no start-up code, no initialised data.

That is a tested property, not a promise: `sdk-assembly-abi` in
`tests/emulator/sdk.suite` nulls cc65's software stack pointer before calling
`ultimate_init`, `uci_exec`, `ultimate_identify` and `ultimate_get_model`, so
anything reaching for it would write through a null pointer into the 6510's port
registers rather than working by accident.

The usual link is still `cl65`, because it is what assembles this and links the
library:

```
cl65 -t c64 --asm-include-dir path/to/bindings/asm \
     myprog.s path/to/ultimate.lib -o myprog.prg
```

with `.forceimport __STARTUP__` and an entry point called `_main` if you want
cc65's start-up to run — but that is a convenience, not a requirement. A
cartridge image or a custom loader can `jsr ultimate_init` with no start-up at
all.

The one place a C runtime does appear is the C API. `ultimate_identify()`,
`ultimate_get_model()` and `uci_decode_status()` take more arguments than fit in
registers, so their `_`-prefixed C entry points in `bindings/cc65` unpack
cc65's software stack. Assembly callers use the unprefixed names and the
variable block instead, and never touch it.

## Placing the SDK's memory

Every address the core touches is the caller's choice. This matters most for
cartridge projects, where the code is in ROM and which RAM it may use is the
programmer's decision, not a library's — but it is equally the answer for a
custom linker script, or an assembler with no segment support at all.

| Knob | Default | What it places |
|---|---|---|
| `UCI_ZP` | `$FB` | `UCI_ZP_SIZE` (4) bytes of zero page |
| `UCI_VARS` | undefined — the BSS segment | `UCI_VARS_SIZE` (88) bytes of variables |
| the request block | — | not a knob: `uci_exec` takes it by pointer |

```
ca65 -D UCI_VARS=$CF00 -D UCI_ZP=$A3 uci_core.s
```

**With `UCI_VARS` defined the core emits no BSS at all** — every variable
becomes an equate off that address, so there is nothing left for a linker to
place and nothing that needs clearing at start-up. Without it, the variables go
to the BSS segment, which is what a `cl65` link expects and what almost every
program wants.

`UCI_ZP_SIZE` and `UCI_VARS_SIZE` come from `uci_protocol.inc`, so you can
reserve the space without hard-coding a number that might change:

```asm
        .include "uci_protocol.inc"

sdk_vars:   .res UCI_VARS_SIZE
```

The core asserts at assembly time that its own layout still matches
`UCI_VARS_SIZE`, so the two cannot drift apart quietly.

A request block needs no knob at all. `uci_exec` takes a pointer in A/X, so put
the block wherever suits you and pass it:

```asm
        lda #<my_request
        ldx #>my_request
        jsr uci_exec
```

`uci_req` and `uci_exec_block` in `bindings/asm` are a convenience for programs
that only need one; a cartridge is free to ignore them.

This is a tested property, not a documented intention. `tests/emulator` builds
the harness twice — once normally, once with `UCI_VARS=$CF00` and `UCI_ZP=$A3` —
and runs the same suite against both.

## Getting the includes

```asm
        .include "ultimate.inc"
```

`bindings/asm/ultimate.inc` pulls in `uci_protocol.inc`, which is generated from
the same source as the C header — so the register map, target IDs, command codes
and error codes cannot drift between the two. Put `bindings/asm` on ca65's
include path (`--asm-include-dir`, or `-I` if you invoke `ca65` directly).

## Register contract

| | |
|---|---|
| Arguments | in `A`, or in the request block |
| Return | result code in `A` |
| Clobbers | `A`, `X`, `Y`, processor flags |
| Zero page | `UCI_ZP_SIZE` (4) bytes at `UCI_ZP`, which defaults to `$FB`. Nothing else. |
| Stack | shallow: a handful of nested `jsr`s, no recursion, no deep call chains |
| Interrupts | none required, none installed, safe to call with interrupts disabled |

`$FB-$FE` is free on a stock C64 and cc65's runtime does not allocate it, which
is why it is the default — but it is the SDK's while the SDK is linked in. If
your program wants those four bytes, move the SDK's with `UCI_ZP` rather than
sharing them.

## Entry points

| Symbol | In | Out |
|---|---|---|
| `ultimate_init` | — | `A` = `ULTIMATE_OK` or an error code |
| `ultimate_available` | — | `A` = 1 when the SDK is up |
| `ultimate_identify` | `A` = target, `ult_buf`, `ult_buflen`, `ult_outlen` | `A` = result code |
| `ultimate_get_model` | `ult_buf`, `ult_buflen`, `ult_outlen` | `A` = result code |
| `ultimate_detect` | `A`/`X` = pointer to a 4-byte capability block | `A` = result code |
| `ultimate_strerror` | `A` = result code | `A`/`X` = pointer to the text, in PETSCII |
| `uci_present` | — | `A` = 1 when the signature is on the bus |
| `uci_ident` | — | `A` = the raw identification register |
| `uci_req_clear` | — | zeroes the request block |
| `uci_exec_block` | the request block | `A` = result code |
| `uci_exec` | `A`/`X` = pointer to a request block | `A` = result code |
| `uci_abort` | — | `A` = result code |
| `uci_set_timeout_a` | `A` = budget, 0 = forever | — |
| `uci_get_timeout_a` | — | `A` = current budget |
| `uci_last_code` | — | `A` = low, `X` = high of the raw device code |

## The request block

`uci_req` is `UCI_REQ_SIZE` (22) bytes, exported by the SDK — in BSS by
default, or an equate off `UCI_VARS` when that is defined (see "Placing the
SDK's memory" above). Fill it in, call `uci_exec_block`, read the results back
out.

| Offset | Constant | Size | Meaning |
|---|---|---|---|
| 0 | `UCI_REQ_TARGET` | byte | target id, optionally `| UCI_TARGET_NO_REPLY` |
| 1 | `UCI_REQ_COMMAND` | byte | command code |
| 2 | `UCI_REQ_ARGS` | word | pointer to argument bytes, 0 for none |
| 4 | `UCI_REQ_ARGLEN` | word | number of argument bytes |
| 6 | `UCI_REQ_PAYLOAD` | word | pointer to payload bytes, 0 for none |
| 8 | `UCI_REQ_PAYLOADLEN` | word | number of payload bytes |
| 10 | `UCI_REQ_DATA` | word | buffer for the reply, 0 to discard it |
| 12 | `UCI_REQ_DATAMAX` | word | size of that buffer |
| 14 | `UCI_REQ_DATALEN` | word | out: reply bytes stored |
| 16 | `UCI_REQ_STATUS` | word | buffer for the status string, 0 to discard |
| 18 | `UCI_REQ_STATUSMAX` | word | size of that buffer |
| 20 | `UCI_REQ_STATUSLEN` | word | out: status bytes stored |

The command placed on the wire is `<target> <command> <args> <payload>`. Two
spans rather than one so a block write can send a fixed header and a large body
without copying them together.

These offsets are asserted against the C struct at build time in
`bindings/cc65/abi_assert.c`. If the struct ever changes shape the build fails
naming the field that moved, rather than your program writing into the wrong one.

## A complete call

```asm
        .include "ultimate.inc"

        .forceimport __STARTUP__
        .export _main

REPLY_MAX = 64

        .bss
reply:  .res REPLY_MAX

        .code
_main:
        jsr ultimate_init
        cmp #ULTIMATE_OK
        bne no_ultimate

        jsr uci_req_clear

        lda #UCI_TARGET_DOS1
        sta uci_req + UCI_REQ_TARGET
        lda #UCI_CMD_IDENTIFY
        sta uci_req + UCI_REQ_COMMAND

        lda #<reply
        sta uci_req + UCI_REQ_DATA
        lda #>reply
        sta uci_req + UCI_REQ_DATA + 1
        lda #<REPLY_MAX
        sta uci_req + UCI_REQ_DATAMAX
        lda #>REPLY_MAX
        sta uci_req + UCI_REQ_DATAMAX + 1

        jsr uci_exec_block
        cmp #ULTIMATE_OK
        bne failed

        ; reply now holds the identification string,
        ; uci_req + UCI_REQ_DATALEN holds its length
        rts
```

`examples/asm/identify.s` is this program with the printing filled in.

## Result codes

The `ULTIMATE_*` values from `uci_protocol.inc`. `ULTIMATE_OK` is zero, so
`cmp #ULTIMATE_OK` / `bne` reads naturally and `tax` / `bne` works if you prefer.

## Character sets

The Ultimate speaks ASCII. Target identification strings are uppercase, and the
C64's default character set prints uppercase ASCII unchanged, so those can go
straight to `CHROUT`.

The model name from `CTRL_CMD_GET_HWINFO` cannot: it is mixed case
(`Ultimate 64 Elite`), and lowercase ASCII renders as graphics glyphs. Fold it to
upper case, or convert properly, before printing. Anything else containing
lowercase needs the same treatment.

**`ca65 -t c64` installs the c64 character map**, which turns every string
literal into PETSCII: `.byte "OK"` assembles to `$CF $CB`, not `$4F $4B`. That is
right for text you print and wrong for anything you compare against the Ultimate,
so the SDK draws the line explicitly — display strings are literals, and every
byte that touches the wire is emitted numerically or generated by
`tools/gen_protocol.py`. `ult_no_target` in `src/uci/ultimate.s` is the example
to copy. The bug this prevents is described in
[api-design.md](api-design.md#protocol-bytes-are-never-string-literals).

The consequence for callers: `ultimate_strerror` returns PETSCII, ready for
`CHROUT`. Do not compare its result against an ASCII literal.

## Assemblers other than ca65

ca65 links the library directly. Every other assembler uses the standalone
binary in [bindings/blob](../bindings/blob), which has a jump table at its base
and needs no linking at all — see [its README](../bindings/blob/README.md).

Protocol constants are generated for ca65, KickAssembler and ACME from the same
source, so they cannot drift: `bindings/asm/uci_protocol.inc`,
`bindings/kickass/uci_protocol.asm`, `bindings/acme/uci_protocol.a`. Adding a
fourth format is a page of Python in `tools/gen_protocol.py`.
