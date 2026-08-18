; cart.s - the same wedge, as an autostart cartridge.
;
; Power on and it is there: nothing to load, nothing to type, and it survives a
; reset, which the .prg cannot. The cost is BASIC's memory, because an 8K
; cartridge at $8000-$9FFF is mapped for as long as it is plugged in - 38K of
; BASIC RAM becomes 28K. Shipping both builds is what keeps that a choice
; rather than a tax.
;
; **The cartridge is a delivery mechanism, not a second implementation.** It
; carries the same CODE and RODATA the .prg carries, and copies them to the
; same $C000, because the wedge keeps its state beside its code and ROM cannot
; hold state. Nothing here is a port of anything.
;
; The cold start is BASIC's own, opened up: the ROM's sequence at $E394 is
; initv, initcz, initms, set the stack, then READY. The wedge is installed in
; the gap before READY, which is the one moment when BASIC is fully set up and
; has not yet looked at a vector.
;
; SPDX-License-Identifier: MIT

        .include "c64rom.inc"

        .import wedge_install, wedge_copy, wedge_banner

; KERNAL jump table, not the routines behind it: these three entries have been
; the documented way in since 1982.
CINT            = $FF81         ; screen editor
IOINIT          = $FF84         ; CIAs, timers, IRQ
RAMTAS          = $FF87         ; RAM test and the memory pointers
RESTOR          = $FF8A         ; KERNAL vectors to their defaults

; BASIC's own cold start, in pieces.
BASIC_INITV     = $E453         ; the $0300 vectors
BASIC_INITCZ    = $E3BF         ; zero page, including CHRGET
BASIC_INITMS    = $E422         ; the sign-on message and free-memory count

        .segment "CARTHDR"

        .addr cart_cold         ; cold start
        .addr cart_cold         ; warm start: a reset comes back here too
        .byte $C3, $C2, $CD, $38, $30   ; "CBM80", the autostart signature

        .segment "LOADER"

cart_cold:
        sei
        ldx #$FF                ; a stack to run the init sequence on
        txs
        cld

        jsr IOINIT
        jsr RAMTAS
        jsr RESTOR
        jsr CINT
        cli

        jsr BASIC_INITV
        jsr BASIC_INITCZ
        jsr BASIC_INITMS
        ldx #$FB                ; where BASIC's own cold start leaves it
        txs

        jsr wedge_copy          ; ROM to RAM: the wedge keeps state
        jsr wedge_install

        lda #<wedge_banner
        ldy #>wedge_banner
        jsr STROUT

        jmp READY
