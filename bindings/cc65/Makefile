# cc65 binding: builds ultimate.lib for C and assembly callers.
#
#   make                 -> build/ultimate.lib
#   make TARGET=c128     -> same, for another cc65 target
#
# Link it into your program with:
#   cl65 -t c64 -I ../../include myprog.c build/ultimate.lib -o myprog.prg
#
# SPDX-License-Identifier: MIT

ROOT    := ../..
TARGET  ?= c64
BUILD   ?= build

CC65    ?= cc65
CA65    ?= ca65
AR65    ?= ar65

# -Osir turns on the optimiser plus inlining and register variables. The core
# is small and hot; this is what keeps it that way.
CFLAGS  := -t $(TARGET) -Osir -W error -I $(ROOT)/include -I $(ROOT)/src/uci
# ASM_DEFINES lets a caller place the SDK's memory:
#   make ASM_DEFINES="-D UCI_VARS=52992 -D UCI_ZP=163"    ($CF00, $A3)
# See docs/asm-abi.md. Cartridge projects need this; nothing else does.
ASM_DEFINES ?=
AFLAGS  := -t $(TARGET) -I $(ROOT)/bindings/asm -I $(ROOT)/src/uci -I $(BUILD) $(ASM_DEFINES)

# The protocol core is assembly; only the service layer is C.
# The whole SDK is assembly; the only C here is a build-time layout check.
CSRC    := abi_assert.c
ASRC    := $(ROOT)/src/uci/uci_core.s $(ROOT)/src/uci/ultimate.s \
           $(ROOT)/src/uci/ultimate_strerror.s \
           $(ROOT)/bindings/asm/ultimate_asm.s ultimate_cc65.s

COBJ    := $(addprefix $(BUILD)/,$(notdir $(CSRC:.c=.o)))
AOBJ    := $(addprefix $(BUILD)/,$(notdir $(ASRC:.s=.o)))

LIB     := $(BUILD)/ultimate.lib

all: $(LIB)

$(BUILD):
	mkdir -p $(BUILD)

# The generated protocol include lives in bindings/asm; ca65 needs it on its
# search path, which AFLAGS already covers.
$(BUILD)/%.o: $(ROOT)/src/uci/%.c | $(BUILD)
	$(CC65) $(CFLAGS) -o $(BUILD)/$*.s $<
	$(CA65) $(AFLAGS) -o $@ $(BUILD)/$*.s

$(BUILD)/abi_assert.o: abi_assert.c | $(BUILD)
	$(CC65) $(CFLAGS) -o $(BUILD)/abi_assert.s $<
	$(CA65) $(AFLAGS) -o $@ $(BUILD)/abi_assert.s

$(BUILD)/uci_core.o: $(ROOT)/src/uci/uci_core.s | $(BUILD)
	$(CA65) $(AFLAGS) -o $@ $<

$(BUILD)/ultimate.o: $(ROOT)/src/uci/ultimate.s | $(BUILD)
	$(CA65) $(AFLAGS) -o $@ $<

$(BUILD)/ultimate_strerror.o: $(ROOT)/src/uci/ultimate_strerror.s | $(BUILD)
	$(CA65) $(AFLAGS) -o $@ $<

$(BUILD)/ultimate_asm.o: $(ROOT)/bindings/asm/ultimate_asm.s | $(BUILD)
	$(CA65) $(AFLAGS) -o $@ $<

$(BUILD)/ultimate_cc65.o: ultimate_cc65.s | $(BUILD)
	$(CA65) $(AFLAGS) -o $@ $<

$(LIB): $(COBJ) $(AOBJ)
	rm -f $@
	$(AR65) a $@ $^

clean:
	rm -rf $(BUILD)

.PHONY: all clean
