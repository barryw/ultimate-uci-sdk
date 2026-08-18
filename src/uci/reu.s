; reu.s - the RAM expansion, both halves of it.
;
; **This module touches hardware registers directly, and it is the second and
; last module allowed to.** The rule everywhere else - services are built out of
; uci_exec and never write a register - is about not reimplementing the
; transport. Here half the service has no transport to reimplement: there is no
; UCI command that moves bytes between C64 RAM and the REU, so the only way to
; do it is the REU's own DMA registers at $DF00-$DF0A. turbo.s is the other
; exemption, and the test that admits one is the same: does the operation exist
; on the UCI at all.
;
; The other half does go through uci_exec, because there it does exist:
; DOS_CMD_LOAD_REU and DOS_CMD_SAVE_REU move bytes between the *open file* and
; the REU without any of them passing through the C64 at all.
;
;   ultimate_reu_stash   C64 RAM       -> REU        $DF00-$DF0A, under DMA
;   ultimate_reu_fetch   REU           -> C64 RAM    the same, the other way
;   ultimate_reu_load    the open file -> REU        DOS_CMD_LOAD_REU
;   ultimate_reu_save    REU -> the open file        DOS_CMD_SAVE_REU
;
; All four take the same two numbers, in the same two places: ult_reu is the
; address in the expansion and ult_reulen is how many bytes. The DMA pair adds
; ult_addr, the C64 end of the transfer.
;
; **Never wrap the control target's REU pair.** `CTRL_CMD_LOAD_REU` ($04 $08)
; never returns on firmware 3.14d and wedges the interface until a power cycle,
; GideonZ/1541ultimate#740. The DOS pair does the same job and is safe. The
; control pair stays reachable through the generic form, so issuing it is always
; a deliberate act.
;
; Three facts about the registers, read out of
; fpga/cart_slot/vhdl_source/reu.vhd rather than assumed:
;
; - **A transfer runs with the CPU halted.** The REU pulls DMA low for the
;   duration, so by the time the instruction after the write to REU_REG_COMMAND
;   runs, the transfer is over. There is nothing to poll and no interrupt to
;   arrange, which is why these entry points cannot block.
;
; - **REU_CMD_NOW is not optional.** With bit 4 clear the transfer waits for a
;   write to $FF00 - the trick a cartridge uses to swap memory out from under
;   itself. A program driving the REU for its own sake wants it to start now.
;
; - **A length of zero means 65536 bytes.** The counter is compared against 1
;   rather than 0, so zero wraps the whole way round. That is the real REU's
;   behaviour and the FPGA's alike, and it is documented here rather than left
;   as a surprise.
;
; The command interface overlays $DF1B-$DF1F, which this never touches: the REU
; decodes $DF00-$DF17 and the interface lives above it, so the two coexist.
; tools/test_registers.py asserts that the SDK writes nothing in between.
;
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"
        .include "uci_seg.inc"

        .import uci_exec
        .import ult_req, ult_req_clear
        .import ult_addr, ult_reu, ult_reulen, ult_scratch

        .export ultimate_reu_available, _ultimate_reu_available
        .export ultimate_reu_size, _ultimate_reu_size
        .export ultimate_reu_stash
        .export ultimate_reu_fetch
        .export ultimate_reu_load
        .export ultimate_reu_save

; The eight argument bytes go on the wire straight out of the variables, so the
; length has to sit immediately after the address. It does in both layouts - the
; BSS one by declaration order and the placed one by its equates - and this is
; what says so if either ever changes.
.assert ult_reulen = ult_reu + 4, lderror, "ult_reulen must follow ult_reu"

        uci_code

; ---------------------------------------------------------------------------
; ultimate_reu_available  ->  A = 1 when the REU answers, 0 when it does not
;
; Two patterns written to the C64 base register and read back. One would not do:
; a machine with no REU leaves $DF02 floating, and open bus reads back whatever
; was last on it - which can be the byte just written. Two different values
; cannot both be a coincidence.
;
; The register is left holding the second pattern, which costs nothing: every
; transfer writes all of the address registers before it starts.
;
; **A simulator with plain RAM at $DF02 will report a REU that is not there.**
; That is inherent to probing by readback, and it is the right trade for real
; hardware, where a missing REU does not remember what it was told.
; ---------------------------------------------------------------------------
ultimate_reu_available:
_ultimate_reu_available:
        lda #$5A
        sta REU_REG_C64_LO
        cmp REU_REG_C64_LO
        bne @no
        lda #$A5
        sta REU_REG_C64_LO
        cmp REU_REG_C64_LO
        bne @no
        lda #$01
        ldx #$00
        rts
@no:    lda #$00
        ldx #$00
        rts

; ---------------------------------------------------------------------------
; ultimate_reu_stash   ult_addr = C64 address, ult_reu = REU address,
;                      ult_reulen = length (0 = 65536)
;                   -> A = ULTIMATE_* result
;
; ULTIMATE_ERR_NOT_SUPPORTED when there is no REU, which is a normal answer
; rather than a failure: the machine's owner decides whether the expansion is
; switched on, exactly as they do for turbo.
; ---------------------------------------------------------------------------
ultimate_reu_stash:
        lda #REU_MODE_STASH
        jmp reu_transfer

; ---------------------------------------------------------------------------
; ultimate_reu_fetch   the same three, the other way round
; ---------------------------------------------------------------------------
ultimate_reu_fetch:
        lda #REU_MODE_FETCH

; A = transfer mode. Programs every register and runs the transfer.
reu_transfer:
        pha
        jsr ultimate_reu_available
        cmp #$01
        beq @there
        pla
        lda #ULTIMATE_ERR_NOT_SUPPORTED
        ldx #$00
        rts

@there: lda ult_addr
        sta REU_REG_C64_LO
        lda ult_addr + 1
        sta REU_REG_C64_HI
        lda ult_reu
        sta REU_REG_ADDR_LO
        lda ult_reu + 1
        sta REU_REG_ADDR_MID
        lda ult_reu + 2
        sta REU_REG_ADDR_HI
        lda ult_reulen
        sta REU_REG_LEN_LO
        lda ult_reulen + 1
        sta REU_REG_LEN_HI

        pla                     ; the mode this was entered with
        ora #REU_CMD_EXECUTE | REU_CMD_NOW

        ; Interrupts off for these two instructions, and not for the transfer -
        ; the CPU is halted for that and nothing can land in the middle of it.
        ; It is the status read that needs protecting, because it is
        ; destructive: reading REU_REG_STATUS clears the done and verify bits,
        ; so an interrupt handler that also drives the REU would take this
        ; answer away before it was looked at. Everything above is idempotent.
        php
        sei
        sta REU_REG_COMMAND     ; ...and the machine stops here until it is done
        lda REU_REG_STATUS
        plp

        and #REU_STAT_DONE
        beq @failed
        lda #ULTIMATE_OK
        ldx #$00
        rts

; The registers answered the probe and then no transfer finished. On real
; hardware that is the expansion being switched off between the two, or
; something else driving the same registers.
@failed:
        lda #ULTIMATE_ERR_IO
        ldx #$00
        rts

; ---------------------------------------------------------------------------
; ultimate_reu_size  ->  A = low, X = high: the expansion's size in 64K banks,
;                        or zero when there is none
;
;   128 KB = 2      1 MB = 16       8 MB = 128
;   256 KB = 4      2 MB = 32      16 MB = 256
;   512 KB = 8      4 MB = 64
;
; **Banks rather than bytes, and sixteen bits rather than eight.** 16 MB is 256
; banks, which does not fit a byte, and it is 65536 pages of 256, which does not
; fit a word either - both of the compact units are one short at exactly the
; largest machine, which is the one nobody tests on. A bank count in a word has
; room for 4 GB and no boundary to trip over.
;
; **There is no command that answers this.** The control target's hardware-info
; command reports the model and the SID configuration and nothing else, and
; `REU_STAT_SIZE` is the 1764-era bit that only separates 128 KB from everything
; above it - measured on an Ultimate, where it is set for every size from 256 KB
; up. So the size is found the way it always was: by writing past a power of two
; and seeing whether it comes back round to the start.
;
; **The expansion aliases, and that is what makes this work.** Measured across
; four configured sizes on firmware 3.15: a write past the end lands at the
; offset modulo the real size, and because every boundary here is a power of two
; at or above that size, it lands exactly on offset zero. The first boundary
; that disturbs offset zero is the size.
;
; **Nothing is left changed.** Twelve bytes are saved before they are written
; and put back afterwards, offset zero last so that a wrapped write cannot
; outlive the truth.
;
; This costs one DMA burst per boundary - eight at the very most, each of four
; bytes with the CPU halted - so it is cheap enough to call at start-up and not
; worth caching.
; ---------------------------------------------------------------------------

; ult_scratch, divided up: what offset zero held, what the boundary held, what
; came back, and two bytes of bookkeeping. The markers live in rodata and are
; sent straight out of it, so nothing has to be built at run time.
REU_SZ_ORIG  = 0
REU_SZ_SAVED = 4
REU_SZ_WORK  = 8
REU_SZ_BANK  = 12
REU_SZ_I     = 13

ultimate_reu_size:
_ultimate_reu_size:
        jsr ultimate_reu_available
        cmp #$01
        beq @there
        lda #$00                        ; no expansion is no banks
        tax
        rts

@there: lda #$00                        ; keep what offset zero holds
        sta ult_scratch + REU_SZ_BANK
        lda #<(ult_scratch + REU_SZ_ORIG)
        ldx #>(ult_scratch + REU_SZ_ORIG)
        jsr reu_sz_get
        bcc @none

        lda #<reu_sz_mark_a             ; ...and mark it
        ldx #>reu_sz_mark_a
        jsr reu_sz_put
        bcc @none

        lda #$00
        sta ult_scratch + REU_SZ_I

@probe: ldy ult_scratch + REU_SZ_I
        lda reu_sz_banks,y
        beq @full                       ; out of boundaries: it is the whole 16 MB
        sta ult_scratch + REU_SZ_BANK

        lda #<(ult_scratch + REU_SZ_SAVED)  ; whatever lives at the boundary,
        ldx #>(ult_scratch + REU_SZ_SAVED)  ; which may be offset zero already
        jsr reu_sz_get
        bcc @restore

        lda #<reu_sz_mark_b
        ldx #>reu_sz_mark_b
        jsr reu_sz_put
        bcc @restore

        lda #$00                        ; did offset zero move?
        sta ult_scratch + REU_SZ_BANK
        lda #<(ult_scratch + REU_SZ_WORK)
        ldx #>(ult_scratch + REU_SZ_WORK)
        jsr reu_sz_get
        bcc @restore

        ldx #$03
@cmp:   lda ult_scratch + REU_SZ_WORK,x
        cmp reu_sz_mark_b,x
        bne @distinct
        dex
        bpl @cmp

        jsr reu_sz_restore              ; it wrapped, so this boundary is the size
        ldy ult_scratch + REU_SZ_I
        lda reu_sz_banks,y
        ldx #$00
        rts

@distinct:
        ldy ult_scratch + REU_SZ_I      ; a real location; put it back
        lda reu_sz_banks,y
        sta ult_scratch + REU_SZ_BANK
        lda #<(ult_scratch + REU_SZ_SAVED)
        ldx #>(ult_scratch + REU_SZ_SAVED)
        jsr reu_sz_put
        inc ult_scratch + REU_SZ_I
        bne @probe                      ; always

@full:  jsr reu_sz_restore
        lda #$00                        ; 256 banks: 16 MB, which is also the
        ldx #$01                        ; ceiling a 24-bit address can reach
        rts

@restore:
        jsr reu_sz_restore
@none:  lda #$00
        tax
        rts

; Offset zero, back as it was. Nothing else needs restoring by then: a write
; that wrapped can only have landed here.
reu_sz_restore:
        lda #$00
        sta ult_scratch + REU_SZ_BANK
        lda #<(ult_scratch + REU_SZ_ORIG)
        ldx #>(ult_scratch + REU_SZ_ORIG)
        jmp reu_sz_put

; A/X = the C64 end, REU_SZ_BANK = which bank. Four bytes either way, and carry
; set on success, which is all a probe needs to know.
reu_sz_get:
        jsr reu_sz_setup
        jsr ultimate_reu_fetch
        jmp reu_sz_flag

reu_sz_put:
        jsr reu_sz_setup
        jsr ultimate_reu_stash
        jmp reu_sz_flag

reu_sz_setup:
        sta ult_addr
        stx ult_addr + 1
        lda #$00                        ; a boundary is a whole bank, so only
        sta ult_reu                     ; the high byte of the address is set
        sta ult_reu + 1
        lda ult_scratch + REU_SZ_BANK
        sta ult_reu + 2
        lda #$00
        sta ult_reu + 3
        lda #$04
        sta ult_reulen
        lda #$00
        sta ult_reulen + 1
        sta ult_reulen + 2
        sta ult_reulen + 3
        rts

reu_sz_flag:
        cmp #ULTIMATE_OK
        beq @ok
        clc
        rts
@ok:    sec
        rts

        .rodata
; Where each size ends, in 64K banks. 16 MB is absent on purpose: 256 does not
; fit the high address byte, so it is what is left when nothing else aliased.
reu_sz_banks:
        .byte 2, 4, 8, 16, 32, 64, 128, 0
; Two patterns that cannot be mistaken for each other or for plausible data.
reu_sz_mark_a:
        .byte $A5, $5A, $C3, $3C
reu_sz_mark_b:
        .byte $1F, $E0, $77, $88
        uci_code

; ---------------------------------------------------------------------------
; ultimate_reu_load   ult_reu = REU address, ult_reulen = length
;                  -> A = ULTIMATE_* result
;
; The currently open file into the REU, with none of it passing through the C64.
; **There is no filename in this command.** It works on whatever ultimate_open
; left open, exactly as READ_DATA does, and the caller closes it afterwards.
;
; The firmware answers with a sentence - "$  1000 BYTES LOADED TO REU $     0" -
; rather than with a number. It is there for a caller who wants it, through the
; generic form; decoding hex-with-leading-spaces here would be forty bytes of
; code for a figure the caller already asked for.
; ---------------------------------------------------------------------------
ultimate_reu_load:
        lda #DOS_CMD_LOAD_REU
        jmp reu_dos_cmd

; ---------------------------------------------------------------------------
; ultimate_reu_save   the same, out of the REU and into the open file
; ---------------------------------------------------------------------------
ultimate_reu_save:
        lda #DOS_CMD_SAVE_REU

; A = command byte. The eight argument bytes the wire wants - address dword,
; then length dword - are ult_reu and ult_reulen, which are laid out in that
; order on purpose, so the argument span is the variables themselves and nothing
; is copied anywhere first.
reu_dos_cmd:
        pha
        jsr ult_req_clear
        lda #UCI_TARGET_DOS1
        sta ult_req + UCI_REQ_TARGET
        pla
        sta ult_req + UCI_REQ_COMMAND
        lda #<ult_reu
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_reu
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$08
        sta ult_req + UCI_REQ_ARGLEN
        lda #<ult_req
        ldx #>ult_req
        jmp uci_exec
