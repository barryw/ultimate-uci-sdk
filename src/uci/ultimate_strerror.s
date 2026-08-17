; ultimate_strerror.s - result code to printable text.
;
; Its own module because splitting it out saves 176 bytes (18 of code, 158 of
; strings) that a program which never prints an error should not link. ld65
; drops an unreferenced module whole, so the split is the whole mechanism - no
; build flags.
;
; These strings go through ca65's c64 charmap and come out PETSCII, which is
; what CHROUT wants. That is the opposite of every other byte in the SDK; see
; docs/api-design.md, "Protocol bytes are never string literals".
;
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"

        .export ultimate_strerror, _ultimate_strerror

        .code

; ultimate_strerror   A = ULTIMATE_* code  ->  A/X = pointer to the text
ultimate_strerror:
_ultimate_strerror:
        cmp #ULT_ERR_COUNT
        bcc @known
        lda #ULT_ERR_COUNT      ; the "unknown" entry sits one past the end
@known: asl a
        tax
        lda ult_err_table,x
        pha
        lda ult_err_table + 1,x
        tax
        pla
        rts

        .rodata

ULT_ERR_COUNT = 10

ult_err_table:
        .addr ult_e_ok, ult_e_nodev, ult_e_timeout, ult_e_proto
        .addr ult_e_unsup, ult_e_arg, ult_e_io, ult_e_device
        .addr ult_e_trunc, ult_e_abort, ult_e_unknown

ult_e_ok:      .byte "OK", 0
ult_e_nodev:   .byte "NO ULTIMATE FOUND", 0
ult_e_timeout: .byte "TIMEOUT", 0
ult_e_proto:   .byte "PROTOCOL ERROR", 0
ult_e_unsup:   .byte "NOT SUPPORTED", 0
ult_e_arg:     .byte "INVALID ARGUMENT", 0
ult_e_io:      .byte "I/O ERROR", 0
ult_e_device:  .byte "DEVICE ERROR", 0
ult_e_trunc:   .byte "REPLY TRUNCATED", 0
ult_e_abort:   .byte "ABORTED", 0
ult_e_unknown: .byte "UNKNOWN ERROR", 0
