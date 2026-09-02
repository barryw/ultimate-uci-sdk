ROOT := ../..
KICK := kickass
PRG  := followme.prg
BLOB := $(ROOT)/bindings/blob/build/ultimate-7000.bin

$(BLOB):
	$(MAKE) -C $(ROOT)/bindings/blob

$(PRG): followme.asm lib/*.asm $(BLOB)
	$(KICK) followme.asm -o $@ -vicesymbols -bytedump -debugdump

check: $(PRG)
	python3 check.py

run: $(PRG)
	x64sc $(PRG)

clean:
	rm -f $(PRG) followme.sym followme.vs followme.dbg ByteDump.txt
