; install.s - what the .prg loader and the cartridge both need.
;
; The wedge and the SDK are assembled to run at $C000 but travel wherever the
; build puts them - inside a .prg, or in cartridge ROM - so both delivery
; mechanisms start by copying them there. That copy is the only thing they
; share, and it lives here rather than in two places that could drift.
;
; SPDX-License-Identifier: MIT

        .include "c64rom.inc"

        .import __CODE_LOAD__, __CODE_RUN__, __CODE_SIZE__
        .import __RODATA_SIZE__

        .export wedge_copy, wedge_banner

; The copy runs once, before the wedge or the SDK is live, so it can use the
; four free zero page bytes without colliding with either.
PTR_SRC = $FB
PTR_DST = $FD

        .segment "LOADER"

; CODE and RODATA are contiguous in both places, so one walk moves both.
wedge_copy:
        lda #<__CODE_LOAD__
        sta PTR_SRC
        lda #>__CODE_LOAD__
        sta PTR_SRC+1
        lda #<__CODE_RUN__
        sta PTR_DST
        lda #>__CODE_RUN__
        sta PTR_DST+1

        ldx #>(__CODE_SIZE__ + __RODATA_SIZE__)   ; whole pages first
        ldy #$00
@pages: cpx #$00
        beq @tail
@page:  lda (PTR_SRC),y
        sta (PTR_DST),y
        iny
        bne @page
        inc PTR_SRC+1
        inc PTR_DST+1
        dex
        jmp @pages

@tail:  cpy #<(__CODE_SIZE__ + __RODATA_SIZE__)   ; then the odd bytes
        beq @copied
        lda (PTR_SRC),y
        sta (PTR_DST),y
        iny
        bne @tail
@copied:
        rts

; Display text, not protocol text: this goes to the screen through CHROUT, so
; the c64 charmap turning it into PETSCII is exactly what is wanted. The rule
; it looks like it breaks - never put protocol bytes in a string literal - is
; about bytes that go on the wire.
wedge_banner:
        .byte $0D
        .byte "ULTIMATE UCI BASIC WEDGE INSTALLED."
        .byte $0D
        .byte "VIVA LA COMMODORE!"
        .byte $0D, $00
