; cc65 reu adapters. One service per archive member keeps unrelated
; services out of C programs. Register-compatible entries live in src/uci.
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"
        .include "uci_zp.inc"

        .importzp sp
        .import ultimate_reu_stash
        .import ultimate_reu_fetch
        .import ultimate_reu_load
        .import ultimate_reu_save
        .import ult_addr
        .import ult_reu
        .import ult_reulen
        .import incsp4
        .import incsp6
        .importzp sreg
        .export _ultimate_reu_stash
        .export _ultimate_reu_fetch
        .export _ultimate_reu_load
        .export _ultimate_reu_save

; ---------------------------------------------------------------------------
; reu.s. Both pairs put the REU address and the length in the same two
; variables, so the two unpackers differ only in what else they take and in how
; wide the length arrives.
; ---------------------------------------------------------------------------

; uint8_t ultimate_reu_stash(uint16_t addr, uint32_t reuaddr, uint16_t len);
; uint8_t ultimate_reu_fetch(uint16_t addr, uint32_t reuaddr, uint16_t len);
;
; A/X holds len; the C stack holds reuaddr at 0..3 and addr at 4..5.
_ultimate_reu_stash:
        jsr cc_reu_dma
        jmp ultimate_reu_stash

_ultimate_reu_fetch:
        jsr cc_reu_dma
        jmp ultimate_reu_fetch

cc_reu_dma:
        sta ult_reulen          ; a DMA transfer is 16 bits wide, so the top
        stx ult_reulen + 1      ; half of the shared length is zero
        lda #$00
        sta ult_reulen + 2
        sta ult_reulen + 3
        ldy #$00
        lda (sp),y
        sta ult_reu
        iny
        lda (sp),y
        sta ult_reu + 1
        iny
        lda (sp),y
        sta ult_reu + 2
        iny
        lda (sp),y
        sta ult_reu + 3
        iny
        lda (sp),y
        sta ult_addr
        iny
        lda (sp),y
        sta ult_addr + 1
        jmp incsp6

; uint8_t ultimate_reu_load(uint32_t reuaddr, uint32_t len);
; uint8_t ultimate_reu_save(uint32_t reuaddr, uint32_t len);
;
; A/X plus sreg holds len - cc65 passes a long that way - and the C stack holds
; reuaddr at 0..3.
_ultimate_reu_load:
        jsr cc_reu_file
        jmp ultimate_reu_load

_ultimate_reu_save:
        jsr cc_reu_file
        jmp ultimate_reu_save

cc_reu_file:
        sta ult_reulen
        stx ult_reulen + 1
        lda sreg
        sta ult_reulen + 2
        lda sreg + 1
        sta ult_reulen + 3
        ldy #$00
        lda (sp),y
        sta ult_reu
        iny
        lda (sp),y
        sta ult_reu + 1
        iny
        lda (sp),y
        sta ult_reu + 2
        iny
        lda (sp),y
        sta ult_reu + 3
        jmp incsp4
