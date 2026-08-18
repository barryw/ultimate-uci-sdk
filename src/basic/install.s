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
        .import __RODATA_SIZE__, __RODATA_LOAD__
        .import __UCICODE_LOAD__, __UCICODE_RUN__, __UCICODE_SIZE__

        .export wedge_copy, wedge_banner

; The copy runs once, before the wedge or the SDK is live, so it can use the
; four free zero page bytes without colliding with either.
PTR_SRC = $FB
PTR_DST = $FD

; The four free zero page bytes are exactly two pointers, and the copy now
; needs a length as well. It goes in BSS rather than in a fifth zero page byte
; nobody promised us: BSS sits above the region being copied into, so writing it
; first cannot be overwritten by the copy that follows, and it is RAM in the
; cartridge build too, where the LOADER segment is ROM and could not hold it.
        .bss
COUNT:  .res 2

        .segment "LOADER"

; Two blocks now, not one.
;
; CODE and RODATA are contiguous in both places and go to $C000, so one walk
; still moves both. UCICODE is the SDK, which runs at $A000 under BASIC ROM -
; see bank.s - and needs a walk of its own.
;
; **Neither walk banks anything.** A 6510 write always goes to RAM; it is only
; a read that sees ROM. So writing the SDK into $A000-$BFFF works with the
; machine exactly as BASIC left it, and $01 is never touched here.
;
; The first walk depends on CODE and RODATA being adjacent in the load image as
; well as at $C000, which is a property of the segment order in the linker
; config and not of anything visible here. Adding UCICODE between them broke it
; silently: the copy moved CODE plus the first bytes of the SDK, RODATA never
; arrived, and the status decoder read its digit-weight tables out of whatever
; had landed on top of them - so a command that worked perfectly came back as
; ULTIMATE_ERR_DEVICE. Hence the assert.
.assert __RODATA_LOAD__ = __CODE_LOAD__ + __CODE_SIZE__, error, "CODE and RODATA are no longer adjacent in the load image, and wedge_copy moves them as one span"

wedge_copy:
        lda #<__CODE_LOAD__
        ldx #>__CODE_LOAD__
        ldy #<__CODE_RUN__
        jsr @setup
        lda #>__CODE_RUN__
        sta PTR_DST+1
        lda #<(__CODE_SIZE__ + __RODATA_SIZE__)
        sta COUNT
        lda #>(__CODE_SIZE__ + __RODATA_SIZE__)
        sta COUNT+1
        jsr @move

        lda #<__UCICODE_LOAD__
        ldx #>__UCICODE_LOAD__
        ldy #<__UCICODE_RUN__
        jsr @setup
        lda #>__UCICODE_RUN__
        sta PTR_DST+1
        lda #<__UCICODE_SIZE__
        sta COUNT
        lda #>__UCICODE_SIZE__
        sta COUNT+1
        jsr @move
        jmp @copied

@setup: sta PTR_SRC
        stx PTR_SRC+1
        sty PTR_DST
        rts

; PTR_SRC -> PTR_DST, COUNT bytes.
@move:  ldx COUNT+1             ; whole pages first
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

@tail:  cpy COUNT               ; then the odd bytes
        beq @done
        lda (PTR_SRC),y
        sta (PTR_DST),y
        iny
        bne @tail
@done:  rts

@copied:
        rts

; **Written lowercase on purpose. It displays uppercase.**
;
; ca65's c64 charmap maps source 'A'-'Z' to PETSCII $C1-$DA and source 'a'-'z'
; to $41-$5A. CHROUT turns the first range into screen codes $41-$5A, which in
; the default character set are graphics symbols, and the second into $01-$1A,
; which are the letters. So "ULTIMATE" prints as a row of glyphs and "ultimate"
; prints as ULTIMATE. This was found by looking at a real screen; a decoder
; that maps both ranges back to letters hides it completely.
wedge_banner:
        .byte $0D
        .byte "ultimate uci basic wedge installed."
        .byte $0D
        .byte "viva la commodore!"
        .byte $0D, $00
