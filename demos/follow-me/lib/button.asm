/*
    Light a button and play corresponding sound. This will pause once the button
    is lit for a period determined by x and then again once the button is turned
    off by a period determimed by y. The period is in jiffies (1/60sec)

    Requires:
    r2H: A number from 1-4 for the button to light
*/
ButtonWithSound:
    lda ButtonLit
    cmp #$00
    bne !+

    lda r2H
    sta ButtonLit

    jsr PlaySound
    jsr TurnButtonOn
!:
    rts

/*
    This is used when the computer is taking its turn. The button will already be on at this point.
    This routine is used to hold the note for a set period of time, turn the button and sound off
    and then wait another set period of time.

    This is different from how we play the note during the human's turn. When a human is taking their
    turn, we want to keep the button and sound on as long as they're holding down the key.

    Requires:
    r7L: Number of jiffies to keep the button and sound on.
    r7H: Number of jiffies to pause once the button and sound have been turned off.
*/
ButtonHold:
    jsr PauseJiffies
    jsr StopSound
    jsr AllOff
    stb r7H:r7L
    jsr PauseJiffies

    rts

/*
    Turn all buttons off. Also set the sprites to be dark gray
*/
AllOff:
    WriteString($0518, Buttons)
    WriteString($d918, ButtonColors)
    ldx #$04
    lda #vic.DK_GRAY
!:
    sta vic.SPMC1, x
    dex
    bne !-
    stb #$00:ButtonLit

    rts

/*
    Turn on a button. This does not turn the button off. You're responsible for that!

    Requires:
    r2H: A number between 1 and 4 of the button to turn on.
*/
TurnButtonOn:
    ldx r2H
    lda #vic.WHITE
    sta vic.SPMC1, x

    lda r2H

    cmp #$01
    bne !+
    stb #<RED_ADDRESS:r10L
    stb #>RED_ADDRESS:r10H
    stb #vic.LT_RED:r8L
    jmp !++++
!:
    cmp #$02
    bne !+
    stb #<YELLOW_ADDRESS:r10L
    stb #>YELLOW_ADDRESS:r10H
    stb #vic.YELLOW:r8L
    jmp !+++
!:
    cmp #$03
    bne !+
    stb #<GREEN_ADDRESS:r10L
    stb #>GREEN_ADDRESS:r10H
    stb #vic.LT_GREEN:r8L
    jmp !++
!:
    cmp #$04
    bne !+
    stb #<BLUE_ADDRESS:r10L
    stb #>BLUE_ADDRESS:r10H
    stb #vic.LT_BLUE:r8L

!:
    jsr LightButton
    rts

/*
    Draw the button and color it. Each button is 8x8 characters.

    Requires:
    r10: Start screen address of the button to light up
    r8L: The color to light the button
*/
LightButton:
    ldx #$00
    ldy #$00
!:
    lda #$a0
    sta (r10), y

    // Write to color ram
    lda r10L
    sta r9L
    lda r10H
    clc
    adc #$d4
    sta r9H
    lda r8L
    sta (r9), y

    iny
    cpy #$08
    bne !-
    ldy #$00
    clc
    lda r10L
    adc #$28
    sta r10L
    bcc !+
    inc r10H
!:
    inx
    cpx #$08
    bne !--

    rts

ButtonLit:
    .byte $00

