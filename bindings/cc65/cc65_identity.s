; cc65 identity adapters. One service per archive member keeps unrelated
; services out of C programs. Register-compatible entries live in src/uci.
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"
        .include "uci_zp.inc"

        .importzp sp
        .import ultimate_identify
        .import ultimate_get_model
        .import ult_buflen
        .import ult_outlen
        .import incsp4
        .import incsp5
        .import cc_ptr_at_y
        .export _ultimate_identify
        .export _ultimate_get_model

; ---------------------------------------------------------------------------
; The service layer takes its wider parameters in the shared variable block,
; which is natural from assembly and cheap from C. These two wrappers move
; cc65's stacked arguments into it.
; ---------------------------------------------------------------------------



; uint8_t ultimate_identify(uint8_t target, char *buf, uint16_t buflen,
;                           uint16_t *outlen);
;
; A/X holds outlen; the C stack holds buflen at 0..1, buf at 2..3, target at 4.
_ultimate_identify:
        sta ult_outlen
        stx ult_outlen + 1
        ldy #$00
        lda (sp),y
        sta ult_buflen
        iny
        lda (sp),y
        sta ult_buflen + 1
        iny
        jsr cc_ptr_at_y
        iny
        lda (sp),y
        pha                     ; target
        jsr incsp5
        pla
        jsr ultimate_identify
        ldx #$00
        rts

; uint8_t ultimate_get_model(char *buf, uint16_t buflen, uint16_t *outlen);
;
; A/X holds outlen; the C stack holds buflen at 0..1 and buf at 2..3.
_ultimate_get_model:
        sta ult_outlen
        stx ult_outlen + 1
        ldy #$00
        lda (sp),y
        sta ult_buflen
        iny
        lda (sp),y
        sta ult_buflen + 1
        iny
        jsr cc_ptr_at_y
        jsr incsp4
        jsr ultimate_get_model
        ldx #$00
        rts
