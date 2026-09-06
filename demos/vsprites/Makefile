# Software sprites on an Ultimate 64: the vsprites demo.
#
#   make                       vsprites.prg (ca65, selective SDK archive link)
#   make check                 check moving vsprites in VICE
#   make run U64_HOST=<ip>     run it on an Ultimate and check the frame rate

ROOT   := ../..
CA65   ?= ca65
LD65   ?= ld65
PYTHON ?= python3
PRG    := vsprites.prg
LIB    := $(ROOT)/bindings/cc65/build/ultimate.lib

all: $(PRG)

$(LIB): FORCE
	$(MAKE) -C $(ROOT)/bindings/cc65

build/shapes.bin: gen_shapes.py
	$(PYTHON) gen_shapes.py

vsprites.o: vsprites.s build/shapes.bin Makefile $(wildcard $(ROOT)/bindings/asm/*.inc)
	$(CA65) -g -I $(ROOT)/bindings/asm -o $@ vsprites.s

$(PRG): vsprites.o vsprites.cfg $(LIB) Makefile
	$(LD65) -C vsprites.cfg -m vsprites.map -Ln vsprites.lbl -o $@ vsprites.o $(LIB)

check: $(PRG)
	$(PYTHON) $(ROOT)/tools/check_ca65_demos.py vsprites

run: $(PRG)
	@test -n "$(U64_HOST)" || { echo "U64_HOST is required"; exit 2; }
	$(PYTHON) hwtest.py --host $(U64_HOST) --prg $(PRG) --png vsprites-hw.png

clean:
	rm -f $(PRG) vsprites.o vsprites.map vsprites.lbl build/shapes.bin vsprites-vice.png vsprites-hw.png

FORCE:

.PHONY: all check run clean FORCE
