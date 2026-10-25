; Run a service request that firmware may hold longer than the SDK timeout.
; Separate object: services with only bounded requests do not link this code.
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"
        .include "uci_seg.inc"

        .import uci_exec, uci_get_timeout_a, uci_set_timeout_a, ult_req
        .export ult_exec_long

        uci_code

; ult_req is already filled. Return A = result, X = 0, N/Z from A.
ult_exec_long:
        jsr uci_get_timeout_a
        pha
        lda #UCI_TIMEOUT_FOREVER
        jsr uci_set_timeout_a
        lda #<ult_req
        ldx #>ult_req
        jsr uci_exec
        tax
        pla
        jsr uci_set_timeout_a
        txa
        ldx #$00
        ora #$00
        rts
