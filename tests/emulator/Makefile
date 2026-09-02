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

# The standalone blob: the same core, linked with a jump table at a fixed base
# address, and no symbol file - what blob.suite drives.
BLOB := $(ROOT)/bindings/blob/build/ultimate-7000.bin

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
     sdk-placed.suite $(BLOB) relocharness.prg relocharness.sym \
     blob-relocated.suite

$(LIB): FORCE
	$(MAKE) -C $(ROOT)/bindings/cc65 TARGET=$(TARGET)

harness.prg harness.lbl: harness.s $(LIB)
	$(CL65) -t $(TARGET) --asm-include-dir $(ROOT)/bindings/asm \
	  -Ln harness.lbl -o harness.prg harness.s $(LIB)

# cl65 emits VICE labels for everything it linked, including cc65 runtime
# helpers whose names repeat. Keep only the harness symbols the suites use, and
# translate them to the KickAssembler form sim6502 reads.
#
# The lists live in this file, so every .sym rule below depends on it. Without
# that, adding a symbol here leaves the .sym untouched and the suite that uses
# it calls address zero - which reads as a wedge bug rather than a build one.
HARNESS_SYMS := boot t_break_cstack t_init t_present t_ident_reg t_status_reg t_available \
                t_identify_dos1 t_identify_absent t_detect \
                t_identify t_get_model t_req_reset t_exec t_wedge \
                t_sid_info t_sid_info_null sid_info \
                t_palette_get t_palette_set t_palette_color t_palette_reset \
                t_palette_get_null t_palette_set_null pal_index \
                t_turbo_available t_turbo_get t_turbo_set t_turbo_badlines \
                turbo_arg \
                t_chdir t_getpath t_opendir t_readdir \
                t_open t_close t_read dir_attrib \
                t_create t_write t_seek t_delete wr_len seek_pos \
                t_stat t_fstat t_rename t_copy t_mkdir t_home name2 finfo \
                t_mount t_unmount t_swap t_get_time t_set_time \
                t_reboot t_freeze t_drive_enable t_drive_power \
                t_drive_info t_ramdisk_info t_drvinfo_reply drvinfo_len \
                t_net_setip \
                t_body t_body_free t_body_clear t_body_up t_body_int \
                t_body_bool t_body_string t_body_object t_body_array \
                t_body_binary drive_arg flag_arg body_arg time_arg val_arg \
                t_load t_bload t_save load_addr load_max load_end \
                t_reu_avail t_reu_stash t_reu_fetch t_reu_load t_reu_save \
                t_flags_init t_flags_reu_avail t_flags_audio_avail \
                reu_at reu_len \
                t_net_ifcount t_net_ipconfig \
                t_net_connect t_net_connect_null \
                t_net_read_null t_net_read_tiny t_net_write_null \
                net_iface net_sock net_got \
                t_abort \
                t_decode t_status_fmt t_strerror t_set_timeout t_get_timeout \
                result devcode reply reply_len reply0 reply1 reply2 reply3 \
                caps caps_present caps_ident caps_targets_lo caps_targets_hi \
                ident_target ident_buflen dec_target dec_buf dec_len \
                fmt_target err_code err_text timeout_val \
                req req_target req_command req_args req_arglen \
                req_payload req_payloadlen req_data req_datamax req_datalen \
                req_status req_statusmax req_statuslen \
                buf_args buf_payload buf_data buf_status

harness.sym: harness.lbl Makefile
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

harness-placed.sym: harness-placed.lbl Makefile
	awk -v want="$(HARNESS_SYMS)" ' \
	  BEGIN { n = split(want, a, " "); for (i = 1; i <= n; i++) keep[a[i]] = 1 } \
	  /^al / { name = $$3; sub(/^\./, "", name); \
	           if (name in keep) printf ".label %s=$$%s\n", name, tolower(substr($$2, 3)) } \
	' $< > $@

sdk-placed.suite: sdk.suite
	sed -e 's|harness\.|harness-placed.|g' \
	    -e 's|ultimate sdk on 6502|ultimate sdk on 6502, memory relocated|' $< > $@

# The relocator test harness: loads the blob at $7000, moves it to $6000 with
# bindings/blob/reloc.s, and calls through the moved jump table - the only way
# to prove the relocation table has no missing entries.
RELOCHARNESS_SYMS := t_reloc t_call_init result

# How big the blob actually is, in two places that both used to guess. The
# harness copies that many pages and the suite compares that many bytes; both
# were hard-wired to the 2860-byte blob of the day, and the SDK growing past it
# would have quietly narrowed what either of them verified rather than failing.
blobsize.inc: $(BLOB)
	printf 'BLOB_SIZE = %d\n' $$(wc -c < $<) > $@

# tr strips the leading spaces BSD wc pads its output with; without it the
# substitution splits into two shell words and sed silently writes nothing.
blob-relocated.suite: blob-relocated.suite.in $(BLOB)
	sed "s/@BLOBSIZE@/$$(wc -c < $(BLOB) | tr -d ' ')/" $< > $@

relocharness.prg relocharness.lbl: relocharness.s blobsize.inc $(LIB) $(BLOB)
	$(CL65) -t $(TARGET) --asm-include-dir $(ROOT)/bindings/asm \
	  -I $(ROOT)/bindings/blob \
	  -Ln relocharness.lbl -o relocharness.prg \
	  relocharness.s $(ROOT)/bindings/blob/reloc.s $(LIB)

relocharness.sym: relocharness.lbl Makefile
	awk -v want="$(RELOCHARNESS_SYMS)" ' \
	  BEGIN { n = split(want, a, " "); for (i = 1; i <= n; i++) keep[a[i]] = 1 } \
	  /^al / { name = $$3; sub(/^\./, "", name); \
	           if (name in keep) printf ".label %s=$$%s\n", name, tolower(substr($$2, 3)) } \
	' $< > $@

# The interface latency timeout.suite needs: comfortably longer than the SDK's
# smallest budget of 256 status polls, so the poll loop gives up first.
SLOW_LATENCY := 200000

# Long enough for the SDK to build and push a command before the simulated
# firmware services the abort that uci_init issued - the race real firmware
# always won against the SDK before uci_abort waited for the abort flag.
ABORT_LATENCY := 4000

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
	$(SIM6502) -s /code/tests/emulator/abort-latency.suite \
	  --backend u64sim --u64sim-fs-root $(FS_ROOT) \
	  --u64sim-uci-latency $(ABORT_LATENCY)
# No --backend: the plain simulator has nothing at $DF1B-$DF1F, which is the
# only way to test a machine with no Ultimate in it.
	$(SIM6502) -s /code/tests/emulator/absent.suite
	$(SIM6502) -s /code/tests/emulator/blob.suite \
	  --backend u64sim --u64sim-fs-root $(FS_ROOT)
	$(SIM6502) -s /code/tests/emulator/blob-relocated.suite \
	  --backend u64sim --u64sim-fs-root $(FS_ROOT)
	$(MAKE) basic

# The BASIC wedge, against the real BASIC ROM.
#
# The wedge's tokeniser only exists because of what the ROM's CRUNCH does
# first, so there is nothing worth testing without it. Commodore's ROM images
# cannot be committed, so this skips with a message that names the fix rather
# than failing - the same shape as hardware-run needing U64_HOST.
#
#   make basic                          uses tests/emulator/roms
#   make basic C64_ROMS=/path/to/roms   uses somewhere else
C64_ROMS ?= roms

basic: $(WEDGE_PRG) basic.sym
	@if [ -r "$(C64_ROMS)/basic.bin" ] && [ -r "$(C64_ROMS)/kernal.bin" ]; then \
	  mkdir -p roms; \
	  [ "$(C64_ROMS)" = "roms" ] || cp "$(C64_ROMS)/basic.bin" "$(C64_ROMS)/kernal.bin" roms/; \
	  $(SIM6502) -s /code/tests/emulator/basic.suite \
	    --backend u64sim --u64sim-fs-root $(FS_ROOT); \
	else \
	  echo "skipping basic.suite: no C64 ROM images."; \
	  echo "  put basic.bin and kernal.bin in tests/emulator/roms,"; \
	  echo "  or run: make basic C64_ROMS=/path/to/them"; \
	fi

WEDGE_PRG := $(ROOT)/src/basic/uci.prg

$(WEDGE_PRG): FORCE
	$(MAKE) -C $(ROOT)/src/basic

# The wedge's symbols, filtered from its link map exactly as the harness's are.
WEDGE_SYMS := BUF TXTPTR ICRNCH IQPLOP IGONE IEVAL DORES \
              wedge_copy wedge_install wedge_crunch wedge_qplop \
              wedge_print_keyword wedge_find_keyword wedge_len \
              wedge_src wedge_dst wedge_verbatim \
              wedge_gone wedge_eval wedge_do_uci wedge_do_turbo wedge_err \
              wedge_do_load wedge_do_bload wedge_do_save \
              wedge_do_dir wedge_do_stash wedge_do_fetch \
              wedge_target wedge_command wedge_arglen wedge_argbuf \
              wedge_reply wedge_status uci_req

basic.sym: $(WEDGE_PRG) Makefile
	awk -v want="$(WEDGE_SYMS)" ' \
	  BEGIN { n = split(want, a, " "); for (i = 1; i <= n; i++) keep[a[i]] = 1 } \
	  /^al / { name = $$3; sub(/^\./, "", name); \
	           if (name in keep) printf ".label %s=$$%s\n", name, tolower(substr($$2, 3)) } \
	' $(ROOT)/src/basic/uci.lbl | sort -u > $@

# The same protocol expectations, against a real Ultimate on the network.
#   make hardware U64_HOST=192.168.1.62
#
# Only protocol.suite runs here: the u64 backend carries UCI traffic over the
# firmware's REST API and has no way to jsr into a loaded program, so sdk.suite
# stays simulator-only. tests/hardware covers the SDK on real silicon instead.
#
# The u64 backend pushes commands through the UCI hardware registers, which
# only answer when the machine's "Command Interface" setting is Enabled - not
# its normal state, since the owner's Ultimate is reconfigured constantly by
# other firmware testing. tools/u64_settings.py reads that setting first,
# enables it only if it is not already, runs sim6502, and restores exactly
# what it changed - on success, on failure, and on Ctrl-C alike.
hardware:
	@test -n "$(U64_HOST)" || { echo "set U64_HOST=<ip of your Ultimate>"; exit 1; }
	python3 $(REPO)/tools/u64_settings.py --host $(U64_HOST) \
	  --require "C64 and Cartridge Settings:Command Interface=Enabled" \
	  -- $(SIM6502) -s /code/tests/emulator/protocol.suite \
	  --backend u64 --u64-host $(U64_HOST)

clean:
	rm -f basic.sym
	rm -f harness.prg harness.lbl harness.sym harness.o
	rm -f harness-placed.prg harness-placed.lbl harness-placed.sym sdk-placed.suite
	rm -f relocharness.prg relocharness.lbl relocharness.sym relocharness.o
	rm -f blobsize.inc blob-relocated.suite
	rm -rf $(ROOT)/bindings/cc65/build-placed
	$(MAKE) -C $(ROOT)/bindings/blob clean

FORCE:

.PHONY: all run hardware clean FORCE
