# Oscar64 binding. BROKEN - do not use yet.
#
# The three sources below are the C core that the assembly rewrite replaced;
# src/uci is 6502 now, and Oscar64 cannot link ca65 objects. Making this work
# again needs either an Oscar64 core held to tests/emulator, or a relocatable
# binary with a jump table. docs/handover.md says to leave it until the service
# API has settled, because every port multiplies the cost of an API change.
#
# Oscar64 compiles and links a whole program in one pass - there is no object
# librarian to hand it a .lib - so the binding is a list of sources and the
# include paths that go with them. Add them to your own oscar64 command line:
#
#     include ../../bindings/oscar64/ultimate.mk
#
#     game.prg: game.c $(ULTIMATE_SRC)
#         $(OSCAR64) $(ULTIMATE_INC) -tm=c64 -o=$@ game.c $(ULTIMATE_SRC)
#
# The sources are the same ones cc65 and llvm-mos compile. There is no
# Oscar64-specific copy of the protocol to fall behind.
#
# SPDX-License-Identifier: MIT

ULTIMATE_ROOT ?= $(dir $(lastword $(MAKEFILE_LIST)))../..

ULTIMATE_SRC := \
	$(ULTIMATE_ROOT)/src/uci/uci_core.c \
	$(ULTIMATE_ROOT)/src/uci/uci_status.c \
	$(ULTIMATE_ROOT)/src/uci/ultimate.c

ULTIMATE_INC := -i=$(ULTIMATE_ROOT)/include -i=$(ULTIMATE_ROOT)/src/uci

# Point this at your oscar64 binary if it is not on PATH.
OSCAR64 ?= oscar64
