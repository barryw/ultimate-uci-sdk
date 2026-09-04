# Boing ball. make (self-contained boing.prg);
# make check (VICE screenshots + status readback);
# make run U64_HOST=<ip> (FTP to /Temp, run from file, read the status block).
KICK   ?= kickass
ROOT   := ../..
SAMPLE ?= $(if $(wildcard boing-orig8.pcm),boing-orig8.pcm 8363)
# The blob at $8000 with code below $ad30 and its variables in the free page at
# $5900. A separate build keeps the default blob untouched.
BLOB   := $(ROOT)/bindings/blob/build-boing/ultimate-8000.bin

all: boing.prg

ball.bin disc.bin: genball.py
	python3 genball.py
bg.bin bgscr.bin shadow.bin: genbg.py
	python3 genbg.py
boing.pcm boing_pcm.inc: mkpcm.py genboing.py
	python3 mkpcm.py $(SAMPLE)

$(BLOB): FORCE
	$(MAKE) -C $(ROOT)/bindings/blob BUILD=build-boing BASE=8000 VARS=22784 LIMIT=44336

boing.prg: boing.asm ball.bin disc.bin bg.bin bgscr.bin shadow.bin boing.pcm $(BLOB)
	$(KICK) boing.asm -o $@ -symbolfile

check: boing.prg
	python3 vicecheck.py

run: boing.prg
	@test -n "$(U64_HOST)" || { echo "U64_HOST is required"; exit 2; }
	python3 hwtest.py --host $(U64_HOST)

clean:
	rm -f boing.prg boing.sym ball.bin disc.bin bg.bin bgscr.bin shadow.bin boing.pcm \
	      preview*.png bg-preview.png vice-*.png

FORCE:
.PHONY: all check run clean FORCE
