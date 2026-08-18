; dos.s - Layer 2: files and directories, on the Ultimate DOS target.
;
; Every entry point is uci_exec plus argument marshalling; nothing here touches
; a hardware register or reimplements a byte of the handshake.
;
; Target $01 throughout. The second DOS instance exists and has its own open
; file and its own current directory, but a service that silently shared one
; set of state between two of them would be worse than not offering it - the
; generic form reaches $02 today, and giving these entry points an instance is
; a later decision that does not have to be made now.
;
; **Reading a directory is the reason uci_exec_first / uci_exec_next exist.**
; DOS_CMD_READ_DIR does not answer with a list. It answers with one reply block
; per entry, each of them <attrib> <name> with no terminator and no length, and
; the block boundary is the only thing separating one name from the next. Drain
; the chain into a single buffer the way every other command wants and the
; result is unparseable: an attribute byte of $20 is a space, so a filename
; containing one is indistinguishable from the start of the next entry. So
; ultimate_readdir walks the blocks itself, one call per entry.
;
; Strings are what the caller passed, byte for byte. The Ultimate speaks ASCII
; and a C64 program holds PETSCII, and converting here would be the SDK
; guessing: docs/uci.md has the conversion, and file.s does it where the
; operation is a BASIC one.
;
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"
        .include "uci_zp.inc"

        .import uci_exec, uci_exec_first, uci_exec_next, uci_more
        .import ult_req, ult_buf, ult_buflen, ult_outlen
        .import ult_attrib, ult_dir, ult_num
        .import ult_req_clear, ult_exec_string

        .export ultimate_chdir,   _ultimate_chdir
        .export ultimate_getpath
        .export ultimate_opendir, _ultimate_opendir
        .export ultimate_readdir
        .export ultimate_open
        .export ultimate_close,   _ultimate_close
        .export ultimate_read
        .export ultimate_write
        .export ultimate_seek

        .code

; ---------------------------------------------------------------------------
; ultimate_chdir   ult_buf = NUL-terminated path  ->  A = ULTIMATE_* result
;
; A/X from C, which is the same thing: the C entry point stores the pointer and
; falls straight through.
; ---------------------------------------------------------------------------
_ultimate_chdir:
        sta ult_buf
        stx ult_buf + 1
ultimate_chdir:
        lda #DOS_CMD_CHANGE_DIR
        jmp ult_str_cmd

; ---------------------------------------------------------------------------
; ultimate_getpath   ult_buf, ult_buflen, ult_outlen  ->  A = result
;
; The current directory as a NUL-terminated string, same rules as
; ultimate_identify: at most buflen-1 bytes are stored, and a path that did not
; fit is ULTIMATE_OK with the length it kept, not an error - a truncated path is
; still the answer to "where am I".
; ---------------------------------------------------------------------------
ultimate_getpath:
        lda ult_buf
        ora ult_buf + 1
        beq @invalid
        lda ult_buflen
        ora ult_buflen + 1
        beq @invalid

        jsr ult_req_clear
        jsr ult_dos_target
        lda #DOS_CMD_GET_PATH
        sta ult_req + UCI_REQ_COMMAND
        jsr ult_exec_string
        cmp #ULTIMATE_ERR_TRUNCATED
        bne @out
        lda #ULTIMATE_OK
@out:   ldx #$00
        rts

@invalid:
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        ldx #$00
        rts

; ---------------------------------------------------------------------------
; ultimate_opendir  ->  A = ULTIMATE_* result
;
; Opens the current directory for reading. ultimate_readdir returns its entries
; one at a time afterwards.
; ---------------------------------------------------------------------------
ultimate_opendir:
_ultimate_opendir:
        lda #$00
        sta ult_dir             ; a failed open must not leave a walk armed

        jsr ult_req_clear
        jsr ult_dos_target
        lda #DOS_CMD_OPEN_DIR
        sta ult_req + UCI_REQ_COMMAND
        jsr ult_dos_exec
        cmp #ULTIMATE_OK
        bne @out
        lda #ULT_DIR_FIRST
        sta ult_dir
        lda #ULTIMATE_OK
@out:   ldx #$00
        rts

; ---------------------------------------------------------------------------
; ultimate_readdir   ult_buf, ult_buflen  ->  A = result, ult_attrib = attributes
;
; One entry per call. ULTIMATE_END means the directory is finished - it is not
; a failure, and it is a distinct code precisely so that a caller does not have
; to tell "no more entries" apart from "something went wrong".
;
; The name is NUL-terminated in the caller's buffer; a name that does not fit is
; clipped rather than refused, exactly as ultimate_identify clips.
;
; **Do not issue other commands between calls.** The walk is a live exchange
; with the Ultimate, and another command in the middle of it ends the
; directory. Read the whole directory, then do something with it.
; ---------------------------------------------------------------------------
ULT_DIR_FIRST = 1
ULT_DIR_NEXT  = 2

ultimate_readdir:
        lda ult_buf
        ora ult_buf + 1
        beq @invalid
        lda ult_buflen
        ora ult_buflen + 1
        beq @invalid

        lda ult_dir
        bne @walking
        lda #ULTIMATE_END       ; no directory open, or this one is finished
        ldx #$00
        rts

@walking:
        lda ult_dir
        cmp #ULT_DIR_FIRST
        bne @next

        jsr ult_req_clear
        jsr ult_dos_target
        lda #DOS_CMD_READ_DIR
        sta ult_req + UCI_REQ_COMMAND
        jsr ult_dir_buffers
        lda #<ult_req
        ldx #>ult_req
        jsr uci_exec_first
        jmp @block

        ; The buffer is the caller's and may differ from call to call, so the
        ; request block is re-aimed every time rather than once at the start.
@next:  jsr ult_dir_buffers
        jsr uci_exec_next

@block: cmp #ULTIMATE_OK
        beq @got
        pha                     ; the walk is over, however it ended
        lda #$00
        sta ult_dir
        pla
        ldx #$00
        rts

        ; Another block follows only while uci_more says so. Recording that now
        ; is what makes the *next* call return ULTIMATE_END instead of
        ; re-entering a finished exchange.
@got:   lda uci_more
        beq @last
        lda #ULT_DIR_NEXT
        sta ult_dir
        bne @unpack             ; always
@last:  lda #$00
        sta ult_dir

        ; An entry is <attrib> <name>. A block with nothing in it is the end.
@unpack:
        lda ult_req + UCI_REQ_DATALEN
        ora ult_req + UCI_REQ_DATALEN + 1
        bne @have
        lda #ULTIMATE_END
        ldx #$00
        rts

@have:  jsr ult_shift_name
        lda #ULTIMATE_OK
        ldx #$00
        rts

@invalid:
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        ldx #$00
        rts

; ---------------------------------------------------------------------------
; ultimate_open   A = DOS_FA_* mask, ult_buf = NUL-terminated name
;              -> A = ULTIMATE_* result
;
; The command is <attrib> <filename>, which is exactly what the request block's
; two spans are for: the attribute byte is the argument span and the name is the
; payload, so neither has to be copied into a buffer of ours first.
; ---------------------------------------------------------------------------
ultimate_open:
        sta ult_attrib
        jsr ult_strlen
        bcc @toolong

        jsr ult_req_clear
        jsr ult_dos_target
        lda #DOS_CMD_OPEN_FILE
        sta ult_req + UCI_REQ_COMMAND
        lda #<ult_attrib
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_attrib
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$01
        sta ult_req + UCI_REQ_ARGLEN
        jsr ult_name_payload
        jmp ult_dos_exec

@toolong:
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        ldx #$00
        rts

; ---------------------------------------------------------------------------
; ultimate_close  ->  A = ULTIMATE_* result
; ---------------------------------------------------------------------------
ultimate_close:
_ultimate_close:
        jsr ult_req_clear
        jsr ult_dos_target
        lda #DOS_CMD_CLOSE_FILE
        sta ult_req + UCI_REQ_COMMAND
        jmp ult_dos_exec

; ---------------------------------------------------------------------------
; ultimate_read   ult_buf = buffer, ult_buflen = how many bytes to ask for,
;                 ult_outlen = where to report how many arrived
;              -> A = ULTIMATE_* result
;
; The firmware answers in 512-byte blocks and uci_exec walks the chain, so a
; caller asks for what it wants and gets it whole. Fewer bytes than asked for is
; the end of the file, not an error: ult_outlen is the answer.
; ---------------------------------------------------------------------------
ultimate_read:
        lda ult_buf
        ora ult_buf + 1
        beq @invalid
        lda ult_buflen
        ora ult_buflen + 1
        beq @invalid

        lda ult_buflen
        sta ult_num
        lda ult_buflen + 1
        sta ult_num + 1

        jsr ult_req_clear
        jsr ult_dos_target
        lda #DOS_CMD_READ_DATA
        sta ult_req + UCI_REQ_COMMAND
        lda #<ult_num
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_num
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$02
        sta ult_req + UCI_REQ_ARGLEN

        lda ult_buf
        sta ult_req + UCI_REQ_DATA
        lda ult_buf + 1
        sta ult_req + UCI_REQ_DATA + 1
        lda ult_buflen
        sta ult_req + UCI_REQ_DATAMAX
        lda ult_buflen + 1
        sta ult_req + UCI_REQ_DATAMAX + 1

        jsr ult_dos_exec
        pha
        jsr ult_report_len
        pla
        ldx #$00
        rts

@invalid:
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        ldx #$00
        rts

; ---------------------------------------------------------------------------
; ultimate_write   ult_buf = data, ult_buflen = length  ->  A = result
;
; DOS_CMD_WRITE_DATA is <$00> <$00> <data>: the firmware skips two bytes before
; the payload and never looks at them. They are sent from rodata rather than
; copied in front of the caller's data, which is what keeps this zero-copy.
; ---------------------------------------------------------------------------
ultimate_write:
        lda ult_buf
        ora ult_buf + 1
        beq @invalid
        lda ult_buflen
        ora ult_buflen + 1
        beq @invalid

        jsr ult_req_clear
        jsr ult_dos_target
        lda #DOS_CMD_WRITE_DATA
        sta ult_req + UCI_REQ_COMMAND
        lda #<ult_write_pad
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_write_pad
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$02
        sta ult_req + UCI_REQ_ARGLEN
        jsr ult_name_payload
        jmp ult_dos_exec

@invalid:
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        ldx #$00
        rts

; ---------------------------------------------------------------------------
; ultimate_seek   ult_num = 32-bit position, little endian  ->  A = result
; ---------------------------------------------------------------------------
ultimate_seek:
        jsr ult_req_clear
        jsr ult_dos_target
        lda #DOS_CMD_FILE_SEEK
        sta ult_req + UCI_REQ_COMMAND
        lda #<ult_num
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_num
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$04
        sta ult_req + UCI_REQ_ARGLEN
        jmp ult_dos_exec

; ---------------------------------------------------------------------------
; Internals
; ---------------------------------------------------------------------------

ult_dos_target:
        lda #UCI_TARGET_DOS1
        sta ult_req + UCI_REQ_TARGET
        rts

ult_dos_exec:
        lda #<ult_req
        ldx #>ult_req
        jmp uci_exec

; The caller's buffer as the reply span, for one directory entry.
ult_dir_buffers:
        lda ult_buf
        sta ult_req + UCI_REQ_DATA
        lda ult_buf + 1
        sta ult_req + UCI_REQ_DATA + 1
        lda ult_buflen
        sta ult_req + UCI_REQ_DATAMAX
        lda ult_buflen + 1
        sta ult_req + UCI_REQ_DATAMAX + 1
        rts

; Lift the attribute byte out of the block and slide the name down over it, so
; the caller is left holding the name alone, NUL-terminated. Moving down rather
; than up means source and destination can overlap safely.
;
; The length is clamped to 254 so that the terminator always fits: a directory
; entry cannot be longer than a FAT long name, and a caller with a smaller
; buffer has already had the reply clipped by the transport.
ult_shift_name:
        lda ult_buf
        sta uci_ptr
        lda ult_buf + 1
        sta uci_ptr + 1
        ldy #$00
        lda (uci_ptr),y
        sta ult_attrib

        lda ult_req + UCI_REQ_DATALEN + 1
        bne @clamp
        ldx ult_req + UCI_REQ_DATALEN
        dex                             ; without the attribute byte
        cpx #255
        bcc @slide
@clamp: ldx #254
@slide: stx ult_num                     ; free here: readdir sends no arguments
        ldy #$00
@loop:  cpy ult_num
        beq @term
        iny
        lda (uci_ptr),y
        dey
        sta (uci_ptr),y
        iny
        jmp @loop
@term:  lda #$00
        sta (uci_ptr),y
        rts

; ult_buf / ult_buflen as the payload span.
ult_name_payload:
        lda ult_buf
        sta ult_req + UCI_REQ_PAYLOAD
        lda ult_buf + 1
        sta ult_req + UCI_REQ_PAYLOAD + 1
        lda ult_buflen
        sta ult_req + UCI_REQ_PAYLOADLEN
        lda ult_buflen + 1
        sta ult_req + UCI_REQ_PAYLOADLEN + 1
        rts

; Report req.datalen through ult_outlen, when the caller asked for it.
ult_report_len:
        lda ult_outlen
        ora ult_outlen + 1
        beq @none
        lda ult_outlen
        sta uci_ptr
        lda ult_outlen + 1
        sta uci_ptr + 1
        ldy #$00
        lda ult_req + UCI_REQ_DATALEN
        sta (uci_ptr),y
        iny
        lda ult_req + UCI_REQ_DATALEN + 1
        sta (uci_ptr),y
@none:  rts

; A command whose only argument is the string in ult_buf.
;   A = command byte
ult_str_cmd:
        pha
        jsr ult_strlen
        bcc @toolong
        jsr ult_req_clear
        jsr ult_dos_target
        pla
        sta ult_req + UCI_REQ_COMMAND
        lda ult_buf
        sta ult_req + UCI_REQ_ARGS
        lda ult_buf + 1
        sta ult_req + UCI_REQ_ARGS + 1
        lda ult_buflen
        sta ult_req + UCI_REQ_ARGLEN
        lda ult_buflen + 1
        sta ult_req + UCI_REQ_ARGLEN + 1
        jmp ult_dos_exec

@toolong:
        pla
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        ldx #$00
        rts

; ult_buflen = strlen(ult_buf), carry set when it fit.
;
; Bounded at 255 on purpose: an unterminated string would otherwise walk the
; whole address space looking for a zero, and every name this SDK can carry -
; a FAT long name, the wedge's 256-byte buffer - fits inside it anyway. Longer
; than that is a caller bug and says so.
ult_strlen:
        lda ult_buf
        sta uci_ptr
        lda ult_buf + 1
        sta uci_ptr + 1
        ldy #$00
@loop:  lda (uci_ptr),y
        beq @done
        iny
        bne @loop
        clc                     ; 256 bytes with no terminator in sight
        rts
@done:  sty ult_buflen
        lda #$00
        sta ult_buflen + 1
        sec
        rts

        .rodata

; The two bytes DOS_CMD_WRITE_DATA skips. Numeric, like every other byte that
; goes on the wire.
ult_write_pad:
        .byte $00, $00
