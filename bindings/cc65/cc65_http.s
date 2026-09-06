; cc65 http adapters. One service per archive member keeps unrelated
; services out of C programs. Register-compatible entries live in src/uci.
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"
        .include "uci_zp.inc"

        .importzp sp
        .import incsp3
        .import ultimate_http_open
        .import ultimate_http_header
        .import ultimate_http_exchange
        .import ultimate_http_get
        .import ult_url
        .import ult_http
        .import ult_body
        .import ult_httplen
        .import ult_buflen
        .import incsp1
        .import incsp6
        .import cc_ptr_at_y
        .import cc_hold_out
        .import cc_out_byte
        .import cc_out_ptr
        .import cc_url_at_y
        .export _ultimate_http_get
        .export _ultimate_http_exchange
        .export _ultimate_http_open
        .export _ultimate_http_header

; ---------------------------------------------------------------------------
; http.s. Same convention as the net shims above: the out-parameter waits in
; ult_outlen while uci_exec runs, because the zero page slots do not survive it.
; ---------------------------------------------------------------------------

; uint8_t ultimate_http_get(const char *url, uint8_t *buf, uint16_t bufsize,
;                           uint16_t *got);
;
; A/X holds got; the C stack holds bufsize at 0..1, buf at 2..3, url at 4..5.
_ultimate_http_get:
        jsr cc_hold_out
        ldy #$00
        lda (sp),y
        sta ult_buflen
        iny
        lda (sp),y
        sta ult_buflen + 1
        iny
        jsr cc_ptr_at_y                 ; buf -> ult_buf
        iny
        jsr cc_url_at_y                 ; url -> ult_url
        jsr incsp6
        jsr ultimate_http_get
        jmp cc_out_http

; uint8_t ultimate_http_exchange(uint8_t handle, uint8_t body, uint8_t *buf,
;                                uint16_t bufsize, uint16_t *got);
;
; A/X holds got; the C stack holds bufsize at 0..1, buf at 2..3, body at 4 and
; the handle at 5.
_ultimate_http_exchange:
        jsr cc_hold_out
        ldy #$00
        lda (sp),y
        sta ult_buflen
        iny
        lda (sp),y
        sta ult_buflen + 1
        iny
        jsr cc_ptr_at_y                 ; buf -> ult_buf
        iny
        lda (sp),y
        sta ult_body
        iny
        lda (sp),y
        sta ult_http
        jsr incsp6
        jsr ultimate_http_exchange
        jmp cc_out_http

; uint8_t ultimate_http_open(uint8_t verb, const char *url, uint8_t *handle);
;
; A/X holds handle; the C stack holds url at 0..1 and the verb at 2.
_ultimate_http_open:
        jsr cc_hold_out
        ldy #$00
        jsr cc_url_at_y
        iny
        lda (sp),y
        pha                             ; the verb, past the stack adjustment
        jsr incsp3
        pla
        jsr ultimate_http_open
        ldx ult_http
        jmp cc_out_byte

; uint8_t ultimate_http_header(uint8_t handle, const char *line);
;
; A/X holds the line; the C stack holds the handle at 0.
_ultimate_http_header:
        sta ult_url
        stx ult_url + 1
        ldy #$00
        lda (sp),y
        sta ult_http
        jsr incsp1
        jsr ultimate_http_header
        ldx #$00
        rts

; A = the result to hand back; ult_httplen is what gets stored.
cc_out_http:
        pha
        jsr cc_out_ptr
        bcc @none
        ldy #$00
        lda ult_httplen
        sta (uci_ptr),y
        iny
        lda ult_httplen + 1
        sta (uci_ptr),y
@none:  pla
        ldx #$00
        rts
