# Oscar64 example.
#
#   make OSCAR64=/path/to/oscar64
#
# SPDX-License-Identifier: MIT

include ../../bindings/oscar64/ultimate.mk

all: identify.prg

identify.prg: identify.c $(ULTIMATE_SRC)
	$(OSCAR64) $(ULTIMATE_INC) -tm=c64 -O2 -o=$@ identify.c $(ULTIMATE_SRC)

clean:
	rm -f identify.prg identify.map identify.asm identify.lbl identify.int identify.dbj

.PHONY: all clean
