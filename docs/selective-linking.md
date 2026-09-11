# Link only the SDK services you use

For cc65 C and ca65 assembly, use `ultimate.lib` normally. The linker selects
referenced archive members and their dependencies automatically. There is no
feature switch, per-service library, or special dead-code flag to enable.
Including `ultimate.h` or `ultimate.inc` does not include the whole SDK.

Selection is **per object/service, not per function**. Calling one turbo
function brings in `turbo.o`, including the other turbo functions. Services
that use the command interface also need shared transport and state. The
standalone blob remains a complete SDK; the BASIC wedge retains its compiled
command set, regardless of what a BASIC program calls.

All commands below run from the repository root, with cc65 on your PATH.

## C: a complete small program

[guide/examples/selective.c](../guide/examples/selective.c):

```c
#include <ultimate.h>

int main(void)
{
    unsigned char color = 2;
    if (ultimate_turbo_available())
        color = 5;
    *(volatile unsigned char *)0xd020 = color;
    return 0;
}
```

```sh
make lib
cl65 -t c64 -I include -c -o guide/examples/selective-c.o \
  guide/examples/selective.c
cl65 -t c64 -m guide/examples/selective-c.map \
  -o guide/examples/selective-c.prg guide/examples/selective-c.o \
  bindings/cc65/build/ultimate.lib
```

Result on the C64: the border becomes green when the turbo register is
available, red otherwise, and the program returns to BASIC. It prints no text
and does not change CPU speed. Copy the PRG to Ultimate storage and choose
Run, or load and run it using your usual PRG workflow.

This particular API reads a hardware register and needs no `ultimate_init()`.
Do not omit initialization from command-interface operations such as file or
palette access merely to shrink a map. Follow each API's initialization rules.

## Assembly: native ca65/ld65, no C runtime

[guide/examples/selective.s](../guide/examples/selective.s) performs the same
operation. It supplies its own BASIC stub instead of importing `__STARTUP__`:

```asm
.include "ultimate.inc"

.segment "LOADADDR"
    .word $0801
.segment "STARTUP"
    .word $080b, 10
    .byte $9e, "2304", 0  ; 10 SYS 2304
    .word 0

.code
.export start
start:
    jsr ultimate_turbo_available
    cmp #0
    beq absent
    lda #5                  ; green
    bne paint
absent:
    lda #2                  ; red
paint:
    sta $d020
    rts                     ; return to BASIC
```

Its complete linker configuration,
[guide/examples/selective.cfg](../guide/examples/selective.cfg):

```text
MEMORY {
    HEADER: start = $07ff, size = 2, file = %O;
    RAM: start = $0801, size = $37ff, file = %O;
}
SEGMENTS {
    LOADADDR: load = HEADER, type = ro;
    STARTUP: load = RAM, type = ro, start = $0801;
    CODE: load = RAM, type = ro, start = $0900;
    RODATA: load = RAM, type = ro, optional = yes;
    BSS: load = RAM, type = bss, optional = yes;
}
```

```sh
make lib
ca65 -t c64 -I bindings/asm -o guide/examples/selective.o \
  guide/examples/selective.s
ld65 -C guide/examples/selective.cfg -m guide/examples/selective-asm.map \
  -o guide/examples/selective-asm.prg guide/examples/selective.o \
  bindings/cc65/build/ultimate.lib
```

Result: the same green/red border, no printed text, then back to BASIC.
The first two file bytes are the PRG load address, not data loaded at `$07ff`.
The BASIC line loads at `$0801`; `SYS 2304` enters code at `$0900`. Keep the
stub and configuration in agreement if you change the entry address. Put your
object before the library in the link command. RAM is limited to below `$4000`
in this example; ld65 reports overflow if code or BSS outgrows it.

`RODATA` and `BSS` are optional because turbo uses neither. Other services may
need them. BSS reserves runtime RAM but is not stored in the PRG; without a
runtime, initialize your own variables explicitly. The SDK's initialization
requirements still apply. This is not a general replacement for a game's
VIC/REU memory layout: see the `.cfg` and Makefile in
[Boing](../demos/boing/) or [Follow Me](../demos/follow-me/) for those layouts.

## Read the map, not the archive's size

Open either `.map` file and find **Modules list**. Its only SDK member is:

```text
bindings/cc65/build/ultimate.lib(turbo.o):
```

The path prefix varies with the working directory. The C map also lists
`c64.lib(...)` members for startup and compiler helpers. That is C runtime
overhead, not extra SDK services. The native assembly map has only the
application object and `ultimate.lib(turbo.o)`; there is no `c64.lib`.

- **Modules list:** which objects were selected; each object's `CODE`,
  `RODATA`, and `BSS` sizes describe its contribution. `Offs` is an offset
  within a segment, not an absolute C64 address.
- **Segment list:** final memory addresses and combined sizes. In the native
  example, `CODE` starts at `$0900`.
- **Imports list:** which objects reference each linked symbol. If a service
  appears unexpectedly, follow the references here back to its caller.

For example, `ultimate_load()` needs the file and DOS modules plus transport
helpers; its C form also needs C adapters. Calling `ultimate_init()` adds
initialization/identity code. Shared dependencies are included once, not once
per call. Assembly uses unprefixed SDK entry points; C adapters are selected
only when referenced. Some simple APIs, including turbo, share one entry
implementation between C and assembly and need no separate adapter object.

The archive on disk still contains every service. Its size is not your PRG's
SDK footprint. Nor is PRG size alone a complete RAM measure: BSS is uninitialized
RAM, and fixed-layout PRGs can contain padding. Boing retains its fixed asset
addresses even though its SDK portion is smaller.

## Place SDK workspace safely

The usual library puts SDK variables in BSS and uses `$fb-$fe` as its four-byte
zero-page workspace. When your memory layout needs different locations, build
a separate archive with the same definitions applied to all SDK objects:

```sh
make -B -C bindings/cc65 BUILD=build-custom \
  ASM_DEFINES="-D UCI_VARS=52992 -D UCI_ZP=163"
cl65 -t c64 --asm-include-dir bindings/asm \
  -m guide/examples/hello-custom.map -o guide/examples/hello-custom.prg \
  guide/examples/hello.s bindings/cc65/build-custom/ultimate.lib
```

This builds the existing UCI startup example against SDK variables at `$cf00`
and zero page at `$a3`. Decimal values avoid shell expansion of `$CF00` and
`$A3`. `-B` deliberately rebuilds the archive: changing a Make variable does
not by itself invalidate existing object files. Keep a separate `BUILD`
directory per set of definitions and link the matching archive, not the
default one. Defining these values only while assembling your application
does not relocate an already-built SDK.

Reserve `UCI_VARS_SIZE` bytes at the chosen base (currently 191, so
`$cf00-$cfbe`) and `UCI_ZP_SIZE` bytes (4, so `$a3-$a6`). Fixed SDK variables
are equates, not linker-allocated BSS: the linker cannot catch overlaps with
your code, stack, sprites, or other buffers. This tiny hello program fits;
check the map and explicitly reserve these ranges in a larger application.
These settings move workspace, not SDK code. Your linker configuration places
`CODE` and `RODATA`. See [the assembly ABI](asm-abi.md#placing-the-sdks-memory).

## Keep it selective as your project grows

Link `ultimate.lib`, not a list of every SDK `.o` or the standalone blob.
Do not force-import unused services. References in retained application
objects or dispatch tables can keep services linked even if you never take
that runtime branch; this is not whole-program reachability analysis.

Existing example/demo Makefiles emit maps and recheck the SDK before linking.
Use them as templates. `make -C guide check-examples` builds both examples;
`python3 -m unittest discover -s tools -p test_link_modularity.py` verifies the
selected SDK module sets for both languages and the demos. These are build/link
checks, not evidence of execution on Ultimate hardware.

For real-machine verification, run `make -C guide hardware U64_HOST=<address>`.
It checks the standalone examples, both workspace layouts, and red/green
border results from the C/native assembly turbo examples with UCI disabled.
Run affected demo hardware checks too; see [the test guide](../tests/README.md#hardware-is-part-of-completion).
