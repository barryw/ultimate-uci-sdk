# Assembly example.
#
# Linked with cl65 for the examples' standard C64 startup. The SDK itself
# needs no C runtime; see docs/asm-abi.md for startup-free assembly callers.
# ultimate.lib selects only required SDK objects; the .map files show them.
#
# SPDX-License-Identifier: MIT

ROOT   := ../..
TARGET ?= c64
CL65   ?= cl65

LIB    := $(ROOT)/bindings/cc65/build/ultimate.lib

all: identify.prg sid-info.prg fileinfo.prg

$(LIB): FORCE
	$(MAKE) -C $(ROOT)/bindings/cc65 TARGET=$(TARGET)

identify.prg: identify.s $(LIB) Makefile
	$(CL65) -t $(TARGET) --asm-include-dir $(ROOT)/bindings/asm -m $(@:.prg=.map) -o $@ identify.s $(LIB)

sid-info.prg: sid-info.s $(LIB) Makefile
	$(CL65) -t $(TARGET) --asm-include-dir $(ROOT)/bindings/asm -m $(@:.prg=.map) -o $@ sid-info.s $(LIB)

fileinfo.prg: fileinfo.s $(LIB) Makefile
	$(CL65) -t $(TARGET) --asm-include-dir $(ROOT)/bindings/asm -m $(@:.prg=.map) -o $@ fileinfo.s $(LIB)

clean:
	rm -f identify.prg identify.o sid-info.prg sid-info.o fileinfo.prg fileinfo.o identify.map sid-info.map fileinfo.map

FORCE:

.PHONY: all clean FORCE
