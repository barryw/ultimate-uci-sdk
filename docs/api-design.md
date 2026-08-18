# API design

The decisions behind the SDK's surface, and the reasoning that will still be
here when someone wants to change one of them.

---

## One implementation, in 6502

The core protocol is a single body of ca65 assembly — `src/uci/uci_core.s` and
`src/uci/ultimate.s` — and every binding calls into it. A binding that
reimplements the handshake is a bug, not a feature.

It was C first, and the argument for C was reach: the same source compiles on
cc65, Oscar64, llvm-mos and a host compiler, so no toolchain needs a hand
translation of the protocol. What that bought in reach it charged for in every
other column. cc65 compiles C into code that uses its software stack, so an
assembly program had to bring up a C runtime before it could call anything —
in an SDK that advertises assembly as a first-class interface.

The assembly core costs the reach and keeps everything else:

| | C core | assembly core |
|---|---|---|
| size | — | 1694 bytes for the transport, 498 for the service layer, and 98-731 for each service on top |
| assembly callers | must initialise cc65's software stack | need nothing at all |
| RAM | BSS, wherever the linker puts it | `UCI_VARS` places every byte, or BSS by default |
| zero page | the C runtime's | four bytes, at an address you choose |
| cc65 | native | native |
| Oscar64, llvm-mos, KickC | native | the jump-table binary in `bindings/blob` |

That last row was the whole bill, and it is paid: the blob is the same object
files linked at a base address, with a jump table at its first bytes and a
parameter block behind it, so a toolchain that cannot link a ca65 object does
not need a port at all. One implementation reaches all of them.

`tests/emulator` is what would make a real port safe if one were ever wanted.
Any replacement core has to pass it unchanged.

## Protocol bytes are never string literals

`"NO TARGET"` is not nine ASCII bytes on a C64. Both halves of the toolchain
translate string literals into the target character set — cc65 for C, and
`ca65 -t c64` for assembly — so that literal reaches the machine as PETSCII
`$CE $CF $20 $D4 ...` while the Ultimate sends ASCII `$4E $4F $20 $54 ...`. The
comparison silently fails, and only on hardware: the host tests the SDK had at
the time did no translation and passed.

So every byte that goes on the wire or gets compared against the wire is spelled
out numerically, generated from `tools/gen_protocol.py`:

```asm
ult_no_target:
        UCI_STR_NO_TARGET_BYTES
```

Character constants follow the same rule, even where ASCII and PETSCII agree
(they do for digits, which is why the status parser looked fine) — `uci_is_digit`
compares against `UCI_ASCII_ZERO`, not against `'0'`.

Display strings — `ultimate_strerror()`, everything an example prints — are
ordinary literals on purpose: there translation is exactly what you want, and
`sdk-strerror` in `tests/emulator/sdk.suite` asserts the PETSCII values so the
two conventions cannot be quietly swapped.

## Constants are generated, not typed

`tools/gen_protocol.py` is the single source of truth for the register map, the
bit definitions, target IDs, command codes and error codes. It emits the C
header, the ca65 include and a documentation table.

Four hand-maintained copies of sixty constants is not a thing that stays correct.
The generator is ninety lines and refuses to run if two constants share a name.

## The error model

Callers get a small, stable set:

```
ULTIMATE_OK                 ULTIMATE_ERR_INVALID_ARGUMENT
ULTIMATE_ERR_NO_DEVICE      ULTIMATE_ERR_IO
ULTIMATE_ERR_TIMEOUT        ULTIMATE_ERR_DEVICE
ULTIMATE_ERR_PROTOCOL       ULTIMATE_ERR_TRUNCATED
ULTIMATE_ERR_NOT_SUPPORTED  ULTIMATE_ERR_ABORTED
```

These are stable across firmware versions and across targets, which the raw
status codes are not: `82` means "parameter out of range" on the network target
and "errors on track" on the control target, and the three targets do not even
agree on how to encode a status. That decoding belongs in one place.

The raw code is not thrown away. `uci_last_device_code()` returns exactly what
the target said, in the target's own numbering, and it is the right thing to
consult when a diagnostic needs to be precise or when a service wants to
distinguish two failures the SDK maps to one class.

Three deliberate choices inside the mapping:

- **`01` and `02` are successes.** `01,DIRECTORY EMPTY` and `02,REQUEST
  TRUNCATED` mean the command did what was asked and has something to add.
  Failing them would break working programs.
- **HTTP `4xx`/`5xx` map to `ULTIMATE_ERR_DEVICE`, not to an argument error.**
  That channel carries both firmware errors and the remote server's response
  code, and nothing distinguishes them. A `404` from a web server is not SDK
  misuse. HTTP callers read the number.
- **Silence is success.** Several commands send no status when all is well.

## Wire formats are decided by the bytes, not by the documentation

The published protocol presents the status encoding as a property of the target.
It is not: `SOFTIEC_CMD_IDENTIFY` answers in ASCII while every other command on
that target answers in binary. Trusting the documented mapping made capability
probing report a working SoftwareIEC target as absent — on hardware, with every
host and emulator test passing.

The fix was not to special-case that command. `uci_decode_status()` classifies a
status by its leading bytes, and the four encodings are mutually exclusive on
sight: `HTTP/` is the response line an exchange answers with, three leading
ASCII digits is the firmware's own `NNN TEXT`, two is `NN,TEXT`, and any other
leading non-digit is a single binary byte. The binary codes in use are
`$00`-`$09` and `$80`, none of which is an ASCII digit or an `H`, so nothing can
be read two ways.

The fourth was added the same way and for the same reason: an HTTP exchange
answers with the whole response header block rather than a code, and until the
decoder knew that shape every successful request came back as a device error.

The target hint still has a job — deciding whether a binary status is plausible
at all, since the numeric meanings of a binary status are SoftwareIEC's and
applying them to some other target would be inventing an error rather than
reporting one. But it no longer decides how to parse.

Two things follow. A firmware that makes the target consistent, in either
direction, needs no change here. And because the classification depends on the
leading bytes, the SDK always captures the first four status bytes itself rather
than decoding from the caller's buffer — otherwise a caller passing a two-byte
status buffer would turn `404 ENTRY NOT FOUND` into a cheerful `40`.

## Caller-owned buffers, everywhere

```c
uint8_t ultimate_read(uint8_t handle, void *buf, uint16_t len, uint16_t *got);
```

not

```c
uint8_t *ultimate_read(uint8_t handle, uint16_t len);   /* no */
```

No allocator, no hidden static buffers a second call would stomp, no surprises
about where memory came from on a machine with 38 kilobytes of it. The SDK's
entire private state is 25 bytes.

Two conventions make this pleasant rather than tedious:

- A `NULL` data buffer means "I do not want the reply", and the bytes are read
  and dropped. That is not truncation. A buffer that *fills up* is, and returns
  `ULTIMATE_ERR_TRUNCATED` with the exchange still completed cleanly.
- A `NULL` status buffer is always safe. The numeric code is decoded either way,
  so a command that fails never looks like one that succeeded.

## The request block

```c
typedef struct {
    uint8_t         target, command;
    const uint8_t  *args;    uint16_t arglen;
    const uint8_t  *payload; uint16_t payloadlen;
    uint8_t        *data;    uint16_t datamax, datalen;
    uint8_t        *status;  uint16_t statusmax, statuslen;
} uci_request;
```

One struct instead of an eight-argument function, because eight arguments on a
6502 means eight pushes onto a software stack at every call site, and because a
fixed block in RAM is the natural shape for an assembly caller. `args` and
`payload` are separate spans so a caller can send a fixed header plus a large
body without copying them together first — which is what a block write is.

`bindings/cc65/abi_assert.c` asserts the byte offsets at compile time so the
assembly view of this struct cannot silently drift.

## Capabilities, not model numbers

```c
ultimate_capabilities caps;
ultimate_detect(&caps);
if (ultimate_has_http(&caps)) { ... }
```

Never "is this an Ultimate 64". An Ultimate-II+ on current firmware has more
targets than an Ultimate 64 on old firmware, so the model tells you less than the
probe does. `ultimate_get_model()` exists for display and bug reports, not for
branching.

Detection works by asking each target to identify itself and recognising the
firmware's placeholder reply. See [uci.md](uci.md), "Probing for a target", for
why that is reliable and for the trap it contains.

## Timeouts

Every wait is bounded. `uci_set_timeout()` takes a budget in units of 256 status
polls; zero means wait forever, which is a legitimate choice for a command whose
duration genuinely cannot be bounded.

Polls, not milliseconds, because there is no timer a game can safely borrow.
The consequence is that the budget scales with CPU speed, and Ultimate hardware
spans 1 MHz to 48 MHz — see [compatibility.md](compatibility.md). Services that
wait on a network or a disk raise the budget themselves and put it back
afterwards.

## Naming

`ultimate_*` for the public API, `uci_*` for the transport. If a caller is
typing `uci_`, they are either writing a service or doing something the SDK does
not cover yet — both fine, and both worth being able to see at a glance.

## Assembly as a real interface

Not "you can call the C functions if you set up the stack". The assembly binding
provides a request block at a fixed address, entry points that take their
arguments in registers, and a documented register contract. The one thing it
does inherit from the C core is the runtime initialisation requirement, which
[asm-abi.md](asm-abi.md) states up front rather than leaving to be discovered.

## Room left deliberately

- **Fire and forget.** `UCI_TARGET_NO_REPLY` is supported today: set it and
  `uci_exec()` returns as soon as the interface is idle, with no data phase.
  Undocumented upstream; see [uci.md](uci.md).
- **DMA and IRQ.** The control bits are defined and documented. Nothing uses
  them yet. They are how a future high-speed path will work.
- **The control target's REU pair.** `src/uci/reu.s` wraps the DOS pair
  (`$21`/`$22`) and the expansion's own DMA registers. `CTRL_CMD_LOAD_REU` stays
  unwrapped on purpose: it never returns on firmware 3.14d and wedges the
  interface until a power cycle, so it is reachable only through the generic
  form, where issuing it is a deliberate act.
