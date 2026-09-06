# The Ultimate SDK Programmer's Reference Guide.
#
#   make          build guide.pdf
#   make clean    remove the build litter, keep the pdf
#   make distclean also remove the pdf
#
# Needs a TeX installation with tcolorbox, titlesec, avant and inconsolata -
# all of which ship with TeX Live and MacTeX.
#
# SPDX-License-Identifier: MIT

LATEXMK ?= latexmk
CL65    ?= cl65
CA65    ?= ca65
LD65    ?= ld65
PYTHON  ?= python3
VERSION ?= $(shell git -C .. describe --tags --always --dirty 2>/dev/null || echo unknown)
LIB     := ../bindings/cc65/build/ultimate.lib

all: check-reference check-examples guide.pdf

check-reference:
	$(PYTHON) ../tools/check_guide_reference.py

check-examples: examples/discover.prg examples/hello-c.prg examples/hello-asm.prg examples/hello-custom.prg examples/selective-c.prg examples/selective-asm.prg examples/c_calls.o examples/assembly_calls.o

$(LIB): FORCE
	$(MAKE) -C ../bindings/cc65

examples/discover.prg: examples/discover.c ../include/ultimate.h $(LIB) Makefile
	$(CL65) -t c64 -I ../include -m $(@:.prg=.map) -o $@ $< $(LIB)

examples/hello-c.prg: examples/hello.c ../include/ultimate.h $(LIB) Makefile
	$(CL65) -t c64 -I ../include -m $(@:.prg=.map) -o $@ $< $(LIB)

examples/hello-asm.prg: examples/hello.s ../bindings/asm/ultimate.inc $(LIB) Makefile
	$(CL65) -t c64 --asm-include-dir ../bindings/asm -m $(@:.prg=.map) -o $@ $< $(LIB)

../bindings/cc65/build-custom/ultimate.lib: FORCE
	$(MAKE) -C ../bindings/cc65 BUILD=build-custom \
	  ASM_DEFINES="-D UCI_VARS=52992 -D UCI_ZP=163"

examples/hello-custom.prg: examples/hello.s ../bindings/asm/ultimate.inc ../bindings/cc65/build-custom/ultimate.lib Makefile
	$(CL65) -t c64 --asm-include-dir ../bindings/asm -m $(@:.prg=.map) -o $@ $< ../bindings/cc65/build-custom/ultimate.lib

hardware: check-examples
	@test -n "$(U64_HOST)" || { echo "set U64_HOST=<Ultimate IP>"; exit 1; }
	$(MAKE) -C .. examples
	$(PYTHON) ../tools/check_hardware_examples.py --host $(U64_HOST)

examples/selective-c.prg: examples/selective.c ../include/ultimate.h $(LIB) Makefile
	$(CL65) -t c64 -I ../include -m $(@:.prg=.map) -o $@ $< $(LIB)

examples/selective.o: examples/selective.s $(wildcard ../bindings/asm/*.inc) Makefile
	$(CA65) -t c64 -I ../bindings/asm -o $@ $<

examples/selective-asm.prg: examples/selective.o examples/selective.cfg $(LIB) Makefile
	$(LD65) -C examples/selective.cfg -m $(@:.prg=.map) -o $@ $< $(LIB)

examples/c_calls.o: examples/c_calls.c ../include/ultimate.h ../include/uci.h
	$(CL65) -t c64 -I ../include -c -o $@ $<

examples/assembly_calls.o: examples/assembly_calls.s ../bindings/asm/ultimate.inc
	$(CA65) -I ../bindings/asm -o $@ $<

version.tex: FORCE
	@printf '\\newcommand{\\SDKVersion}{%s}\n' "$(VERSION)" > $@

guide.pdf: guide.tex version.tex ultimatesdk.sty $(wildcard chapters/*.tex) examples/selective.c examples/selective.s examples/selective.cfg
	$(LATEXMK) -pdf -interaction=nonstopmode -halt-on-error guide.tex

clean:
	$(LATEXMK) -c guide.tex
	rm -f *.aux *.log *.out *.toc *.idx *.ilg *.ind *.fls *.fdb_latexmk chapters/*.aux \
	  examples/*.o examples/*.prg examples/*.map version.tex

distclean: clean
	rm -f guide.pdf

FORCE:

.PHONY: all check-reference check-examples hardware clean distclean FORCE
