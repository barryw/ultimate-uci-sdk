; dispatch.s - the wedge's IGONE and IEVAL halves: making the tokens run.
;
;   IGONE   statement position    UCI t, c [, arg ...]
;   IEVAL   expression position   UERR UDEV ULEN UST$ UDAT$ UBYTE( and the
;                                 six target constants
;
; **`IF X THEN UCI ...` does not work, and cannot.** BASIC's IF jumps straight
; to the ROM's statement dispatcher rather than going back through IGONE, and
; that dispatcher rejects any token above NEW. Every extension that adds
; statement keywords to BASIC V2 has this hole. Functions are unaffected -
; expression evaluation does go through IEVAL - so `IF UERR THEN ...` is fine,
; and the workaround for the other direction is `IF X THEN 100`.
;
; Errors never reach BASIC. A failed command sets UERR and returns, because a
; demo dropping to READY. in the middle of a part is worse than a load that
; quietly did nothing. That mirrors DS/DS$ from the CBM DOS wedges.
;
; SPDX-License-Identifier: MIT

        .include "c64rom.inc"
        .include "uci_protocol.inc"
        .include "uci_keywords.inc"

        .import uci_init, uci_exec, uci_abort, uci_last_code, uci_req

        .export wedge_gone, wedge_eval, wedge_do_uci, wedge_sdk_init
        .export wedge_err, wedge_target, wedge_command, wedge_arglen
        .export wedge_argbuf, wedge_reply, wedge_status

; The reply buffer sizes UBYTE( exactly and covers what the generic form is
; for: directory entries, paths, identification strings. A longer reply sets
; UERR to ULTIMATE_ERR_TRUNCATED; the transport still drains it, so the
; interface is never left mid-transfer.
WEDGE_REPLY_SIZE  = 256
WEDGE_STATUS_SIZE = 40
WEDGE_ARG_SIZE    = 64

        .segment "CODE"

; ---------------------------------------------------------------------------
; One-time SDK bring-up. Its result is not interesting here: a machine with no
; Ultimate simply answers ULTIMATE_ERR_NO_DEVICE to everything, which is what
; UERR is for.
; ---------------------------------------------------------------------------

wedge_sdk_init:
        jmp uci_init

; ---------------------------------------------------------------------------
; IGONE - statement dispatch.
;
; The ROM's own path is CHRGET then NGONE1. Doing the CHRGET here and handing
; the rest to NGONE1 is what keeps every statement the wedge does not own
; behaving exactly as before.
; ---------------------------------------------------------------------------

wedge_gone:
        jsr CHRGET
        cmp #UCI_TOK_UCI
        beq @ours
        jmp NGONE1

@ours:  jsr wedge_do_uci
        jmp NEWSTT              ; on to the next statement, ':' or end of line

; ---------------------------------------------------------------------------
; UCI t, c [, arg ...]
;
; A bare UCI is the rescue hatch: abort whatever a crashed program left behind
; so the interface is usable again from the prompt.
; ---------------------------------------------------------------------------

wedge_do_uci:
        lda #$00
        sta wedge_arglen

        jsr CHRGOT
        bne @args
        jmp uci_abort           ; bare UCI

@args:  jsr GETBYT              ; target
        stx wedge_target
        jsr CHKCOM
        jsr GETBYT              ; command
        stx wedge_command

@more:  jsr CHRGOT
        cmp #','
        beq @next
        jmp wedge_exec
@next:  jsr CHRGET              ; step over the comma
        jsr wedge_arg
        jmp @more

; ---------------------------------------------------------------------------
; One argument.
;
; The default rule is one numeric argument for one protocol byte, and a string
; for its own bytes. UW() and UL() are the escape for a command whose shape the
; SDK's table has never heard of, which is the whole reason the generic form
; exists.
; ---------------------------------------------------------------------------

wedge_arg:
        jsr CHRGOT
        cmp #UCI_TOK_UW
        beq @word
        cmp #UCI_TOK_UL
        beq @long

        jsr FRMEVL              ; any expression, of either type
        lda VALTYP
        bne @string

        jsr GETADR              ; numeric: the low byte, per the default rule
        lda LINNUM
        jmp wedge_putarg

; A string argument contributes its bytes and nothing else - no length, no
; terminator. The firmware splits on whatever the command's shape says.
@string:
        jsr FRESTR              ; A = length, X/Y = where the bytes are
        pha
        stx INDEX
        sty INDEX+1
        pla
        beq @done               ; the empty string contributes nothing
        sta wedge_scount
        ldy #$00
@copy:  lda (INDEX),y
        sty wedge_scur
        jsr wedge_putarg
        ldy wedge_scur
        iny
        cpy wedge_scount
        bne @copy
@done:  rts

; UW(x) - two bytes, LSB first.
@word:  jsr CHRGET              ; the token carries its own '('
        jsr FRMNUM
        jsr GETADR
        jsr CHKCLS
        lda LINNUM
        jsr wedge_putarg
        lda LINNUM+1
        jmp wedge_putarg

; UL(x) - four bytes, LSB first. QINT is the ROM's own float to 32-bit signed,
; so a value past 65535 survives, which GETADR alone would not manage.
@long:  jsr CHRGET
        jsr FRMNUM
        jsr QINT
        jsr CHKCLS
        lda FACHO+3
        jsr wedge_putarg
        lda FACHO+2
        jsr wedge_putarg
        lda FACHO+1
        jsr wedge_putarg
        lda FACHO
        jmp wedge_putarg

; Append A to the argument bytes. A full buffer is dropped rather than allowed
; to run into the code behind it; the command then fails on its own terms.
wedge_putarg:
        ldx wedge_arglen
        cpx #WEDGE_ARG_SIZE
        bcs @full
        sta wedge_argbuf,x
        inc wedge_arglen
@full:  rts

; ---------------------------------------------------------------------------
; Fill the request block and run it.
; ---------------------------------------------------------------------------

wedge_exec:
        lda wedge_target
        sta uci_req + UCI_REQ_TARGET
        lda wedge_command
        sta uci_req + UCI_REQ_COMMAND

        lda #<wedge_argbuf
        sta uci_req + UCI_REQ_ARGS
        lda #>wedge_argbuf
        sta uci_req + UCI_REQ_ARGS + 1
        lda wedge_arglen
        sta uci_req + UCI_REQ_ARGLEN
        lda #$00
        sta uci_req + UCI_REQ_ARGLEN + 1

        sta uci_req + UCI_REQ_PAYLOAD           ; A is still zero
        sta uci_req + UCI_REQ_PAYLOAD + 1
        sta uci_req + UCI_REQ_PAYLOADLEN
        sta uci_req + UCI_REQ_PAYLOADLEN + 1

        lda #<wedge_reply
        sta uci_req + UCI_REQ_DATA
        lda #>wedge_reply
        sta uci_req + UCI_REQ_DATA + 1
        lda #<WEDGE_REPLY_SIZE
        sta uci_req + UCI_REQ_DATAMAX
        lda #>WEDGE_REPLY_SIZE
        sta uci_req + UCI_REQ_DATAMAX + 1

        lda #<wedge_status
        sta uci_req + UCI_REQ_STATUS
        lda #>wedge_status
        sta uci_req + UCI_REQ_STATUS + 1
        lda #WEDGE_STATUS_SIZE
        sta uci_req + UCI_REQ_STATUSMAX
        lda #$00
        sta uci_req + UCI_REQ_STATUSMAX + 1

        lda #<uci_req
        ldx #>uci_req
        jsr uci_exec
        sta wedge_err
        rts

; ---------------------------------------------------------------------------
; IEVAL - a term in an expression.
;
; TXTPTR is saved rather than backed up by one, because a term can start on a
; page boundary and "decrement the low byte" is wrong exactly there.
; ---------------------------------------------------------------------------

wedge_eval:
        lda TXTPTR
        sta wedge_savptr
        lda TXTPTR+1
        sta wedge_savptr+1

        jsr CHRGET
        cmp #UCI_TOK_UERR
        beq @uerr
        cmp #UCI_TOK_UDEV
        beq @udev
        cmp #UCI_TOK_ULEN
        beq @ulen
        cmp #UCI_TOK_USTS
        beq @usts
        cmp #UCI_TOK_UDATS
        beq @udats
        cmp #UCI_TOK_UBYTE
        beq @ubyte
        cmp #UCI_TOK_UDOS1
        bcc @rom
        cmp #UCI_TOK_UHTTP+1
        bcs @rom

; A target constant. Their tokens and their values both run in order, so the
; distance from the first is the distance from UCI_TARGET_DOS1.
        sec
        sbc #UCI_TOK_UDOS1
        clc
        adc #UCI_KWVAL_UDOS1
        jmp wedge_ret_byte

@rom:   lda wedge_savptr        ; not ours: put the text pointer back and let
        sta TXTPTR              ; the ROM evaluate the term it was going to
        lda wedge_savptr+1
        sta TXTPTR+1
        jmp NEVAL

@uerr:  lda wedge_err
        jmp wedge_ret_byte

@udev:  jsr uci_last_code       ; A = low, X = high
        tay
        txa
        jmp GIVAYF

@ulen:  ldy uci_req + UCI_REQ_DATALEN
        lda uci_req + UCI_REQ_DATALEN + 1
        jmp GIVAYF

@usts:  lda uci_req + UCI_REQ_STATUSLEN
        ldx #<wedge_status
        ldy #>wedge_status
        jmp wedge_ret_string

@udats: lda uci_req + UCI_REQ_DATALEN + 1
        beq @datlen             ; 256 or more cannot be a BASIC string
        lda #$FF
        bne @datgo              ; always
@datlen:
        lda uci_req + UCI_REQ_DATALEN
@datgo: ldx #<wedge_reply
        ldy #>wedge_reply
        jmp wedge_ret_string

; UBYTE(n) - byte n of the reply, or zero past the end. Zero rather than an
; error because a program walking a reply should not have to know its length
; before it starts.
@ubyte: jsr CHRGET              ; the token carries its own '('
        jsr FRMNUM
        jsr GETADR
        jsr CHKCLS
        lda LINNUM+1
        bne @past
        ldx LINNUM
        cpx uci_req + UCI_REQ_DATALEN
        lda uci_req + UCI_REQ_DATALEN + 1
        bne @inrange            ; a reply of 256 makes every index valid
        bcs @past
@inrange:
        lda wedge_reply,x
        jmp wedge_ret_byte
@past:  lda #$00
        jmp wedge_ret_byte

; ---------------------------------------------------------------------------
; Returning values to BASIC.
; ---------------------------------------------------------------------------

; A -> FAC1 as an unsigned byte. GIVAYF takes the high byte in A and the low in
; Y, which is the wrong way round from most things and worth saying once.
wedge_ret_byte:
        tay
        lda #$00
        jmp GIVAYF

; A = length, X/Y = bytes -> FAC1 as a string.
;
; STRSPA reserves the space and leaves the descriptor in DSCTMP; PUTNEW makes
; it the current temporary and sets VALTYP. Copying rather than pointing at the
; buffer matters: the next command overwrites it, and a BASIC string has to
; outlive that.
wedge_ret_string:
        stx wedge_sptr          ; not INDEX yet: STRSPA can garbage-collect,
        sty wedge_sptr+1        ; and the collector uses INDEX itself
        jsr STRSPA
        beq @empty
        sta wedge_scount
        lda wedge_sptr
        sta INDEX
        lda wedge_sptr+1
        sta INDEX+1
        ldy #$00
@copy:  lda (INDEX),y
        sta (FACEXP+1),y        ; DSCTMP+1: where STRSPA reserved the space
        iny
        cpy wedge_scount
        bne @copy
@empty: jmp PUTNEW

; ---------------------------------------------------------------------------
; State and buffers.
; ---------------------------------------------------------------------------

        .segment "CODE"

wedge_err:      .byte 0         ; the last ULTIMATE_* result, what UERR reads
wedge_target:   .byte 0
wedge_command:  .byte 0
wedge_arglen:   .byte 0
wedge_savptr:   .word 0         ; TXTPTR across a term the wedge did not want
wedge_scount:   .byte 0
wedge_scur:     .byte 0
wedge_sptr:     .word 0         ; string source across a call that may collect

        .segment "BSS"

wedge_argbuf:   .res WEDGE_ARG_SIZE
wedge_reply:    .res WEDGE_REPLY_SIZE
wedge_status:   .res WEDGE_STATUS_SIZE
