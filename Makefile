# Ultimate SDK.
#
#   make test        unit tests, then the SDK under sim6502 (Python 3, cc65, Docker)
#   make unittest    host-side Python unit tests only       (Python 3)
#   make lib         the cc65 library                      (cc65)
#   make blob        standalone binary with a jump table    (cc65)
#   make examples    the assembly and cc65 examples          (cc65)
#   make emulator    the same thing; test is an alias      (cc65, Docker)
#   make hardware    build the on-device test program      (cc65)
#   make hardware-run U64_HOST=<ip>   drive it over the REST API
#   make time-run U64_HOST=<ip>       time a UCI round trip in frames
#   make boing       build the self-contained Boing Ball PRG
#   make boing-run U64_HOST=<ip>      build and run it on an Ultimate
#   make protocol    regenerate the protocol constants     (Python 3)
#   make release VERSION=vX.Y.Z   package every release artifact
#   make all         everything that needs no hardware
#
# SPDX-License-Identifier: MIT

.DEFAULT_GOAL := test


all: lib examples emulator wedge demos

# The SDK itself is 6502 assembly, so the only place that logic can be tested
# is on a 6502 - that is what `emulator` is for. `unittest` covers the one
# piece of this repo that is ordinary host Python: the settings guard in
# tools/u64_settings.py. It needs neither Docker nor network, so adding it
# here does not change what `make test` depends on.
test: unittest emulator

# The wedge first: tools/test_make_crt.py compares the .prg and the cartridge
# byte for byte, and skips itself when they have not been built - which on a
# clean tree means the one test that guards "the cartridge is not a second
# implementation" would quietly never run.
unittest: wedge
	python3 -m unittest discover -s tools -p 'test_*.py'

lib:
	$(MAKE) -C bindings/cc65

# The SDK as a standalone binary with a jump table, for every toolchain that
# cannot link a ca65 object. See bindings/blob/README.md.
blob:
	$(MAKE) -C bindings/blob

# Two examples, because there are two ways in: a ca65 link and a cc65 link.
# Every other toolchain reaches the SDK through the standalone blob, which
# needs no linking and no example of its own beyond bindings/blob/README.md.
examples: lib
	$(MAKE) -C examples/asm
	$(MAKE) -C examples/cc65

demos: lib
	$(MAKE) -C demos/sid-visualizer

demo-run: lib
	$(MAKE) -C demos/sid-visualizer run U64_HOST=$(U64_HOST)

# Software sprites under turbo, through the standalone blob. KickAssembler,
# like demos/follow-me, so it is not part of `demos`.
#   make vsprites-run U64_HOST=192.168.1.62
vsprites: blob
	$(MAKE) -C demos/vsprites

vsprites-run: blob
	$(MAKE) -C demos/vsprites run U64_HOST=$(U64_HOST)

# The Boing ball uses its own blob layout, so its Makefile builds that directly.
#   make boing-run U64_HOST=192.168.1.62
boing:
	$(MAKE) -C demos/boing

boing-run:
	$(MAKE) -C demos/boing run U64_HOST=$(U64_HOST)

emulator: lib
	$(MAKE) -C tests/emulator run

hardware: lib
	$(MAKE) -C tests/hardware

# Run the hardware suite against a real Ultimate on the network.
#   make hardware-run U64_HOST=192.168.1.62
hardware-run: lib
	$(MAKE) -C tests/hardware run U64_HOST=$(U64_HOST)

# The BASIC wedge, typed at a real C64. Separate from hardware-run because it
# tests the wedge rather than the SDK, and because the wedge's tokeniser can
# only be reached by typing - which is why four bugs lived through a green
# emulator suite until this existed.
#   make basic-run U64_HOST=192.168.1.62
basic-run: wedge
	$(MAKE) -C tests/hardware basic-run U64_HOST=$(U64_HOST)

# How long a UCI round trip takes, measured on the machine itself. Not a test:
# it answers a design question, and the answer changes with the firmware.
#   make time-run U64_HOST=192.168.1.62
time-run: lib
	$(MAKE) -C tests/hardware time-run U64_HOST=$(U64_HOST)

# Regenerate include/uci_protocol.h, bindings/asm/uci_protocol.inc,
# bindings/asm/uci_argtable.inc, bindings/asm/uci_keywords.inc,
# bindings/kickass/uci_protocol.asm, bindings/acme/uci_protocol.a and the
# tables in the documentation. Run this after editing the protocol definition
# or the keyword set; never edit the generated files by hand.
protocol:
	python3 tools/gen_protocol.py
	python3 tools/gen_keywords.py
	python3 tools/gen_coverage.py

# The BASIC wedge .prg. LOAD "UCI",8 then RUN installs it.
wedge:
	$(MAKE) -C src/basic

# Fail when an SDK entry point has no test behind it.
coverage:
	python3 tools/gen_coverage.py --check

release: lib blob examples
	@test -n "$(VERSION)" || { echo "VERSION is required (for example v1.2.3)"; exit 2; }
	$(MAKE) -B -C src/basic VERSION="$(VERSION)"
	$(MAKE) -B -C guide VERSION="$(VERSION)"
	$(MAKE) -B -C demos/sid-visualizer VERSION="$(VERSION)"
	tools/package-release.sh "$(VERSION)"

clean:
	$(MAKE) -C src/basic clean
	$(MAKE) -C tests/emulator clean
	$(MAKE) -C tests/hardware clean
	$(MAKE) -C examples/asm clean
	$(MAKE) -C examples/cc65 clean
	$(MAKE) -C demos/sid-visualizer clean
	$(MAKE) -C bindings/cc65 clean
	$(MAKE) -C bindings/blob clean

.PHONY: all test unittest lib blob examples demos demo-run vsprites vsprites-run boing boing-run emulator hardware hardware-run \
		basic-run time-run protocol coverage release clean
