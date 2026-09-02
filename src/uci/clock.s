; clock.s - Layer 2: the Ultimate's battery-backed clock.
;
; Two commands on the Ultimate DOS target, and they are not symmetrical.
;
; **The time comes back as text and goes in as numbers.** DOS_CMD_GET_TIME
; answers "YYYY/MM/DD HH:MM:SS" - nineteen ASCII bytes, or twenty-three with the
; weekday in front when the format byte is 1 - because that is what
; `sprintf` in software/filemanager/dos.cc produces. DOS_CMD_SET_TIME takes six
; binary bytes. Nothing here parses the text back into numbers: a program that
; wants the fields can read them out of the string it asked for, and a decoder
; that guessed wrong about a firmware change would be worse than none.
;
; **The year byte is the year less 1900.** The firmware subtracts 80 from it and
; stores the result, and prints 1980 plus that on the way out, so 2026 is 126.
; It is the one field that is not what it looks like.
;
; **SET_TIME is checked on length, not on content.** dos.cc refuses a command
; that is not exactly eight bytes long - target, command and the six numbers -
; and answers "21,UNKNOWN COMMAND" for anything else, so all six are always
; sent. Whether the numbers make a real date is the clock's business.
;
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"
        .include "uci_seg.inc"
        .include "uci_zp.inc"

        .import ult_req, ult_stage
        .import ult_req_clear, ult_exec_string, ult_have_buf, ult_invalid
        .import ult_dos_target, ult_dos_exec

        .export ultimate_get_time
        .export ultimate_set_time

; The six bytes SET_TIME wants, in the order it wants them.
ULT_TIME_YEAR   = 0
ULT_TIME_MONTH  = 1
ULT_TIME_DAY    = 2
ULT_TIME_HOUR   = 3
ULT_TIME_MINUTE = 4
ULT_TIME_SECOND = 5
ULT_TIME_BYTES  = 6

        uci_code

; ---------------------------------------------------------------------------
; ultimate_get_time   A = format, ult_buf, ult_buflen, ult_outlen
;                  -> A = ULTIMATE_* result
;
; Format 0 is "2026/08/22 14:30:00" and format 1 puts the weekday in front of
; it. Anything else is "21,UNKNOWN COMMAND", which arrives as
; ULTIMATE_ERR_NOT_SUPPORTED.
;
; The string is NUL-terminated, at most buflen-1 bytes are stored, and a buffer
; too small for it is still ULTIMATE_OK with the length that fitted - the same
; rule ultimate_getpath follows, for the same reason.
;
; ULTIMATE_TIME_BUFFER is a buffer size that always fits.
; ---------------------------------------------------------------------------
ultimate_get_time:
        sta ult_stage                   ; <fmt>

        jsr ult_have_buf
        bcc @invalid

        jsr ult_req_clear
        jsr ult_dos_target
        lda #DOS_CMD_GET_TIME
        sta ult_req + UCI_REQ_COMMAND
        lda #<ult_stage
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_stage
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$01
        sta ult_req + UCI_REQ_ARGLEN

        jsr ult_exec_string
        cmp #ULTIMATE_ERR_TRUNCATED
        bne @out
        lda #ULTIMATE_OK
@out:   ldx #$00
        ora #$00                ; N and Z from A, not the ldx
        rts

@invalid:
        jmp ult_invalid

; ---------------------------------------------------------------------------
; ultimate_set_time   ult_stage holds the six bytes, in ULT_TIME_* order
;                  -> A = ULTIMATE_* result
;
; An assembly caller fills ult_stage itself; the cc65 binding takes six
; arguments and does the same thing. Firmware that has no writable clock answers
; "99,FUNCTION NOT IMPLEMENTED".
; ---------------------------------------------------------------------------
ultimate_set_time:
        jsr ult_req_clear
        jsr ult_dos_target
        lda #DOS_CMD_SET_TIME
        sta ult_req + UCI_REQ_COMMAND
        lda #<ult_stage
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_stage
        sta ult_req + UCI_REQ_ARGS + 1
        lda #ULT_TIME_BYTES
        sta ult_req + UCI_REQ_ARGLEN
        jmp ult_dos_exec
