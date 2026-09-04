# Architecture

## The shape of it

```
        assembly          cc65 C         Oscar64 C       llvm-mos, KickC, BASIC
            |                |               |                     |
            +----------------+---------------+---------------------+
                                     |
                          Layer 3: language bindings
                          thin adapters, no protocol knowledge
                                     |
                          Layer 2: services
                          files, disks, control, network, HTTP,
                          palette, clock, REU, audio, vsprites
                                     |
                          Layer 1: UCI core
                          framing, handshake, timeouts, error translation
                                     |
                              $DF1B - $DF1F
```

One rule holds the whole thing together: **the protocol is implemented once.**
Every binding, every language, every future service runs the same transport. A
binding that reimplements the handshake is a bug, not a feature.

## Layer 1 — UCI core

`src/uci/uci_core.s`, implemented in 6502 assembly.

Owns: command framing, the four-state handshake, bounded waiting, queue
draining, abort and recovery, and the translation of firmware status replies
into SDK error codes.

Knows nothing about files, sockets or HTTP. Application code should almost never
call it.

Constraints it holds itself to:

- No heap. Reply data lands in caller-owned buffers. The transport keeps a
  16-byte status prefix so decoding does not depend on the caller's buffer size.
- `UCI_VARS_SIZE` (currently 191) bytes of static RAM across the whole SDK. The
  generated constant and assembly-time layout assertion are authoritative.
- Four bytes of zero page, and the caller picks the address.
- No interrupts. The IRQ-on-completion bit exists in the hardware and is exposed
  as a constant, but nothing in the SDK requires an interrupt handler.
- Ordinary calls use a bounded polling budget. Network connect, its UDP twin and
  HTTP exchange wait without that limit because firmware connection attempts can
  exceed it; reboot does not return, and freeze waits for the user. See
  [uci.md](uci.md), "Queue pointer saturation".

## Layer 2 — services

Each service turns a family of UCI commands or a documented hardware block into
an API that reads naturally on a C64:

```
src/uci/ultimate.s  bring-up, capability detection and identity
src/uci/dos.s       open, close, read, write, seek, delete, directories
src/uci/dosinfo.s   metadata, rename, copy, directories and home
src/uci/disk.s      mount, unmount and swap disk images
src/uci/file.s      load, bload, save - two-tier, over dos or SoftwareIEC
src/uci/reu.s       stash and fetch over DMA, the DOS REU pair, and how big it is
src/uci/palette.s   the running palette, on the control target
src/uci/turbo.s     CPU speed, which is not a UCI command at all
src/uci/net.s       TCP and UDP sockets, on the network target
src/uci/http.s      HTTP requests
src/uci/httpbody.s  firmware-side HTTP request bodies
src/uci/control.s   reset, freeze and drive state
src/uci/clock.s     the battery-backed clock
src/uci/audio.s     direct Ultimate Audio voice control
src/uci/wav.s       PCM WAV loading into the REU
src/uci/vsprite.s   local bitmap compositing, with no Ultimate required
```

Services are where target-specific knowledge lives — that `82` means something
different on the network target than on the control target, that SoftwareIEC
answers in binary, that a `READ_DATA` longer than 512 bytes arrives in chunks.
The core deliberately does not know any of that.

One file per service, flat, because a service is a few hundred bytes of 6502 and
a directory per file would be filing rather than structure. Every target the
firmware offers now has one.

`net.s` and `http.s` are the clearest cases for why this layer exists at all. Every one of its
answers is invisible from `uci_exec()`: a socket read reports data, end of
stream and "nothing yet" as device codes `0`, `1` and `2`, and all three are
success in the numbering the status decoder follows — so the generic form
returns `ULTIMATE_OK` for all three and a caller cannot tell a finished download
from an idle one. Turning that into `ULTIMATE_END` is target-specific knowledge,
which is exactly what a service is for. `http.s` is the same story with a
different ending: there the fix belonged in the core, because an HTTP exchange
answers with its response line rather than a status code and the *generic form*
was reporting a device error for every request that worked. A service-layer
patch would have left `uci_exec()` callers wrong. See docs/uci.md.

Turbo control, REU stash/fetch and Ultimate Audio drive documented hardware
registers directly because no UCI command provides those operations. Software
vsprites only modify caller-owned bitmap memory. `tools/test_registers.py`
enforces the REU and audio register boundaries.

## Layer 3 — bindings

Different C64 toolchains cannot link each other's objects, so a binding is
whatever thin thing makes the one implementation reachable from that toolchain.

| Toolchain | Binding | Status |
|---|---|---|
| ca65 / cl65 assembly | `bindings/asm` — request block, jump-table entry points, generated constants | working |
| cc65 | `bindings/cc65` — compiles the core into `ultimate.lib` | working |
| KickAssembler, ACME, 64tass | `bindings/blob` — a standalone binary with a jump table, plus generated constant files | working |
| Oscar64, llvm-mos, KickC | `bindings/blob` — the same, since none of them can link a ca65 object | working |
| BASIC | `src/basic` — a wedge that owns four RAM vectors and adds 23 keywords | working, `.prg` and `.crt` |

None of these contain protocol knowledge. `bindings/asm/ultimate_asm.s` is a
thin adapter, and the blob is the library's own object files linked at a base
address — not a port, and not a second implementation.

## Testing

| Layer | Where | Runs | Catches |
|---|---|---|---|
| Host invariants | `tools/test_*.py` | Python | generated tables, ABI/layout drift, source boundaries and packaging rules |
| Emulator | `tests/emulator` | sim6502 in Docker | the assembled code itself, against a device that makes it wait |
| Hardware | `tests/hardware` | a real Ultimate | firmware reality, on whatever version the machine runs |

Host tests protect generated and structural contracts; they do not pretend to
execute SDK logic. The SDK is 6502 assembly, so behavioral tests run that code
under sim6502 and on hardware.

The layer that existed before the assembly rewrite is the argument for that.
It compiled the SDK's C source with a host compiler, where a string literal is
ASCII; cc65 translates literals into PETSCII. The `"NO TARGET"` marker that
capability detection depends on therefore matched perfectly on the host and
never matched on a C64 — a bug no amount of host testing could find, caught
within minutes of running the compiled code against a simulated Ultimate. The
fix is in
[api-design.md](api-design.md#protocol-bytes-are-never-string-literals).

Its 182 assertions were not lost: they are `tests/emulator/sdk.suite`,
`absent.suite` and `timeout.suite`, which assert the same behaviour against
instructions the C64 will really execute.

## What is deliberately not here

**A game engine.** Movement, frame timing, object lists and hardware-sprite
multiplexing remain application policy. The SDK supplies reusable primitives
such as turbo, audio, REU transfers and software-vsprite compositing.

**Anything that assumes the newest hardware.** See
[compatibility.md](compatibility.md).
