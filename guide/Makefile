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
PYTHON  ?= python3
VERSION ?= $(shell git -C .. describe --tags --always --dirty 2>/dev/null || echo unknown)
LIB     := ../bindings/cc65/build/ultimate.lib

all: check-reference check-examples guide.pdf

check-reference:
	$(PYTHON) ../tools/check_guide_reference.py

check-examples: examples/discover.prg examples/hello-c.prg examples/hello-asm.prg examples/c_calls.o examples/assembly_calls.o

$(LIB):
	$(MAKE) -C ../bindings/cc65

examples/discover.prg: examples/discover.c ../include/ultimate.h $(LIB)
	$(CL65) -t c64 -I ../include -o $@ $< $(LIB)

examples/hello-c.prg: examples/hello.c ../include/ultimate.h $(LIB)
	$(CL65) -t c64 -I ../include -o $@ $< $(LIB)

examples/hello-asm.prg: examples/hello.s ../bindings/asm/ultimate.inc $(LIB)
	$(CL65) -t c64 --asm-include-dir ../bindings/asm -o $@ $< $(LIB)

examples/c_calls.o: examples/c_calls.c ../include/ultimate.h ../include/uci.h
	$(CL65) -t c64 -I ../include -c -o $@ $<

examples/assembly_calls.o: examples/assembly_calls.s ../bindings/asm/ultimate.inc
	$(CA65) -I ../bindings/asm -o $@ $<

version.tex: FORCE
	@printf '\\newcommand{\\SDKVersion}{%s}\n' "$(VERSION)" > $@

guide.pdf: guide.tex version.tex ultimatesdk.sty $(wildcard chapters/*.tex)
	$(LATEXMK) -pdf -interaction=nonstopmode -halt-on-error guide.tex

clean:
	$(LATEXMK) -c guide.tex
	rm -f *.aux *.log *.out *.toc *.idx *.ilg *.ind *.fls *.fdb_latexmk chapters/*.aux \
	  examples/*.o examples/*.prg version.tex

distclean: clean
	rm -f guide.pdf

FORCE:

.PHONY: all check-reference check-examples clean distclean FORCE
