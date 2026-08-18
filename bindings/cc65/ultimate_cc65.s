; ultimate_cc65.s - the one place cc65's calling convention needs unpacking.
;
; Most of the SDK's entry points take a pointer in A/X and return a byte in A,
; which is exactly cc65's convention for a one-argument function - so the core
; exports its C names directly and costs a C caller nothing.
;
; uci_decode_status takes three arguments, so cc65 passes the first two on its
; software stack. Unpacking that belongs here, in the binding, and not in the
; core: assembly callers use uci_decode with its parameter block and never touch
; a C runtime.
;
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"

        .import uci_decode, uci_dec_target, uci_dec_ptr, uci_dec_len
        .importzp c_sp
        .import incsp3

        .export _uci_decode_status

; uint8_t uci_decode_status(uint8_t target, const uint8_t *status,
;                           uint16_t statuslen);
;
; On entry A/X holds statuslen; the C stack holds the status pointer at offset
; 0..1 and the target at offset 2.
_uci_decode_status:
        sta uci_dec_len         ; a status longer than 255 bytes cannot exist:
                                ; the queue is 256 and only the prefix matters
        ldy #$00
        lda (c_sp),y
        sta uci_dec_ptr
        iny
        lda (c_sp),y
        sta uci_dec_ptr + 1
        iny
        lda (c_sp),y
        sta uci_dec_target

        jsr incsp3
        jsr uci_decode
        ldx #$00
        rts

; ---------------------------------------------------------------------------
; The service layer takes its wider parameters in the shared variable block,
; which is natural from assembly and cheap from C. These two wrappers move
; cc65's stacked arguments into it.
; ---------------------------------------------------------------------------

        .import ultimate_identify, ultimate_get_model
        .import ultimate_palette_set_color
        .import ult_buf, ult_buflen, ult_outlen, ult_color
        .import incsp4, incsp5

        .export _ultimate_identify
        .export _ultimate_get_model
        .export _ultimate_palette_set_color

; uint8_t ultimate_identify(uint8_t target, char *buf, uint16_t buflen,
;                           uint16_t *outlen);
;
; A/X holds outlen; the C stack holds buflen at 0..1, buf at 2..3, target at 4.
_ultimate_identify:
        sta ult_outlen
        stx ult_outlen + 1
        ldy #$00
        lda (c_sp),y
        sta ult_buflen
        iny
        lda (c_sp),y
        sta ult_buflen + 1
        iny
        lda (c_sp),y
        sta ult_buf
        iny
        lda (c_sp),y
        sta ult_buf + 1
        iny
        lda (c_sp),y
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
        lda (c_sp),y
        sta ult_buflen
        iny
        lda (c_sp),y
        sta ult_buflen + 1
        iny
        lda (c_sp),y
        sta ult_buf
        iny
        lda (c_sp),y
        sta ult_buf + 1
        jsr incsp4
        jsr ultimate_get_model
        ldx #$00
        rts

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
        lda (c_sp),y
        sta ult_color + 2       ; g
        iny
        lda (c_sp),y
        sta ult_color + 1       ; r
        iny
        lda (c_sp),y
        sta ult_color           ; index
        jsr incsp3
        jsr ultimate_palette_set_color
        ldx #$00
        rts
