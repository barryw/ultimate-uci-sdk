; cc65 audio adapters. One service per archive member keeps unrelated
; services out of C programs. Register-compatible entries live in src/uci.
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"
        .include "uci_zp.inc"

        .importzp sp
        .import ultimate_audio_start
        .import incsp1
        .export _ultimate_audio_start

; uint8_t ultimate_audio_start(uint8_t channel, uint8_t flags);
;
; A holds flags; the C stack holds channel. The assembly entry takes A/X so it
; remains pleasant to call without dragging the C stack into the core.
_ultimate_audio_start:
        pha                             ; flags
        ldy #$00
        lda (sp),y
        pha                             ; channel
        jsr incsp1
        pla
        tay                             ; channel
        pla
        tax                             ; flags
        tya
        jmp ultimate_audio_start
