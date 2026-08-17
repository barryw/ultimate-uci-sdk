; ultimate_asm.s - convenience layer for assembly callers.
;
; The core in src/uci/uci_core.s already takes its request block by pointer, so
; this adds only what a program would otherwise write for itself: a request
; block to use, and a way to clear it.
;
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"

        .import uci_exec

        .export uci_exec_block
        .export uci_req_clear


; With UCI_VARS defined the whole SDK is equates off one address, so the
; request block comes from uci_core.s and nothing here reserves storage.
.ifdef UCI_VARS
        .import uci_req
.else
        .export uci_req
        .bss
uci_req:
        .res UCI_REQ_SIZE
.endif

        .code

; Run the command described by uci_req. A = ULTIMATE_* result.
uci_exec_block:
        lda #<uci_req
        ldx #>uci_req
        jmp uci_exec

; Zero the request block. Call it before setting up a command unless you set
; every field yourself; a stale pointer from a previous command is a bug that is
; unpleasant to find.
uci_req_clear:
        lda #$00
        ldx #UCI_REQ_SIZE - 1
@loop:  sta uci_req,x
        dex
        bpl @loop
        rts
