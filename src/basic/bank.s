; bank.s - reaching the SDK, which lives under BASIC ROM.
;
; Phase 3 took the wedge and the SDK together past the 4K at $C000, so the SDK
; moved to $A000 and the wedge kept the block. $A000-$BFFF is RAM that a read
; cannot see while BASIC ROM is banked in, so every call into the SDK goes
; through one of the stubs below: bank the ROM out, call, bank it back.
;
; **This is the cheap half of the trade, and that is the whole point.** Putting
; the *hook handlers* under ROM would have been the expensive half - `IGONE` is
; called by BASIC ROM, so it cannot reach a handler that is not there, and the
; wedge calls ROM routines like `GETBYT` and `CHRGET` to parse its own
; arguments. None of that applies here: the SDK is never called by BASIC ROM
; and calls no BASIC routine, so twelve bytes and about fifteen cycles per call
; buy the whole block back. See docs/superpowers/specs, section 8.
;
; Three things make the stubs safe to use anywhere the wedge already runs:
;
;   - **A survives.** It is the argument to uci_exec (pointer low byte) and to
;     ultimate_turbo_set, and it is the result on the way back, so the bank
;     switch is wrapped in pha/pla going in and uses Y coming out.
;   - **X and Y.** X is the pointer's high byte going in and part of the result
;     of uci_last_code coming back, so it is never touched. Y is documented as
;     clobbered by every SDK entry point, which is what makes it free for the
;     restore.
;   - **Interrupts stay on.** $36 leaves the KERNAL and I/O banked in, so the
;     interrupt handler at $EA31 is still there and still works; only BASIC ROM
;     goes away, and nothing in an interrupt reaches for it. There is no `sei`
;     here on purpose - a `jsr uci_exec` can poll for a long time, and stopping
;     the jiffy clock for it would be a worse bargain than the fifteen cycles.
;
; The SDK's variables are not affected. They are in BSS at $C000, which is RAM
; whatever $01 says, and so is its RODATA.
;
; SPDX-License-Identifier: MIT

        .include "c64rom.inc"

        .import uci_init, uci_exec, uci_abort, uci_last_code
        .import ultimate_turbo_set, ultimate_turbo_get
        .import ultimate_load, ultimate_bload, ultimate_save
        .import ultimate_opendir, ultimate_readdir
        .import ultimate_reu_stash, ultimate_reu_fetch

        .export bank_uci_init, bank_uci_exec, bank_uci_abort
        .export bank_uci_last_code
        .export bank_turbo_set, bank_turbo_get
        .export bank_load, bank_bload, bank_save
        .export bank_opendir, bank_readdir
        .export bank_reu_stash, bank_reu_fetch

; $37 is the machine as BASIC left it: BASIC ROM, KERNAL and I/O all mapped.
; $36 is the same with BASIC ROM swapped for the RAM underneath it.
BANK_RAM = $36
BANK_ROM = $37

        .segment "CODE"

.macro  banked  target
        pha                     ; A is an argument on the way in
        lda #BANK_RAM
        sta CPU_PORT
        pla
        jsr target
        ldy #BANK_ROM           ; ...and the result on the way out, so Y does this
        sty CPU_PORT
        rts
.endmacro

bank_uci_init:
        banked uci_init

bank_uci_exec:
        banked uci_exec

bank_uci_abort:
        banked uci_abort

bank_uci_last_code:
        banked uci_last_code

bank_turbo_set:
        banked ultimate_turbo_set

bank_turbo_get:
        banked ultimate_turbo_get

; The file and REU services. Their arguments are in the shared variable block,
; which is BSS at $C000 and needs no banking at all - only the call does.

bank_load:
        banked ultimate_load

bank_bload:
        banked ultimate_bload

bank_save:
        banked ultimate_save

bank_opendir:
        banked ultimate_opendir

bank_readdir:
        banked ultimate_readdir

bank_reu_stash:
        banked ultimate_reu_stash

bank_reu_fetch:
        banked ultimate_reu_fetch
