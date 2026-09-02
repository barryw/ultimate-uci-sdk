# Boing ball. make; make check (VICE screenshots + status readback);
# make run U64_HOST=<ip> (FTP to /Temp, run from file, read the status block).
KICK   ?= kickass
ROOT   := ../..
# The blob at $8000 with its variables at $a800, built into its own directory
# so the default $7000 build's objects (variables at $9f00) are not disturbed.
BLOB   := $(ROOT)/bindings/blob/build-boing/ultimate-8000.bin

all: boing.prg

ball.bin disc.bin: genball.py
	python3 genball.py
bg.bin bgscr.bin shadow.bin: genbg.py
	python3 genbg.py
boing.pcm boing_pcm.inc: mkpcm.py genboing.py
	python3 mkpcm.py $(SAMPLE)

$(BLOB): FORCE
	$(MAKE) -C $(ROOT)/bindings/blob BUILD=build-boing BASE=8000 VARS=43008

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
