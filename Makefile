# Ultimate SDK.
#
#   make test        the SDK under sim6502                 (cc65, Docker)
#   make lib         the cc65 library                      (cc65)
#   make examples    assembly, cc65 and Oscar64 examples   (cc65, Oscar64)
#   make emulator    the same thing; test is an alias      (cc65, Docker)
#   make hardware    build the on-device test program      (cc65)
#   make hardware-run U64_HOST=<ip>   drive it over the REST API
#   make protocol    regenerate the protocol constants     (Python 3)
#   make all         everything that needs no hardware
#
# SPDX-License-Identifier: MIT

.DEFAULT_GOAL := test

# Point this at your oscar64 binary to include the Oscar64 example.
OSCAR64 ?= oscar64

all: lib examples emulator

# There is no host test layer: the SDK is 6502 assembly, so the only place its
# logic can be tested is on a 6502. `make test` runs the emulator suites.
test: emulator

lib:
	$(MAKE) -C bindings/cc65

# The Oscar64 example is not built. bindings/oscar64/ultimate.mk lists the C
# core that the assembly rewrite replaced, so the binding has to be redone -
# and docs/handover.md says not to, until the service API has settled. Building
# it conditionally on the compiler being installed only hid that.
examples: lib
	$(MAKE) -C examples/asm
	$(MAKE) -C examples/cc65

emulator: lib
	$(MAKE) -C tests/emulator run

hardware: lib
	$(MAKE) -C tests/hardware

# Run the hardware suite against a real Ultimate on the network.
#   make hardware-run U64_HOST=192.168.1.62
hardware-run: lib
	$(MAKE) -C tests/hardware run U64_HOST=$(U64_HOST)

# Regenerate include/uci_protocol.h, bindings/asm/uci_protocol.inc,
# bindings/kickass/uci_protocol.asm, bindings/acme/uci_protocol.a and the
# constant tables in the documentation. Run this after editing the protocol
# definition; never edit the generated files by hand.
protocol:
	python3 tools/gen_protocol.py
	python3 tools/gen_coverage.py

# Fail when an SDK entry point has no test behind it.
coverage:
	python3 tools/gen_coverage.py --check

clean:
	$(MAKE) -C tests/emulator clean
	$(MAKE) -C tests/hardware clean
	$(MAKE) -C examples/asm clean
	$(MAKE) -C examples/cc65 clean
	$(MAKE) -C examples/oscar64 clean
	$(MAKE) -C bindings/cc65 clean

.PHONY: all test lib examples emulator hardware hardware-run protocol coverage clean
