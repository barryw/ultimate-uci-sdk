.include "ultimate.inc"

.segment "LOADADDR"
    .word $0801
.segment "STARTUP"
    .word $080b, 10
    .byte $9e, "2304", 0  ; 10 SYS 2304
    .word 0

.code
.export start
start:
    jsr ultimate_turbo_available
    cmp #0
    beq absent
    lda #5                  ; green
    bne paint
absent:
    lda #2                  ; red
paint:
    sta $d020
    rts                     ; return to BASIC
