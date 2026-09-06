; Shared service request helpers, independent of identity and detection.
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"
        .include "uci_seg.inc"
        .include "uci_zp.inc"

        .import uci_exec, ult_req, ult_buf, ult_buflen, ult_outlen
        .export ult_req_clear, ult_exec_string, ult_have_buf, ult_invalid

        uci_code

; ---------------------------------------------------------------------------
; Internal: zero the service layer's request block.
; ---------------------------------------------------------------------------
ult_req_clear:
        lda #$00
        ldx #UCI_REQ_SIZE - 1
@loop:  sta ult_req,x
        dex
        bpl @loop
        rts

; ---------------------------------------------------------------------------
; Internal: did the caller give us somewhere to put the answer?
;
; Carry set when ult_buf and ult_buflen are both non-zero. Six entry points ask
; exactly this before they touch the hardware, and the answer is always the same
; five instructions - so it is written once here and jsr'd, which is smaller
; than six copies and harder to get subtly different.
; ---------------------------------------------------------------------------
ult_have_buf:
        lda ult_buf
        ora ult_buf + 1
        beq @none
        lda ult_buflen
        ora ult_buflen + 1
        beq @none
        sec
        rts
@none:  clc
        rts

; ---------------------------------------------------------------------------
; Internal: the answer to a caller that asked for something impossible.
;
; A tail, not a subroutine: jmp here rather than jsr. Ten entry points end this
; way, and X is zero because that is what a cc65 caller needs to see for an
; unsigned char return.
; ---------------------------------------------------------------------------
ult_invalid:
        ldx #$00
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        rts

; ---------------------------------------------------------------------------
; Internal: run ult_req and NUL-terminate the reply in ult_buf.
;
; Every caller of this wants the same three things afterwards: the exchange run,
; the caller's buffer terminated so C can use it as a string, and the length
; reported through ult_outlen if one was asked for.
; ---------------------------------------------------------------------------
ult_exec_string:
        ; datamax = buflen - 1, leaving room for the terminator
        sec
        lda ult_buflen
        sbc #$01
        sta ult_req + UCI_REQ_DATAMAX
        lda ult_buflen + 1
        sbc #$00
        sta ult_req + UCI_REQ_DATAMAX + 1

        lda ult_buf
        sta ult_req + UCI_REQ_DATA
        lda ult_buf + 1
        sta ult_req + UCI_REQ_DATA + 1

        lda #<ult_req
        ldx #>ult_req
        jsr uci_exec
        pha                     ; keep the result across the bookkeeping

        ; terminate at buf[datalen]
        clc
        lda ult_buf
        adc ult_req + UCI_REQ_DATALEN
        sta uci_ptr
        lda ult_buf + 1
        adc ult_req + UCI_REQ_DATALEN + 1
        sta uci_ptr + 1
        lda #$00
        ldy #$00
        sta (uci_ptr),y

        ; report the length if the caller wanted it
        lda ult_outlen
        ora ult_outlen + 1
        beq @no_outlen
        lda ult_outlen
        sta uci_ptr
        lda ult_outlen + 1
        sta uci_ptr + 1
        ldy #$00
        lda ult_req + UCI_REQ_DATALEN
        sta (uci_ptr),y
        iny
        lda ult_req + UCI_REQ_DATALEN + 1
        sta (uci_ptr),y
@no_outlen:
        pla
        rts
