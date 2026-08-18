; C64 BASIC and KERNAL entry points the wedge hooks into.
;
; Every address here was read out of a build of the Commodore BASIC/KERNAL
; source, not quoted from memory. The build produces images identical to
; 901226-01 and 901227-03, and its label file is the authority:
;
;     ca65 -g basic/basic.s && ca65 -g kernal/kernal.s
;     ld65 -C rom.cfg -o rom.bin basic/basic.o kernal/kernal.o -Ln rom.txt
;
; The names are Commodore's own, lower-cased in their source. Addresses of ROM
; routines are facts about the machine, not code: nothing is copied from the
; ROM, and the wedge only calls into it.
;
; SPDX-License-Identifier: MIT

; ---- zero page ----
CHRGET          = $0073         ; advance TXTPTR and fetch
CHRGOT          = $0079         ; re-fetch without advancing
TXTPTR          = $007A         ; BASIC's text pointer
VALTYP          = $000D         ; 0 numeric, $FF string
DORES           = $000F         ; CRUNCH: verbatim flag. LIST: in-string flag
LSTPNT          = $0049         ; LIST: saved index into the line being listed
FACEXP          = $0061         ; FAC1 exponent; also DSCTMP, the string descriptor
FACHO           = $0062         ; FAC1 mantissa, high byte

; ---- the input buffer ----
BUF             = $0200         ; where a typed line lands, and where CRUNCH
                                ; writes the tokenised result back

; ---- the RAM vectors the wedge owns ----
IERROR          = $0300
IMAIN           = $0302
ICRNCH          = $0304         ; tokenise
IQPLOP          = $0306         ; LIST one byte
IGONE           = $0308         ; dispatch a statement
IEVAL           = $030A         ; evaluate a term

; ---- the ROM handlers those vectors normally point at ----
NCRNCH          = $A57C
NQPLOP          = $A71A
NGONE           = $A7E4
NEVAL           = $AE86

; ---- BASIC routines ----
SCRTCH          = $A644         ; NEW
PLOOP1          = $A700         ; LIST: advance to the next byte of the line
NEWSTT          = $A7AE         ; run the next statement
GONE3           = $A7ED         ; dispatch a statement token
STROUT          = $AB1E         ; print the string at A/Y
OUTDO           = $AB47         ; print the character in A
FRMNUM          = $AD8A         ; evaluate a numeric expression into FAC1
FRMEVL          = $AD9E         ; evaluate any expression
CHKCLS          = $AEF7         ; require ')'
CHKOPN          = $AEFA         ; require '('
CHKCOM          = $AEFD         ; require ','
SNERR           = $AF08         ; ?SYNTAX ERROR
GIVAYF          = $B391         ; A/Y (signed 16-bit) into FAC1
STRSPA          = $B47D         ; reserve A bytes of string space
STRLIT          = $B487         ; build a descriptor for the string at A/Y
FRESTR          = $B6A3         ; free a temporary string, descriptor to A/X/Y
GETBYT          = $B79E         ; evaluate a byte into X
GETADR          = $B7F7         ; FAC1 into LINNUM as unsigned 16-bit
GETNUM          = $B7EB         ; GETADR then CHKCOM then GETBYT

; ---- KERNAL ----
READY           = $E386         ; print READY. and enter the direct-mode loop

; ---- tokens the wedge has to recognise in a crunched line ----
TOK_DATA        = $83           ; both arm CRUNCH's verbatim mode, so the wedge
TOK_REM         = $8F           ; must stop matching until the next ':'

; ---- added for dispatch ----
LINNUM          = $0014         ; GETADR's 16-bit result
INDEX           = $0022         ; BASIC's own pointer scratch, free inside a
                                ; statement handler
FACMO           = $0063         ; FAC1 mantissa, middle bytes
NGONE1          = $A7E7         ; the ROM's statement path, after its own CHRGET
QINT            = $BC9B         ; FAC1 -> 32-bit signed in FACHO..FACHO+3, MSB first
PUTNEW          = $B4CA         ; make the descriptor in DSCTMP the current
                                ; temporary string, and set VALTYP
