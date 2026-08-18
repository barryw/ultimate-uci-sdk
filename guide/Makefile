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

all: guide.pdf

guide.pdf: guide.tex ultimatesdk.sty $(wildcard chapters/*.tex)
	$(LATEXMK) -pdf -interaction=nonstopmode -halt-on-error guide.tex

clean:
	$(LATEXMK) -c guide.tex
	rm -f *.aux *.log *.out *.toc *.fls *.fdb_latexmk chapters/*.aux

distclean: clean
	rm -f guide.pdf

.PHONY: all clean distclean
