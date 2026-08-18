# The BASIC wedge.
#
#   make            -> uci.prg
#
# LOAD "UCI",8 then RUN installs it. The .crt build comes with phase 2's
# cartridge target.
#
# SPDX-License-Identifier: MIT

ROOT   := ../..
CA65   ?= ca65
LD65   ?= ld65

ASMINC := $(ROOT)/bindings/asm

OBJS := loader.o wedge.o dispatch.o

all: uci.prg

%.o: %.s
	$(CA65) -t c64 -g -I . -I $(ASMINC) -o $@ $<

LIB := $(ROOT)/bindings/cc65/build/ultimate.lib

$(LIB):
	$(MAKE) -C $(ROOT)/bindings/cc65

uci.prg uci.lbl: $(OBJS) uci-wedge.cfg $(LIB)
	$(LD65) -C uci-wedge.cfg -o uci.prg -Ln uci.lbl $(OBJS) $(LIB)

clean:
	rm -f $(OBJS) uci.prg uci.lbl

.PHONY: all clean
