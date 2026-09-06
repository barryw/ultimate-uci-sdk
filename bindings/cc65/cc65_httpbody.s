; cc65 httpbody adapters. One service per archive member keeps unrelated
; services out of C programs. Register-compatible entries live in src/uci.
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"
        .include "uci_zp.inc"

        .importzp sp
        .import incsp3
        .import ult_url
        .import ult_body
        .import ult_buf
        .import ult_buflen
        .import incsp1
        .importzp sreg
        .import ultimate_http_body
        .import ultimate_http_body_int
        .import ultimate_http_body_bool
        .import ultimate_http_body_string
        .import ultimate_http_body_object
        .import ultimate_http_body_array
        .import ultimate_http_body_binary
        .import ult_val
        .import cc_ptr_at_y
        .import cc_hold_out
        .import cc_out_byte
        .import cc_url_at_y
        .export _ultimate_http_body
        .export _ultimate_http_body_int
        .export _ultimate_http_body_bool
        .export _ultimate_http_body_string
        .export _ultimate_http_body_object
        .export _ultimate_http_body_array
        .export _ultimate_http_body_binary

; ---------------------------------------------------------------------------
; httpbody.s.
; ---------------------------------------------------------------------------

; uint8_t ultimate_http_body(uint8_t format, uint8_t *handle);
;
; A/X holds handle; the C stack holds the format at 0.
_ultimate_http_body:
        jsr cc_hold_out
        ldy #$00
        lda (sp),y
        pha                             ; the format
        jsr incsp1
        pla
        jsr ultimate_http_body
        ldx ult_body
        jmp cc_out_byte

; uint8_t ultimate_http_body_int(uint8_t handle, const char *key, int32_t value);
;
; A/X plus sreg holds the value - cc65 passes a long that way - and the C stack
; holds the key at 0..1 and the handle at 2.
_ultimate_http_body_int:
        sta ult_val
        stx ult_val + 1
        lda sreg
        sta ult_val + 2
        lda sreg + 1
        sta ult_val + 3
        jsr cc_body_key
        jsr ultimate_http_body_int
        ldx #$00
        rts

; uint8_t ultimate_http_body_bool(uint8_t handle, const char *key, uint8_t value);
_ultimate_http_body_bool:
        sta ult_val
        jsr cc_body_key
        jsr ultimate_http_body_bool
        ldx #$00
        rts

; uint8_t ultimate_http_body_string(uint8_t handle, const char *key,
;                                   const char *value);
;
; A/X holds the value; the C stack holds the key at 0..1 and the handle at 2.
_ultimate_http_body_string:
        sta ult_buf
        stx ult_buf + 1
        jsr cc_body_key
        jsr ultimate_http_body_string
        ldx #$00
        rts

; The key at 0..1 and the handle at 2, which is the shape the three keyed
; commands taking a value all have.
cc_body_key:
        ldy #$00
        jsr cc_url_at_y                 ; key -> ult_url
        iny
        lda (sp),y
        sta ult_body
        jmp incsp3

; uint8_t ultimate_http_body_object(uint8_t handle, const char *key);
; uint8_t ultimate_http_body_array (uint8_t handle, const char *key);
;
; A/X holds the key; the C stack holds the handle at 0.
_ultimate_http_body_object:
        jsr cc_body_handle_key
        jsr ultimate_http_body_object
        ldx #$00
        rts

_ultimate_http_body_array:
        jsr cc_body_handle_key
        jsr ultimate_http_body_array
        ldx #$00
        rts

cc_body_handle_key:
        sta ult_url
        stx ult_url + 1
        ldy #$00
        lda (sp),y
        sta ult_body
        jmp incsp1

; uint8_t ultimate_http_body_binary(uint8_t handle, const uint8_t *data,
;                                   uint16_t len);
;
; A/X holds len; the C stack holds data at 0..1 and the handle at 2.
_ultimate_http_body_binary:
        sta ult_buflen
        stx ult_buflen + 1
        ldy #$00
        jsr cc_ptr_at_y                 ; data -> ult_buf
        iny
        lda (sp),y
        sta ult_body
        jsr incsp3
        jsr ultimate_http_body_binary
        ldx #$00
        rts
