# Disk-streamed Ultimate Audio demo.

ROOT       := ../..
CL65       ?= cl65
PYTHON     ?= python3
VERSION    ?= dev
WAV_PATH   ?= /usb1/hall22.wav
PRG        := pcm-visualizer.prg
LIB        := $(ROOT)/bindings/cc65/build/ultimate.lib

all: $(PRG)

$(LIB): FORCE
	$(MAKE) -C $(ROOT)/bindings/cc65

$(PRG): visualizer.c $(LIB)
	$(CL65) -t c64 -Osir -W error \
		-D 'SDK_VERSION="$(VERSION)"' -D 'WAV_PATH="$(WAV_PATH)"' \
		-I $(ROOT)/include \
		-m pcm-visualizer.map -o $@ visualizer.c $(LIB)

run: $(PRG)
	@test -n "$(U64_HOST)" || { echo "U64_HOST is required"; exit 2; }
	$(PYTHON) hwtest.py --host $(U64_HOST) --prg $(PRG)

clean:
	rm -f $(PRG) pcm-visualizer.map

FORCE:

.PHONY: all run clean FORCE
