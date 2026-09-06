; cc65 wav adapters. One service per archive member keeps unrelated
; services out of C programs. Register-compatible entries live in src/uci.
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"
        .include "uci_zp.inc"

        .importzp sp
        .import ultimate_audio_load_wav
        .import ult_reu
        .import incsp6
        .import cc_ptr_at_y
        .export _ultimate_audio_load_wav

; uint8_t ultimate_audio_load_wav(const char *name, uint32_t reuaddr,
;                                 ultimate_audio_voice *voice);
;
; A/X holds voice; the C stack holds reuaddr at 0..3 and name at 4..5.
_ultimate_audio_load_wav:
        pha
        txa
        pha
        ldy #$00
        lda (sp),y
        sta ult_reu
        iny
        lda (sp),y
        sta ult_reu + 1
        iny
        lda (sp),y
        sta ult_reu + 2
        iny
        lda (sp),y
        sta ult_reu + 3
        iny
        jsr cc_ptr_at_y                 ; name -> ult_buf
        jsr incsp6
        pla
        tax
        pla
        jmp ultimate_audio_load_wav
