# The SDK's modules, in one place.
#
# bindings/cc65 and bindings/blob both link the same library out of the same
# object files - the blob is not a port, it is these files linked differently.
# They used to keep two hand-written copies of this list, which meant a new
# module reached the library and silently never reached the blob. It is one
# list now, and both include it.
#
# UCI_SRC is relative to the repository root; each Makefile prefixes its own
# path to it.
#
# SPDX-License-Identifier: MIT

UCI_SRC := src/uci/uci_core.s \
           src/uci/ultimate.s \
           src/uci/palette.s \
           src/uci/dos.s \
           src/uci/file.s \
           src/uci/turbo.s \
           src/uci/reu.s \
           src/uci/ultimate_strerror.s \
           bindings/asm/ultimate_asm.s
