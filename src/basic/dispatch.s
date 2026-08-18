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
        .include "uci_argtable.inc"

; Every call into the SDK goes through bank.s, because the SDK runs at $A000
; under BASIC ROM. uci_req is a variable rather than code - BSS at $C000 - so it
; is reached directly like any other.
        .import uci_req
        .import bank_uci_init, bank_uci_exec, bank_uci_abort
        .import bank_uci_last_code, bank_turbo_set, bank_turbo_get
        .import bank_load, bank_bload, bank_save
        .import bank_opendir, bank_readdir
        .import bank_reu_stash, bank_reu_fetch

; The services take their wider arguments in the SDK's shared variable block.
; It is BSS at $C000 - RAM whatever $01 says - so the wedge writes it directly
; and only the calls above need banking.
        .import ult_buf, ult_buflen, ult_attrib
        .import ult_addr, ult_max, ult_reu, ult_reulen

        .export wedge_gone, wedge_eval, wedge_do_uci, wedge_do_turbo
        .export wedge_do_load, wedge_do_bload, wedge_do_save
        .export wedge_do_dir, wedge_do_stash, wedge_do_fetch
        .export wedge_sdk_init
        .export wedge_err, wedge_target, wedge_command, wedge_arglen
        .export wedge_argbuf, wedge_reply, wedge_status

; The argument table is walked with 8-bit arithmetic, like the keyword one.
        .assert uci_argtable_size < 256, error, "argument table outgrew one page"

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
        lda #$00                ; UERR and ULEN are readable before the first
        sta wedge_err           ; command, so they have to mean something
        sta uci_req + UCI_REQ_DATALEN
        sta uci_req + UCI_REQ_DATALEN + 1
        sta uci_req + UCI_REQ_STATUSLEN
        sta uci_req + UCI_REQ_STATUSLEN + 1
        jmp bank_uci_init

; ---------------------------------------------------------------------------
; IGONE - statement dispatch.
;
; The ROM's own path is CHRGET then NGONE1. Doing the CHRGET here and handing
; the rest to NGONE1 is what keeps every statement the wedge does not own
; behaving exactly as before.
; ---------------------------------------------------------------------------

wedge_gone:
        jsr CHRGET
        php                     ; CHRGET's carry is not incidental: GONE3 does
                                ; `sbc #endtk` with it, so the flag decides
                                ; which statement the ROM dispatches. A plain
                                ; CMP here clears it for every token below
                                ; ours, which shifts the whole table down by
                                ; one - PRINT becomes PRINT#, and every
                                ; statement in every program is the wrong one.
        cmp #UCI_TOK_UCI
        beq @ours
        cmp #UCI_TOK_UTURBO
        beq @turbo
        cmp #UCI_TOK_ULOAD
        bcc @rom                ; below the file keywords: not one of ours
        cmp #UCI_TOK_UFETCH + 1
        bcc @file
@rom:   plp
        jmp NGONE1

@ours:  plp
        jsr wedge_do_uci
        jmp NEWSTT              ; on to the next statement, ':' or end of line

@turbo: plp
        jsr wedge_do_turbo
        jmp NEWSTT

; ULOAD through UFETCH are contiguous and all statements, so one range test and
; one table replace six comparisons and six branches.
@file:  plp
        sec
        sbc #UCI_TOK_ULOAD
        asl                     ; two bytes per entry
        tax
        lda wedge_file_vec,x
        sta wedge_jump
        lda wedge_file_vec + 1,x
        sta wedge_jump + 1
        jsr wedge_via_jump
        jmp NEWSTT

; The 6510 has no jmp (addr,x), so the handler's address is copied into one
; place and jumped through from there. Behind a jsr, so every handler can end
; with an rts and the return to NEWSTT is written once.
wedge_via_jump:
        jmp (wedge_jump)

wedge_file_vec:
        .addr wedge_do_load     ; ULOAD
        .addr wedge_do_bload    ; UBLOAD
        .addr wedge_do_save     ; USAVE
        .addr wedge_do_dir      ; UDIR
        .addr wedge_do_stash    ; USTASH
        .addr wedge_do_fetch    ; UFETCH

; ---------------------------------------------------------------------------
; UCI t, c [, arg ...]
;
; A bare UCI is the rescue hatch: abort whatever a crashed program left behind
; so the interface is usable again from the prompt.
; ---------------------------------------------------------------------------

; Entered with TXTPTR on the UCI token itself, which is where IGONE's CHRGET
; leaves it. Stepping past it here rather than in the caller is what keeps the
; tests honest: they enter at the same point the interpreter does.
wedge_do_uci:
        lda #$00
        sta wedge_arglen

        jsr CHRGET              ; past the token, onto the first argument
        bne @args
        jmp bank_uci_abort           ; bare UCI

@args:  jsr GETBYT              ; target
        stx wedge_target
        jsr CHKCOM
        jsr GETBYT              ; command
        stx wedge_command

        jsr wedge_find_shape    ; what the SDK knows about this command

; Literals belong to the command, not to the caller, so they are emitted on
; the way to the next argument the caller did type.
@more:  jsr wedge_emit_literals
        jsr CHRGOT
        cmp #','
        beq @next
        jmp wedge_exec
@next:  jsr CHRGET              ; step over the comma
        jsr wedge_kind_at       ; how wide is this one meant to be
        sta wedge_kind
        inc wedge_shape_i
        jsr wedge_arg
        jmp @more

; ---------------------------------------------------------------------------
; UTURBO n  -  set the CPU speed index.
;
; The one wedge keyword that does not reach the Ultimate through uci_exec,
; because there is no UCI command for CPU speed: turbo is memory-mapped I/O.
; See src/uci/turbo.s for why that is an exception rather than the rule
; eroding.
;
; The result lands in UERR like every other command's, which is how a program
; discovers that the machine's owner has left turbo switched off in its
; settings - the common case, and one a program cannot do anything about
; except carry on at 1MHz:
;
;     UTURBO 3 : IF UERR THEN PRINT "no turbo here"
;
; The function form, which reads the current index back, is in wedge_eval.
; ---------------------------------------------------------------------------

wedge_do_turbo:
        jsr CHRGET              ; past the token, onto the speed
        jsr GETBYT              ; X = index. Nothing there is the ROM's own
                                ; ?SYNTAX ERROR, which is the right one.
        txa
        jsr bank_turbo_set
        sta wedge_err
        rts

; ---------------------------------------------------------------------------
; The file keywords.
;
;   ULOAD  name$ [,address]         a PRG; no address means the file's own
;   UBLOAD name$, address, length   raw bytes, and not one past the length
;   USAVE  name$, start, length     memory to a file
;
; A name goes on the wire byte for byte, with no character conversion. That is
; not an omission: uppercase PETSCII and uppercase ASCII are the same bytes, so
; a name typed at a C64 arrives as the Ultimate expects it, and FAT lookup is
; case-insensitive besides. See docs/uci.md.
;
; Errors land in UERR rather than stopping the program, like every other
; keyword here:
;
;     ULOAD "GAME",$C000 : IF UERR THEN PRINT "no": END
; ---------------------------------------------------------------------------

wedge_do_load:
        jsr CHRGET              ; past the token, onto the name
        jsr wedge_name
        lda #$00                ; no address given: the file's own, which is
        sta ult_addr            ; what a zero means to ultimate_load
        sta ult_addr + 1
        jsr CHRGOT
        cmp #','
        bne @go
        jsr wedge_argword
        lda LINNUM
        sta ult_addr
        lda LINNUM + 1
        sta ult_addr + 1
@go:    jsr bank_load
        sta wedge_err
        rts

wedge_do_bload:
        jsr CHRGET
        jsr wedge_name
        jsr wedge_argword       ; the address
        lda LINNUM
        sta ult_addr
        lda LINNUM + 1
        sta ult_addr + 1
        jsr wedge_argword       ; and the limit, which bload insists on
        lda LINNUM
        sta ult_max
        lda LINNUM + 1
        sta ult_max + 1
        jsr bank_bload
        sta wedge_err
        rts

wedge_do_save:
        jsr CHRGET
        jsr wedge_name
        jsr wedge_argword       ; the start
        lda LINNUM
        sta ult_addr
        lda LINNUM + 1
        sta ult_addr + 1
        jsr wedge_argword       ; and how much of it
        lda LINNUM
        sta ult_max
        lda LINNUM + 1
        sta ult_max + 1
        jsr bank_save
        sta wedge_err
        rts

; ---------------------------------------------------------------------------
; UDIR - the current directory, on the screen.
;
; **A directory walk is one live exchange.** The firmware answers READ_DIR with
; one reply block per entry and the block boundary is the only separator there
; is, so no other command may go out between calls - which is why this prints
; as it goes rather than collecting first.
;
; The names arrive in ASCII and CHROUT wants PETSCII. Only the letters differ
; and only in one direction: ASCII $41-$5A already displays as letters, and
; ASCII $61-$7A would display as graphics symbols, so lowercase is folded up.
; Every name therefore reads as lowercase on a stock screen, which is what the
; SDK's own strings do - see tools/test_charmap.py for the whole of that rule.
; ---------------------------------------------------------------------------

wedge_do_dir:
        jsr CHRGET              ; past the token; UDIR takes no arguments
        jsr bank_opendir
        sta wedge_err
        cmp #ULTIMATE_OK
        bne @out

@next:  lda #<wedge_reply
        sta ult_buf
        lda #>wedge_reply
        sta ult_buf + 1
        lda #<WEDGE_REPLY_SIZE
        sta ult_buflen
        lda #>WEDGE_REPLY_SIZE
        sta ult_buflen + 1
        jsr bank_readdir
        cmp #ULTIMATE_OK
        bne @end

        ldy #$00
@char:  lda wedge_reply,y
        beq @eol
        cmp #$61                ; ASCII 'a'
        bcc @put
        cmp #$7B                ; ...through 'z'
        bcs @put
        sec
        sbc #$20                ; which CHROUT draws as letters
@put:   sty wedge_tmp
        jsr OUTDO
        ldy wedge_tmp
        iny
        bne @char               ; a name is 255 bytes at the very most

@eol:   lda ult_attrib
        and #DOS_ATTR_DIR
        beq @crlf
        lda #$2F                ; '/', so a directory looks like one
        jsr OUTDO
@crlf:  lda #$0D
        jsr OUTDO
        jmp @next

; ULTIMATE_END is how a directory finishes and is not a failure, so it does not
; reach UERR. Anything else does.
@end:   cmp #ULTIMATE_END
        beq @done
        sta wedge_err
        rts
@done:  lda #ULTIMATE_OK
        sta wedge_err
@out:   rts

; ---------------------------------------------------------------------------
; USTASH address, reu address, length
; UFETCH address, reu address, length
;
; The REU address is 24 bits, so it is evaluated as a 32-bit value rather than
; with GETADR: a BASIC program addressing the sixteenth megabyte is doing the
; thing the expansion is for. The length is a plain 16-bit count, and zero means
; 65536 - the REU's own convention, not the SDK's.
; ---------------------------------------------------------------------------

wedge_do_stash:
        jsr wedge_reu_args
        jsr bank_reu_stash
        sta wedge_err
        rts

wedge_do_fetch:
        jsr wedge_reu_args
        jsr bank_reu_fetch
        sta wedge_err
        rts

wedge_reu_args:
        jsr CHRGET              ; past the token, onto the C64 address
        jsr FRMNUM
        jsr GETADR
        lda LINNUM
        sta ult_addr
        lda LINNUM + 1
        sta ult_addr + 1

        jsr CHKCOM              ; the REU address, in full
        jsr FRMNUM
        jsr QINT                ; FACHO..FACHO+3, most significant first
        lda FACHO + 3
        sta ult_reu
        lda FACHO + 2
        sta ult_reu + 1
        lda FACHO + 1
        sta ult_reu + 2
        lda FACHO
        sta ult_reu + 3

        jsr wedge_argword       ; and the length
        lda LINNUM
        sta ult_reulen
        lda LINNUM + 1
        sta ult_reulen + 1
        lda #$00
        sta ult_reulen + 2      ; a DMA transfer is 16 bits wide; the other half
        sta ult_reulen + 3      ; of the shared length belongs to the DOS pair
        rts

; ---------------------------------------------------------------------------
; Argument helpers for the keywords above.
; ---------------------------------------------------------------------------

; A string expression into wedge_argbuf, NUL terminated, with ult_buf aimed at
; it. A name longer than the buffer is cut rather than allowed to run into what
; follows; the command then fails on its own terms, which is the same bargain
; the generic form's arguments make.
wedge_name:
        jsr FRMEVL
        lda VALTYP
        bne @string
        jmp SNERR               ; a number where a name belongs is the ROM's
                                ; own ?SYNTAX ERROR, and it should be

@string:
        jsr FRESTR              ; A = length, X/Y = the bytes
        stx INDEX
        sty INDEX + 1
        cmp #WEDGE_ARG_SIZE
        bcc @fits
        lda #WEDGE_ARG_SIZE - 1
@fits:  sta wedge_scount
        ldy #$00
        cpy wedge_scount
        beq @term
@copy:  lda (INDEX),y
        sta wedge_argbuf,y
        iny
        cpy wedge_scount
        bne @copy
@term:  lda #$00
        sta wedge_argbuf,y
        lda #<wedge_argbuf
        sta ult_buf
        lda #>wedge_argbuf
        sta ult_buf + 1
        rts

; A comma, then a 16-bit value, in LINNUM.
wedge_argword:
        jsr CHKCOM
        jsr FRMNUM
        jmp GETADR

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

        lda wedge_kind          ; a number is as wide as the command says
        cmp #UCI_ARG_WORD
        beq @nword
        cmp #UCI_ARG_DWORD
        beq @nlong

        jsr GETADR              ; and one byte when it says nothing
        lda LINNUM
        jmp wedge_putarg

@nword: jsr GETADR
        lda LINNUM
        jsr wedge_putarg
        lda LINNUM+1
        jmp wedge_putarg

@nlong: jsr QINT
        jmp wedge_put32

; A string argument contributes its bytes and nothing else - no length, no
; terminator. The firmware splits on whatever the command's shape says.
@string:
        jsr FRESTR              ; A = length, X/Y = where the bytes are
        pha
        stx INDEX
        sty INDEX+1
        ldy wedge_kind          ; a length-prefixed string carries its count
        cpy #UCI_ARG_PSTR
        bne @nolen
        jsr wedge_putarg
@nolen: pla
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
        jmp wedge_put32

; QINT leaves a 32-bit signed value in FACHO..FACHO+3, most significant first,
; and the wire wants it the other way round.
wedge_put32:
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
; The argument shapes.
;
; Only commands the default rule cannot marshal have an entry - a wide number,
; a length-prefixed string, or a literal the caller never types. Everything
; else falls through to one byte per number, which is what nearly every command
; wants and costs the 6502 nothing.
;
; UW() and UL() still win over whatever the table says: the table is what the
; SDK knows today, and the escape has to keep working for firmware newer than
; the table.
; ---------------------------------------------------------------------------

; Find the entry for wedge_target / wedge_command.
; Leaves wedge_shape_n = 0 when there is none, which is the default rule.
wedge_find_shape:
        lda #$00
        sta wedge_shape_n
        sta wedge_shape_i
        sta wedge_kind

        lda wedge_target
        cmp #UCI_TARGET_DOS2    ; one command set on two targets, stored once
        bne @have
        lda #UCI_TARGET_DOS1
@have:  sta wedge_shape_t

        ldy #$00
@entry: sty wedge_shape_e
        lda uci_argtable,y
        beq @none               ; a zero target ends the table
        cmp wedge_shape_t
        bne @next
        iny
        lda uci_argtable,y
        cmp wedge_command
        beq @found

@next:  ldy wedge_shape_e       ; step over this entry: three header bytes and
        iny                     ; one packed byte per two arguments
        iny
        lda uci_argtable,y      ; the count
        clc
        adc #$01
        lsr a
        sta wedge_tmp
        iny
        tya
        clc
        adc wedge_tmp
        tay
        jmp @entry

@found: iny                     ; -> the count
        lda uci_argtable,y
        sta wedge_shape_n
        iny                     ; -> the first packed byte
        sty wedge_shape_off
@none:  rts

; The kind of shape entry wedge_shape_i, or UCI_ARG_END when the shape has run
; out - which is also what a command with no entry at all reports.
wedge_kind_at:
        lda wedge_shape_i
        cmp wedge_shape_n
        bcs @none

        lsr a                   ; two kinds to a byte
        clc
        adc wedge_shape_off
        tay
        lda uci_argtable,y
        pha
        lda wedge_shape_i
        and #$01
        bne @low

        pla                     ; even: the high nibble
        lsr a
        lsr a
        lsr a
        lsr a
        rts

@low:   pla
        and #$0F
        rts

@none:  lda #UCI_ARG_END
        rts

; Emit any literals sitting at the current shape position. They are part of the
; command's shape rather than something the caller types, so the caller's
; arguments have to step over them without knowing they exist.
wedge_emit_literals:
        jsr wedge_kind_at
        cmp #UCI_ARG_LIT0
        bne @done
        inc wedge_shape_i
        lda #$00
        jsr wedge_putarg
        jmp wedge_emit_literals
@done:  rts

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
        jsr bank_uci_exec
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
        sta wedge_evtok         ; CHRGET clobbers A, and stepping past the
                                ; token below needs another one
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
        cmp #UCI_TOK_UTURBO
        beq @uturbo
        cmp #UCI_TOK_UDOS1
        bcc @rom
        cmp #UCI_TOK_UHTTP+1
        bcs @rom

; A target constant. Their tokens and their values both run in order, so the
; distance from the first is the distance from UCI_TARGET_DOS1.
        jsr CHRGET
        lda wedge_evtok
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

; Every one of these steps TXTPTR past its own token before returning. CHRGET
; left it pointing AT the token, and a caller that evaluates a term and then
; looks at TXTPTR - which is every caller - finds the same token again.
; PRINT UDOS1 printed 1 for ever on a real machine before these existed.
@uerr:  jsr CHRGET
        lda wedge_err
        jmp wedge_ret_byte

; UTURBO as a function: the speed index the machine is running at, or 255 when
; turbo is switched off in its settings. 255 is not a speed - the index is four
; bits - so the two can never be confused, and a program can test for it.
@uturbo:
        jsr CHRGET
        jsr bank_turbo_get
        jmp wedge_ret_byte

@udev:  jsr CHRGET
        jsr bank_uci_last_code       ; A = low, X = high
        tay
        txa
        jmp GIVAYF

@ulen:  jsr CHRGET
        ldy uci_req + UCI_REQ_DATALEN
        lda uci_req + UCI_REQ_DATALEN + 1
        jmp GIVAYF

@usts:  jsr CHRGET
        lda uci_req + UCI_REQ_STATUSLEN
        ldx #<wedge_status
        ldy #>wedge_status
        jmp wedge_ret_string

@udats: jsr CHRGET
        lda uci_req + UCI_REQ_DATALEN + 1
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
wedge_kind:     .byte 0         ; UCI_ARG_* for the argument being parsed
wedge_evtok:    .byte 0         ; the token IEVAL is looking at
wedge_shape_t:  .byte 0         ; target the shape is looked up under
wedge_shape_n:  .byte 0         ; arguments in the shape, 0 when there is none
wedge_shape_i:  .byte 0         ; which one is next
wedge_shape_off: .byte 0        ; where its packed kinds start
wedge_shape_e:  .byte 0         ; start of the entry being examined
wedge_tmp:      .byte 0
wedge_jump:     .word 0         ; where the statement dispatch is going

        .segment "BSS"

wedge_argbuf:   .res WEDGE_ARG_SIZE
wedge_reply:    .res WEDGE_REPLY_SIZE
wedge_status:   .res WEDGE_STATUS_SIZE
