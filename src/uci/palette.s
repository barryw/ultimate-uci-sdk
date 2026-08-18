; palette.s - Layer 2: the VIC-II palette, through the control target.
;
; Four commands, all of them firmware newer than 3.15, all of them affecting the
; **live palette only** - not flash, not a VPL file. A program that crashes
; halfway through a colour cycle cannot leave the machine looking wrong
; permanently, which is what makes this safe to drive from a demo.
;
; Its own module rather than more of ultimate.s, because cc65 links whole object
; files: folding these into ultimate.s would charge every program that calls
; ultimate_init() for palette code it never uses.
;
; Built entirely out of uci_exec, like every other service. Nothing here touches
; a hardware register - the VIC's own $D021 family is a different palette
; (which colour index a pixel is), and these commands are the other one (what
; that index looks like).
;
; Timing, measured on real hardware: a whole-palette write is about 4100 cycles,
; a quarter of a frame, and a single colour about 2100. See
; docs/handover-next.md; `make time-run` re-measures it.
;
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"
        .include "uci_seg.inc"
        .include "uci_zp.inc"

        .import uci_exec
        .import ult_req, ult_buf, ult_color
        .import ult_req_clear, ult_invalid

        .export ultimate_palette_get,   _ultimate_palette_get
        .export ultimate_palette_set,   _ultimate_palette_set
        .export ultimate_palette_reset, _ultimate_palette_reset
        .export ultimate_palette_set_color

        uci_code

; ---------------------------------------------------------------------------
; ultimate_palette_get   A/X = pointer to UCI_PALETTE_BYTES bytes
;                     -> A = ULTIMATE_* result
;
; Sixteen colours of R, G, B. A reply that is not exactly 48 bytes is reported
; as ULTIMATE_ERR_PROTOCOL rather than left in the caller's buffer half-written:
; a partially updated palette looks like a working one.
; ---------------------------------------------------------------------------
ultimate_palette_get:
_ultimate_palette_get:
        jsr pal_take_ptr
        bcc @invalid

        jsr ult_req_clear
        jsr pal_control
        lda #CTRL_CMD_GET_PALETTE
        sta ult_req + UCI_REQ_COMMAND

        lda ult_buf
        sta ult_req + UCI_REQ_DATA
        lda ult_buf + 1
        sta ult_req + UCI_REQ_DATA + 1
        lda #UCI_PALETTE_BYTES
        sta ult_req + UCI_REQ_DATAMAX
        lda #$00
        sta ult_req + UCI_REQ_DATAMAX + 1

        jsr pal_exec
        cmp #ULTIMATE_OK
        bne @out

        lda ult_req + UCI_REQ_DATALEN + 1
        bne @short
        lda ult_req + UCI_REQ_DATALEN
        cmp #UCI_PALETTE_BYTES
        bne @short
        lda #ULTIMATE_OK        ; and not the length still in A, which is what
        beq @out                ; the first version of this returned. Always taken.
@short: lda #ULTIMATE_ERR_PROTOCOL
@out:   ldx #$00
        rts

@invalid:
        jmp ult_invalid

; ---------------------------------------------------------------------------
; ultimate_palette_set   A/X = pointer to UCI_PALETTE_BYTES bytes
;                     -> A = ULTIMATE_* result
;
; All sixteen colours in one command. This is the one a colour cycle wants: a
; rotation is every colour moving at once, and sixteen separate single-colour
; writes cost four times as much.
; ---------------------------------------------------------------------------
ultimate_palette_set:
_ultimate_palette_set:
        jsr pal_take_ptr
        bcc @invalid

        jsr ult_req_clear
        jsr pal_control
        lda #CTRL_CMD_SET_PALETTE
        sta ult_req + UCI_REQ_COMMAND

        lda ult_buf
        sta ult_req + UCI_REQ_ARGS
        lda ult_buf + 1
        sta ult_req + UCI_REQ_ARGS + 1
        lda #UCI_PALETTE_BYTES
        sta ult_req + UCI_REQ_ARGLEN

        jsr pal_exec
        ldx #$00
        rts

@invalid:
        jmp ult_invalid

; ---------------------------------------------------------------------------
; ultimate_palette_set_color   ult_color = index, r, g, b
;                           -> A = ULTIMATE_* result
;
; Wider parameters go in the shared variable block, as everywhere else in the
; service layer. The C binding moves cc65's stacked arguments into it.
;
; An index past the sixteenth colour is a caller bug and is refused here rather
; than sent: what the firmware does with one is not documented.
; ---------------------------------------------------------------------------
ultimate_palette_set_color:
        lda ult_color
        cmp #UCI_PALETTE_COLORS
        bcs @invalid

        jsr ult_req_clear
        jsr pal_control
        lda #CTRL_CMD_SET_PALETTE_COLOR
        sta ult_req + UCI_REQ_COMMAND

        lda #<ult_color
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_color
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$04                        ; index, r, g, b
        sta ult_req + UCI_REQ_ARGLEN

        jsr pal_exec
        ldx #$00
        rts

@invalid:
        jmp ult_invalid

; ---------------------------------------------------------------------------
; ultimate_palette_reset  ->  A = ULTIMATE_* result
;
; Back to the machine's built-in palette. Worth calling on the way out of a
; demo, and worth knowing about as the way back from a palette experiment that
; went wrong: it is a command, so it works even when the screen is unreadable.
; ---------------------------------------------------------------------------
ultimate_palette_reset:
_ultimate_palette_reset:
        jsr ult_req_clear
        jsr pal_control
        lda #CTRL_CMD_RESET_PALETTE
        sta ult_req + UCI_REQ_COMMAND

        jsr pal_exec
        ldx #$00
        rts

; ---------------------------------------------------------------------------
; Internals
; ---------------------------------------------------------------------------

; A/X -> ult_buf. Carry set when it is a usable pointer, clear when it is null.
pal_take_ptr:
        sta ult_buf
        stx ult_buf + 1
        ora ult_buf + 1
        beq @null
        sec
        rts
@null:  clc
        rts

pal_control:
        lda #UCI_TARGET_CONTROL
        sta ult_req + UCI_REQ_TARGET
        rts

pal_exec:
        lda #<ult_req
        ldx #>ult_req
        jmp uci_exec
