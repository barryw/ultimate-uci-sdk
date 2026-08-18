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
; The cartridge in cart.s is the same payload reached a different way.
;
; SPDX-License-Identifier: MIT

        .include "c64rom.inc"

        .import wedge_install, wedge_copy, wedge_banner

        .export boot

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

        .segment "LOADER"

boot:
        jsr wedge_copy
        jsr wedge_install

        lda #<wedge_banner
        ldy #>wedge_banner
        jsr STROUT

        jsr SCRTCH              ; NEW: $0801 is the user's again
        jmp READY
