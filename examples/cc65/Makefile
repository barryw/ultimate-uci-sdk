# cc65 examples. Refresh ultimate.lib before linking only the SDK objects each
# program needs. The .map files show the selected archive members.
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

identify.prg: identify.c $(LIB) Makefile
	$(CL65) -t $(TARGET) -Osir -I $(ROOT)/include -m $(@:.prg=.map) -o $@ identify.c $(LIB)

sid-info.prg: sid-info.c $(LIB) Makefile
	$(CL65) -t $(TARGET) -Osir -I $(ROOT)/include -m $(@:.prg=.map) -o $@ sid-info.c $(LIB)

files.prg: files.c $(LIB) Makefile
	$(CL65) -t $(TARGET) -Osir -I $(ROOT)/include -m $(@:.prg=.map) -o $@ files.c $(LIB)

clean:
	rm -f identify.prg identify.o sid-info.prg sid-info.o files.prg files.o identify.map sid-info.map files.map

FORCE:

.PHONY: all clean FORCE
