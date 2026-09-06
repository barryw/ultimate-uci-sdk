ROOT := ../..
CA65 ?= ca65
LD65 ?= ld65
PRG  := followme.prg
# $a3-$a6 avoids the game's pseudo-registers and keyboard scratch zero page.
LIB := $(ROOT)/bindings/cc65/build-follow-me/ultimate.lib

all: $(PRG)

$(LIB): FORCE
	$(MAKE) -C $(ROOT)/bindings/cc65 BUILD=build-follow-me \
	  ASM_DEFINES="-D UCI_VARS=40704 -D UCI_ZP=163"

followme.o: followme.s $(wildcard lib/*.inc) Makefile $(wildcard $(ROOT)/bindings/asm/*.inc)
	$(CA65) -g -I $(ROOT)/bindings/asm -o $@ followme.s

$(PRG): followme.o followme.cfg $(LIB) Makefile
	$(LD65) -C followme.cfg -m followme.map -Ln followme.lbl -o $@ followme.o $(LIB)

check: $(PRG)
	python3 check.py

check-vice: check
	python3 $(ROOT)/tools/check_ca65_demos.py follow-me

run: $(PRG)
	x64sc $(PRG)

hardware: check
	@test -n "$(U64_HOST)" || { echo "set U64_HOST=<Ultimate IP>"; exit 1; }
	python3 hwtest.py --host $(U64_HOST)

clean:
	rm -f $(PRG) followme.o followme.map followme.lbl

FORCE:

.PHONY: all check check-vice run hardware clean FORCE
