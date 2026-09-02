#importonce

/*
    Generate a random number between 1 and 4

    Returns:
    a - contains random number between 1 and 4
*/
GenerateRandom:
    lda $d41b
    and #$03
    clc
    adc #$01
    rts

InitRandom:
    stb #$ff:sid.FRELO3
    stb #$ff:sid.FREHI3
    stb #$80:sid.VCREG3
    rts

