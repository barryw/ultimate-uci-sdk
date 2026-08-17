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
                          dos, file, network, http, control
                          (today: detection and identity)
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

`src/uci/uci_core.s`. About 1000 lines of 6502, assembling to 1398 bytes.

Owns: command framing, the four-state handshake, bounded waiting, queue
draining, abort and recovery, and the translation of firmware status replies
into SDK error codes.

Knows nothing about files, sockets or HTTP. Application code should almost never
call it.

Constraints it holds itself to:

- No heap. No hidden buffers. Every byte lands somewhere the caller owns, except
  a four-byte scratch used when the caller wants no status buffer at all.
- `UCI_VARS_SIZE` (65) bytes of static RAM across the whole SDK: 18 in the
  transport, 47 in the service layer (16 of which is the buffer capability
  probing compares against, and 22 its request block).
- Four bytes of zero page, and the caller picks the address.
- No interrupts. The IRQ-on-completion bit exists in the hardware and is exposed
  as a constant, but nothing in the SDK requires an interrupt handler.
- Every entry point terminates. There is no unbounded loop anywhere, including
  the ones the hardware's queue behaviour would otherwise make infinite — see
  [uci.md](uci.md), "Queue pointer saturation".

## Layer 2 — services

`src/uci/ultimate.s` today: bring-up, capability detection, identity.

This is where the growth happens. Each service turns a family of UCI commands
into an API that reads naturally on a C64, and each one is built from
`uci_exec()` alone:

```
services/dos/       open, close, read, write, seek, stat, directories
services/file/      streaming helpers over dos
services/network/   sockets
services/http/      requests, headers, JSON bodies
services/control/   drives, freeze, reboot, REU images, palette
```

Services are where target-specific knowledge lives — that `82` means something
different on the network target than on the control target, that SoftwareIEC
answers in binary, that a `READ_DATA` longer than 512 bytes arrives in chunks.
The core deliberately does not know any of that.

The directories above do not exist yet. They will be created when there is code
to put in them.

## Layer 3 — bindings

Different C64 toolchains cannot link each other's objects, so a binding is
whatever thin thing makes the one implementation reachable from that toolchain.

| Toolchain | Binding | Status |
|---|---|---|
| ca65 / cl65 assembly | `bindings/asm` — request block, jump-table entry points, generated constants | working |
| cc65 | `bindings/cc65` — compiles the core into `ultimate.lib` | working |
| Oscar64 | `bindings/oscar64` — a source list; Oscar64 links whole programs | **broken**: it lists the C core the assembly rewrite replaced |
| llvm-mos | needs its own core or a relocatable binary with a jump table | designed, not built |
| KickC | needs its own core, held to the conformance tests | designed, not built |
| BASIC | a separate project on top of the C API, e.g. CustomBasicCommands | out of scope here |

None of these contain protocol knowledge. `bindings/asm/ultimate_asm.s` is 30
lines of `jmp`; `bindings/oscar64/ultimate.mk` is a list of filenames.

## Testing, in two layers

| Layer | Where | Runs | Catches |
|---|---|---|---|
| Emulator | `tests/emulator` | sim6502 in Docker | the assembled code itself, against a device that makes it wait |
| Hardware | `tests/hardware` | a real Ultimate | firmware reality, on whatever version the machine runs |

There is no host layer, and there deliberately is not one. The SDK is 6502
assembly, so the only machine that can run its logic is a 6502 — a host test
would have to reimplement the thing it is testing.

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

**Game and demo services.** Sprite multiplexers, REU streaming, DMA helpers,
turbo control, audio. These belong in an Ultimate Game SDK built on this one.
Keeping them out is what lets the core stay small enough to audit.

**A BASIC extension.** The public API is shaped so one can be written against
it, and nothing in it assumes a C caller.

**Anything that assumes the newest hardware.** See
[compatibility.md](compatibility.md).
