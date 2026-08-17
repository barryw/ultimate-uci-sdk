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
Elite running firmware 3.15. The file, network and HTTP services are next.

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

Today: find the Ultimate, discover what it can do, identify the machine, and
issue any raw UCI command with framing, timeouts and error translation handled
for you.

Under construction, in this order: Ultimate DOS (files and directories),
networking, HTTP, machine control.

## Getting started

```bash
make lib           # build bindings/cc65/build/ultimate.lib
make blob          # standalone binary with a jump table, for every other toolchain
make examples      # assembly and cc65 versions of the same program
make test          # run the assembled SDK against a simulated Ultimate
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

## From Oscar64, llvm-mos, KickC

Not yet. The core is ca65 assembly, and none of those toolchains can link a ca65
object, so each needs either its own port of `src/uci/*.s` or a relocatable
binary with a jump table. `bindings/oscar64` and `examples/oscar64` are left in
the tree as the shape the answer should take, but they list the C core the
assembly rewrite replaced and do not build.

Both routes stay open, and `tests/emulator` is what either has to pass.
[docs/handover.md](docs/handover.md) explains why they are deliberately not
being started yet: every port multiplies the cost of a change to a service API
that is still being designed.

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
- 88 bytes of static RAM in total, request block included. No allocation, ever.
- Four bytes of zero page, at an address you choose.
- No interrupts required, and no interrupt handler installed.
- Every entry point is bounded: it completes or returns `ULTIMATE_ERR_TIMEOUT`.

## Testing

Two layers, each catching what the other cannot.

```bash
make test         # sim6502 in Docker: the assembled SDK, against a simulated Ultimate
make -C tests/hardware && copy ucitest.prg to your Ultimate    # the real thing, TAP output
```

Current results: **73 emulator tests, 13 hardware tests, all passing** — the
last of those on an Ultimate 64 Elite, firmware 3.15.

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
| [docs/handover.md](docs/handover.md) | picking up the service layers: state, traps, order of work |

## Credits

The Ultimate hardware, firmware and command interface are the work of
[Gideon Zweijtzer](https://github.com/GideonZ). This SDK is a client for it and
is not affiliated with Gideon's Logic Architectures or Commodore.

Prior art worth naming: [xlar54/ultimateii-dos-lib](https://github.com/xlar54/ultimateii-dos-lib),
the cc65 library most Ultimate programs have used until now.

## License

MIT. See [LICENSE](LICENSE).
