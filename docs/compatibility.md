# Compatibility

The SDK's position: **old Ultimate hardware stays valuable and stays supported.**
New machines get extra capabilities. Nothing gets an incompatible ecosystem.

## Verified on

| Machine | Firmware | Result |
|---|---|---|
| Ultimate 64 Elite | 3.15 (FPGA 123, core 1.4E) | `protocol.suite` 9/9, `ucitest.prg` 0 failed — 45 passed and 4 skipped with no peer built in, 68 passed with the socket and HTTP peers |

Everything else in this document comes from the firmware and FPGA sources rather
than from a machine on a bench. Reports from other hardware are welcome.

## Hardware

The command interface exists on every Ultimate product from the 1541 Ultimate-II
through to the Commodore 64 Ultimate, at the same five addresses, speaking the
same protocol. The SDK's foundation layer targets all of them.

| Machine | Command interface | Notes |
|---|---|---|
| 1541 Ultimate-II | yes | oldest supported |
| 1541 Ultimate-II+ / II+L | yes | |
| Ultimate 64 | yes | `CTRL_CMD_U64_SAVEMEM` and turbo modes |
| Ultimate 64 Elite / Elite-II | yes | |
| Commodore 64 Ultimate | yes | up to 48 MHz; more RAM |

Nothing in the SDK requires a machine newer than a 1541 Ultimate-II.

## The first compatibility question is not the model

It is whether the interface is switched on at all.

Mapping the `$DF1B-$DF1F` block into I/O space is optional and is enabled in the
Ultimate's **Command Interface** configuration menu. With it off, the registers
do not answer, and an Ultimate is indistinguishable from no Ultimate.

So `ULTIMATE_ERR_NO_DEVICE` is a normal outcome, not a crash, and it is worth
telling the user what to do about it:

```c
if (ultimate_init() != ULTIMATE_OK) {
    puts("no ultimate command interface.");
    puts("enable it in the ultimate settings menu.");
    return 1;
}
```

## Detection

Two steps, cheap then thorough.

**The signature.** `$DF1D` reads `$C9`, or `$49` while an interrupt is pending —
bit 7 is the inverted IRQ line. `uci_signature_present()` masks that bit off
before comparing. Gideon's own kernal compares against `$C9` exactly, which is
correct in a context where the IRQ feature is never enabled, but a library
cannot assume that about its caller.

The value is distinctive: an unmapped I/O2 address returns open bus, and a real
REU returns `$FF` from its unimplemented registers.

**The functional check.** `ultimate_init()` aborts and clears the state error,
which both verifies the device is answering and recovers whatever the previous
program left behind. A signature with no working transport returns
`ULTIMATE_ERR_TIMEOUT` rather than pretending.

## Firmware

The interface has grown targets over time. Probe, do not assume.

| Firmware | What arrived |
|---|---|
| 2.6 | command interface; Ultimate DOS on targets `$01` and `$02` |
| 3.0 | `DOS_CMD_COPY_UI_PATH` deprecated, answers `99,FUNCTION NOT IMPLEMENTED` |
| 3.x | network (`$03`), control (`$04`), SoftwareIEC (`$05`) targets |
| 3.15 | HTTP target (`$06`); IRQ-on-completion; `CTRL_CMD_GET_HWINFO` sub-command optional |
| after 3.15 | runtime palette commands `$51`-`$54` on the control target |

```c
ultimate_capabilities caps;
ultimate_detect(&caps);

if (ultimate_has_http(&caps))    { /* firmware 3.15 or newer */ }
if (ultimate_has_network(&caps)) { /* raw sockets available */ }
```

This costs one UCI round trip per target, so call it once at start-up and keep
the result.

Two things worth knowing about what the probe reports:

- **`ultimate_has_softiec()` does not track the IEC Drive setting, by design.**
  The documentation says every SoftwareIEC command returns `$05 IEC MODULE NOT
  LOADED` when no emulated drive sits behind the interface, which would make the
  target probe reflect whether the drive is switched on. It does not: target
  `$05` identifies itself and serves commands with the IEC Drive setting
  disabled, and
  [GideonZ/1541ultimate#794](https://github.com/GideonZ/1541ultimate/issues/794)
  settles that this is intended and permanent. Disabling the drive takes it off
  the *IEC bus*; UCI is a separate path to the same code, and it is the path the
  hyperspeed kernal uses.

  The useful consequence: **a program driving SoftwareIEC over UCI does not need
  the user to enable the IEC drive first.** `ultimate_has_softiec()` means "this
  firmware has the target", which is the thing you actually need to know. Still
  fall back on a command failing rather than on the probe — the probe cannot see
  a mounted image, a valid path, or a full disk.
- **`ultimate_get_model()` is for humans.** It reads `CTRL_CMD_GET_HWINFO`,
  which needs the control target and returns mixed-case strings —
  `Ultimate 64 Elite`, `Ultimate II+`, `Ultimate 64-II`. Note the case: unlike
  the uppercase identification strings, this one renders as graphics glyphs if
  you send it straight to the screen. Use it in a bug report or a splash screen.
  Do not branch on it: an Ultimate-II+ on current firmware can do more than an
  Ultimate 64 on old firmware.

## CPU speed

This is the compatibility problem most likely to bite, and it has nothing to do
with the protocol.

There is no timer the SDK can safely borrow — a game owns the CIAs and the
raster — so waits are counted in status polls. A poll takes a fixed number of
cycles, which means the wall-clock budget scales with the clock:

| Machine | Clock | Roughly, at the default budget |
|---|---|---|
| Ultimate-II+ in a stock C64 | 1 MHz | about 1.5 s |
| Ultimate 64 | up to 8 MHz | about 200 ms |
| Commodore 64 Ultimate | up to 48 MHz | about 30 ms |

The default (`UCI_TIMEOUT_DEFAULT`) is comfortable for the local commands: file
operations, directory listings, identification. It is *not* comfortable for a
network or HTTP command on a fast machine.

```c
uci_set_timeout(UCI_TIMEOUT_FOREVER);       /* an HTTP GET can take seconds */
err = ultimate_http_get(...);
uci_set_timeout(UCI_TIMEOUT_DEFAULT);
```

Services that wait on the outside world will do this for you. Until they exist,
do it yourself.

## Interoperating with the REU

The command interface overlays the last five REU registers. The REU proper uses
`$DF00-$DF0A`, so the two coexist — but a program that pokes the whole
`$DF00-$DF1F` range as if it were one device will disturb the interface.

The SDK touches `$DF1B-$DF1F` for the command interface, and `$DF00-$DF0A` in
`src/uci/reu.s` alone, where driving the REU is the whole point — there is no
UCI command that moves bytes between C64 RAM and the expansion. Nothing else in
the range is written from anywhere. `tools/test_registers.py` asserts both
halves of that: no `$DFxx` literal exists in the SDK at all, and the REU
register names appear in `reu.s` and in no other file.

## Where the SDK is stricter than the documentation

Two places where following the published protocol literally will hurt you, both
covered in [uci.md](uci.md):

- **Commands are capped at 895 bytes**, not the documented 896. The command
  write pointer saturates on the last byte of the buffer, so a 896th byte
  overwrites the 895th and the firmware is told the command was 895 bytes long.
  The SDK rejects the oversized command instead of sending a corrupted one.
- **Queue reads are bounded.** A reply that exactly fills the 896-byte response
  queue leaves the data-available bit set permanently. `while (DATA_AV) read`
  never returns. The SDK reads at most one queue's worth, which is both correct
  and terminating.

## Known upstream issues

- `CTRL_CMD_LOAD_REU` (`$04 $08`) never returns on firmware 3.14d and wedges the
  command interface until the cartridge is power-cycled
  ([GideonZ/1541ultimate#740](https://github.com/GideonZ/1541ultimate/issues/740)).
  The SDK's timeout means your program recovers, but the Ultimate does not.
  Avoid it on that firmware.
- `CTRL_CMD_FREEZE` completes only after the user leaves the menu, so the
  acknowledgement can be arbitrarily delayed. Send it with
  `UCI_TARGET_NO_REPLY`.
- `CTRL_CMD_REBOOT` resets the C64 and the interface with it. There is no reply,
  by design.
- The SoftwareIEC target answers `SOFTIEC_CMD_IDENTIFY` with the firmware's
  shared ASCII status `00,OK`, while every other command on that target answers
  with a single binary status byte. A decoder that picks its status format from
  the target ID alone reads the `'0'` of `00,OK` as binary `$30` and fails the
  one command that cannot fail. The SDK handles both — see [uci.md](uci.md),
  "Status encodings".
- Target availability is not retracted at runtime. Switching a subsystem on
  makes its target appear to a probe; switching it off again does not make it
  disappear within the same power cycle.
