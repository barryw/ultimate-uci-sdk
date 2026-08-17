# The SDK as a standalone binary with a jump table.
#
#   make                      -> ultimate-c000.bin at $C000
#   make BASE=a000            -> ultimate-a000.bin at $A000
#   make VARS=53248 ZP=251    -> place the SDK's RAM elsewhere
#
# SPDX-License-Identifier: MIT

ROOT   := ../..
TARGET ?= c64
CA65   ?= ca65
LD65   ?= ld65

# Where the code goes, as four hex digits, and where its RAM goes, in decimal.
BASE ?= c000
VARS ?= 52992
ZP   ?= 251

AFLAGS := -t $(TARGET) -I $(ROOT)/bindings/asm -I $(ROOT)/src/uci \
          -D UCI_VARS=$(VARS) -D UCI_ZP=$(ZP)

SRC := $(ROOT)/src/uci/uci_core.s \
       $(ROOT)/src/uci/ultimate.s \
       $(ROOT)/src/uci/ultimate_strerror.s \
       $(ROOT)/bindings/asm/ultimate_asm.s \
       blob.s

BUILD := build
OBJ   := $(addprefix $(BUILD)/,$(notdir $(SRC:.s=.o)))

BIN := $(BUILD)/ultimate-$(BASE).bin

all: $(BIN)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/%.o: $(ROOT)/src/uci/%.s | $(BUILD)
	$(CA65) $(AFLAGS) -o $@ $<

$(BUILD)/ultimate_asm.o: $(ROOT)/bindings/asm/ultimate_asm.s | $(BUILD)
	$(CA65) $(AFLAGS) -o $@ $<

$(BUILD)/blob.o: blob.s | $(BUILD)
	$(CA65) $(AFLAGS) -o $@ $<

$(BUILD)/blob-$(BASE).cfg: blob.cfg.in | $(BUILD)
	sed 's/@BASE@/$$$(BASE)/' $< > $@

$(BIN): $(OBJ) $(BUILD)/blob-$(BASE).cfg
	$(LD65) -C $(BUILD)/blob-$(BASE).cfg -o $@ $(OBJ)

clean:
	rm -rf $(BUILD)

.PHONY: all clean
