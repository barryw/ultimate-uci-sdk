        .include "ultimate.inc"

        .forceimport __STARTUP__
        .export _main

CHROUT = $FFD2

        .code

_main:  jsr ultimate_init
        cmp #ULTIMATE_OK
        bne failed

        ldx #0
found:  lda msg_found,x
        beq done
        jsr CHROUT
        inx
        bne found

done:   rts

failed: ldx #0
absent: lda msg_absent,x
        beq done
        jsr CHROUT
        inx
        bne absent

        .rodata

msg_found:  .byte "ultimate found", 13, 0
msg_absent: .byte "no ultimate found", 13, 0
