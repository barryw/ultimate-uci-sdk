# Boing ball. make (self-contained boing.prg);
# make check (VICE screenshots + status readback);
# make run U64_HOST=<ip> (FTP to /Temp, run from file, read the status block).
CA65   ?= ca65
LD65   ?= ld65
ROOT   := ../..
SAMPLE ?= $(if $(wildcard boing-orig8.pcm),boing-orig8.pcm 8363)
# SDK code remains at $8000, variables at $5900, below the fixed PCM pieces.
LIB    := $(ROOT)/bindings/cc65/build-boing/ultimate.lib

all: boing.prg

ball.bin disc.bin: genball.py
	python3 genball.py
bg.bin bgscr.bin shadow.bin: genbg.py
	python3 genbg.py
boing.pcm boing_pcm.inc: mkpcm.py genboing.py
	python3 mkpcm.py $(SAMPLE)

$(LIB): FORCE
	$(MAKE) -C $(ROOT)/bindings/cc65 BUILD=build-boing ASM_DEFINES="-D UCI_VARS=22784"

boing.o: boing.s ball.bin disc.bin bg.bin bgscr.bin shadow.bin boing.pcm boing_pcm.inc Makefile $(wildcard $(ROOT)/bindings/asm/*.inc)
	$(CA65) -g -I $(ROOT)/bindings/asm -o $@ boing.s

boing.prg: boing.o boing.cfg $(LIB) Makefile
	$(LD65) -C boing.cfg -m boing.map -Ln boing.lbl -o $@ boing.o $(LIB)

check: boing.prg
	python3 vicecheck.py

run: boing.prg
	@test -n "$(U64_HOST)" || { echo "U64_HOST is required"; exit 2; }
	python3 hwtest.py --host $(U64_HOST)

clean:
	rm -f boing.prg boing.o boing.map boing.lbl ball.bin disc.bin bg.bin bgscr.bin shadow.bin boing.pcm boing_pcm.inc \
	      preview*.png bg-preview.png vice-*.png

FORCE:
.PHONY: all check run clean FORCE
