; ultimate.s - Layer 2: bring-up, capability detection, identity.
;
; Built entirely out of uci_exec. This layer adds no protocol knowledge of its
; own beyond two facts: every target answers command $01, and the firmware's
; placeholder target answers "NO TARGET".
;
; Parameters that do not fit in registers go in the shared variable block, which
; keeps the calling sequence obvious from assembly and costs a C binding nothing
; more than a few stores. Nothing here needs a C runtime.
;
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"
        .include "uci_seg.inc"
        .include "uci_zp.inc"

        .import uci_exec, uci_init, uci_present, uci_ident
        .import ult_up, ult_buf, ult_buflen, ult_outlen, ult_caps
        .import ult_scratch, ult_req, ult_probe

        .export ultimate_init,      _ultimate_init
        .export ultimate_available, _ultimate_available
        .export ultimate_identify
        .export ultimate_detect,    _ultimate_detect
        .export ultimate_get_model
        .export ultimate_legacy_get_sid_info, _ultimate_legacy_get_sid_info
        ; The other service modules build on these four.
        .export ult_req_clear, ult_exec_string
        .export ult_have_buf, ult_invalid

; The probe buffer is deliberately small. Detection does not need to read an
; identification string, only to tell "NO TARGET" from anything else, and
; ultimate_identify stores at most buflen-1 bytes - so sixteen leaves room for
; fifteen, comfortably more than the nine the marker needs and short enough that
; a real identification string is clipped and therefore cannot be mistaken for
; it.
ULT_SCRATCH_LEN = 16
ULT_SID_MAX = 4
ULT_SID_INFO_SIZE = 1 + ULT_SID_MAX * 5

        uci_code

; ---------------------------------------------------------------------------
; ultimate_init  ->  A = ULTIMATE_* result
; ---------------------------------------------------------------------------
ultimate_init:
_ultimate_init:
        jsr uci_init
        pha
        cmp #ULTIMATE_OK
        beq @up
        lda #$00
        beq @store              ; always taken
@up:    lda #$01
@store: sta ult_up
        ldx #$00
        pla
        rts

; ---------------------------------------------------------------------------
; ultimate_available  ->  A = 1 when the SDK is up. Touches no hardware.
; ---------------------------------------------------------------------------
ultimate_available:
_ultimate_available:
        ldx #$00
        lda ult_up
        rts

; ---------------------------------------------------------------------------
; Internal: zero the service layer's request block.
; ---------------------------------------------------------------------------
ult_req_clear:
        lda #$00
        ldx #UCI_REQ_SIZE - 1
@loop:  sta ult_req,x
        dex
        bpl @loop
        rts

; ---------------------------------------------------------------------------
; Internal: did the caller give us somewhere to put the answer?
;
; Carry set when ult_buf and ult_buflen are both non-zero. Six entry points ask
; exactly this before they touch the hardware, and the answer is always the same
; five instructions - so it is written once here and jsr'd, which is smaller
; than six copies and harder to get subtly different.
; ---------------------------------------------------------------------------
ult_have_buf:
        lda ult_buf
        ora ult_buf + 1
        beq @none
        lda ult_buflen
        ora ult_buflen + 1
        beq @none
        sec
        rts
@none:  clc
        rts

; ---------------------------------------------------------------------------
; Internal: the answer to a caller that asked for something impossible.
;
; A tail, not a subroutine: jmp here rather than jsr. Ten entry points end this
; way, and X is zero because that is what a cc65 caller needs to see for an
; unsigned char return.
; ---------------------------------------------------------------------------
ult_invalid:
        ldx #$00
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        rts

; ---------------------------------------------------------------------------
; Internal: run ult_req and NUL-terminate the reply in ult_buf.
;
; Every caller of this wants the same three things afterwards: the exchange run,
; the caller's buffer terminated so C can use it as a string, and the length
; reported through ult_outlen if one was asked for.
; ---------------------------------------------------------------------------
ult_exec_string:
        ; datamax = buflen - 1, leaving room for the terminator
        sec
        lda ult_buflen
        sbc #$01
        sta ult_req + UCI_REQ_DATAMAX
        lda ult_buflen + 1
        sbc #$00
        sta ult_req + UCI_REQ_DATAMAX + 1

        lda ult_buf
        sta ult_req + UCI_REQ_DATA
        lda ult_buf + 1
        sta ult_req + UCI_REQ_DATA + 1

        lda #<ult_req
        ldx #>ult_req
        jsr uci_exec
        pha                     ; keep the result across the bookkeeping

        ; terminate at buf[datalen]
        clc
        lda ult_buf
        adc ult_req + UCI_REQ_DATALEN
        sta uci_ptr
        lda ult_buf + 1
        adc ult_req + UCI_REQ_DATALEN + 1
        sta uci_ptr + 1
        lda #$00
        ldy #$00
        sta (uci_ptr),y

        ; report the length if the caller wanted it
        lda ult_outlen
        ora ult_outlen + 1
        beq @no_outlen
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
@no_outlen:
        pla
        rts

; ---------------------------------------------------------------------------
; ultimate_identify   A = target
;                     ult_buf, ult_buflen, ult_outlen set by the caller
;                  -> A = ULTIMATE_* result
;
; Returns ULTIMATE_ERR_NOT_SUPPORTED when the firmware has no such target.
; ---------------------------------------------------------------------------
ultimate_identify:
        pha
        jsr ult_have_buf
        bcc @invalid

        jsr ult_req_clear
        pla
        and #UCI_TARGET_MASK
        sta ult_req + UCI_REQ_TARGET
        lda #UCI_CMD_IDENTIFY
        sta ult_req + UCI_REQ_COMMAND

        jsr ult_exec_string
        pha

        ; Check the data before the status. A firmware that lacks the
        ; SoftwareIEC target still answers on $05, but through the placeholder,
        ; which replies in the ASCII status format while that target's own
        ; format is a binary byte. The "NO TARGET" marker is unambiguous, so it
        ; wins.
        jsr ult_is_no_target
        bcc @keep

        pla                     ; drop the exchange result: absent beats it
        lda #$00                ; hand back an empty string, not "NO TARGET"
        ldy #$00
        sta (uci_ptr),y    ; still pointing at ult_buf from the check
        lda ult_outlen
        ora ult_outlen + 1
        beq @absent
        lda ult_outlen
        sta uci_ptr
        lda ult_outlen + 1
        sta uci_ptr + 1
        lda #$00
        ldy #$00
        sta (uci_ptr),y
        iny
        sta (uci_ptr),y
@absent:
        ldx #$00
        lda #ULTIMATE_ERR_NOT_SUPPORTED
        rts

@keep:  pla
        cmp #ULTIMATE_ERR_TRUNCATED
        bne @out
        lda #ULTIMATE_OK        ; an identification string we clipped is fine
@out:   ldx #$00
        ora #$00                ; N and Z from A, not the ldx
        rts

@invalid:
        pla
        ldx #$00
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        rts

; ---------------------------------------------------------------------------
; Internal: carry set when the reply in ult_buf is exactly "NO TARGET".
; Leaves uci_ptr pointing at ult_buf.
; ---------------------------------------------------------------------------
ult_is_no_target:
        lda ult_buf
        sta uci_ptr
        lda ult_buf + 1
        sta uci_ptr + 1

        lda ult_req + UCI_REQ_DATALEN + 1
        bne @no
        lda ult_req + UCI_REQ_DATALEN
        cmp #UCI_STR_NO_TARGET_LEN
        bne @no

        ldy #UCI_STR_NO_TARGET_LEN - 1
@loop:  lda (uci_ptr),y
        cmp ult_no_target,y
        bne @no
        dey
        bpl @loop
        sec
        rts
@no:    clc
        rts

; ---------------------------------------------------------------------------
; ultimate_detect   A/X = pointer to a 4-byte capability block
;                -> A = ULTIMATE_* result
;
;   +0 present   +1 ident   +2..3 targets bitmap
; ---------------------------------------------------------------------------
ultimate_detect:
_ultimate_detect:
        sta ult_caps
        stx ult_caps + 1
        lda ult_caps
        ora ult_caps + 1
        bne @have_caps
        ldx #$00
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        rts

@have_caps:
        lda ult_caps
        sta uci_ptr
        lda ult_caps + 1
        sta uci_ptr + 1
        lda #$00
        ldy #$03
@zero:  sta (uci_ptr),y
        dey
        bpl @zero

        jsr uci_present
        cmp #$00
        bne @probe
        ldx #$00
        lda #ULTIMATE_ERR_NO_DEVICE
        rts

@probe: jsr uci_ident
        ldy #$01
        sta (uci_ptr),y

        jsr uci_init
        cmp #ULTIMATE_OK
        beq @up
        ldx #$00
        ora #$00                ; N and Z from A, not the ldx
        rts

@up:    lda #$01
        sta ult_up
        ldy #$00
        sta (uci_ptr),y    ; present = 1

        ; One round trip per target: call this once at start-up and keep the
        ; answer.
        lda #<ult_scratch
        sta ult_buf
        lda #>ult_scratch
        sta ult_buf + 1
        lda #ULT_SCRATCH_LEN
        sta ult_buflen
        lda #$00
        sta ult_buflen + 1
        sta ult_outlen
        sta ult_outlen + 1

        lda #UCI_TARGET_DOS1
        sta ult_probe
@next:  lda ult_probe
        jsr ultimate_identify
        cmp #ULTIMATE_OK
        bne @absent

        ; targets |= 1 << target
        lda ult_caps
        sta uci_ptr
        lda ult_caps + 1
        sta uci_ptr + 1
        ; targets |= 1 << target. Only targets $01..$06 are probed, so the
        ; bit always lands in the low byte; the assert below keeps that true if
        ; the probe range ever grows.
        .assert UCI_TARGET_HTTP < 8, error, "the target bitmap needs its high byte"
        ldx ult_probe
        lda #$01
@shift: cpx #$00
        beq @or_lo
        asl a
        dex
        jmp @shift
@or_lo: ldy #$02
        ora (uci_ptr),y
        sta (uci_ptr),y

@absent:
        inc ult_probe
        lda ult_probe
        cmp #UCI_TARGET_HTTP + 1
        bcc @next

        ldx #$00
        lda #ULTIMATE_OK
        rts

; ---------------------------------------------------------------------------
; ultimate_get_model   ult_buf, ult_buflen, ult_outlen set
;                   -> A = ULTIMATE_* result
;
; The sub-command byte is optional from firmware 3.15 on but required before it,
; so it is always sent.
; Firmware documentation marks CTRL_CMD_GET_HWINFO deprecated. This existing
; model wrapper is retained for compatibility.
;
; The string that comes back is mixed case ("Ultimate 64 Elite"), unlike the
; uppercase identification strings - see docs/uci.md. A program printing it on a
; stock C64 has to fold or convert it first.
; ---------------------------------------------------------------------------
ultimate_get_model:
        jsr ult_have_buf
        bcc @invalid

        jsr ult_req_clear
        lda #UCI_TARGET_CONTROL
        sta ult_req + UCI_REQ_TARGET
        lda #CTRL_CMD_GET_HWINFO
        sta ult_req + UCI_REQ_COMMAND
        lda #<ult_hwinfo_arg
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_hwinfo_arg
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

        .rodata

; The marker is emitted as bytes, never as a string literal: a compiler or an
; assembler charmap must not reach anything compared against the wire.
ult_no_target:
        UCI_STR_NO_TARGET_BYTES

ult_hwinfo_arg:
        .byte CTRL_HWINFO_MODEL

; ---------------------------------------------------------------------------
; ultimate_legacy_get_sid_info   A/X = caller's ULT_SID_INFO_SIZE-byte block
;                      -> A = ULTIMATE_* result
;
; The reply already has the public structure's layout: count, then five-byte
; records containing two little-endian addresses and the raw type byte. Keep it
; in place and validate the count against the actual reply length.
; CTRL_CMD_GET_HWINFO is deprecated, hence this entry point's legacy name.
; ---------------------------------------------------------------------------
        uci_code

ultimate_legacy_get_sid_info:
_ultimate_legacy_get_sid_info:
        sta ult_buf
        stx ult_buf + 1
        ora ult_buf + 1
        beq @invalid

        jsr @clear_count
        jsr ult_req_clear
        lda #UCI_TARGET_CONTROL
        sta ult_req + UCI_REQ_TARGET
        lda #CTRL_CMD_GET_HWINFO
        sta ult_req + UCI_REQ_COMMAND
        lda #<ult_hwinfo_sid_arg
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_hwinfo_sid_arg
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$01
        sta ult_req + UCI_REQ_ARGLEN
        lda ult_buf
        sta ult_req + UCI_REQ_DATA
        lda ult_buf + 1
        sta ult_req + UCI_REQ_DATA + 1
        lda #ULT_SID_INFO_SIZE
        sta ult_req + UCI_REQ_DATAMAX

        lda #<ult_req
        ldx #>ult_req
        jsr uci_exec
        cmp #ULTIMATE_OK
        bne @failed

        lda ult_req + UCI_REQ_DATALEN + 1
        bne @protocol
        lda ult_buf
        sta uci_ptr
        lda ult_buf + 1
        sta uci_ptr + 1
        ldy #$00
        lda (uci_ptr),y
        tax
        cpx #ULT_SID_MAX + 1
        bcs @protocol
        lda ult_sid_reply_lengths,x
        cmp ult_req + UCI_REQ_DATALEN
        bne @protocol
        ldx #$00
        lda #ULTIMATE_OK
        rts

@protocol:
        lda #ULTIMATE_ERR_PROTOCOL
@failed:
        pha
        jsr @clear_count
        ldx #$00
        pla
        rts

@invalid:
        jmp ult_invalid

@clear_count:
        lda ult_buf
        sta uci_ptr
        lda ult_buf + 1
        sta uci_ptr + 1
        lda #$00
        ldy #$00
        sta (uci_ptr),y
        rts

        .rodata

ult_hwinfo_sid_arg:
        .byte CTRL_HWINFO_SID

ult_sid_reply_lengths:
        .byte 1, 6, 11, 16, 21
