; Keep Machine Yearning's shared zero-page state separate from cc65 and the SDK.
;
; The PSID player initializes and uses $06-$FF. cc65 overlaps at $06-$1B and
; the SDK uses $FB-$FE. Only those 26 bytes need swapping; the SID shadows at
; $39-$70 and $89-$A1 can remain in zero page and be read directly by C.
;
; SPDX-License-Identifier: MIT

        .export _music_init, _music_play, _visualizer_level
        .export _machine_reset

        .segment "BSS"
music_low: .res 22
c_low:     .res 22
music_high:.res 4
c_high:    .res 4
_visualizer_level: .res 6

        .segment "CODE"

; void __fastcall__ music_init(uint8_t tune)
_music_init:
        pha
        ldx #21
@save_low:
        lda $06,x
        sta c_low,x
        dex
        bpl @save_low
        ldx #3
@save_high:
        lda $FB,x
        sta c_high,x
        dex
        bpl @save_high
        pla
        jsr $1000
        ldx #21
@keep_low:
        lda $06,x
        sta music_low,x
        lda c_low,x
        sta $06,x
        dex
        bpl @keep_low
        ldx #3
@keep_high:
        lda $FB,x
        sta music_high,x
        lda c_high,x
        sta $FB,x
        dex
        bpl @keep_high
        rts

; void music_play(void)
_music_play:
        ldx #21
@in_low:
        lda $06,x
        sta c_low,x
        lda music_low,x
        sta $06,x
        dex
        bpl @in_low
        ldx #3
@in_high:
        lda $FB,x
        sta c_high,x
        lda music_high,x
        sta $FB,x
        dex
        bpl @in_high
        jsr $1003
        ldx #21
@out_low:
        lda $06,x
        sta music_low,x
        lda c_low,x
        sta $06,x
        dex
        bpl @out_low
        ldx #3
@out_high:
        lda $FB,x
        sta music_high,x
        lda c_high,x
        sta $FB,x
        dex
        bpl @out_high
        rts

_machine_reset:
        jmp $FCE2
