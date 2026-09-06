; cc65 control adapters. One service per archive member keeps unrelated
; services out of C programs. Register-compatible entries live in src/uci.
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"
        .include "uci_zp.inc"

        .importzp sp
        .import incsp1
        .import ultimate_drive_enable
        .import ultimate_drive_power
        .import ult_stage
        .import cc_hold_out
        .import cc_out_byte
        .export _ultimate_drive_enable
        .export _ultimate_drive_power

; uint8_t ultimate_drive_enable(uint8_t drive, uint8_t on);
;
; A holds on; the C stack holds the drive at 0. The entry point wants the drive
; in A and the flag in X.
_ultimate_drive_enable:
        tax
        ldy #$00
        lda (sp),y
        pha
        jsr incsp1
        pla
        jsr ultimate_drive_enable
        ldx #$00
        rts

; uint8_t ultimate_drive_power(uint8_t drive, uint8_t *on);
;
; A/X holds the out-pointer; the C stack holds the drive at 0. The answer waits
; in ult_stage while uci_exec runs, as every other out-parameter here does.
_ultimate_drive_power:
        jsr cc_hold_out
        ldy #$00
        lda (sp),y
        pha
        jsr incsp1
        pla
        jsr ultimate_drive_power
        ldx ult_stage
        jmp cc_out_byte
