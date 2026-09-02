# Software sprite experiment. make; make check (VICE); make run U64_HOST=<ip>
KICK ?= kickass
all: bobs16.prg bobs32.prg
bobs16.prg: bobs.asm
	$(KICK) bobs.asm :BOB_H=16 -o $@ -symbolfile && mv bobs.sym bobs16.sym
bobs32.prg: bobs.asm
	$(KICK) bobs.asm :BOB_H=32 -o $@ -symbolfile && mv bobs.sym bobs32.sym
blob:
	$(MAKE) -C ../../bindings/blob BASE=3400
check: all
	python3 vicecheck.py bobs16.prg bobs32.prg
	NBOBS=128 python3 vicecheck.py bobs16.prg
run: all
	@test -n "$(U64_HOST)" || { echo "U64_HOST is required"; exit 2; }
	python3 bobtest.py --host $(U64_HOST) --prg bobs16.prg --sweep --png hw16.png
clean:
	rm -f bobs16.prg bobs32.prg *.sym *-vice.png hw*.png
.PHONY: all blob check run clean
