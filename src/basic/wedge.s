; wedge.s - the Ultimate UCI BASIC wedge.
;
; Adds keywords to BASIC V2 by owning its RAM vectors. This file is the
; tokeniser and the LIST side; dispatch comes next.
;
;   ICRNCH  tokenise    - the ROM crunches the line, then the wedge substitutes
;   IQPLOP  LIST        - the wedge prints its own keywords, the ROM the rest
;
; **The wedge claims no zero page.** It runs from RAM, so its state lives in
; absolute memory beside the code. The SDK already claims UCI_ZP..UCI_ZP+3,
; which defaults to $FB, and a wedge quietly taking the other free bytes is the
; kind of collision nobody finds until someone else's program misbehaves.
;
; Two facts about CRUNCH shape everything here. Both are modelled and tested in
; tools/c64_crunch.py rather than assumed:
;
;   - CRUNCH DROPS input bytes >= $80, pi excepted. So the wedge cannot write
;     its tokens into the input buffer and let the ROM crunch afterwards - they
;     would vanish. It runs the ROM first and substitutes into the result.
;
;   - CRUNCH matches a reserved word ANYWHERE, not only at a word boundary, so
;     by the time the wedge sees the line ULEN is already 'U' $C3. The patterns
;     in uci_keywords.inc are those crunched forms, which is why they are
;     generated rather than typed.
;
; SPDX-License-Identifier: MIT

        .include "c64rom.inc"
        .include "uci_keywords.inc"

        .import wedge_gone, wedge_eval, wedge_sdk_init

        .export wedge_install
        .export wedge_crunch, wedge_qplop, wedge_match
        .export wedge_print_keyword, wedge_find_keyword, wedge_len
        .export wedge_src, wedge_dst, wedge_verbatim

; Exported for the test suite, whose memory references take a symbol and not an
; address. They are ROM and zero page facts, not wedge storage.
        .export BUF, TXTPTR, ICRNCH, IQPLOP, IGONE, IEVAL, DORES

; The table is walked with 8-bit arithmetic, so it has to fit in one page.
        .assert uci_keywords_size < 256, error, "keyword table outgrew one page"

; The CODE segment loads with the .prg and runs at $C000; the loader copies it
; there. The SDK's own modules land in the same segment, so a NEW cannot leave
; BASIC growing over the transport. See uci-wedge.cfg.
        .segment "CODE"

; ---------------------------------------------------------------------------
; Installation.
;
; Returns, so a test can install the wedge and carry on. The banner, the NEW
; and the jump to READY belong to the loader, not to this.
; ---------------------------------------------------------------------------

wedge_install:
        lda #<wedge_crunch
        sta ICRNCH
        lda #>wedge_crunch
        sta ICRNCH+1
        lda #<wedge_qplop
        sta IQPLOP
        lda #>wedge_qplop
        sta IQPLOP+1
        lda #<wedge_gone
        sta IGONE
        lda #>wedge_gone
        sta IGONE+1
        lda #<wedge_eval
        sta IEVAL
        lda #>wedge_eval
        sta IEVAL+1
        jmp wedge_sdk_init

; ---------------------------------------------------------------------------
; ICRNCH - tokenise.
;
; The ROM crunches the line into BUF, NUL terminated, and leaves TXTPTR at
; $01FF so its caller's next CHRGET lands on BUF. The wedge then walks BUF
; substituting its tokens, writing back over the same buffer: every
; substitution replaces two or more bytes with one, so the write index can
; never overtake the read index and compacting in place is safe.
;
; TXTPTR is left alone, so the ROM's contract with its caller is unchanged.
; ---------------------------------------------------------------------------

wedge_crunch:
        jsr NCRNCH              ; let the ROM tokenise first - see the header

        lda #$00
        sta wedge_src
        sta wedge_dst
        sta wedge_verbatim

@loop:  ldx wedge_src
        lda BUF,x
        bne @live

        ldx wedge_dst           ; end of line: terminate the compacted copy
        sta BUF,x               ; A is already zero
        rts

@live:  ldy wedge_verbatim      ; inside DATA or REM the ROM stopped tokenising,
        beq @active             ; so the wedge stops substituting too
        cmp #':'
        bne @copy
        ldy #$00                ; ':' ends the statement and matching resumes
        sty wedge_verbatim
        beq @copy               ; always

@active:
        cmp #'"'
        beq @string
        jsr wedge_match         ; C set and A = token when one matched
        bcc @copy

        ldx wedge_dst           ; one token replaces the whole pattern, and
        sta BUF,x               ; wedge_match has already advanced wedge_src
        inc wedge_dst
        jmp @loop

; Not the start of one of ours. Copy it, and notice the two tokens that turn
; the rest of the statement into plain text.
@copy:  ldx wedge_dst
        sta BUF,x
        inc wedge_src
        inc wedge_dst
        cmp #TOK_DATA
        beq @verbatim
        cmp #TOK_REM
        bne @loop
@verbatim:
        lda #$FF
        sta wedge_verbatim
        jmp @loop

; A string constant holds whatever the user typed, so PRINT "UCI" has to come
; out with UCI still three letters.
@string:
        ldx wedge_dst
        sta BUF,x               ; the opening quote
        inc wedge_src
        inc wedge_dst
@strloop:
        ldx wedge_src
        lda BUF,x
        beq @loop               ; unterminated: let the end-of-line case finish
        ldx wedge_dst
        sta BUF,x
        inc wedge_src
        inc wedge_dst
        cmp #'"'
        bne @strloop
        jmp @loop

; ---------------------------------------------------------------------------
; wedge_match - is one of our keywords at BUF + wedge_src?
;
; Out: C=1, A = the token, wedge_src advanced past the pattern.
;      C=0, A = the byte that was looked at, nothing else touched.
;
; The generator guarantees no pattern is a prefix of another, so the first match
; is the only match and table order does not decide the answer.
; ---------------------------------------------------------------------------

wedge_match:
        lda #$00
        sta wedge_token
        ldy #$00                        ; cursor into the keyword table

@entry: lda uci_keywords,y
        beq @nomatch                    ; a zero length ends the table
        sta wedge_len
        sty wedge_entry                 ; keep the start, for stepping over it
        iny                             ; -> first pattern byte

        ldx wedge_src
@cmp:   lda uci_keywords,y
        cmp BUF,x
        bne @next
        inx
        iny
        dec wedge_len
        bne @cmp

        stx wedge_src                   ; the whole pattern matched
        lda wedge_token
        clc
        adc #UCI_TOK_FIRST
        sec
        rts

@next:  ldy wedge_entry
        jsr wedge_next_entry
        inc wedge_token
        jmp @entry

@nomatch:
        ldx wedge_src
        lda BUF,x
        clc
        rts

; ---------------------------------------------------------------------------
; wedge_next_entry - step Y from one table entry to the next.
;
; In:  Y = offset of an entry's pattern-length byte
; Out: Y = offset of the following entry's, A and wedge_cur clobbered
;
; Entry layout: matchlen, match..., displaylen, display... where displaylen is
; zero for a keyword that lists exactly as it matches.
; ---------------------------------------------------------------------------

wedge_next_entry:
        sty wedge_cur
        lda uci_keywords,y              ; pattern length
        clc
        adc wedge_cur
        tay
        iny                             ; -> the display-length byte

        sty wedge_cur
        lda uci_keywords,y              ; display length, often zero
        clc
        adc wedge_cur
        tay
        iny                             ; -> the next entry
        rts

; ---------------------------------------------------------------------------
; IQPLOP - LIST one byte.
;
; In: A = the byte, Y = its index into the line being listed.
; Anything that is not one of ours goes straight to the ROM.
; ---------------------------------------------------------------------------

wedge_qplop:
        cmp #UCI_TOK_FIRST
        bcc @rom
        cmp #UCI_TOK_LAST+1
        bcs @rom
        bit DORES                       ; inside a string constant the ROM
        bmi @rom                        ; prints the byte raw, and so do we

        sty LSTPNT                      ; the ROM's own slot for this
        jsr wedge_print_keyword
        ldy LSTPNT
        jmp PLOOP1

@rom:   jmp NQPLOP

; ---------------------------------------------------------------------------
; wedge_print_keyword - print the name of the token in A, through OUTDO.
;
; Its own entry point because BASIC's LIST ends in the direct-mode loop rather
; than returning, so a test cannot drive LIST to completion and look at the
; screen afterwards. This is the part with logic in it - finding the entry, and
; choosing the display text over the match pattern for a keyword like ULEN
; whose two forms differ.
; ---------------------------------------------------------------------------

wedge_print_keyword:
        jsr wedge_find_keyword
@print: lda uci_keywords,y
        sty wedge_cur
        jsr OUTDO
        ldy wedge_cur
        iny
        dec wedge_len
        bne @print
        rts

; ---------------------------------------------------------------------------
; wedge_find_keyword - where is token A's display text?
;
; In:  A = the token
; Out: Y = offset into uci_keywords of its first display byte
;      wedge_len = how many bytes, A = the first of them
;
; Split from the printing because this is the part with logic in it - walking
; entries of two variable-length pieces, and choosing the display text over the
; match pattern for the one keyword whose forms differ - and because printing
; needs a screen editor that the test backend does not bring up.
; ---------------------------------------------------------------------------

wedge_find_keyword:
        sec
        sbc #UCI_TOK_FIRST
        sta wedge_token

        ldy #$00                        ; walk to that entry
@skip:  lda wedge_token
        beq @found
        jsr wedge_next_entry
        dec wedge_token
        jmp @skip

@found: lda uci_keywords,y              ; pattern length
        sta wedge_len
        sty wedge_entry
        clc
        adc wedge_entry
        tay
        iny                             ; -> the display-length byte

        lda uci_keywords,y
        beq @aspattern                  ; zero: the pattern is the display text
        sta wedge_len
        iny                             ; -> first display byte
        bne @ready                      ; always

@aspattern:
        ldy wedge_entry
        iny                             ; -> first pattern byte, wedge_len is
                                        ; already the pattern length

@ready: lda uci_keywords,y
        rts

; ---------------------------------------------------------------------------
; State, in RAM beside the code, so the wedge needs no zero page at all.
; ---------------------------------------------------------------------------

wedge_src:      .byte 0         ; read index into BUF
wedge_dst:      .byte 0         ; write index into BUF, never ahead of src
wedge_verbatim: .byte 0         ; non-zero once DATA or REM stopped tokenising
wedge_token:    .byte 0         ; table entry being considered, then the token
wedge_len:      .byte 0         ; bytes left to compare or print
wedge_entry:    .byte 0         ; start of the entry being looked at
wedge_cur:      .byte 0         ; scratch for the 8-bit table arithmetic
