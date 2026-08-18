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

OBJS := loader.o wedge.o

all: uci.prg

%.o: %.s
	$(CA65) -t c64 -g -I . -I $(ASMINC) -o $@ $<

uci.prg uci.lbl: $(OBJS) uci-wedge.cfg
	$(LD65) -C uci-wedge.cfg -o uci.prg -Ln uci.lbl $(OBJS)

clean:
	rm -f $(OBJS) uci.prg uci.lbl

.PHONY: all clean
