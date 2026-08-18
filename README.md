# Ultimate SDK

**Files, networking, HTTP and hardware control from a Commodore 64, through the
Ultimate Command Interface — without implementing the protocol yourself.**

```c
#include <ultimate.h>

int main(void)
{
    ultimate_capabilities caps;

    if (ultimate_init() != ULTIMATE_OK)
        return 1;                       /* no Ultimate, or the UCI is switched off */

    ultimate_detect(&caps);
    if (ultimate_has_http(&caps)) {
        /* firmware 3.15 or newer: the HTTP client is available */
    }
    return 0;
}
```

---

## What is it?

Gideon Zweijtzer's Ultimate hardware exposes a command interface at
`$DF1B-$DF1F`: five registers, a four-state handshake, and a set of targets that
give a C64 program access to the SD card, the network stack, an HTTP client and
the machine's own configuration.

The protocol is documented, but every project that wants it has been
re-implementing the handshake, re-deriving the status codes, and re-discovering
the same handful of undocumented behaviours. This SDK implements it once, tests
it under an emulator and on real hardware, and exposes it to assembly and C.

**Status: early.** The transport, the error model and capability detection are
complete and tested — under a simulated Ultimate, and on a real Ultimate 64
Elite running firmware 3.15. So are the palette, turbo, file and REU services:
directories, open/read/write/seek, load and save, and both directions of the
RAM expansion. The network and HTTP services are next.

## What hardware does it support?

Everything from the 1541 Ultimate-II to the Commodore 64 Ultimate, on the same
code path:

| | |
|---|---|
| 1541 Ultimate-II, II+, II+L | yes |
| Ultimate 64, Elite, Elite-II | yes |
| Commodore 64 Ultimate | yes |

Nothing here needs a machine newer than a 1541 Ultimate-II. Newer machines and
newer firmware bring extra targets; those are found by probing, never assumed.

**The command interface is optional and off by default on some setups.** It is
switched on in the Ultimate's *Command Interface* configuration menu. Until it
is, an Ultimate looks exactly like no Ultimate, so tell your users:

```
no ultimate command interface.
enable it in the ultimate settings menu.
```

## What can I do with it?

| | |
|---|---|
| find the Ultimate, and ask what it can do | `ultimate_init`, `ultimate_detect` |
| files and directories | `chdir`, `getpath`, `opendir`, `readdir`, `open`, `close`, `read`, `write`, `seek`, `delete` |
| load and save | `load`, `bload`, `save` — the load takes the firmware's fast path when there is one |
| the RAM expansion | `reu_stash`, `reu_fetch`, and file-to-expansion without the C64 in between |
| the running palette | `palette_get`, `palette_set`, `palette_set_color`, `palette_reset` |
| CPU speed on an Ultimate 64 | `turbo_set`, `turbo_get`, `turbo_badlines` |
| anything else the firmware offers | the generic form: any command, on any target, with framing, timeouts and error translation handled |

Networking and HTTP have no wrappers yet. They are reachable today through the
generic form, which is the whole reason it exists.

## Getting started

```bash
make lib           # build bindings/cc65/build/ultimate.lib
make blob          # standalone binary with a jump table, for every other toolchain
make wedge         # the BASIC wedge: src/basic/uci.prg and uci.crt
make examples      # assembly and cc65 versions of the same program
make test          # the host unit tests, then the SDK against a simulated Ultimate
```

`make lib`, `make blob` and `make examples` need [cc65](https://cc65.github.io/).
`make test` needs cc65 and Docker; `make emulator` is the same thing under its
own name.

## From assembly

Assembly is a supported interface, not a side effect. Constants, a request block
at a fixed address, arguments in registers, results in `A`.

```asm
        .include "ultimate.inc"

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
        lda #<64
        sta uci_req + UCI_REQ_DATAMAX
        lda #>64
        sta uci_req + UCI_REQ_DATAMAX + 1

        jsr uci_exec_block          ; A = ULTIMATE_* result code
```

```bash
cl65 -t c64 --asm-include-dir bindings/asm myprog.s bindings/cc65/build/ultimate.lib -o myprog.prg
```

The core is 6502 assembly and needs nothing from a C runtime — no software
stack, no start-up code, no initialised data. Four bytes of zero page and
`UCI_VARS_SIZE` bytes of RAM, both at addresses you choose.
[docs/asm-abi.md](docs/asm-abi.md) is the contract.

Full example: [examples/asm/identify.s](examples/asm/identify.s).

## From cc65

```bash
make -C bindings/cc65
cl65 -t c64 -I include myprog.c bindings/cc65/build/ultimate.lib -o myprog.prg
```

```c
#include <ultimate.h>

char name[48];

if (ultimate_identify(UCI_TARGET_DOS1, name, sizeof(name), NULL) == ULTIMATE_OK)
    printf("%s\n", name);        /* ULTIMATE-II DOS V1.2 */
```

Full example: [examples/cc65/identify.c](examples/cc65/identify.c).

## From BASIC

`LOAD "UCI",8` then `RUN` installs a wedge that adds 22 keywords to BASIC V2 and
gives the whole 38K back. There is a cartridge build too, which survives a
reset and costs BASIC 8K while it is in.

```basic
ULOAD "/USB1/DATA/SPRITES.PRG",832 : IF UERR THEN PRINT "no file"
UDIR
USTASH 49152,0,4096 : UFETCH 49152,0,4096
UCI UDOS1,17,"/USB1" : PRINT UST$
```

`ULOAD`, `UBLOAD`, `USAVE`, `UDIR`, `USTASH` and `UFETCH` are the file and
expansion services; `UTURBO` is the CPU speed; `UCI` is the generic form, and
`UERR`, `UDEV`, `ULEN`, `UST$`, `UDAT$` and `UBYTE(` are how a program reads
what came back. Errors set `UERR` instead of stopping the program, because a
demo dropping to `READY.` in the middle of a part is worse than a load that
quietly did nothing.

The full table, with every token value, is in
[docs/generated/basic-keywords.md](docs/generated/basic-keywords.md).

## From KickAssembler, ACME, 64tass, Oscar64, llvm-mos, KickC

Through the standalone blob, which needs no linking at all. It is the same SDK
— the same object files — linked at a base address you choose, with a jump table
at its first bytes and a page-aligned parameter block behind it.

```asm
        // KickAssembler, with the blob loaded at $8000. The name goes in the
        // parameter block, NUL terminated, and so does everything else.
        jsr $8004               // +$04  uci_init
        lda #$00                // +$103 bp_addr: 0 takes the address from the
        sta $8103               //       file's own first two bytes
        sta $8104
        jsr $806d               // +$6D  load
        lda $8100               // +$100 bp_result: 0 is ULTIMATE_OK
```

Every offset is in [bindings/blob/README.md](bindings/blob/README.md), and the
constants come generated for [ACME](bindings/acme/uci_protocol.a) and
[KickAssembler](bindings/kickass/uci_protocol.asm) so no toolchain has to
retype them. If the base address is only known at run time, load the `.reloc`
table alongside and call `blob_relocate`.

A port of the core to another compiler stays possible and is not planned: the
blob answers the same question with one implementation instead of five.

## How do I detect optional capabilities?

Probe, do not assume a model.

```c
ultimate_capabilities caps;
ultimate_detect(&caps);

if (ultimate_has_dos(&caps))     { /* files: every firmware with a UCI */ }
if (ultimate_has_network(&caps)) { /* raw TCP and UDP sockets */ }
if (ultimate_has_http(&caps))    { /* HTTP client: firmware 3.15+ */ }
if (ultimate_has_control(&caps)) { /* drives, freeze, reboot, REU, palette */ }
```

An Ultimate-II+ on current firmware can do more than an Ultimate 64 on old
firmware, which is why the model name is for bug reports and splash screens
rather than for branching. Detection costs one round trip per target: do it once
at start-up and keep the answer.

## Error handling

One small, stable set of codes, whatever the firmware version and whatever the
target:

```
ULTIMATE_OK                 ULTIMATE_ERR_INVALID_ARGUMENT
ULTIMATE_ERR_NO_DEVICE      ULTIMATE_ERR_IO
ULTIMATE_ERR_TIMEOUT        ULTIMATE_ERR_DEVICE
ULTIMATE_ERR_PROTOCOL       ULTIMATE_ERR_TRUNCATED
ULTIMATE_ERR_NOT_SUPPORTED  ULTIMATE_ERR_ABORTED
```

`ultimate_strerror()` turns one into text. `uci_last_device_code()` gives you the
raw number the firmware reported, for when a diagnostic needs to be exact — the
same raw code means different things on different targets, which is why the
public model does not expose them.

## Memory and performance

Built for a machine with 38 kilobytes.

- No heap, no hidden buffers. Every byte lands in a buffer you own.
- 119 bytes of static RAM in total, request block included. No allocation, ever.
- Four bytes of zero page, at an address you choose.
- No interrupts required, and no interrupt handler installed.
- Every entry point is bounded: it completes or returns `ULTIMATE_ERR_TIMEOUT`.

## Testing

Two layers, each catching what the other cannot.

```bash
make test         # sim6502 in Docker: the assembled SDK, against a simulated Ultimate
make -C tests/hardware && copy ucitest.prg to your Ultimate    # the real thing, TAP output
```

Current results: **110 host unit tests, 187 emulator tests and 5/5 hardware
scenarios, all passing** — the last of those on an Ultimate 64 Elite running
firmware 3.15, where the BASIC wedge is also typed at the machine line by line
and checked on the screen.

Every mutating hardware test writes to `/Temp`, the FAT filesystem the firmware
formats in RAM at boot, so running them cannot fill a medium, wear flash, or
leave anything behind after a power cycle.

There is no host layer: the SDK is 6502 assembly, so a host test would have to
reimplement the thing it is testing. The layer that existed before the assembly
rewrite is the argument. cc65 translates string literals into PETSCII, so the
`"NO TARGET"` marker capability detection relies on matched perfectly in the
host tests and never matched on a real C64. Running the compiled code against a
simulated Ultimate found it in minutes.

## Documentation

| | |
|---|---|
| [docs/uci.md](docs/uci.md) | the protocol, with every fact sourced, and documented behaviour separated from what was read out of the firmware |
| [docs/architecture.md](docs/architecture.md) | the layers, and what belongs in each |
| [docs/api-design.md](docs/api-design.md) | why the API looks like this |
| [docs/compatibility.md](docs/compatibility.md) | hardware, firmware, CPU speed, known upstream issues |
| [docs/asm-abi.md](docs/asm-abi.md) | the assembly contract |
| [docs/generated/protocol-constants.md](docs/generated/protocol-constants.md) | every constant, generated from the same source as the code |
| [docs/generated/command-coverage.md](docs/generated/command-coverage.md) | which UCI commands the tests actually send |
| [docs/generated/basic-keywords.md](docs/generated/basic-keywords.md) | every wedge keyword, its token, and what CRUNCH does to it |
| [bindings/blob/README.md](bindings/blob/README.md) | the jump table and parameter block, for toolchains that cannot link |
| [docs/handover.md](docs/handover.md) | picking the SDK up cold: state, traps, ground truth |
| [docs/handover-cleanup.md](docs/handover-cleanup.md) | the most recent work, and what is next in the order it should be done |

## Credits

The Ultimate hardware, firmware and command interface are the work of
[Gideon Zweijtzer](https://github.com/GideonZ). This SDK is a client for it and
is not affiliated with Gideon's Logic Architectures or Commodore.

Prior art worth naming: [xlar54/ultimateii-dos-lib](https://github.com/xlar54/ultimateii-dos-lib),
the cc65 library most Ultimate programs have used until now.

## License

MIT. See [LICENSE](LICENSE).
