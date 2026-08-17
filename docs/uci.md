# The Ultimate Command Interface

Everything the SDK knows about the wire protocol, and where each fact came from.

Two kinds of statement appear below:

- **Documented** — stated in the official *Ultimate Command Interface Programming
  Guide*.
- **Inferred** — read out of the Ultimate firmware or FPGA sources, or out of
  Gideon's own 6502 client code. These are correct for the firmware they were
  read from and may change. They are called out individually, because a fact you
  cannot cite is a fact you will eventually get wrong.

Sources:

| Source | Used for |
|---|---|
| [Ultimate Command Interface Programming Guide](https://1541u-documentation.readthedocs.io/en/latest/uci/index.html) | registers, handshake, target and command reference |
| `fpga/io/command_interface/vhdl_source/command_protocol.vhd` | register semantics, pointer behaviour, what a write actually latches |
| `fpga/io/command_interface/vhdl_source/command_if_pkg.vhd` | buffer sizes and end addresses |
| `software/io/command_interface/command_intf.cc`, `command_target.h` | dispatch, the no-reply flag, the placeholder target |
| `roms/c64rom/kernal/uci.s` | Gideon's own 6502 client; the reference for recovery and streaming |
| `software/filemanager/dos.cc`, `control_target.cc`, `network_target.cc`, `softiec_target.cc`, `http_target.cc` | identification and status strings, per-target command lists |
| [xlar54/ultimateii-dos-lib](https://github.com/xlar54/ultimateii-dos-lib) | the widely used cc65 client; a source of prior art and of two bugs worth not repeating |

Firmware read for this document: `v3.15-69`.

Verified against hardware: **Ultimate 64 Elite, firmware 3.15, FPGA 123, core
1.4E**. `tests/emulator/protocol.suite` passes 8/8 and `tests/hardware/ucitest.prg`
passes 13/13 on that machine. Facts marked INFERRED below that the suites cover
are therefore confirmed behaviour, not just readings of the source.

---

## Transport

The interface is five bytes of cartridge I/O space, overlaying the last five
registers of the REU.

| Address | Direction | Name | Notes |
|---|---|---|---|
| `$DF1B` | R | Bus ID | SoftwareIEC device number; `$00` when unset |
| `$DF1C` | W | Control | Write-only. Bits are commands, not state |
| `$DF1C` | R | Status | State machine and queue flags |
| `$DF1D` | W | Command data | One command byte per write |
| `$DF1D` | R | Identification | `$C9`, or `$49` while an IRQ is pending |
| `$DF1E` | R | Response data | One reply byte per read |
| `$DF1F` | R | Status data | One status byte per read |

**Mapping the block is optional.** It is switched on in the Ultimate's
*Command Interface* configuration menu. An Ultimate with it switched off is
indistinguishable from no Ultimate at all, which is why "no device" is a normal
outcome the SDK reports rather than an error condition — see
[compatibility.md](compatibility.md).

### Control register (`$DF1C`, write)

| Bit | Name | Effect |
|---|---|---|
| 0 | `PUSH_CMD` | Submit the buffered command |
| 1 | `DATA_ACC` | Release the current data block |
| 2 | `ABORT` | Ask the Ultimate to abandon the exchange |
| 3 | `CLR_ERR` | Clear the state-error flag |
| 5 | `IRQ` | Interrupt on completion (firmware 3.15+) |
| 6 | `TRIGGER` | Enter DMA mode when `$FF00` is written |
| 7 | `DMA` | Enter DMA mode immediately |

**Inferred — bits 5, 6 and 7 are only sampled on a push.** In
`command_protocol.vhd` they are latched inside `if slot_req.data(0)='1'`, so a
write with `PUSH_CMD` clear cannot turn DMA on or off. Practically: `DMA`,
`TRIGGER` and `IRQ` are modifiers of the push, not standalone commands.

**Never read-modify-write this register.** Reading `$DF1C` returns the *status*
register, so `*ctrl |= 1` in C, or `lda $DF1C / ora #$01 / sta $DF1C` in
assembly, feeds status bits back in as control bits. Today's gating makes that
survivable in the common case; it is not guaranteed and it is not something to
build on. `ultimateii-dos-lib` does exactly this in `uii_sendcommand()` and
`uii_accept()`. The SDK always writes a literal mask.

### Status register (`$DF1C`, read)

| Bit | Name | Meaning |
|---|---|---|
| 0 | `CMD_BUSY` | A command is pending in command memory |
| 1 | `DATA_ACC` | The Ultimate has seen your data acknowledge |
| 2 | `ABORT_P` | An abort request is still outstanding |
| 3 | `ERROR` | A command was pushed while the interface was not idle |
| 4-5 | `STATE` | `00` idle, `01` busy, `10` data-last, `11` data-more |
| 6 | `STAT_AV` | A status byte is waiting at `$DF1F` |
| 7 | `DATA_AV` | A response byte is waiting at `$DF1E` |

Note that `ERROR` is bit 3, value `$08`. `ultimateii-dos-lib` tests `& 4`, which
is `ABORT_P` — so it clears an error condition it never actually detects.

### The exchange

1. Wait for `STATE == idle`.
2. Write the command bytes to `$DF1D`, first byte first.
3. Write `PUSH_CMD` to `$DF1C`. The state goes to *busy*.
4. Poll `$DF1C` until the state leaves *busy*.
5. While `DATA_AV`, read `$DF1E`. While `STAT_AV`, read `$DF1F`. Read both
   before step 6: releasing the block resets both queues.
6. Write `DATA_ACC`. On *data-last* the state returns to idle; on *data-more* it
   returns to *busy* and another block follows, so go back to step 4.

**Inferred — reads past the end of a queue return `$00`, not garbage.** The FPGA
gates the RAM output with `response_valid`/`status_valid`.

**Inferred — a command can also complete with no data phase at all.** The state
goes busy and then straight back to idle. This happens for `CTRL_CMD_REBOOT`, for
a zero-length command, and whenever the caller set the no-reply flag. A reader
that assumes a data state always arrives will hang on those.

---

## Queue pointer saturation

The single most important undocumented behaviour, because the obvious reading of
the protocol description hangs the machine.

From `command_if_pkg.vhd`:

```
c_cmd_if_response_buffer_addr = 896
c_cmd_if_response_buffer_size = 896
c_cmd_if_response_buffer_end  = 896 + 896 - 1     -- the LAST byte, not one past it
```

and from `command_protocol.vhd`:

```vhdl
when c_cif_slot_response =>
    if response_pointer /= c_cmd_if_response_buffer_end then
        response_pointer <= response_pointer + 1;
    end if;
```

with availability computed as `(pointer - base) < length`.

So each pointer stops **on** the last byte of its buffer instead of moving past
it. Two consequences:

**Reading.** A reply that exactly fills the 896-byte response queue leaves
`DATA_AV` set for ever: the pointer sticks at offset 895, `895 < 896` stays true,
and every further read of `$DF1E` returns that same last byte. `while (DATA_AV)
read` never terminates. The 256-byte status queue behaves identically. A client
must bound the loop; reading at most one queue's worth is both correct and
terminating, since no single block can contain more.

**Writing.** The command pointer saturates the same way, at offset 895. The 896th
byte written lands on top of the 895th, and `command_length` — computed as
`command_pointer - base` — is reported as 895. **The largest command the hardware
can actually receive is 895 bytes**, not the 896 the queue is documented to hold.
The SDK rejects anything longer rather than sending a command the firmware will
silently misread.

---

## Recovering a wedged interface

**Inferred, from `command_protocol.vhd` and `roms/c64rom/kernal/uci.s`.**

The command write pointer is only rewound when the Ultimate *accepts* a command
(handshake bit 0) or when the interface is reset. A program that wrote some
command bytes and then crashed before pushing leaves them at the front of the
command queue, where they will be prepended to the next program's first command.
No status bit exposes this.

Abort fixes it. When the Ultimate services an abort it writes
`HANDSHAKE_RESET` (`$87`), whose bit 0 rewinds the command pointer and whose bit
7 forces the state back to idle. So a single abort clears all three failure modes
at once: a stuck state, a half-written command, and (with `CLR_ERR` after it) a
latched state error. Gideon's kernal does exactly this on reset, in
`ulti_restor`. The SDK does it in `uci_init()`.

---

## Targets

The first byte of a command selects the target.

**Inferred — only bits 0-3 select the target, and bit 7 is a "no reply" flag.**
From `command_intf.cc`:

```cpp
target = incoming_command.message[0] & CMD_IF_MAX_TARGET;          // 0x0F
bool no_reply = ((incoming_command.message[0] & CMD_IF_NO_REPLY) != 0);   // 0x80
```

With the flag set, the firmware parses the command and then forces the state
straight back to idle instead of producing a data phase — fire and forget, with
no round trip to wait for. This is not in the published documentation.

| ID | Target | Identification string | Status format |
|---|---|---|---|
| `$01` | Ultimate DOS #1 | `ULTIMATE-II DOS V1.2` | `NN,TEXT` |
| `$02` | Ultimate DOS #2 | `ULTIMATE-II DOS V1.2` | `NN,TEXT` |
| `$03` | Network | `ULTIMATE-II NETWORK INTERFACE V1.0` | `NN,TEXT` |
| `$04` | Control | `CONTROL TARGET V1.1` | `NN,TEXT` |
| `$05` | SoftwareIEC | `SOFTWARE IEC TARGET V1.0` | single binary byte |
| `$06` | HTTP | `ULTIMATE HTTP TARGET V1.0` | `NNN TEXT` |

The two DOS instances hold independent state: two current directories, two open
files.

**Identification strings are uppercase; the model name is not.** Every string in
the table above is uppercase ASCII, which a C64 prints unchanged in its default
character set. `CTRL_CMD_GET_HWINFO` is the exception: it returns
`getProductString()`, which is mixed case — `Ultimate 64 Elite`, `Ultimate II+`,
`Ultimate 64-II`. Lowercase ASCII renders as graphics glyphs in the default
character set, so a program that prints the model name has to fold or convert it
first. The examples and `tests/hardware/ucitest.c` show the two lines it takes.

### Probing for a target

**Inferred, from `command_target.h`.** Unimplemented target IDs are not rejected.
Every ID from `$00` to `$0F` is bound at start-up to a placeholder target whose
behaviour is:

```cpp
if (command->message[1] == CMD_IDENTIFY) { reply = "NO TARGET";  status = "00,OK"; }
else                                     { reply = "";           status = "21,UNKNOWN COMMAND"; }
```

So `<target> $01` is safe to send to any ID, and a reply of exactly `NO TARGET`
means "this firmware does not implement that target". That is what
`ultimate_detect()` uses, and it is the only reliable enumeration mechanism.

One trap follows from it: the placeholder always answers in the ASCII status
format, even standing in for target `$05`, whose real status is a binary byte. A
client that decides how to parse the status purely from the target ID will read
`'0'` (`$30`) as a SoftwareIEC error code. The SDK checks the `NO TARGET` marker
in the data channel first, before it looks at the status at all.

---

## Status encodings

Three incompatible encodings share one channel.

**`NN,TEXT`** — DOS, network, control, and the placeholder. Two ASCII digits, a
comma, then text. Observed values, taken from the firmware sources:

| Code | Example | Class |
|---|---|---|
| `00` | `00,OK` | success |
| `01` | `01,DIRECTORY EMPTY`, `01,CONNECTION CLOSED BY HOST` | advisory |
| `02` | `02,REQUEST TRUNCATED` | advisory |
| `03` | `03,MORE DATA NOT SUPPORTED` | failure |
| `21` | `21,UNKNOWN COMMAND` | not implemented |
| `81` | `81,INVALID PARAMS` | bad argument |
| `82` | `82,PARAMETER(S) OUT OF RANGE` (network), `82,ERRORS ON TRACK` (control) | failure — **meaning depends on the target** |
| `83`-`8F` | `84,REU NOT ENABLED`, `85,NO FILE OPEN`, `90,DRIVE NOT PRESENT`, ... | failure |
| `98`, `99` | `98,FUNCTION PROHIBITED`, `99,FUNCTION NOT IMPLEMENTED` | not implemented |

`01` and `02` are advisory: the command did what was asked and has something to
add. Treating them as failures breaks working programs, so the SDK reports them
as success with the numeric code preserved.

Note `82`. The same number means different things on different targets, which is
exactly why the SDK's public error model is a small fixed set and the raw code is
kept separately.

**`NNN TEXT`** — HTTP only. Three ASCII digits and a space. This channel carries
both firmware errors (`500 BAD FORMAT`, `507 NO HEADER SLOT`) and the response
code the remote server returned (`200 OK`, `404 ENTRY NOT FOUND`). Nothing
distinguishes the two, so the SDK maps everything below 400 to success and
everything at or above it to a device error, and expects HTTP callers to read the
number.

**A single binary byte** — SoftwareIEC only. `$00` OK, `$01` file not found,
`$02` save error, `$03` no input channel, `$04` unknown command, `$05` IEC module
not loaded, `$06` invalid parameters, `$07` invalid name, `$08` invalid
partition, `$09` invalid directory, `$80` verify failure.

`$05` deserves attention. The documentation says **every** command on that
target returns it when the emulated drive behind the SoftwareIEC interface has
not been loaded, which would make a capability probe tell you whether the target
is usable. Firmware 3.15 does not behave that way: with the IEC Drive setting
disabled, target `$05` still identifies itself *and still serves functional
commands* — `SOFTIEC_CMD_GET_FATNAME` returns a resolved host path. The
availability guard tests a pointer that is set unconditionally at boot rather
than the drive's enable flag, so that status is effectively unreachable.

**This is intended and it is not going to change.** Asked directly in
[GideonZ/1541ultimate#794](https://github.com/GideonZ/1541ultimate/issues/794),
Gideon confirmed it: disabling the drive removes it from the *IEC bus*, not from
UCI, because UCI is exactly the path the hyperspeed kernal uses to reach it. So
the IEC Drive setting and SoftwareIEC-over-UCI are two independent things, and
`$05` is reachable whether or not a drive is answering on the bus. Treat the
`$05` status as documented-but-unreachable rather than as a case to design
around — the SDK still maps it in `uci_map_binary`, which costs six bytes and
means a future firmware that does fire it is handled without a change.

**The SoftwareIEC target mixes two status encodings.** `SOFTIEC_CMD_IDENTIFY`
answers with the firmware's shared ASCII message `00,OK`; every other command on
that target answers with a single binary byte. So the status encoding is not a
property of the target after all, and a decoder that dispatches on the target ID
alone reads the `'0'` of `00,OK` as binary `$30` and reports a device error for
the one command that is documented as unable to fail. The SDK sniffs instead:
the binary codes in use are `$00`-`$09` and `$80`, none of which is an ASCII
digit, so the two are always distinguishable. This one cost real debugging time —
it made capability probing declare a working SoftwareIEC target absent, and only
hardware testing showed it.

**Silence is success.** Several commands, `DOS_CMD_READ_DATA` among them, send no
status at all when everything went well.

---

## Command reference

Machine-generated from the same definition the code and the assembler include are
generated from: [generated/protocol-constants.md](generated/protocol-constants.md).

Commands present in the firmware but absent from the published documentation are
marked `INFERRED` there. At the time of writing those are, on the control target:
`READ_RTC` (`$02`), `ENCODE_TRACK` (`$12`), `LOAD_CONFIG` (`$50`) and the palette
commands `$51`-`$54`; and on the network target, the TCP listener commands
`$12`-`$15`, which `ultimateii-dos-lib` uses.

---

## Timing

Nothing in the protocol is specified in time. The Ultimate runs its own
processor, so how long *busy* lasts depends on what the command does — a
`DOS_CMD_IDENTIFY` is immediate, an HTTP exchange can take seconds.

There is no timer to key off that a game can rely on, so the SDK counts status
polls instead. That makes the budget a function of CPU speed, which on Ultimate
hardware spans 1 MHz to 48 MHz. See [compatibility.md](compatibility.md) for what
that means in practice and how to set it.

---

## The control register's freeze bits are not a fast path

`UCI_CTRL_DMA` (`$80`) and `UCI_CTRL_TRIGGER` (`$40`) sound like a way to make
transfers faster. They are not. Both latch into `freeze_i` in
`fpga/io/command_interface/vhdl_source/command_protocol.vhd`, which is the
cartridge freeze line — the mechanism the Ultimate's freezer uses to take the
bus. `TRIGGER` is the classic "freeze on the next `$FF00` write".

The actual fast load path is a different target entirely: `SOFTIEC_CMD_LOAD_SU`
followed by `SOFTIEC_CMD_LOAD_EX` on target `$05`. The firmware writes straight
into C64 RAM and returns the end address in status bytes 1-2; the data never
passes through `$DF1E`. The Ultimate's own kernal wedge pushes those commands
with a plain `UCI_CTRL_PUSH_CMD` and no freeze bit at all.
