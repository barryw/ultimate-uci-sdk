; turbo.s - the Ultimate 64's CPU speed.
;
; **This module touches hardware registers directly, and it is allowed to.**
; The rule everywhere else in the SDK - services are built out of uci_exec and
; never write a register - is about not reimplementing the transport. Here
; there is no transport to reimplement: the control target's full command set is
; in docs/generated/protocol-constants.md and nothing in it touches CPU speed.
; Turbo is memory-mapped I/O and nothing else. reu.s in Phase 3 is the only
; other module with this exemption, for the same reason.
;
;   $D031  bits 0-3  speed index into the machine's own table
;          bit 7     1 = badlines off, so the VIC stops stealing cycles
;   $D030  bit 0     only in "TurboEnable Bit" mode; not used here
;
; Three facts that shape all four entry points:
;
; - **The register reads $FF when turbo is unavailable**, which makes
;   availability testable instead of assumed. Available means the machine's
;   "Turbo Control" setting is "U64 Turbo Registers" or "TurboEnable Bit" - a
;   program cannot set that for itself, so anything shipping to other people has
;   to cope with turbo simply not being there. On a plain C64 the same read
;   returns $FF too, because unimplemented VIC registers do.
;
; - **The speed index is not portable above 4 MHz.** The U64's table is
;   1,2,3,4,5,6,8,10,12,14,16,20,24,32,40,48 and the U64-II's is
;   1,2,3,4,6,8..64, so index 4 is 5 MHz on one machine and 6 MHz on the other.
;   Only U64_SPEED_1MHZ..U64_SPEED_4MHZ mean the same thing on both. The SDK
;   passes the index through rather than pretending to know megahertz.
;
; - **Setting the speed must not disturb the badline bit, and vice versa**,
;   because they share a register and a demo wants to change one without
;   thinking about the other.
;
; Nothing here allocates, blocks, or can fail slowly: every entry point is a
; register read, a branch and possibly a register write.
;
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"
        .include "uci_seg.inc"

        .export ultimate_turbo_available, _ultimate_turbo_available
        .export ultimate_turbo_get,       _ultimate_turbo_get
        .export ultimate_turbo_set,       _ultimate_turbo_set
        .export ultimate_turbo_badlines,  _ultimate_turbo_badlines

        uci_code

; ---------------------------------------------------------------------------
; ultimate_turbo_available  ->  A = 1 when the turbo registers answer, 0 when not
; ---------------------------------------------------------------------------
ultimate_turbo_available:
_ultimate_turbo_available:
        lda U64_REG_TURBO
        cmp #U64_TURBO_UNAVAILABLE
        beq @no
        lda #$01
        ldx #$00
        rts
@no:    lda #$00
        ldx #$00
        rts

; ---------------------------------------------------------------------------
; ultimate_turbo_get  ->  A = the current speed index, or U64_TURBO_UNAVAILABLE
;
; $FF is not a speed: the index is four bits, so an unavailable machine and a
; real answer can never be confused.
; ---------------------------------------------------------------------------
ultimate_turbo_get:
_ultimate_turbo_get:
        lda U64_REG_TURBO
        cmp #U64_TURBO_UNAVAILABLE
        beq @out
        and #U64_TURBO_SPEED_MASK
@out:   ldx #$00
        rts

; ---------------------------------------------------------------------------
; ultimate_turbo_set   A = speed index 0-15  ->  A = ULTIMATE_* result
;
; An index past the fifteenth is refused rather than masked: masking would turn
; a caller's mistake into a silent speed change, and the top bit of a masked
; value is the badline bit, which is not the caller's to set from here.
; ---------------------------------------------------------------------------
ultimate_turbo_set:
_ultimate_turbo_set:
        cmp #U64_TURBO_SPEED_MASK + 1
        bcs @invalid
        tay                             ; Y = the index we were asked for

        lda U64_REG_TURBO
        cmp #U64_TURBO_UNAVAILABLE
        beq @absent

        ; Rebuild the register from the requested speed plus the badline bit
        ; exactly as it stands. There is no scratch byte and no self-modified
        ; code here on purpose: this module has to work from a cartridge ROM.
        and #U64_TURBO_NO_BADLINES
        beq @badlines_on
        tya
        ora #U64_TURBO_NO_BADLINES
        bne @store                      ; bit 7 is set, so always taken
@badlines_on:
        tya
@store: sta U64_REG_TURBO
        lda #ULTIMATE_OK
        ldx #$00
        rts

@absent:
        lda #ULTIMATE_ERR_NOT_SUPPORTED
        ldx #$00
        rts

@invalid:
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        ldx #$00
        rts

; ---------------------------------------------------------------------------
; ultimate_turbo_badlines   A = 0 to stop the VIC stealing cycles,
;                           non-zero to put badlines back
;                        -> A = ULTIMATE_* result
;
; The argument reads as "are badlines on?", which is the way round a caller
; thinks about it; the register stores the opposite, which is why this exists
; rather than leaving the bit to the caller.
;
; Worth about 25 lines of stolen cycles per frame on a stock machine, and it is
; the one turbo feature that is a real win at 1 MHz too.
; ---------------------------------------------------------------------------
ultimate_turbo_badlines:
_ultimate_turbo_badlines:
        tay                             ; Y = 0 means "no badlines"

        lda U64_REG_TURBO
        cmp #U64_TURBO_UNAVAILABLE
        beq @absent

        and #U64_TURBO_SPEED_MASK       ; keep the speed exactly as it was
        cpy #$00
        bne @store                      ; badlines on: bit 7 stays clear
        ora #U64_TURBO_NO_BADLINES
@store: sta U64_REG_TURBO
        lda #ULTIMATE_OK
        ldx #$00
        rts

@absent:
        lda #ULTIMATE_ERR_NOT_SUPPORTED
        ldx #$00
        rts
