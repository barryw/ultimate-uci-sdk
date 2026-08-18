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
        .include "uci_seg.inc"

        .export ultimate_strerror, _ultimate_strerror

        uci_code

; ultimate_strerror   A = ULTIMATE_* code  ->  A/X = pointer to the text
ultimate_strerror:
_ultimate_strerror:
        cmp #ULTIMATE_ERR_COUNT
        bcc @known
        lda #ULTIMATE_ERR_COUNT ; the "unknown" entry sits one past the end
@known: asl a
        tax
        lda ult_err_table,x
        pha
        lda ult_err_table + 1,x
        tax
        pla
        rts

        .rodata

; **The strings are lowercase in the source and print as uppercase.**
;
; ca65's c64 charmap maps source 'A'-'Z' to PETSCII $C1-$DA, and CHROUT turns
; those into screen codes $41-$5A - which are graphics symbols, not letters. It
; is source 'a'-'z' that becomes PETSCII $41-$5A and displays as ABC. Written
; the obvious way, every one of these printed as a row of glyphs on a real
; machine; the wedge's banner did too, and that is how it was noticed.
ult_err_table:
        .addr ult_e_ok, ult_e_nodev, ult_e_timeout, ult_e_proto
        .addr ult_e_unsup, ult_e_arg, ult_e_io, ult_e_device
        .addr ult_e_trunc, ult_e_abort, ult_e_end, ult_e_unknown

; The count is generated with the codes themselves, and the table is asserted
; against it here. It used to be a hand-written 10 sitting beside ten generated
; codes, so an eleventh would have printed "unknown error" for ever with nothing
; failing - which is exactly what ULTIMATE_END would have done.
.assert (* - ult_err_table) = 2 * (ULTIMATE_ERR_COUNT + 1), error, "the strerror table and ULTIMATE_ERR_COUNT have drifted apart"

ult_e_ok:      .byte "ok", 0
ult_e_nodev:   .byte "no ultimate found", 0
ult_e_timeout: .byte "timeout", 0
ult_e_proto:   .byte "protocol error", 0
ult_e_unsup:   .byte "not supported", 0
ult_e_arg:     .byte "invalid argument", 0
ult_e_io:      .byte "i/o error", 0
ult_e_device:  .byte "device error", 0
ult_e_trunc:   .byte "reply truncated", 0
ult_e_abort:   .byte "aborted", 0
ult_e_end:     .byte "no more entries", 0
ult_e_unknown: .byte "unknown error", 0
