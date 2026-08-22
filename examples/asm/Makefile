# Assembly example.
#
# Linked with cl65 so the program gets the standard c64 start-up code. That
# start-up is what initialises the C runtime the SDK core was compiled against;
# see docs/asm-abi.md if you need to link without it.
#
# SPDX-License-Identifier: MIT

ROOT   := ../..
TARGET ?= c64
CL65   ?= cl65

LIB    := $(ROOT)/bindings/cc65/build/ultimate.lib

all: identify.prg sid-info.prg fileinfo.prg

$(LIB): FORCE
	$(MAKE) -C $(ROOT)/bindings/cc65 TARGET=$(TARGET)

identify.prg: identify.s $(LIB)
	$(CL65) -t $(TARGET) --asm-include-dir $(ROOT)/bindings/asm -o $@ identify.s $(LIB)

sid-info.prg: sid-info.s $(LIB)
	$(CL65) -t $(TARGET) --asm-include-dir $(ROOT)/bindings/asm -o $@ sid-info.s $(LIB)

fileinfo.prg: fileinfo.s $(LIB)
	$(CL65) -t $(TARGET) --asm-include-dir $(ROOT)/bindings/asm -o $@ fileinfo.s $(LIB)

clean:
	rm -f identify.prg identify.o sid-info.prg sid-info.o fileinfo.prg fileinfo.o

FORCE:

.PHONY: all clean FORCE
