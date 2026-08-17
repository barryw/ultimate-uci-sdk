; identify.s - the Ultimate SDK vertical slice, from assembly.
;
; Same job as examples/cc65/identify.c: find the Ultimate and ask the DOS target
; who it is. The point is that assembly gets there through the documented SDK
; entry points, not by re-implementing the handshake.
;
; Build:  make
;
; The Ultimate's identification strings are plain uppercase ASCII, which the
; C64's default character set prints as-is, so this example sends them straight
; to CHROUT without a PETSCII conversion pass.
;
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"

        ; Pull in the standard cc65 start-up code, which sets up the C runtime
        ; the SDK core was compiled against. See docs/asm-abi.md.
        .forceimport __STARTUP__
        .export _main

CHROUT  = $FFD2

; $FB-$FE are left alone by both the KERNAL (outside tape routines) and the
; cc65 runtime, whose zero page allocation is $02-$1B on this target.
str_ptr = $FB

REPLY_MAX = 64

; ---------------------------------------------------------------------------

        .bss

reply:  .res REPLY_MAX

; ---------------------------------------------------------------------------

        .code

_main:
        lda #<msg_title
        ldy #>msg_title
        jsr puts

        jsr ultimate_init
        cmp #ULTIMATE_OK
        beq found

        pha
        lda #<msg_absent
        ldy #>msg_absent
        jsr puts
        pla
        jsr put_hex
        jmp newline

found:
        jsr uci_req_clear

        lda #UCI_TARGET_DOS1
        sta uci_req + UCI_REQ_TARGET
        lda #UCI_CMD_IDENTIFY
        sta uci_req + UCI_REQ_COMMAND

        lda #<reply
        sta uci_req + UCI_REQ_DATA
        lda #>reply
        sta uci_req + UCI_REQ_DATA + 1
        lda #<REPLY_MAX
        sta uci_req + UCI_REQ_DATAMAX
        lda #>REPLY_MAX
        sta uci_req + UCI_REQ_DATAMAX + 1

        jsr uci_exec_block
        cmp #ULTIMATE_OK
        beq show

        pha
        lda #<msg_failed
        ldy #>msg_failed
        jsr puts
        pla
        jsr put_hex
        jmp newline

show:
        lda #<msg_dos
        ldy #>msg_dos
        jsr puts

        ; The reply is short enough to index with Y; anything longer than 255
        ; bytes needs a 16-bit loop over UCI_REQ_DATALEN.
        ldy #$00
print:  cpy uci_req + UCI_REQ_DATALEN
        beq newline
        lda reply,y
        jsr CHROUT
        iny
        bne print

newline:
        lda #$0d
        jsr CHROUT
        rts

; ---------------------------------------------------------------------------
; Print the NUL-terminated string at A/Y.

puts:
        sta str_ptr
        sty str_ptr + 1
        ldy #$00
@loop:  lda (str_ptr),y
        beq @done
        jsr CHROUT
        iny
        bne @loop
@done:  rts

; Print A as two hex digits.

put_hex:
        pha
        lsr a
        lsr a
        lsr a
        lsr a
        jsr @nibble
        pla
        and #$0f
@nibble:
        clc
        adc #'0'
        cmp #'9' + 1
        bcc @emit
        adc #6                  ; carry is set here, so this adds 7
@emit:  jmp CHROUT

; ---------------------------------------------------------------------------

        .rodata

msg_title:  .byte "ULTIMATE SDK - IDENTIFY", $0d, $0d, $00
msg_absent: .byte "NO ULTIMATE FOUND, ERROR $", $00
msg_failed: .byte "IDENTIFY FAILED, ERROR $", $00
msg_dos:    .byte "DOS 1: ", $00
