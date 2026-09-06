; cc65 dos adapters. One service per archive member keeps unrelated
; services out of C programs. Register-compatible entries live in src/uci.
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"
        .include "uci_zp.inc"

        .importzp sp
        .import ultimate_getpath
        .import ultimate_readdir
        .import ultimate_open
        .import ultimate_read
        .import ultimate_write
        .import ultimate_seek
        .import ult_buflen
        .import ult_outlen
        .import ult_attrib
        .import ult_num
        .import incsp2
        .import incsp4
        .importzp sreg
        .import cc_ptr_at_y
        .export _ultimate_getpath
        .export _ultimate_read
        .export _ultimate_readdir
        .export _ultimate_open
        .export _ultimate_write
        .export _ultimate_seek

; ---------------------------------------------------------------------------
; The DOS service. Its wide parameters go in the same shared block as the rest
; of the service layer, so these move cc65's stacked arguments into it and get
; out of the way.
; ---------------------------------------------------------------------------

; Internal: A/X = the last argument, stack = <word> <pointer>. Leaves the
; pointer in ult_buf, the word in ult_buflen and the last argument in
; ult_outlen, which is the shape ultimate_identify already established.
cc_buf_len_out:
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
        jmp incsp4

; uint8_t ultimate_getpath(char *buf, uint16_t buflen, uint16_t *outlen);
_ultimate_getpath:
        jsr cc_buf_len_out
        jsr ultimate_getpath
        ldx #$00
        rts

; uint8_t ultimate_read(uint8_t *buf, uint16_t len, uint16_t *outlen);
_ultimate_read:
        jsr cc_buf_len_out
        jsr ultimate_read
        ldx #$00
        rts

; uint8_t ultimate_readdir(char *name, uint16_t namelen, uint8_t *attrib);
;
; attrib rides in on ult_outlen only to be borrowed as a pointer here: readdir
; itself reports the attributes in ult_attrib, and this writes them through.
_ultimate_readdir:
        jsr cc_buf_len_out
        jsr ultimate_readdir
        pha
        lda ult_outlen
        ora ult_outlen + 1
        beq @none
        lda ult_outlen
        sta uci_ptr
        lda ult_outlen + 1
        sta uci_ptr + 1
        ldy #$00
        lda ult_attrib
        sta (uci_ptr),y
@none:  pla
        ldx #$00
        rts

; uint8_t ultimate_open(const char *name, uint8_t attrib);
;
; A holds attrib; the C stack holds the name pointer at 0..1.
_ultimate_open:
        pha
        ldy #$00
        jsr cc_ptr_at_y
        jsr incsp2
        pla
        jsr ultimate_open
        ldx #$00
        rts

; uint8_t ultimate_write(const uint8_t *buf, uint16_t len);
;
; A/X holds len; the C stack holds the buffer pointer at 0..1.
_ultimate_write:
        sta ult_buflen
        stx ult_buflen + 1
        ldy #$00
        jsr cc_ptr_at_y
        jsr incsp2
        jsr ultimate_write
        ldx #$00
        rts

; uint8_t ultimate_seek(uint32_t pos);
;
; cc65 passes a long in A/X plus sreg: A is bits 0-7, X bits 8-15, and sreg the
; high word.
_ultimate_seek:
        sta ult_num
        stx ult_num + 1
        lda sreg
        sta ult_num + 2
        lda sreg + 1
        sta ult_num + 3
        jsr ultimate_seek
        ldx #$00
        rts
