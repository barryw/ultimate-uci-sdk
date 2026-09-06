;
;    Light a button and play corresponding sound. This will pause once the button
;    is lit for a period determined by x and then again once the button is turned
;    off by a period determimed by y. The period is in jiffies (1/60sec)
;
;    Requires:
;    r2H: A number from 1-4 for the button to light
;
ButtonWithSound:
    lda ButtonLit
    cmp #$00
    bne local_button_0

    lda r2H
    sta ButtonLit

    jsr PlaySound
    jsr TurnButtonOn
local_button_0:
    rts

;
;    This is used when the computer is taking its turn. The button will already be on at this point.
;    This routine is used to hold the note for a set period of time, turn the button and sound off
;    and then wait another set period of time.
;
;    This is different from how we play the note during the human's turn. When a human is taking their
;    turn, we want to keep the button and sound on as long as they're holding down the key.
;
;    Requires:
;    r7L: Number of jiffies to keep the button and sound on.
;    r7H: Number of jiffies to pause once the button and sound have been turned off.
;
ButtonHold:
    jsr PauseJiffies
    jsr StopSound
    jsr AllOff
    lda r7H
    sta r7L
    jsr PauseJiffies

    rts

;
;    Turn all buttons off. Also set the sprites to be dark gray
;
AllOff:
    M_WriteString $0518, Buttons
    M_WriteString $d918, ButtonColors
    ldx #$04
    lda #vic::DK_GRAY
local_button_1:
    sta vic::SPMC1, x
    dex
    bne local_button_1
    lda #$00
    sta ButtonLit

    rts

;
;    Turn on a button. This does not turn the button off. You're responsible for that!
;
;    Requires:
;    r2H: A number between 1 and 4 of the button to turn on.
;
TurnButtonOn:
    ldx r2H
    lda #vic::WHITE
    sta vic::SPMC1, x

    lda r2H

    cmp #$01
    bne local_button_2
    lda #<RED_ADDRESS
    sta r10L
    lda #>RED_ADDRESS
    sta r10H
    lda #vic::LT_RED
    sta r8L
    jmp local_button_5
local_button_2:
    cmp #$02
    bne local_button_3
    lda #<YELLOW_ADDRESS
    sta r10L
    lda #>YELLOW_ADDRESS
    sta r10H
    lda #vic::YELLOW
    sta r8L
    jmp local_button_5
local_button_3:
    cmp #$03
    bne local_button_4
    lda #<GREEN_ADDRESS
    sta r10L
    lda #>GREEN_ADDRESS
    sta r10H
    lda #vic::LT_GREEN
    sta r8L
    jmp local_button_5
local_button_4:
    cmp #$04
    bne local_button_5
    lda #<BLUE_ADDRESS
    sta r10L
    lda #>BLUE_ADDRESS
    sta r10H
    lda #vic::LT_BLUE
    sta r8L

local_button_5:
    jsr LightButton
    rts

;
;    Draw the button and color it. Each button is 8x8 characters.
;
;    Requires:
;    r10: Start screen address of the button to light up
;    r8L: The color to light the button
;
LightButton:
    ldx #$00
    ldy #$00
local_button_6:
    lda #$a0
    sta (r10), y

    ; Write to color ram
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
    bne local_button_6
    ldy #$00
    clc
    lda r10L
    adc #$28
    sta r10L
    bcc local_button_7
    inc r10H
local_button_7:
    inx
    cpx #$08
    bne local_button_6

    rts

ButtonLit:
    .byte $00
