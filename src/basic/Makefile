# The BASIC wedge, in both of its delivery forms.
#
#   make            -> uci.prg and uci.crt
#
#   uci.prg   LOAD "UCI",8 then RUN. BASIC keeps all 38K.
#   uci.crt   power on and it is there, and it survives a reset. Costs BASIC
#             10K, because the cartridge is mapped for as long as it is in.
#
# Both carry the same CODE and RODATA and copy them to the same $C000. The
# cartridge is a delivery mechanism, not a second implementation.
#
# SPDX-License-Identifier: MIT

ROOT   := ../..
CA65   ?= ca65
LD65   ?= ld65
VERSION ?= $(shell git -C $(ROOT) describe --tags --always --dirty 2>/dev/null || echo unknown)

ASMINC := $(ROOT)/bindings/asm

COMMON := install.o wedge.o dispatch.o bank.o

# The SDK runs at $A000 under BASIC ROM, so the wedge links a second flavour of
# the library whose code is in its own segment - see uci-wedge.cfg and bank.s.
# Same sources, same objects, one ca65 flag apart.
LIB    := $(ROOT)/bindings/cc65/build-banked/ultimate.lib

all: uci.prg uci.crt

# Every object here includes at least one generated table, and the tables are
# what the wedge *is*: the keyword list, the token numbers, the argument
# shapes. Without this line a regenerated include leaves the objects that only
# read it untouched, and the wedge ships half-knowing a keyword - the tokeniser
# missing it while dispatch handles it, or the other way round, with nothing in
# the build complaining.
GENERATED := $(ASMINC)/uci_protocol.inc $(ASMINC)/uci_keywords.inc \
             $(ASMINC)/uci_argtable.inc

%.o: %.s $(GENERATED) c64rom.inc
	$(CA65) -t c64 -g -I . -I $(ASMINC) -o $@ $<

version.inc: FORCE
	@printf '.define SDK_VERSION "%s"\n' "$(VERSION)" > $@

install.o: version.inc

$(LIB): FORCE
	$(MAKE) -C $(ROOT)/bindings/cc65 BUILD=build-banked \
	  ASM_DEFINES="-D UCI_BANKED"

uci.prg uci.lbl: loader.o $(COMMON) uci-wedge.cfg $(LIB)
	$(LD65) -C uci-wedge.cfg -o uci.prg -Ln uci.lbl loader.o $(COMMON) $(LIB)

uci-cart.bin uci-cart.lbl: cart.o $(COMMON) uci-cart.cfg $(LIB)
	$(LD65) -C uci-cart.cfg -o uci-cart.bin -Ln uci-cart.lbl cart.o $(COMMON) $(LIB)

uci.crt: uci-cart.bin
	python3 $(ROOT)/tools/make_crt.py uci-cart.bin uci.crt "ULTIMATE UCI WEDGE"

clean:
	rm -f loader.o cart.o $(COMMON) version.inc
	rm -rf $(ROOT)/bindings/cc65/build-banked
	rm -f uci.prg uci.lbl uci-cart.bin uci-cart.lbl uci.crt

FORCE:

.PHONY: all clean FORCE
