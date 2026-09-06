ROOT := ../..
CL65 ?= cl65
LIB := $(ROOT)/bindings/cc65/build/ultimate.lib

all: palette-timing.prg palette-raw.prg fmv-budget.prg

player.prg: player.c $(LIB)
	mkdir -p build
	$(CL65) -t c64 -Osir -I $(ROOT)/include -m build/player.map -o $@ $< $(LIB)

$(LIB):
	$(MAKE) -C $(ROOT)/bindings/cc65

palette-timing.prg: palette-timing.c $(LIB)
	$(CL65) -t c64 -Osir -I $(ROOT)/include -o $@ $< $(LIB)

palette-raw.prg: palette-raw.c
	$(CL65) -t c64 -Osir -o $@ $<

fmv-budget.prg: fmv-budget.c $(LIB)
	$(CL65) -t c64 -Osir -I $(ROOT)/include -o $@ $< $(LIB)

clean:
	rm -f palette-timing.o palette-timing.prg palette-raw.o palette-raw.prg \
		fmv-budget.o fmv-budget.prg player.o player.prg

.PHONY: all clean
