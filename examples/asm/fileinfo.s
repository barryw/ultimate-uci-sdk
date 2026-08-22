; fileinfo.s - a file's size and the machine's drives, from assembly.
;
; Two of the SDK's structured replies, both received straight into a block this
; program owns. Nothing is parsed byte by byte: the firmware's layout is the
; caller's layout, and the DOS_INFO_* and CTRL_DRVINFO_* offsets in
; uci_protocol.inc name every field.
;
; The calling convention is the one docs/asm-abi.md describes. Arguments that do
; not fit in a register go in the shared variable block:
;
;     ult_buf     the filename, and the block a drive report is written into
;     ult_arg2    the block a file report is written into
;
; Build:  make
;
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"

        ; The standard cc65 start-up code, which sets up the C runtime the SDK
        ; core was compiled against. See docs/asm-abi.md.
        .forceimport __STARTUP__
        .export _main

CHROUT  = $FFD2

; $FB-$FE are left alone by both the KERNAL (outside tape routines) and the
; cc65 runtime, whose zero page allocation is $02-$1B on this target.
str_ptr = $FB

; ---------------------------------------------------------------------------

        .bss

; The two replies. ULTIMATE_FILEINFO_SIZE and CTRL_DRVINFO_BYTES come from
; ultimate.inc and uci_protocol.inc, so neither number is written here.
finfo:  .res ULTIMATE_FILEINFO_SIZE
drives: .res CTRL_DRVINFO_BYTES

rec_off:   .res 1               ; where the drive record being printed starts
cur_drive: .res 1               ; and which drive that is

; ---------------------------------------------------------------------------

        .code

_main:
        lda #<msg_title
        ldy #>msg_title
        jsr puts

        jsr ultimate_init
        cmp #ULTIMATE_OK
        beq up

        pha
        lda #<msg_absent
        ldy #>msg_absent
        jsr puts
        pla
        jsr put_hex
        jmp newline

; --- the file ---
;
; The name is sent byte for byte. The Ultimate speaks ASCII and a C64 program
; usually holds PETSCII, so the SDK converts nothing and the name below is
; written as the bytes the firmware is to receive.
up:
        lda #<filename
        sta ult_buf
        lda #>filename
        sta ult_buf + 1
        lda #<finfo
        sta ult_arg2
        lda #>finfo
        sta ult_arg2 + 1

        jsr ultimate_stat
        cmp #ULTIMATE_OK
        beq have_file

        pha
        lda #<msg_nofile
        ldy #>msg_nofile
        jsr puts
        pla
        jsr put_hex
        jsr newline
        jmp do_drives

have_file:
        lda #<msg_size
        ldy #>msg_size
        jsr puts

        ; The size is 32 bits, little-endian, at DOS_INFO_SIZE. Printed here as
        ; four hex bytes, most significant first, which needs no division.
        lda finfo + DOS_INFO_SIZE + 3
        jsr put_hex
        lda finfo + DOS_INFO_SIZE + 2
        jsr put_hex
        lda finfo + DOS_INFO_SIZE + 1
        jsr put_hex
        lda finfo + DOS_INFO_SIZE
        jsr put_hex
        jsr newline

        ; The name the firmware reported, which the SDK terminated for us.
        lda #<msg_name
        ldy #>msg_name
        jsr puts
        lda #<(finfo + DOS_INFO_NAME)
        ldy #>(finfo + DOS_INFO_NAME)
        jsr puts
        jsr newline

; --- the drives ---
;
; A count, then one record per drive. The device number in each record is what
; ultimate_mount takes, so this is how a program finds a drive to mount into
; without asking whoever is at the keyboard.
do_drives:
        jsr newline
        lda #<drives
        ldx #>drives
        jsr ultimate_drive_info
        cmp #ULTIMATE_OK
        beq have_drives

        pha
        lda #<msg_nodrives
        ldy #>msg_nodrives
        jsr puts
        pla
        jsr put_hex
        jmp newline

have_drives:
        lda #CTRL_DRVINFO_FIRST
        sta rec_off
        ldx #$00                        ; which record

next_drive:
        cpx drives + CTRL_DRVINFO_COUNT
        beq done
        stx cur_drive

        lda #<msg_drive
        ldy #>msg_drive
        jsr puts

        ; A record is three bytes: type, device number, power. rec_off holds
        ; where this one starts, and puts clobbers Y, so it is loaded again for
        ; each field rather than kept.
        ldy rec_off
        lda drives + 1, y               ; the device number
        jsr put_hex

        lda #<msg_type
        ldy #>msg_type
        jsr puts
        ldy rec_off
        lda drives, y                   ; the CTRL_DRVTYPE_* code
        jsr put_hex

        ldy rec_off
        lda drives + 2, y               ; 1 while the drive is running
        beq off
        lda #<msg_running
        ldy #>msg_running
        jsr puts
        jmp stepped
off:    lda #<msg_off
        ldy #>msg_off
        jsr puts

stepped:
        clc
        lda rec_off
        adc #CTRL_DRVINFO_RECORD
        sta rec_off
        ldx cur_drive
        inx
        jmp next_drive

done:   rts

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

newline:
        lda #$0d
        jmp CHROUT

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

; Lowercase in the source, uppercase on the screen: ca65's c64 charmap sends
; source 'A'-'Z' to PETSCII $C1-$DA, which CHROUT renders as graphics symbols.
msg_title:    .byte "ultimate sdk - file info", $0d, $0d, $00
msg_absent:   .byte "no ultimate found, error $", $00
msg_nofile:   .byte "no such file, error $", $00
msg_size:     .byte "size  : $", $00
msg_name:     .byte "name  : ", $00
msg_nodrives: .byte "no drive commands, error $", $00
msg_drive:    .byte "drive at device $", $00
msg_type:     .byte ", type $", $00
msg_running:  .byte ", running", $0d, $00
msg_off:      .byte ", off", $0d, $00

; The name the firmware receives, as ASCII bytes rather than as a string
; literal: ca65's charmap would rewrite a literal on its way to the wire. This
; spells "/Usb0/big.bin", which is the fixture the emulator suite uses; change
; it to a file your own medium has.
filename:
        .byte $2F, $55, $73, $62, $30, $2F       ; /Usb0/
        .byte $62, $69, $67, $2E, $62, $69, $6E  ; big.bin
        .byte $00
