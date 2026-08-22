# cc65 example. Build the SDK library first (the rule below does it for you).
#
#   make          -> identify.prg, sid-info.prg, files.prg
#
# SPDX-License-Identifier: MIT

ROOT   := ../..
TARGET ?= c64
CL65   ?= cl65

LIB    := $(ROOT)/bindings/cc65/build/ultimate.lib

all: identify.prg sid-info.prg files.prg

$(LIB): FORCE
	$(MAKE) -C $(ROOT)/bindings/cc65 TARGET=$(TARGET)

identify.prg: identify.c $(LIB)
	$(CL65) -t $(TARGET) -Osir -I $(ROOT)/include -o $@ identify.c $(LIB)

sid-info.prg: sid-info.c $(LIB)
	$(CL65) -t $(TARGET) -Osir -I $(ROOT)/include -o $@ sid-info.c $(LIB)

files.prg: files.c $(LIB)
	$(CL65) -t $(TARGET) -Osir -I $(ROOT)/include -o $@ files.c $(LIB)

clean:
	rm -f identify.prg identify.o sid-info.prg sid-info.o files.prg files.o

FORCE:

.PHONY: all clean FORCE
