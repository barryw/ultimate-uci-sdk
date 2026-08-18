; loader.s - the .prg that installs the wedge.
;
;   LOAD "UCI",8
;   RUN
;
; One BASIC line, SYS 2061, then this. It copies the wedge to its run address,
; installs the vectors, prints the banner, and performs a NEW so $0801 is empty
; again - the loader is above the stub and survives its own NEW, because NEW
; resets pointers rather than clearing RAM, and by the time anything is typed
; over it the wedge has already been copied out.
;
; SPDX-License-Identifier: MIT

        .include "c64rom.inc"

        .import wedge_install
        .import __WEDGE_LOAD__, __WEDGE_RUN__, __WEDGE_SIZE__

        .export boot, wedge_copy

; The loader runs once, before the wedge or the SDK is live, so it can use the
; four free zero page bytes without colliding with either.
PTR_SRC = $FB
PTR_DST = $FD

; ---------------------------------------------------------------------------
; 10 SYS 2061
; ---------------------------------------------------------------------------

; The two-byte load address a .prg starts with.
        .segment "LOADADDR"
        .addr $0801

        .segment "BASSTUB"

        .word @next             ; link to the next line
        .word 10                ; line number
        .byte $9E               ; SYS
        .byte "2061", $00       ; ...which is boot, immediately below
@next:  .word $0000             ; end of program

; ---------------------------------------------------------------------------

        .segment "CODE"

boot:
        jsr wedge_copy
        jsr wedge_install

        lda #<banner
        ldy #>banner
        jsr STROUT

        jsr SCRTCH              ; NEW: $0801 is the user's again
        jmp READY

; Copying is its own entry point because boot never returns - it lands in the
; direct-mode loop - and a test has to be able to get the wedge to $C000 and
; carry on.
wedge_copy:
        lda #<__WEDGE_LOAD__
        sta PTR_SRC
        lda #>__WEDGE_LOAD__
        sta PTR_SRC+1
        lda #<__WEDGE_RUN__
        sta PTR_DST
        lda #>__WEDGE_RUN__
        sta PTR_DST+1

        ldx #>__WEDGE_SIZE__    ; whole pages first
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

@tail:  cpy #<__WEDGE_SIZE__    ; then the odd bytes
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
banner:
        .byte $0D
        .byte "ULTIMATE UCI BASIC WEDGE INSTALLED."
        .byte $0D
        .byte "VIVA LA COMMODORE!"
        .byte $0D, $00
