
;
;    Generate a random number between 1 and 4
;
;    Returns:
;    a - contains random number between 1 and 4
;
GenerateRandom:
    lda $d41b
    and #$03
    clc
    adc #$01
    rts

InitRandom:
    lda #$ff
    sta sid::FRELO3
    lda #$ff
    sta sid::FREHI3
    lda #$80
    sta sid::VCREG3
    rts
