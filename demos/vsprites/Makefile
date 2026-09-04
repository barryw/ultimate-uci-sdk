# Software sprites on an Ultimate 64: the vsprites demo.
#
#   make                       vsprites.prg (KickAssembler, and the SDK blob)
#   make check                 run it in VICE and write vsprites-vice.png
#   make run U64_HOST=<ip>     run it on an Ultimate and check the frame rate

ROOT   := ../..
KICK   ?= kickass
PYTHON ?= python3
PRG    := vsprites.prg
BLOB   := $(ROOT)/bindings/blob/build/ultimate-7000.bin

all: $(PRG)

$(BLOB): FORCE
	$(MAKE) -C $(ROOT)/bindings/blob

$(PRG): vsprites.asm $(BLOB)
	$(KICK) vsprites.asm -o $@ -symbolfile

check: $(PRG)
	rm -f vsprites-vice.png
	-x64sc -console -warp +sound -limitcycles 14000000 \
	  -exitscreenshot vsprites-vice.png -autostart $(PRG) >/dev/null 2>&1
	@test -s vsprites-vice.png

run: $(PRG)
	@test -n "$(U64_HOST)" || { echo "U64_HOST is required"; exit 2; }
	$(PYTHON) hwtest.py --host $(U64_HOST) --prg $(PRG) --png vsprites-hw.png

clean:
	rm -f $(PRG) vsprites.sym vsprites-vice.png vsprites-hw.png

FORCE:

.PHONY: all check run clean FORCE
