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

**There is a fourth mode, and abort alone does not clear it.** An abort is not
serviced while the interface is holding a reply block: the firmware is waiting
for `DATA_ACC`, the state never leaves *data-more*, and the abort's own wait for
idle times out. A program that abandons a reply chain half way - a directory
walk given up after the first entry is the ordinary way to get here - is then
stuck with every later command returning `ULTIMATE_ERR_TIMEOUT`, including the
abort meant to rescue it.

`uci_abort()` therefore releases whatever is held first, with `DATA_ACC`, until
the state falls below *data-last*, and only then aborts. Releasing without
reading is exactly right for this: `DATA_ACC` resets both queues whether or not
anything read them. The loop is bounded by the same timeout budget as every
other wait in the SDK.

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

Four incompatible encodings share one channel.

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

**`NNN TEXT`** — HTTP only. Three ASCII digits and a space. On firmware 3.15
this is what the HTTP target's *own* commands answer with: `000 OK` when a
header or a body command works, `400 BAD COMMAND` for a handle that does not
exist, `400 NO VALID JSON` when `DO_EXCHANGE_OBJ` cannot parse the reply. The
SDK maps everything below 400 to success and everything at or above it to a
device error, and keeps the number.

**`HTTP/1.1 NNN TEXT`** — an HTTP exchange, and it is not a code at all. The
status is **the response line the remote server sent, followed by the whole
header block**:

```
HTTP/1.0 200 OK\r\nServer: SimpleHTTP/0.6 Python/3.13\r\nContent-Type: ...
```

Measured, not documented: this file used to say that the `NNN` form carried both
the firmware's errors and the server's response code with nothing to tell them
apart. It does not. **They are different shapes**, and that is what makes them
separable — the firmware's own errors are three digits, and the server's answer
arrives inside a response line.

The SDK reads the three digits after the first space and applies the same rule:
below 400 is success, at or above it is a device error with the number kept. The
rest of the block stays in the caller's status buffer, which is where a
`Content-Type` or a `Location` has to come from.

**This was a real bug, and it was invisible from a unit test.** Before the
decoder knew this shape it read the leading `H` as the binary form and answered
`ULTIMATE_ERR_DEVICE`, so *every successful HTTP request looked like a failure*.
Two things had to change: the shape had to be recognised, and the core's
captured status prefix had to grow from four bytes to sixteen — four is enough
for `NNN ` and nowhere near enough for `HTTP/1.1 404 `. A test that called the
decoder directly passed the whole status in and never exercised that capture,
which is why the fault only appeared on hardware.

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

**A fourth shape: bare text with no code at all.** Ultimate DOS answers every
failure that came out of the *filesystem* rather than out of DOS itself with
`FileSystem::get_error_string(res)` and nothing else — `DISK IS FULL`,
`FILE DOESN'T EXIST`, `WRITE PROTECTED`, `ACCESS DENIED`. Only the canned
DOS-level statuses in the table above carry a `NN,` prefix. In
`software/filemanager/dos.cc` the commands that can answer this way are
`OPEN_FILE`, `WRITE_DATA`, `FILE_SEEK`, `DELETE_FILE`, `RENAME_FILE`,
`COPY_FILE` and `CREATE_DIR` — which is most of what a program does with files.

Found on the wire on firmware 3.15, writing to a full USB stick, and confirmed
against the source afterwards. The SDK reads a status of two bytes or more that
begins with a non-digit, on a target whose status is meant to be decimal, as
`ULTIMATE_ERR_DEVICE` with no device code: the target reported a failure in
words, and the words are in the caller's status buffer. Reading it as a protocol
error — which is what the SDK did until this was seen — tells a program the
transport is broken when the disk is.

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

## How big is the RAM expansion?

**No command answers this.** The control target's hardware-info command reports
the model name and the SID configuration, and that is the whole of it. The
firmware knows — `REU Size` is a setting, and it offers `128 KB`, `256 KB`,
`512 KB`, `1 MB`, `2 MB`, `4 MB`, `8 MB`, `16 MB` — but the only way to read it
is the REST API, which is no use to a program running on the C64.

`REU_STAT_SIZE` (`$10` in `$DF00`) is not the answer either. It is the 1764-era
bit that separated 128 KB from 256 KB, and on an Ultimate it is measured as
clear at 128 KB and set at every size above it. One bit cannot distinguish eight
sizes.

So `ultimate_reu_size()` measures it, and the measurement rests on one fact
verified across all eight sizes on firmware 3.15: **the expansion aliases.** A
write past the end lands at the offset modulo the real size, and because every
boundary worth testing is a power of two at or above that size, it lands exactly
on offset zero. The first boundary whose write disturbs offset zero is the size.

| configured | measured |
|---|---|
| 128 KB | 2 banks |
| 256 KB | 4 |
| 512 KB | 8 |
| 1 MB | 16 |
| 2 MB | 32 |
| 4 MB | 64 |
| 8 MB | 128 |
| 16 MB | 256 |

**16 MB is the ceiling whatever the machine has**, because `REU_REG_ADDR_LO`,
`MID` and `HI` are 24 bits between them. A Commodore 64 Ultimate with far more
RAM than that cannot reach the rest through these registers — there is no fourth
address byte and no bank register in the documented set.

**The size is reported in 64K banks, and in a word.** 16 MB is 256 banks, which
does not fit a byte; counted in 256-byte pages it is 65536, which does not fit a
word. Both of the compact units are one short at exactly the largest machine,
which is the one nobody has to hand. Banks in a word reach 4 GB.

The probe borrows twelve bytes and puts them back, offset zero last so a wrapped
write cannot outlive the truth. `tests/hardware` asserts that too: a size probe
that quietly corrupted offset zero would pass every size check and still be
wrong.

---

## Sockets, and what the network target really does

The protocol document gives the argument shapes for target `$03` and stops
there. Everything below was measured against firmware 3.15 on an Ultimate 64
Elite, because the parts it stops before are the parts a caller trips over.
`src/uci/net.s` is built on these and nothing else.

### A read never waits for the wire

`NET_CMD_READ_SOCKET` answers immediately whether or not anything has arrived —
a read issued straight after a connect reports "nothing yet" even when the peer
sent its greeting on accept. **Callers poll.** That is the right behaviour for a
C64: a blocking read would freeze the machine for as long as the other end felt
like being quiet.

### The reply carries its own count

A read answers `<count:16 LE> <bytes>`, and a count of `$FFFF` means nothing was
available. `ultimate_net_read()` strips the count, which is why the buffer it is
given holds `UCI_NET_READ_PREFIX` fewer bytes of payload than its size.

### The device code is the whole state machine

| code | status text | what it means |
|---|---|---|
| `0` | `00,OK` | the reply carries data |
| `1` | `01,CONNECTION CLOSED BY HOST` | end of stream, said exactly once |
| `2` | `02,NO DATA: 11` | the socket is open and nothing is pending |
| `2` | `02,NO DATA: 9` | the handle is dead, closed, or was never opened |

**All three decode to `ULTIMATE_OK`.** `00`, `01` and `02` are success in the CBM
DOS numbering that [status decoding](#status-encodings) follows, so `uci_exec()`
cannot tell them apart and neither can a caller using it directly. Reading
`uci_last_device_code()` back is what separates them, and it is what
`ultimate_net_read()` does to turn code `1` into `ULTIMATE_END`. Nothing needs to
parse the status text.

Once end of stream has been reported the firmware has already released the
handle, so closing it answers `12,ERROR ON CLOSE`. A caller that reads to the end
must not then close.

### A connect can take thirty seconds

| operation | cycles at 1 MHz | wall clock |
|---|---|---|
| connect to a host that is up | 47,585–74,939 | 48–75 ms |
| **connect to an address with nothing at it** | **30,787,778** | **30.8 s** |
| name that does not resolve | 28,258 | 28 ms |
| read with data waiting | 3,577–21,218 | 4–21 ms |
| read with nothing pending | 41,862–44,860 | 42–45 ms |
| write | 3,279–6,635 | 3–7 ms |

The SDK's timeout budget is a byte of 256-poll units: about 0.65 s at
`UCI_TIMEOUT_DEFAULT` and about 1 s at its maximum. **No value of it reaches 30
seconds**, so `ultimate_net_connect()` and `ultimate_net_udp()` run on
`UCI_TIMEOUT_FOREVER` and rely on the firmware's own connect timeout, which fired
every time it was tested. They restore the caller's budget afterwards, and they
are the only entry points in the SDK not bounded by the SDK. Every other network
command finished in 75 ms or less.

### Read lengths between 769 and 1023 are dangerous

The firmware range-checks the requested length at 1024 and answers
`82,PARAMETER(S) OUT OF RANGE` above it. Its response queue is
`UCI_MAX_RESPONSE` = `$380` = 896 bytes, which is smaller than the largest
request it accepts.

**A probe stepping through that gap took the machine off the network entirely
and needed a power cycle.** The exact edge has not been pinned, deliberately —
finding it means wedging the machine again to no useful end. `UCI_NET_READ_MAX`
is 512, which has been verified with 700 bytes queued behind it, and
`ultimate_net_read()` will not ask for more however large a buffer it is given.

Writes are bounded by the SDK instead: the whole command must fit
`UCI_MAX_COMMAND_USABLE` (`$37F`), and `uci_exec()` answers
`ULTIMATE_ERR_INVALID_ARGUMENT` before anything reaches the wire.

### Interfaces are numbered from zero, and one of them may be idle

`NET_CMD_GET_INTERFACE_COUNT` reported 2 on the bench machine. Interface 1 was
the live Ethernet; interface 0 had a MAC address and an all-zero IP
configuration. **A count is not a list of usable interfaces** — ask
`NET_CMD_GET_IPADDR` and use the one with an address. An index past the count is
`82,PARAMETER(S) OUT OF RANGE`.

### The network stack is fragile, and the damage is not always immediate

On the bench machine, firmware 3.15, exercising this target took the Ultimate
off the network entirely three times. Each needed a power cycle; nothing was
written to flash and the machine came back clean every time.

| when | what preceded it |
|---|---|
| immediately | a read of 800-1023 bytes — inside the gap between the firmware's own range check and its response queue |
| about 15 minutes later | a socket probe that had completed cleanly and restored its settings |
| about 2 minutes later | a run that hung connecting the C64 **to the Ultimate's own address** |

Two of the three have a credible cause: a request the firmware accepts but
cannot buffer, and a connect that asks the stack to reach itself. The middle one
has no explanation. **What they share is socket traffic, and that the failure can
arrive minutes after the program that caused it has finished** — which makes it
easy to blame whatever happened to be running at the time.

Two consequences for anyone building on this:

- **Do not connect to the machine's own address.** The run that did hung in the
  connect and never returned. Whether it is refused, dropped, or merely slower
  than any sensible timeout was not established, and finding out costs a power
  cycle each attempt.
- `tests/hardware/ucitest.c` opens no socket unless it is given a peer
  (`NET_PEER=<dotted-quad>:<port>`), so the routine hardware run cannot trigger
  any of this. The interface count, the addresses and the argument checks all
  run without one, and they are what the harness asserts on.

### The listener commands stay unwrapped

`$12`-`$15` are marked `INFERRED`: their numbers are not in the published
specification. The generic form reaches them, so issuing one remains a
deliberate act rather than something the SDK appears to vouch for.

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
