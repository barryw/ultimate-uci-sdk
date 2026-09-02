ROOT       := ../..
CL65       ?= cl65
PYTHON     ?= python3
BANK_PATH  ?= /usb1/logan-auditions.reu
START_INDEX ?= 0
PRG        := logan-comms.prg
SCREEN_PRG := logan-screen.prg
LIB        := $(ROOT)/bindings/cc65/build/ultimate.lib

all: $(PRG)

screen: $(SCREEN_PRG)

pack:
	$(PYTHON) generate_previews.py --pack-final-auditions

$(LIB): FORCE
	$(MAKE) -C $(ROOT)/bindings/cc65

$(PRG): player.c generate_previews.py comms.json pack $(LIB)
	$(CL65) -t c64 -Osir -W error \
		-D 'BANK_PATH="$(BANK_PATH)"' -D START_INDEX=$(START_INDEX) -I $(ROOT)/include \
		-m logan-comms.map -o $@ player.c $(LIB)

$(SCREEN_PRG): screen.c mux.s $(LIB)
	$(CL65) -t c64 -Osir -W error -I $(ROOT)/include \
		-m logan-screen.map -o $@ screen.c mux.s $(LIB)

clean:
	rm -f $(PRG) $(SCREEN_PRG) logan-comms.map logan-screen.map

FORCE:

.PHONY: all screen pack clean FORCE
