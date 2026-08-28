# The SDK as a standalone binary with a jump table.
#
#   make                      -> ultimate-7000.bin at $7000
#   make BASE=6000            -> ultimate-6000.bin at $6000
#   make VARS=53248 ZP=251    -> place the SDK's RAM elsewhere
#
# SPDX-License-Identifier: MIT

ROOT   := ../..
TARGET ?= c64
CA65   ?= ca65
LD65   ?= ld65

# Where the code goes, as four hex digits, and where its RAM goes, in decimal.
#
# **The default is $7000, because the SDK no longer fits in the 8K at $8000.**
# It was $C000 until file.s landed and overflowed the 4K there, and $8000 until
# the DOS, disk, clock, machine and HTTP body services landed and overflowed the
# 8K. The link fails rather than overlapping the variables, which is what
# blob.cfg.in is for.
#
# The blob has to sit below $A000, because $A000-$BFFF is BASIC ROM: a caller
# reaches every byte of a blob at $7000 with the machine exactly as it found it,
# and would have to bank for one that ran past $A000. That is the difference
# between the blob and the BASIC wedge, which does put its SDK under BASIC ROM
# and pays a stub per call for it - the wedge can bank, because the wedge is the
# only thing calling. A blob's caller cannot be asked to.
#
# $7000 is inside BASIC's own memory, not above it: BASIC has $0801-$9FFF unless
# it is told otherwise. A program that leaves BASIC running has to lower the top
# of memory to the base address before loading the blob. README.md says how.
#
# Everything here is still a link-time choice. Build it anywhere there is room:
#   make BASE=6000                 lower, for a program that wants $7000
#   make BASE=6000 VARS=36864      wherever suits the program using it
BASE ?= 7000
VARS ?= 40704
ZP   ?= 251

AFLAGS := -t $(TARGET) -I $(ROOT)/bindings/asm -I $(ROOT)/src/uci \
          -D UCI_VARS=$(VARS) -D UCI_ZP=$(ZP)

# The module list is shared with bindings/cc65 - see src/uci/sources.mk. The
# blob is not a port: it is the library's own object files linked differently,
# so the two must never be able to drift apart.
include $(ROOT)/src/uci/sources.mk

SRC := $(addprefix $(ROOT)/,$(UCI_SRC)) blob.s

BUILD := build
OBJ   := $(addprefix $(BUILD)/,$(notdir $(SRC:.s=.o)))

BIN := $(BUILD)/ultimate-$(BASE).bin

# The relocation table comes from diffing two builds one page apart. Nothing
# here knows anything about 6502 addressing modes; see tools/gen_reloc.py.
PROBE_BASE := $(shell printf '%04x' $$(( 0x$(BASE) + 0x100 )))

RELOC := $(BUILD)/ultimate-$(BASE).reloc

all: $(BIN) $(RELOC) $(BUILD)/ultimate-6000.bin

$(BUILD):
	mkdir -p $(BUILD)

# Makefile, because -D UCI_VARS is baked into every object: changing VARS has to
# rebuild them, or the code keeps addressing the variables where they used to be
# and every command comes back INVALID_ARGUMENT.
$(BUILD)/%.o: $(ROOT)/src/uci/%.s Makefile | $(BUILD)
	$(CA65) $(AFLAGS) -o $@ $<

$(BUILD)/ultimate_asm.o: $(ROOT)/bindings/asm/ultimate_asm.s Makefile | $(BUILD)
	$(CA65) $(AFLAGS) -o $@ $<

$(BUILD)/blob.o: blob.s Makefile | $(BUILD)
	$(CA65) $(AFLAGS) -o $@ $<

# Where the code may run to: the start of the SDK's variables, less the header
# and parameter pages that sit in front of it. ld65 then refuses a build whose
# code would reach the variables instead of quietly producing one that does.
MAINSIZE = $(shell printf '$$%04x' $$(( $(VARS) - 0x$(BASE) - 0x300 )))

$(BUILD)/blob-$(BASE).cfg: blob.cfg.in Makefile | $(BUILD)
	sed -e 's/@BASE@/$$$(BASE)/' -e 's/@MAINSIZE@/$(MAINSIZE)/' $< > $@

# The size is reported rather than written down anywhere, because a byte count
# in a document is wrong the next time a service is added - and this one has
# been wrong twice already.
$(BIN): $(OBJ) $(BUILD)/blob-$(BASE).cfg
	$(LD65) -C $(BUILD)/blob-$(BASE).cfg -o $@ $(OBJ)
	@echo "$@: $$(wc -c < $@) bytes at \$$$(BASE), variables at $(VARS)"

$(BUILD)/probe-$(PROBE_BASE).cfg: blob.cfg.in Makefile | $(BUILD)
	sed -e 's/@BASE@/$$$(PROBE_BASE)/' -e 's/@MAINSIZE@/$(MAINSIZE)/' $< > $@

$(BUILD)/ultimate-$(PROBE_BASE).bin: $(OBJ) $(BUILD)/probe-$(PROBE_BASE).cfg
	$(LD65) -C $(BUILD)/probe-$(PROBE_BASE).cfg -o $@ $(OBJ)

$(RELOC): $(BIN) $(BUILD)/ultimate-$(PROBE_BASE).bin
	python3 $(ROOT)/tools/gen_reloc.py $(BIN) \
	  $(BUILD)/ultimate-$(PROBE_BASE).bin $@

# A second full blob, linked at $6000 rather than $(BASE). This is the ground
# truth tests/emulator/blob-relocated.suite compares a runtime-relocated copy
# against: the relocator's output must be byte-identical to what the linker
# itself produces for that address. Same objects, different config - same
# pattern as the probe build above.
$(BUILD)/blob-6000.cfg: blob.cfg.in Makefile | $(BUILD)
	sed -e 's/@BASE@/$$6000/' -e 's/@MAINSIZE@/$(MAINSIZE)/' $< > $@

$(BUILD)/ultimate-6000.bin: $(OBJ) $(BUILD)/blob-6000.cfg
	$(LD65) -C $(BUILD)/blob-6000.cfg -o $@ $(OBJ)

clean:
	rm -rf $(BUILD)

.PHONY: all clean
