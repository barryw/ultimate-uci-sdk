; file.s - Layer 2b: load and save, the operations a program actually wants.
;
; `ultimate_load` is the one with two tiers, and the difference is not small:
;
;     SoftwareIEC usable?  -> LOAD_SU + LOAD_EX   the firmware writes straight
;     |                                           into C64 RAM
;     `- otherwise         -> DOS OPEN/READ/CLOSE every byte through the
;                                                 response queue
;
; **Which tier is chosen by trying, not by asking.** Target $05 reports present
; even when the IEC drive is switched off - GideonZ/1541ultimate#794 settles
; that this is intended, because UCI is how the hyperspeed kernal reaches it -
; and detection could not tell you a *file* is loadable in any case. So the fast
; path is attempted and the slow one runs if it did not work, which is also what
; makes this correct on a firmware with no SoftwareIEC target at all.
;
; Two things about LOAD_SU that were read out of the firmware rather than
; guessed, and that a reimplementation would get wrong:
;
; - **Its argument block is <sec> <verify> <addr16> <unused16>, and the unused
;   pair must be sent.** `cmd_load_su()` opens `&command->message[8]`: a load
;   shares SAVE's layout and has to carry the end-address pair it never reads.
;   Send the name at offset 6 and the firmware opens whatever follows it, which
;   surfaces as "file not found" on a file that is plainly there.
; - **`sec` is the same 0-or-1 that `LOAD"X",8,1` uses.** 1 takes the address
;   from the file's own first two bytes, 0 takes it from the caller. That is the
;   firmware's own meaning, so `ultimate_load(name, 0)` and `LOAD"X",8,1` do the
;   same thing on purpose.
;
; LOAD_EX returns the end address in status bytes 1 and 2. The transport keeps
; the first four status bytes for its own decoder, so they are there to be read
; without the caller providing a buffer for them.
;
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"
        .include "uci_seg.inc"
        .include "uci_zp.inc"

        .import uci_exec, uci_stat
        .import ult_req, ult_buf, ult_buflen, ult_outlen
        .import ult_req_clear
        .import ult_fargs, ult_addr, ult_max, ult_end, ult_got
        .import ultimate_open, ultimate_close, ultimate_read, ultimate_write

        .export ultimate_load
        .export ultimate_bload
        .export ultimate_save
        .export ultimate_last_end, _ultimate_last_end

; How much is asked for in one go on the slow path. Bigger is fewer round trips
; - a round trip is about 2700 cycles, measured, and the transport walks the
; firmware's 512-byte block chain by itself - and the destination is plain RAM,
; so there is nothing to be gained by matching any particular block size.
FILE_CHUNK = 4096

        uci_code

; ---------------------------------------------------------------------------
; ultimate_load   ult_buf = name, ult_addr = address (0 = the file's own)
;              -> A = ULTIMATE_* result, ult_end = the address after the last
;                 byte written
;
; A PRG load. The two header bytes are always consumed and never stored, which
; is what "load" means as opposed to ultimate_bload.
; ---------------------------------------------------------------------------
ultimate_load:
        lda ult_buf
        ora ult_buf + 1
        beq file_invalid

        jsr file_load_su
        cmp #ULTIMATE_OK
        bne @slow
        jsr file_load_ex
        cmp #ULTIMATE_OK
        bne @slow
        ldx #$00
        rts

@slow:  jmp file_load_dos

file_invalid:
        ldx #$00
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        rts

; ---------------------------------------------------------------------------
; ultimate_bload   ult_buf = name, ult_addr = address, ult_max = size limit
;               -> A = ULTIMATE_* result, ult_end = the address after the last
;                  byte written
;
; Raw bytes, nothing interpreted: no header is consumed and no address is taken
; from the file. There is no fast path, and that is not an oversight - LOAD_SU
; is PRG-shaped by construction, and a raw load is exactly the case where its
; header handling is wrong.
; ---------------------------------------------------------------------------
ultimate_bload:
        lda ult_buf
        ora ult_buf + 1
        beq file_invalid
        lda ult_addr
        ora ult_addr + 1
        beq file_invalid        ; nowhere to put it
        lda ult_max
        ora ult_max + 1
        beq file_invalid        ; and no idea how much room is there. A zero
                                ; limit means "no limit" further down, which is
                                ; fine for a PRG whose length the header implies
                                ; and is not fine for raw bytes going into RAM
                                ; the caller named.

        lda #DOS_FA_READ
        jsr ultimate_open
        cmp #ULTIMATE_OK
        bne @out
        jsr file_read_body
@out:   pha
        jsr ultimate_close
        ldx #$00
        pla
        rts

; ---------------------------------------------------------------------------
; ultimate_save   ult_buf = name, ult_addr = start, ult_max = length
;              -> A = ULTIMATE_* result
;
; Through the DOS target, in the same chunks the slow load reads. SoftwareIEC
; has a SAVE of its own and it is not used here: a save is not the operation
; anybody is waiting on, and one tier is one thing to get right.
; ---------------------------------------------------------------------------
ultimate_save:
        lda ult_buf
        ora ult_buf + 1
        beq file_invalid
        lda ult_max
        ora ult_max + 1
        beq file_invalid        ; a zero-length save is a caller bug

        lda #DOS_FA_CREATE_ALWAYS | DOS_FA_WRITE
        jsr ultimate_open
        cmp #ULTIMATE_OK
        bne @out

@chunk: lda ult_max
        ora ult_max + 1
        beq @done
        jsr file_chunk_len      ; ult_got = min(ult_max, FILE_CHUNK)
        jsr file_point_buf
        jsr ultimate_write
        cmp #ULTIMATE_OK
        bne @out
        jsr file_advance
        jmp @chunk

@done:  lda #ULTIMATE_OK
@out:   pha
        jsr ultimate_close
        ldx #$00
        pla
        rts

; ---------------------------------------------------------------------------
; ultimate_last_end  ->  A = low, X = high of the address after the last byte
;                        the previous load wrote
; ---------------------------------------------------------------------------
ultimate_last_end:
_ultimate_last_end:
        lda ult_end
        ldx ult_end + 1
        rts

; ---------------------------------------------------------------------------
; The fast path
; ---------------------------------------------------------------------------

; LOAD_SU: <sec> <verify> <addr16> <unused16> <name>
file_load_su:
        lda #$00
        sta ult_fargs + 1       ; verify: no
        sta ult_fargs + 4       ; the unused pair, which must still be sent
        sta ult_fargs + 5

        lda ult_addr            ; sec is 1 exactly when no address was given
        ora ult_addr + 1
        bne @with_addr
        lda #$01
        bne @sec                ; always taken
@with_addr:
        lda #$00
@sec:   sta ult_fargs

        jsr ult_req_clear
        lda #UCI_TARGET_SOFTIEC
        sta ult_req + UCI_REQ_TARGET
        lda #SOFTIEC_CMD_LOAD_SU
        sta ult_req + UCI_REQ_COMMAND
        lda #<ult_fargs
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_fargs
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$06
        sta ult_req + UCI_REQ_ARGLEN

        jsr file_name_payload
        jmp file_exec

; LOAD_EX: <sec> <verify>, and the end address comes back in the status.
file_load_ex:
        jsr ult_req_clear
        lda #UCI_TARGET_SOFTIEC
        sta ult_req + UCI_REQ_TARGET
        lda #SOFTIEC_CMD_LOAD_EX
        sta ult_req + UCI_REQ_COMMAND
        lda #<ult_fargs
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_fargs
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$02
        sta ult_req + UCI_REQ_ARGLEN

        jsr file_exec
        pha
        lda uci_stat + 1        ; status byte 1-2: the address after the load
        sta ult_end
        lda uci_stat + 2
        sta ult_end + 1
        pla
        rts

; ---------------------------------------------------------------------------
; The slow path
; ---------------------------------------------------------------------------

; open, eat the two header bytes, read the rest, close.
file_load_dos:
        lda #DOS_FA_READ
        jsr ultimate_open
        cmp #ULTIMATE_OK
        bne @out

        ; The header always comes off the file. Where the bytes go afterwards
        ; is the caller's business; whether they are read is not.
        lda #<ult_end
        sta ult_buf
        lda #>ult_end
        sta ult_buf + 1
        lda #$02
        sta ult_buflen
        lda #$00
        sta ult_buflen + 1
        sta ult_outlen
        sta ult_outlen + 1
        jsr ultimate_read
        cmp #ULTIMATE_OK
        bne @out

        lda ult_addr            ; no address given: use the file's own
        ora ult_addr + 1
        bne @body
        lda ult_end
        sta ult_addr
        lda ult_end + 1
        sta ult_addr + 1

@body:  lda #$FF                ; read until the file runs out
        sta ult_max
        sta ult_max + 1
        jsr file_read_body

@out:   pha
        jsr ultimate_close
        ldx #$00
        pla
        rts

; Read into ult_addr until a short read says the file has ended, or until
; ult_max bytes have been taken when a limit was given. ult_addr walks, so it
; is the end address when this returns - which is what ult_end wants.
file_read_body:
        lda #<ult_got
        sta ult_outlen
        lda #>ult_got
        sta ult_outlen + 1

@chunk: jsr file_chunk_len
        lda ult_got
        ora ult_got + 1
        beq @done               ; the limit is used up
        jsr file_point_buf
        jsr ultimate_read
        cmp #ULTIMATE_OK
        bne @out

        ; A read shorter than the request is the end of the file. Advance by
        ; what actually arrived either way.
        lda ult_got
        cmp ult_buflen
        bne @last
        lda ult_got + 1
        cmp ult_buflen + 1
        bne @last

        jsr file_advance
        jmp @chunk

@last:  jsr file_advance
@done:  lda #ULTIMATE_OK
@out:   ldx #$00
        pha
        lda ult_addr            ; where the walk stopped is the end address
        sta ult_end
        lda ult_addr + 1
        sta ult_end + 1
        pla
        rts

; ---------------------------------------------------------------------------
; Internals
; ---------------------------------------------------------------------------

file_exec:
        lda #<ult_req
        ldx #>ult_req
        jmp uci_exec

file_name_payload:
        jsr file_strlen
        lda ult_buf
        sta ult_req + UCI_REQ_PAYLOAD
        lda ult_buf + 1
        sta ult_req + UCI_REQ_PAYLOAD + 1
        lda ult_buflen
        sta ult_req + UCI_REQ_PAYLOADLEN
        lda ult_buflen + 1
        sta ult_req + UCI_REQ_PAYLOADLEN + 1
        rts

; Bounded at 255, exactly as dos.s bounds its own: an unterminated string would
; otherwise walk the address space looking for a zero.
file_strlen:
        lda ult_buf
        sta uci_ptr
        lda ult_buf + 1
        sta uci_ptr + 1
        ldy #$00
@loop:  lda (uci_ptr),y
        beq @done
        iny
        bne @loop
        dey                     ; clipped rather than refused: the firmware will
@done:  sty ult_buflen          ; say what it thinks of a 255-byte name
        lda #$00
        sta ult_buflen + 1
        rts

; ult_got = min(ult_max, FILE_CHUNK), and zero when the limit is used up.
;
; Zero used to mean "no limit" here, which read correctly right up until a
; bounded read exhausted its limit - at which point the counter was zero, the
; limit turned itself off, and a 64-byte bload read all 600 bytes of the file.
; "Read to the end" is $FFFF now: a distinct value rather than the same one
; twice, and effectively unlimited on a machine with 64K of address space.
file_chunk_len:
        lda ult_max
        ora ult_max + 1
        beq @none

        lda ult_max + 1         ; more than a chunk left?
        cmp #>FILE_CHUNK
        bcc @rest
        bne @full
        lda ult_max
        cmp #<FILE_CHUNK
        bcc @rest

@full:  lda #<FILE_CHUNK
        sta ult_got
        lda #>FILE_CHUNK
        sta ult_got + 1
        rts

@rest:  lda ult_max
        sta ult_got
        lda ult_max + 1
        sta ult_got + 1
        rts

@none:  lda #$00
        sta ult_got
        sta ult_got + 1
        rts

; Point the caller-buffer fields at ult_addr for ult_got bytes.
file_point_buf:
        lda ult_addr
        sta ult_buf
        lda ult_addr + 1
        sta ult_buf + 1
        lda ult_got
        sta ult_buflen
        lda ult_got + 1
        sta ult_buflen + 1
        rts

; ult_addr += ult_got, and ult_max -= ult_got when a limit is in force.
file_advance:
        clc
        lda ult_addr
        adc ult_got
        sta ult_addr
        lda ult_addr + 1
        adc ult_got + 1
        sta ult_addr + 1

        sec
        lda ult_max
        sbc ult_got
        sta ult_max
        lda ult_max + 1
        sbc ult_got + 1
        sta ult_max + 1
        rts
