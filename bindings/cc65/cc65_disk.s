; cc65 disk adapters. One service per archive member keeps unrelated
; services out of C programs. Register-compatible entries live in src/uci.
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"
        .include "uci_zp.inc"

        .importzp sp
        .import ult_buf
        .import incsp1
        .import ultimate_mount
        .export _ultimate_mount

; uint8_t ultimate_mount(uint8_t device, const char *image);
;
; A/X holds the image name; the C stack holds the device number at 0.
_ultimate_mount:
        sta ult_buf
        stx ult_buf + 1
        ldy #$00
        lda (sp),y
        pha                             ; the device, past the stack adjustment
        jsr incsp1
        pla
        jsr ultimate_mount
        ldx #$00
        rts
