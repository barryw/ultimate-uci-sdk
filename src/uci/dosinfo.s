; dosinfo.s - Layer 2: what a file is, and moving files about.
;
; The rest of the Ultimate DOS command set: stat, rename, copy, make directory
; and the home directory. Its own module rather than more of dos.s, because
; cc65 links whole object files and a program that only opens a file should not
; pay for the reply decoder stat needs.
;
; **Two of these send three runs of caller bytes, and the request block has two
; spans.** RENAME_FILE is <old> $00 <new> and COPY_FILE is <src> $00 <dst>.
; Nothing is copied to achieve that: the first name goes out as the argument
; span with its terminator counted in the length, which is the separator the
; firmware splits on, and the second goes out as the payload span with its
; terminator counted too. Current firmware does not consistently add a missing
; final terminator before handing names to the filesystem.
;
; **The stat reply is a fixed header followed by a name with no terminator.**
; Twelve bytes of size, date, time, extension and attributes, and whatever is
; left of the reply is the name - see the DOS_INFO_* offsets in
; uci_protocol.inc, read out of t_dos_info in software/filemanager/dos.h. The
; reply lands straight in the caller's structure, which has the same layout, and
; the terminator is written afterwards at the length the transport reported.
;
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"
        .include "uci_seg.inc"
        .include "uci_zp.inc"

        .import ult_req, ult_buf, ult_buflen, ult_arg2
        .import ult_req_clear, ult_invalid
        .import ult_dos_target, ult_dos_exec, ult_str_cmd, ult_strlen

        .export ultimate_stat
        .export ultimate_fstat
        .export ultimate_rename
        .export ultimate_copy
        .export ultimate_mkdir,   _ultimate_mkdir
        .export ultimate_home,    _ultimate_home

; The caller's structure: the twelve-byte header, the longest name the firmware
; copies, and the terminator this file writes after it.
ULT_FILEINFO_SIZE = DOS_INFO_NAME + DOS_INFO_NAME_MAX + 1

        uci_code

; ---------------------------------------------------------------------------
; ultimate_mkdir   ult_buf = NUL-terminated name  ->  A = ULTIMATE_* result
;
; One directory, in the current one. A failure comes back from the filesystem
; in words rather than in a code - "DIRECTORY FULL", with no "NN," in front of
; it - which the transport reports as ULTIMATE_ERR_DEVICE and leaves in a status
; buffer if the caller supplied one.
; ---------------------------------------------------------------------------
_ultimate_mkdir:
        sta ult_buf
        stx ult_buf + 1
ultimate_mkdir:
        lda #DOS_CMD_CREATE_DIR
        jmp ult_str_cmd

; ---------------------------------------------------------------------------
; ultimate_home  ->  A = ULTIMATE_* result
;
; Change to the Ultimate's configured home directory. Firmware that does not
; have one answers "99,FUNCTION NOT IMPLEMENTED", which arrives as
; ULTIMATE_ERR_NOT_SUPPORTED.
; ---------------------------------------------------------------------------
ultimate_home:
_ultimate_home:
        jsr ult_req_clear
        jsr ult_dos_target
        lda #DOS_CMD_COPY_HOME_PATH
        sta ult_req + UCI_REQ_COMMAND
        jmp ult_dos_exec

; ---------------------------------------------------------------------------
; ultimate_rename   ult_buf = old name, ult_arg2 = new name
; ultimate_copy     ult_buf = source,   ult_arg2 = destination path
;                -> A = ULTIMATE_* result
;
; Rename uses two names in the current directory. Copy preserves the source
; name and puts it at the directory path named by ult_arg2.
; The Ultimate does the copying, so no bytes pass through the C64.
; ---------------------------------------------------------------------------
ultimate_rename:
        lda #DOS_CMD_RENAME_FILE
        bne dos_two_names               ; always: the command byte is not zero

ultimate_copy:
        lda #DOS_CMD_COPY_FILE

; A = command byte.
dos_two_names:
        pha
        jsr ult_req_clear
        jsr ult_dos_target
        pla
        sta ult_req + UCI_REQ_COMMAND

        jsr ult_strlen                  ; ult_buflen = strlen(ult_buf)
        bcc dosinfo_invalid
        lda ult_buflen
        ora ult_buflen + 1
        beq dosinfo_invalid             ; an empty first name names nothing

        lda ult_buf
        sta ult_req + UCI_REQ_ARGS
        lda ult_buf + 1
        sta ult_req + UCI_REQ_ARGS + 1
        clc                             ; ...+ 1 for the NUL between the names
        lda ult_buflen
        adc #$01
        sta ult_req + UCI_REQ_ARGLEN
        lda ult_buflen + 1
        adc #$00
        sta ult_req + UCI_REQ_ARGLEN + 1

        lda ult_arg2                    ; the second name, measured in place
        sta uci_ptr
        sta ult_req + UCI_REQ_PAYLOAD
        lda ult_arg2 + 1
        sta uci_ptr + 1
        sta ult_req + UCI_REQ_PAYLOAD + 1
        ora ult_arg2
        beq dosinfo_invalid

        ldy #$00
@len:   lda (uci_ptr),y
        beq @got
        iny
        bne @len
@got:   cpy #$00
        beq dosinfo_invalid             ; and an empty second name names nothing
        iny                             ; include its terminator on the wire
        sty ult_req + UCI_REQ_PAYLOADLEN
        jmp ult_dos_exec

; Between the two routines so that both can reach it with a short branch.
dosinfo_invalid:
        jmp ult_invalid

; ---------------------------------------------------------------------------
; ultimate_stat    ult_buf = name, ult_arg2 = ULT_FILEINFO_SIZE-byte structure
; ultimate_fstat   ult_arg2 = the same, for the file that is already open
;               -> A = ULTIMATE_* result
;
; The size is the number a program usually wants: how much room to reserve
; before loading, or whether a save wrote everything it was given.
;
; A reply shorter than the header is ULTIMATE_ERR_PROTOCOL rather than a
; half-filled structure, on the same argument palette_get makes: a size read out
; of two bytes of a four-byte field looks like a real answer.
; ---------------------------------------------------------------------------
ultimate_stat:
        lda #DOS_CMD_FILE_STAT
        bne dos_stat                    ; always

ultimate_fstat:
        lda #DOS_CMD_FILE_INFO

dos_stat:
        pha
        jsr ult_req_clear
        jsr ult_dos_target
        pla
        sta ult_req + UCI_REQ_COMMAND

        lda ult_arg2
        ora ult_arg2 + 1
        beq dosinfo_invalid

        lda ult_req + UCI_REQ_COMMAND
        cmp #DOS_CMD_FILE_STAT
        bne @buffers

        jsr ult_strlen
        bcc dosinfo_invalid
        lda ult_buflen
        ora ult_buflen + 1
        beq dosinfo_invalid
        lda ult_buf
        sta ult_req + UCI_REQ_ARGS
        lda ult_buf + 1
        sta ult_req + UCI_REQ_ARGS + 1
        lda ult_buflen
        clc                             ; firmware needs the NUL on FILE_STAT
        adc #$01
        sta ult_req + UCI_REQ_ARGLEN
        lda ult_buflen + 1
        adc #$00
        sta ult_req + UCI_REQ_ARGLEN + 1

@buffers:
        lda ult_arg2
        sta ult_req + UCI_REQ_DATA
        lda ult_arg2 + 1
        sta ult_req + UCI_REQ_DATA + 1
        lda #ULT_FILEINFO_SIZE - 1      ; one back, so the terminator always fits
        sta ult_req + UCI_REQ_DATAMAX

        jsr ult_dos_exec
        cmp #ULTIMATE_OK
        bne @out

        lda ult_req + UCI_REQ_DATALEN + 1
        bne @short                      ; more than a page is not this reply
        lda ult_req + UCI_REQ_DATALEN
        cmp #DOS_INFO_NAME
        bcc @short

        clc                             ; terminate the name at its own length
        adc ult_arg2
        sta uci_ptr
        lda ult_arg2 + 1
        adc #$00
        sta uci_ptr + 1
        lda #$00
        ldy #$00
        sta (uci_ptr),y
        lda #ULTIMATE_OK
@out:   ldx #$00
        ora #$00                ; N and Z from A, not the ldx
        rts

@short: ldx #$00
        lda #ULTIMATE_ERR_PROTOCOL
        rts
