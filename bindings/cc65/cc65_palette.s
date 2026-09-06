; cc65 palette adapters. One service per archive member keeps unrelated
; services out of C programs. Register-compatible entries live in src/uci.
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"
        .include "uci_zp.inc"

        .importzp sp
        .import incsp3
        .import ultimate_palette_set_color
        .import ult_color
        .export _ultimate_palette_set_color

; uint8_t ultimate_palette_set_color(uint8_t index, uint8_t r, uint8_t g,
;                                    uint8_t b);
;
; A holds b; cc65 pushes the other three as single bytes, so the C stack holds
; g at 0, r at 1 and index at 2. The other three palette entry points take one
; argument or none, which is already cc65's convention, so they export their C
; names straight out of palette.s and cost nothing here.
_ultimate_palette_set_color:
        sta ult_color + 3       ; b
        ldy #$00
        lda (sp),y
        sta ult_color + 2       ; g
        iny
        lda (sp),y
        sta ult_color + 1       ; r
        iny
        lda (sp),y
        sta ult_color           ; index
        jsr incsp3
        jsr ultimate_palette_set_color
        ldx #$00
        rts
