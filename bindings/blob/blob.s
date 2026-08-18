; blob.s - the SDK as a standalone binary with a stable entry table.
;
; Toolchains cannot link each other's objects, so this is the delivery form for
; everything that is not cc65: KickAssembler, ACME, 64tass, Oscar64, llvm-mos,
; KickC, and BASIC through POKE/SYS. It is the same object files, linked
; differently - there is no second implementation.
;
; The table grows only at the end. Entries are never reordered or removed, so a
; program built against version 1 keeps working against version 5.
;
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"

        .import uci_init, uci_exec_block, uci_abort
        .import uci_present, uci_ident
        .import uci_set_timeout_a, uci_get_timeout_a, uci_last_code
        .import ultimate_init, ultimate_available, ultimate_detect
        .import ultimate_identify, ultimate_get_model, ultimate_strerror
        .import uci_req_clear, uci_decode, uci_status_fmt
        .import ultimate_palette_get, ultimate_palette_set
        .import ultimate_palette_set_color, ultimate_palette_reset
        .import ultimate_turbo_available, ultimate_turbo_get
        .import ultimate_turbo_set, ultimate_turbo_badlines

        .export blob_start

BLOB_VERSION = 1

        .segment "BLOBHDR"

blob_start:
        .byte "UCI", BLOB_VERSION       ; +$00 identification and version

        jmp uci_init                    ; +$04
        jmp uci_exec_block              ; +$07
        jmp uci_abort                   ; +$0A
        jmp uci_present                 ; +$0D
        jmp uci_ident                   ; +$10
        jmp uci_set_timeout_a           ; +$13
        jmp uci_get_timeout_a           ; +$16
        jmp uci_last_code               ; +$19
        jmp ultimate_init               ; +$1C
        jmp ultimate_available          ; +$1F
        jmp ultimate_detect             ; +$22
        jmp ultimate_identify           ; +$25
        jmp ultimate_get_model          ; +$28
        jmp ultimate_strerror           ; +$2B

        jmp uci_req_clear               ; +$2E
        jmp uci_decode                  ; +$31
        jmp uci_status_fmt              ; +$34

        jmp ultimate_palette_get        ; +$37
        jmp ultimate_palette_set        ; +$3A
        jmp ultimate_palette_set_color  ; +$3D
        jmp ultimate_palette_reset      ; +$40

        jmp ultimate_turbo_available    ; +$43
        jmp ultimate_turbo_get          ; +$46
        jmp ultimate_turbo_set          ; +$49
        jmp ultimate_turbo_badlines     ; +$4C

; ---------------------------------------------------------------------------
; The parameter block.
;
; Page-aligned so that a BASIC program driving the SDK with POKE and SYS needs
; no address arithmetic: POKE UCI+256+n, v. That is the only calling convention
; BASIC can express without a wedge, and it costs assembly and C nothing.
; ---------------------------------------------------------------------------

        .segment "BLOBPARM"

        .export blob_params
        .export bp_result, bp_devcode, bp_addr, bp_len, bp_end
        .export bp_status, bp_name, bp_reply

BP_STATUS_MAX = 32
BP_NAME_MAX   = 40
BP_REPLY_MAX  = 256

blob_params:
bp_result:  .res 1                  ; +$00  ULTIMATE_* result
bp_devcode: .res 2                  ; +$01  raw device code
bp_addr:    .res 2                  ; +$03  address argument
bp_len:     .res 2                  ; +$05  length argument
bp_end:     .res 2                  ; +$07  end address after a load
bp_status:  .res BP_STATUS_MAX      ; +$09
bp_name:    .res BP_NAME_MAX        ; +$29
bp_reply:   .res BP_REPLY_MAX       ; +$51
