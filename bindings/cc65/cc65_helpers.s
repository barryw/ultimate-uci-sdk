; cc65 helpers adapters. One service per archive member keeps unrelated
; services out of C programs. Register-compatible entries live in src/uci.
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"
        .include "uci_zp.inc"

        .importzp sp
        .import ult_url
        .import ult_buf
        .import ult_outlen
        .export cc_ptr_at_y
        .export cc_hold_out
        .export cc_out_byte
        .export cc_out_ptr
        .export cc_url_at_y

; sp is the software-stack spelling supported by both cc65 2.18 and newer.

; The two bytes at (sp),y into ult_buf. Seven of the unpackers here do exactly
; this, at four different stack offsets, so the offset stays the caller's
; business in Y and the copy is written once.
cc_ptr_at_y:
        lda (sp),y
        sta ult_buf
        iny
        lda (sp),y
        sta ult_buf + 1
        rts

cc_hold_out:
        sta ult_outlen
        stx ult_outlen + 1
        rts

; A = the result to hand back, X = the byte to store through ult_outlen.
cc_out_byte:
        pha
        jsr cc_out_ptr
        bcc @none
        txa
        ldy #$00
        sta (uci_ptr),y
@none:  pla
        ldx #$00
        rts

; ult_outlen into uci_ptr. Carry set when there is somewhere to write.
cc_out_ptr:
        lda ult_outlen
        sta uci_ptr
        ora ult_outlen + 1
        beq @null
        lda ult_outlen + 1
        sta uci_ptr + 1
        sec
        rts
@null:  clc
        rts

; The two bytes at (sp),y into ult_url, which is cc_ptr_at_y for the other
; pointer this layer passes.
cc_url_at_y:
        lda (sp),y
        sta ult_url
        iny
        lda (sp),y
        sta ult_url + 1
        rts
