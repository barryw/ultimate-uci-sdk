# Machine Yearning six-voice palette visualizer for Ultimate hardware.

ROOT       := ../..
CL65       ?= cl65
PYTHON     ?= python3
TUNE       ?= 0
SID1       ?= 0
SID2       ?= 0
VERSION    ?= dev

LIB        := $(ROOT)/bindings/cc65/build/ultimate.lib
BUILD      := build
CORE       := $(BUILD)/visualizer-core.prg
SID        := Machine_Yearning_2SID.sid
PRG        := sid-visualizer.prg

all: $(PRG)

run: $(PRG)
	@test -n "$(U64_HOST)" || { echo "U64_HOST is required"; exit 2; }
	$(PYTHON) hwtest.py --host $(U64_HOST) --prg $(PRG)

$(LIB): FORCE
	$(MAKE) -C $(ROOT)/bindings/cc65

$(BUILD):
	mkdir -p $@

$(CORE): visualizer.c music_state.s visualizer.cfg $(LIB) | $(BUILD)
	$(CL65) -t c64 -C visualizer.cfg -Osir -W error \
		-D TUNE=$(TUNE) -D SID1_ADDRESS=$(SID1) -D SID2_ADDRESS=$(SID2) \
		-D 'SDK_VERSION="$(VERSION)"' \
		-I $(ROOT)/include -m $(BUILD)/visualizer.map \
		-o $@ visualizer.c music_state.s $(LIB)

$(PRG): pack.py $(SID) $(CORE)
	$(PYTHON) pack.py $(SID) $(CORE) $@

clean:
	rm -rf $(BUILD) $(PRG)

FORCE:

.PHONY: all run clean FORCE
