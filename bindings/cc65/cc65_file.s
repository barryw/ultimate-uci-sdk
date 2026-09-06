; cc65 file adapters. One service per archive member keeps unrelated
; services out of C programs. Register-compatible entries live in src/uci.
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"
        .include "uci_zp.inc"

        .importzp sp
        .import ultimate_load
        .import ultimate_bload
        .import ultimate_save
        .import ult_addr
        .import ult_max
        .import incsp2
        .import incsp4
        .import cc_ptr_at_y
        .export _ultimate_load
        .export _ultimate_bload
        .export _ultimate_save

; ---------------------------------------------------------------------------
; file.s. The address and the limit are two more of the shared block's fields,
; so these are the same unpacking as everything above.
; ---------------------------------------------------------------------------

; uint8_t ultimate_load(const char *name, uint16_t addr);
;
; A/X holds addr; the C stack holds the name pointer at 0..1.
_ultimate_load:
        sta ult_addr
        stx ult_addr + 1
        jsr cc_name_only
        jsr ultimate_load
        ldx #$00
        rts

; uint8_t ultimate_bload(const char *name, uint16_t addr, uint16_t max);
; uint8_t ultimate_save (const char *name, uint16_t start, uint16_t len);
;
; The same three arguments in the same places: A/X holds the last one, the C
; stack holds the address at 0..1 and the name at 2..3.
_ultimate_bload:
        jsr cc_name_addr_max
        jsr ultimate_bload
        ldx #$00
        rts

_ultimate_save:
        jsr cc_name_addr_max
        jsr ultimate_save
        ldx #$00
        rts

cc_name_addr_max:
        sta ult_max
        stx ult_max + 1
        ldy #$00
        lda (sp),y
        sta ult_addr
        iny
        lda (sp),y
        sta ult_addr + 1
        iny
        jsr cc_ptr_at_y
        jmp incsp4

cc_name_only:
        ldy #$00
        jsr cc_ptr_at_y
        jmp incsp2
