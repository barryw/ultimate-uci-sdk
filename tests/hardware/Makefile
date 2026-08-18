# Hardware tests: a C64 program that exercises the SDK against a real Ultimate.
#
#   make            -> ucitest.prg
#
# Copy it to your Ultimate and run it. Output is TAP on the C64 screen; see
# tests/README.md for capturing it.
#
# SPDX-License-Identifier: MIT

ROOT   := ../..
TARGET ?= c64
CL65   ?= cl65

LIB := $(ROOT)/bindings/cc65/build/ultimate.lib

all: ucitest.prg

$(LIB): FORCE
	$(MAKE) -C $(ROOT)/bindings/cc65 TARGET=$(TARGET)

ucitest.prg: ucitest.c $(LIB)
	$(CL65) -t $(TARGET) -Osir -I $(ROOT)/include -o $@ ucitest.c $(LIB)

# Drive the settings matrix against a real Ultimate over its REST API.
#   make run U64_HOST=192.168.1.62
run: ucitest.prg
	@test -n "$(U64_HOST)" || { echo "set U64_HOST=<ip of your Ultimate>"; exit 1; }
	python3 hwtest.py --host $(U64_HOST) $(HWTEST_ARGS)

# The BASIC wedge, typed at a real C64.
#   make basic-run U64_HOST=192.168.1.62
# Both deliveries, one after the other. The .crt runs the same checks as the
# .prg, which is the only way to show the cartridge is a delivery mechanism
# rather than a second implementation.
basic-run:
	@test -n "$(U64_HOST)" || { echo "set U64_HOST=<ip of your Ultimate>"; exit 1; }
	$(MAKE) -C $(ROOT)/src/basic
	python3 basictest.py --host $(U64_HOST) $(BASICTEST_ARGS)
	python3 basictest.py --host $(U64_HOST) --crt $(BASICTEST_ARGS)

clean:
	rm -f ucitest.prg ucitest.o

FORCE:

.PHONY: all run basic-run clean FORCE
