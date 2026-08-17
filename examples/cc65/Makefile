# cc65 example. Build the SDK library first (the rule below does it for you).
#
#   make          -> identify.prg
#
# SPDX-License-Identifier: MIT

ROOT   := ../..
TARGET ?= c64
CL65   ?= cl65

LIB    := $(ROOT)/bindings/cc65/build/ultimate.lib

all: identify.prg

$(LIB): FORCE
	$(MAKE) -C $(ROOT)/bindings/cc65 TARGET=$(TARGET)

identify.prg: identify.c $(LIB)
	$(CL65) -t $(TARGET) -Osir -I $(ROOT)/include -o $@ identify.c $(LIB)

clean:
	rm -f identify.prg identify.o

FORCE:

.PHONY: all clean FORCE
