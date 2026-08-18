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

ASMINC := $(ROOT)/bindings/asm

COMMON := install.o wedge.o dispatch.o
LIB    := $(ROOT)/bindings/cc65/build/ultimate.lib

all: uci.prg uci.crt

%.o: %.s
	$(CA65) -t c64 -g -I . -I $(ASMINC) -o $@ $<

$(LIB):
	$(MAKE) -C $(ROOT)/bindings/cc65

uci.prg uci.lbl: loader.o $(COMMON) uci-wedge.cfg $(LIB)
	$(LD65) -C uci-wedge.cfg -o uci.prg -Ln uci.lbl loader.o $(COMMON) $(LIB)

uci-cart.bin uci-cart.lbl: cart.o $(COMMON) uci-cart.cfg $(LIB)
	$(LD65) -C uci-cart.cfg -o uci-cart.bin -Ln uci-cart.lbl cart.o $(COMMON) $(LIB)

uci.crt: uci-cart.bin
	python3 $(ROOT)/tools/make_crt.py uci-cart.bin uci.crt "ULTIMATE UCI WEDGE"

clean:
	rm -f loader.o cart.o $(COMMON)
	rm -f uci.prg uci.lbl uci-cart.bin uci-cart.lbl uci.crt

.PHONY: all clean
