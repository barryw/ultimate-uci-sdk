# Emulator tests: the SDK's compiled code against sim6502's simulated Ultimate.
#
#   make                              build harness.prg and harness.sym
#   make run SIM6502=<path to repo>   run the suites under u64sim
#
# SPDX-License-Identifier: MIT

ROOT    := ../..
TARGET  ?= c64
CL65    ?= cl65
# sim6502 runs from its published container, so CI and a laptop run the exact
# same tool with no .NET install anywhere.
SIM6502_IMAGE ?= ghcr.io/barryw/sim6502:latest
REPO          := $(abspath $(ROOT))
DOCKER        ?= docker
SIM6502       = $(DOCKER) run --rm -v $(REPO):/code $(SIM6502_IMAGE)
FS_ROOT       := /code/tests/emulator/fixtures/usb0

LIB := $(ROOT)/bindings/cc65/build/ultimate.lib

# The standalone blob (Task 6): the same core, linked with a jump table at a
# fixed base address, and no symbol file - what blob.suite drives.
BLOB := $(ROOT)/bindings/blob/build/ultimate-c000.bin

$(BLOB): FORCE
	$(MAKE) -C $(ROOT)/bindings/blob

# The second harness is the same program with the SDK's RAM moved out of BSS to
# a fixed address, the way a cartridge project would build it. Running the same
# suite against both is what makes "placeable" a tested property rather than a
# claim in the documentation.
# Decimal, not $CF00/$A3: a dollar sign has to survive make expansion, a
# recursive make, and a shell, and decimal simply does not care.
PLACED_VARS := 52992
PLACED_ZP   := 163
PLACED_DEFINES := -D UCI_VARS=$(PLACED_VARS) -D UCI_ZP=$(PLACED_ZP)

all: harness.prg harness.sym harness-placed.prg harness-placed.sym \
     sdk-placed.suite $(BLOB) relocharness.prg relocharness.sym

$(LIB): FORCE
	$(MAKE) -C $(ROOT)/bindings/cc65 TARGET=$(TARGET)

harness.prg harness.lbl: harness.s $(LIB)
	$(CL65) -t $(TARGET) --asm-include-dir $(ROOT)/bindings/asm \
	  -Ln harness.lbl -o harness.prg harness.s $(LIB)

# cl65 emits VICE labels for everything it linked, including cc65 runtime
# helpers whose names repeat. Keep only the harness symbols the suites use, and
# translate them to the KickAssembler form sim6502 reads.
HARNESS_SYMS := boot t_break_cstack t_init t_present t_ident_reg t_available \
                t_identify_dos1 t_identify_absent t_detect \
                t_identify t_get_model t_req_reset t_exec t_wedge \
                t_decode t_status_fmt t_strerror t_set_timeout t_get_timeout \
                result devcode reply reply_len reply0 reply1 reply2 reply3 \
                caps caps_present caps_ident caps_targets_lo caps_targets_hi \
                ident_target ident_buflen dec_target dec_buf dec_len \
                fmt_target err_code err_text timeout_val \
                req req_target req_command req_args req_arglen \
                req_payload req_payloadlen req_data req_datamax req_datalen \
                req_status req_statusmax req_statuslen \
                buf_args buf_payload buf_data buf_status

harness.sym: harness.lbl
	awk -v want="$(HARNESS_SYMS)" ' \
	  BEGIN { n = split(want, a, " "); for (i = 1; i <= n; i++) keep[a[i]] = 1 } \
	  /^al / { name = $$3; sub(/^\./, "", name); \
	           if (name in keep) printf ".label %s=$$%s\n", name, tolower(substr($$2, 3)) } \
	' $< > $@

$(ROOT)/bindings/cc65/build-placed/ultimate.lib: FORCE
	$(MAKE) -C $(ROOT)/bindings/cc65 TARGET=$(TARGET) BUILD=build-placed \
	  ASM_DEFINES="$(PLACED_DEFINES)"

harness-placed.prg harness-placed.lbl: harness.s $(ROOT)/bindings/cc65/build-placed/ultimate.lib
	$(CL65) -t $(TARGET) --asm-include-dir $(ROOT)/bindings/asm \
	  --asm-define UCI_VARS=$(PLACED_VARS) --asm-define UCI_ZP=$(PLACED_ZP) \
	  -Ln harness-placed.lbl -o harness-placed.prg harness.s \
	  $(ROOT)/bindings/cc65/build-placed/ultimate.lib

harness-placed.sym: harness-placed.lbl
	awk -v want="$(HARNESS_SYMS)" ' \
	  BEGIN { n = split(want, a, " "); for (i = 1; i <= n; i++) keep[a[i]] = 1 } \
	  /^al / { name = $$3; sub(/^\./, "", name); \
	           if (name in keep) printf ".label %s=$$%s\n", name, tolower(substr($$2, 3)) } \
	' $< > $@

sdk-placed.suite: sdk.suite
	sed -e 's|harness\.|harness-placed.|g' \
	    -e 's|ultimate sdk on 6502|ultimate sdk on 6502, memory relocated|' $< > $@

# The relocator test harness (Task 9): loads the blob at $C000, moves it to
# $8000 with bindings/blob/reloc.s, and calls through the moved jump table -
# the only way to prove the relocation table has no missing entries.
RELOCHARNESS_SYMS := t_reloc t_call_init result

relocharness.prg relocharness.lbl: relocharness.s $(LIB) $(BLOB)
	$(CL65) -t $(TARGET) --asm-include-dir $(ROOT)/bindings/asm \
	  -I $(ROOT)/bindings/blob \
	  -Ln relocharness.lbl -o relocharness.prg \
	  relocharness.s $(ROOT)/bindings/blob/reloc.s $(LIB)

relocharness.sym: relocharness.lbl
	awk -v want="$(RELOCHARNESS_SYMS)" ' \
	  BEGIN { n = split(want, a, " "); for (i = 1; i <= n; i++) keep[a[i]] = 1 } \
	  /^al / { name = $$3; sub(/^\./, "", name); \
	           if (name in keep) printf ".label %s=$$%s\n", name, tolower(substr($$2, 3)) } \
	' $< > $@

# The interface latency timeout.suite needs: comfortably longer than the SDK's
# smallest budget of 256 status polls, so the poll loop gives up first.
SLOW_LATENCY := 200000

run: all
	$(SIM6502) -s /code/tests/emulator/protocol.suite \
	  --backend u64sim --u64sim-fs-root $(FS_ROOT)
	$(SIM6502) -s /code/tests/emulator/sdk.suite \
	  --backend u64sim --u64sim-fs-root $(FS_ROOT)
	$(SIM6502) -s /code/tests/emulator/sdk-placed.suite \
	  --backend u64sim --u64sim-fs-root $(FS_ROOT)
	$(SIM6502) -s /code/tests/emulator/timeout.suite \
	  --backend u64sim --u64sim-fs-root $(FS_ROOT) \
	  --u64sim-uci-latency $(SLOW_LATENCY)
# No --backend: the plain simulator has nothing at $DF1B-$DF1F, which is the
# only way to test a machine with no Ultimate in it.
	$(SIM6502) -s /code/tests/emulator/absent.suite
	$(SIM6502) -s /code/tests/emulator/blob.suite \
	  --backend u64sim --u64sim-fs-root $(FS_ROOT)
	$(SIM6502) -s /code/tests/emulator/blob-relocated.suite \
	  --backend u64sim --u64sim-fs-root $(FS_ROOT)

# The same protocol expectations, against a real Ultimate on the network.
#   make hardware U64_HOST=192.168.1.62
#
# Only protocol.suite runs here: the u64 backend carries UCI traffic over the
# firmware's REST API and has no way to jsr into a loaded program, so sdk.suite
# stays simulator-only. tests/hardware covers the SDK on real silicon instead.
hardware:
	@test -n "$(U64_HOST)" || { echo "set U64_HOST=<ip of your Ultimate>"; exit 1; }
	$(SIM6502) -s /code/tests/emulator/protocol.suite \
	  --backend u64 --u64-host $(U64_HOST)

clean:
	rm -f harness.prg harness.lbl harness.sym harness.o
	rm -f harness-placed.prg harness-placed.lbl harness-placed.sym sdk-placed.suite
	rm -f relocharness.prg relocharness.lbl relocharness.sym relocharness.o
	rm -rf $(ROOT)/bindings/cc65/build-placed
	$(MAKE) -C $(ROOT)/bindings/blob clean

FORCE:

.PHONY: all run hardware clean FORCE
