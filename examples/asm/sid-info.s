; Legacy example: HWINFO is deprecated and may disappear. SPDX-License-Identifier: MIT

        .include "ultimate.inc"

        .forceimport __STARTUP__
        .export _main

CHROUT = $ffd2
ptr    = $fb

        .bss

sid_info:   .res ULTIMATE_SID_INFO_SIZE
sid_index:  .res 1
sid_offset: .res 1

        .code

_main:
        jsr ultimate_init
        cmp #ULTIMATE_OK
        bne failed
        lda #<sid_info
        ldx #>sid_info
        jsr ultimate_legacy_get_sid_info
        cmp #ULTIMATE_OK
        bne failed

        lda #<msg_count
        ldy #>msg_count
        jsr puts
        lda sid_info + ULTIMATE_SID_INFO_COUNT
        jsr put_hex
        jsr newline

        lda #$00
        sta sid_index
        sta sid_offset
next:
        lda sid_index
        cmp sid_info + ULTIMATE_SID_INFO_COUNT
        beq done
        inc sid_index

        lda #<msg_sid
        ldy #>msg_sid
        jsr puts
        lda sid_index
        jsr put_hex
        lda #<msg_primary
        ldy #>msg_primary
        jsr puts

        ldx sid_offset
        lda sid_info + ULTIMATE_SID_INFO_RECORDS + ULTIMATE_SID_PRIMARY_ADDRESS + 1,x
        jsr put_hex
        ldx sid_offset
        lda sid_info + ULTIMATE_SID_INFO_RECORDS + ULTIMATE_SID_PRIMARY_ADDRESS,x
        jsr put_hex

        lda #<msg_type
        ldy #>msg_type
        jsr puts
        ldx sid_offset
        lda sid_info + ULTIMATE_SID_INFO_RECORDS + ULTIMATE_SID_TYPE,x
        jsr put_hex
        jsr newline

        clc
        lda sid_offset
        adc #ULTIMATE_SID_RECORD_SIZE
        sta sid_offset
        jmp next

done:   rts

failed:
        pha
        lda #<msg_failed
        ldy #>msg_failed
        jsr puts
        pla
        jsr put_hex
        jmp newline

puts:
        sta ptr
        sty ptr + 1
        ldy #$00
@next: lda (ptr),y
        beq @done
        jsr CHROUT
        iny
        bne @next
@done: rts

put_hex:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr @nibble
        pla
        and #$0f
@nibble:
        clc
        adc #'0'
        cmp #'9' + 1
        bcc @emit
        adc #6
@emit: jmp CHROUT

newline:
        lda #$0d
        jmp CHROUT

        .rodata

msg_count:   .byte "sid count: $", 0
msg_sid:     .byte "sid $", 0
msg_primary: .byte ": $", 0
msg_type:    .byte " type $", 0
msg_failed:  .byte "sid info failed: $", 0
