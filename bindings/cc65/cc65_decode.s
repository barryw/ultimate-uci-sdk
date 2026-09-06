; cc65 decode adapters. One service per archive member keeps unrelated
; services out of C programs. Register-compatible entries live in src/uci.
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"
        .include "uci_zp.inc"

        .import uci_decode
        .import uci_dec_target
        .import uci_dec_ptr
        .import uci_dec_len
        .importzp sp
        .import incsp3
        .export _uci_decode_status

; uint8_t uci_decode_status(uint8_t target, const uint8_t *status,
;                           uint16_t statuslen);
;
; On entry A/X holds statuslen; the C stack holds the status pointer at offset
; 0..1 and the target at offset 2.
_uci_decode_status:
        ; The decoder counts in bytes. The status queue is 256 bytes, so a
        ; length of exactly 256 is reachable and would arrive here as a low
        ; byte of zero - which the decoder reads as an empty status, and an
        ; empty status is success. Clamp instead: every supported status shape
        ; fits well below 255 bytes, so 255 decodes the same as 256 would.
        cpx #$00
        beq @fits
        lda #$FF
@fits:  sta uci_dec_len
        ldy #$00
        lda (sp),y
        sta uci_dec_ptr
        iny
        lda (sp),y
        sta uci_dec_ptr + 1
        iny
        lda (sp),y
        sta uci_dec_target

        jsr incsp3
        jsr uci_decode
        ldx #$00
        rts
