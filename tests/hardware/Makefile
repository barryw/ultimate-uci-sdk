# Hardware tests: a C64 program that exercises the SDK against a real Ultimate.
#
#   make            -> ucitest.prg, ucitime.prg
#
# Copy ucitest.prg to your Ultimate and run it. Output is TAP on the C64 screen;
# see tests/README.md for capturing it. ucitime.prg answers a different
# question - how long a round trip takes - and is driven by `make time-run`.
#
# SPDX-License-Identifier: MIT

ROOT   := ../..
TARGET ?= c64
CL65   ?= cl65

LIB := $(ROOT)/bindings/cc65/build/ultimate.lib

all: ucitest.prg ucitime.prg

$(LIB): FORCE
	$(MAKE) -C $(ROOT)/bindings/cc65 TARGET=$(TARGET)

# The socket round trip needs something to talk to, and this file will not
# assume one exists - see the fixtures at the top of ucitest.c for what happened
# when it did. Give it a peer and those checks run; leave it out and they skip.
#
#   make NET_PEER=192.168.1.242:6464
#
# A dotted quad, not a name: cc65 charmaps source characters, and digits and
# '.' survive that unchanged where letters do not. The far end only has to
# accept a connection and send a byte.
ifdef NET_PEER
NET_DEFS := -DNET_PEER_HOST='"$(word 1,$(subst :, ,$(NET_PEER)))"' \
            -DNET_PEER_PORT=$(word 2,$(subst :, ,$(NET_PEER)))
endif

ucitest.prg: ucitest.c $(LIB)
	$(CL65) -t $(TARGET) -Osir -I $(ROOT)/include $(NET_DEFS) -o $@ ucitest.c $(LIB)

ucitime.prg: ucitime.c $(LIB)
	$(CL65) -t $(TARGET) -Osir -I $(ROOT)/include -o $@ ucitime.c $(LIB)

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

# How long a UCI round trip takes, measured on the machine itself.
#   make time-run U64_HOST=192.168.1.62
# Wrapped in the settings guard because the command interface is normally
# Disabled on the bench machine, and because this reads no settings of its own.
time-run: ucitime.prg
	@test -n "$(U64_HOST)" || { echo "set U64_HOST=<ip of your Ultimate>"; exit 1; }
	python3 $(ROOT)/tools/u64_settings.py --host $(U64_HOST) \
	    --require "C64 and Cartridge Settings:Command Interface=Enabled" \
	    -- python3 ucitime.py --host $(U64_HOST) $(UCITIME_ARGS)

clean:
	rm -f ucitest.prg ucitest.o ucitime.prg ucitime.o

FORCE:

.PHONY: all run basic-run time-run clean FORCE
