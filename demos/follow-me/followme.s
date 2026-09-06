;
;
;Follow Me
;
;Commodore 64
;
;Inspired by this series: https://www.youtube.com/watch?v=A7vYSsLS00Y&ab_channel=MyDeveloperThoughts
;
;

.include "ultimate.inc"
.segment "LIBCODE"
.include "lib/all.inc"

SPRITES = .lobyte(Sprites / $40)
.assert Sprites < $4000, lderror, "sprite data must remain in VIC bank 0"
TITLE_LOCATION = SCREEN_START + $36
MESSAGE_LOCATION = SCREEN_START + ($28 * $14)

SCORE_ONES = SPRITE_POINTERS + $07
SCORE_TENS = SPRITE_POINTERS + $06
SCORE_HUNDREDS = SPRITE_POINTERS + $05
SCORE_THOUSANDS = SPRITE_POINTERS + $04

MAX_PATTERN = 31
INPUT_TIMEOUT = TIMER_THREE_SECONDS
.export INPUT_TIMEOUT

.segment "LOADADDR"
.word $0801
.segment "STARTUP"
.word $080b, 10
.byte $9e, "2304", 0
.word 0
.segment "MAIN"

Main:
    jsr InitSound
    jsr InitRandom
    jsr ClearTimers
    jsr SetupTimers
    jsr SetupScreen
    jsr SetupSprites
    jsr SetupInterrupt
    lda #GAME_MODE_ATTRACT
    sta GameMode
    jmp GameLoop

;
;    The interrupt runs 60 times a second and is responsible mostly for maintaining timers.
;    For more information, look at the lib/timers.inc file. This bit of code can be used
;    to run continuous or one-off items.
;
SetupInterrupt:
    sei

    lda #LOWER7
    sta vic::CIAICR
    sta vic::CI2ICR

    lda vic::CIAICR
    lda vic::CI2ICR

    lda #$01
    sta vic::VICIRQ
    sta vic::IRQMSK

    lda #$00
    sta vic::RASTER
    lda #$1b
    sta vic::SCROLY
    lda #$35
    sta $01

    M_StoreWord IRQ_VECTOR, Irq

    cli
    rts

;
;    Configure the 4 sprites that we use to indicate which key to press for each
;    button. Each sprite is multicolor with a drop shadow.
;
SetupSprites:
    lda #vic::BLACK
    sta vic::SPMC1
    lda #vic::DK_GRAY
    sta vic::SP0COL
    sta vic::SP1COL
    sta vic::SP2COL
    sta vic::SP3COL

    lda #vic::WHITE
    sta vic::SP4COL
    sta vic::SP5COL
    sta vic::SP6COL
    sta vic::SP7COL

    ; These are the sprites on the buttons
    lda #SPRITES+$01
    sta SPRITE_POINTERS
    lda #SPRITES+$02
    sta SPRITE_POINTERS + $01
    lda #SPRITES+$03
    sta SPRITE_POINTERS + $02
    lda #SPRITES+$04
    sta SPRITE_POINTERS + $03

    ; These are the sprites for the score
    lda #SPRITES+$00
    sta SPRITE_POINTERS + $04
    sta SPRITE_POINTERS + $05
    sta SPRITE_POINTERS + $06
    sta SPRITE_POINTERS + $07

    lda #%11110000 ; Disable sprites 0 - 3, but enable the score sprites
    sta vic::SPENA
    lda #%11111111 ; Enable multicolor sprites for 0 - 7
    sta vic::SPMC

    lda #135
    sta vic::SP0Y
    sta vic::SP1Y
    sta vic::SP2Y
    sta vic::SP3Y

    lda #80
    sta vic::SP4Y
    sta vic::SP5Y
    sta vic::SP6Y
    sta vic::SP7Y

    lda #132
    sta vic::SP4X
    lda #158
    sta vic::SP5X
    lda #184
    sta vic::SP6X
    lda #210
    sta vic::SP7X

    lda #52
    sta vic::SP0X
    lda #132
    sta vic::SP1X
    lda #212
    sta vic::SP2X

    lda #%00001000 ; Need to set MSB for sprite 3
    sta vic::MSIGX
    lda #35
    sta vic::SP3X

    rts

SetupTimers:
    M_CreateTimer 3, ENABLE, TIMER_CONTINUOUS, 30, FlashButtons

    rts

Irq:
    M_PushStack

    jsr UpdateTimers
    inc Clock
    bne local_main_0
    inc Clock + $01

local_main_0:
    lda #$ff
    sta vic::VICIRQ

    M_PopStack

    rti

SetupScreen:
    lda #vic::BLACK
    sta vic::EXTCOL
    sta vic::BGCOL0

    M_ClearScreen SCREEN_START, $20
    M_ClearColorRam vic::WHITE

    M_WriteString TITLE_LOCATION, TitleScreen
    M_WriteString TITLE_LOCATION + $d400, TitleScreenColor

    jsr AllOff

    rts

GameLoop:
    jsr UpdateScore
local_main_1:
    lda GameMode
    cmp #GAME_MODE_ATTRACT
    bne CheckComputer

    jsr Attract

    jmp local_main_1

CheckComputer:
    cmp #GAME_MODE_COMPUTER                 ; Is it the computer's turn?
    bne CheckHuman

    jsr ClearLine
    M_WriteString MESSAGE_LOCATION + $06, MyTurn
    M_WriteString MESSAGE_LOCATION + $d400 + $06, MyTurnColor

    lda #$40 ; Wait a second
    sta r7L
    jsr PauseJiffies

    lda #$00
    sta r8H
ComputerPatternLoop:
    ldx r8H
    cpx PatternLength
    beq ComputerAddMove
    lda GamePattern, x                      ; Get the current note
    sta r2H
    lda GameSpeed
    sta r7L
    lda #$05
    sta r7H
    jsr ButtonWithSound
    jsr ButtonHold
    inc r8H

    jmp ComputerPatternLoop

ComputerAddMove:
    jsr GenerateRandom                      ; Generate a new note and tack it onto the end of the pattern
    ldx PatternLength
    sta GamePattern, x
    inc PatternLength
    sta r2H
    lda GameSpeed
    sta r7L
    lda #$05
    sta r7H
    jsr ButtonWithSound
    jsr ButtonHold

    lda #GAME_MODE_HUMAN ; Pass over to the human to recreate
    sta GameMode

    jmp GameLoop

CheckHuman:
    cmp #GAME_MODE_HUMAN                    ; Is it the human's turn?
    beq local_main_2
    jmp CheckFail

local_main_2:
    jsr ClearLine
    M_WriteString MESSAGE_LOCATION + $02, YourTurn
    M_WriteString MESSAGE_LOCATION + $d400 + $02, YourTurnColor

    lda #$00
    sta r8H
HumanPatternLoop:
    ldx r8H
    cpx PatternLength
    bne HumanWaitForMove

    cpx #MAX_PATTERN
    bne HumanPatternComplete
    lda #GAME_MODE_WIN
    sta GameMode
    jmp GameLoop

HumanPatternComplete:
    lda #GAME_MODE_COMPUTER ; Computer's turn again
    sta GameMode
    jmp GameLoop

HumanWaitForMove:
    lda GamePattern, x                      ; Grab the move in the pattern so that we can make sure the human plays the same note
    sta r12L
    lda Clock
    sta InputStartedAt

HumanWaitForKey:
    jsr Keyboard
    bcc HumanGotKey

HumanCheckTimeout:
    lda Clock
    sec
    sbc InputStartedAt
    cmp #INPUT_TIMEOUT
    bcc HumanWaitForKey

    lda #GAME_MODE_FAIL
    sta GameMode
    jmp GameLoop

HumanGotKey:
    cmp #$ff
    beq HumanCheckTimeout
    sec
    sbc #$31
    cmp #$04
    bcs HumanCheckTimeout
    clc
    adc #$01

    cmp r12L                                ; Is this the right note?

    beq HumanCorrectMove
    lda #GAME_MODE_FAIL ; Wrong note. FAILED!
    sta GameMode
    jmp GameLoop

HumanCorrectMove:
    sta r2H
    jsr ButtonWithSound

    sed
    lda Score + $01
    clc
    adc #$10                                ; Add 10 points
    sta Score + $01
    bcc HumanScoreUpdated
    lda Score
    clc
    adc #$01
    sta Score

HumanScoreUpdated:
    cld
    jsr WaitForKeyRelease                   ; A held button has no time limit

    jsr AllOff
    jsr StopSound
    inc r8H

    jmp HumanPatternLoop

CheckFail:
    cmp #GAME_MODE_FAIL
    bne CheckGameOver

    lda r12L
    sta r2H
    jsr TurnButtonOn
    lda #$00
    jsr PlaySound
    lda #$5a ; Original Simon losing tone: 1.5 seconds
    sta r7L
    jsr PauseJiffies
    jsr StopSound
    jsr AllOff

    lda #GAME_MODE_GAME_OVER
    sta GameMode
    jmp GameLoop

CheckGameOver:
    cmp #GAME_MODE_GAME_OVER
    bne CheckWin

    jsr ClearLine
    M_WriteString MESSAGE_LOCATION + $09, GameOver
    M_WriteString MESSAGE_LOCATION + $d400 + $09, GameOverColor
    jmp WaitForReplayChoice

CheckWin:
    cmp #GAME_MODE_WIN
    beq ShowWin
    jmp GameLoop

ShowWin:
    jsr ClearLine
    M_WriteString MESSAGE_LOCATION + $08, YouWin
    M_WriteString MESSAGE_LOCATION + $d400 + $08, GameOverColor

WaitForReplayChoice:
    jsr WaitForKeyRelease
WaitForReplayKey:
    jsr Keyboard
    bcs WaitForReplayKey
    cmp #$ff
    beq WaitForReplayKey

    cmp #$19
    beq RestartAttract
    cmp #$0e
    bne WaitForReplayKey

    jsr ClearLine
    M_WriteString MESSAGE_LOCATION + $06, SeeYa
    M_WriteString MESSAGE_LOCATION + $d400 + $06, SeeYaColor

    jsr RestorePalette
    lda #$37 ; Turn the kernal back on and reset the machine
    sta $01
    jmp (kernal::VEC_RESET)

RestartAttract:
    lda #GAME_MODE_ATTRACT
    sta GameMode
    lda #%11110000
    sta vic::SPENA
    M_EnableTimer $03
    jsr AllOff

    jmp GameLoop

WaitForKeyRelease:
    jsr Keyboard
    bcc WaitForKeyRelease
    cmp #$01
    bne WaitForKeyRelease
    rts

Attract:
    jsr ClearLine
    M_WriteString MESSAGE_LOCATION + $03, StartMessage
local_main_3:
    jsr Keyboard
    bcs local_main_3

    sec
    sbc #$31
    cmp #$05
    bcs local_main_3

    clc
    adc #$03                                ; Calculate game speed from level

    asl a
    asl a
    sta GameSpeed

    lda #$00
    sta PatternLength
    sta Score
    sta Score + $01
    jsr UpdateScore

    lda #GAME_MODE_COMPUTER ; Key was pressed. Make it the computer's turn
    sta GameMode
    lda #%11111111 ; Enable sprites 0 - 7
    sta vic::SPENA
    jsr AllOff
    M_DisableTimer $03
    ldx #TitleScreen - StartMessage
    lda #$20

local_main_4:
    sta MESSAGE_LOCATION, x
    dex
    bne local_main_4
    jmp local_main_6

local_main_5:
    rts

;
;    Flash the buttons randomly in attract mode
;
FlashButtons:
    jsr AllOff
    jsr GenerateRandom
    sta r2H
    jsr TurnButtonOn
local_main_6:
    rts

;
;    Update the score sprites. Score is stored as 2 BCD bytes.
;    One for thousands and hundreds and one for tens and ones
;
UpdateScore:
    ; Ones
    lda Score + $01
    and #$0f
    clc
    adc #SPRITES
    sta SCORE_ONES

    ; Tens
    lda Score + $01
    and #$f0
    lsr a
    lsr a
    lsr a
    lsr a
    clc
    adc #SPRITES
    sta SCORE_TENS

    ; Hundreds
    lda Score
    and #$0f
    clc
    adc #SPRITES
    sta SCORE_HUNDREDS

    ; Thousands
    lda Score
    and #$f0
    lsr a
    lsr a
    lsr a
    lsr a
    clc
    adc #SPRITES
    sta SCORE_THOUSANDS

    rts

;
;    Write bytes to a location in memory. This can be used for characters as well as colors
;
;    Requires:
;    r6: Address of null terminated data to write
;    r5: Start address to write data
;
WriteString:
    ldy #$00
local_main_7:
    lda (r6), y
    beq local_main_9
    sta (r5), y
    iny
    bne local_main_8
    inc r6H
    inc r5H
local_main_8:
    jmp local_main_7
local_main_9:
    rts

;
;    Clear the message line on the screen
;
ClearLine:
    ldy #$00
    lda #$20
local_main_10:
    sta MESSAGE_LOCATION, y
    iny
    cpy #$28
    bne local_main_10
    rts

AnimateTitle:
    ldx #$00
    ldy CurrentTitleColor
local_main_11:
    lda TitleScreenColor, y
    sta TITLE_LOCATION + $d400, x
    inx
    iny
    cpx #$0c
    bne local_main_11
    inc CurrentTitleColor
    lda CurrentTitleColor
    cmp #$0c
    bne local_main_12
    lda #$00
    sta CurrentTitleColor
local_main_12:
    rts

    .align $40
Sprites:
    ; 0
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $29,$00,$00,$aa,$40,$02,$82,$90
    .byte $02,$82,$90,$02,$82,$90,$02,$8a
    .byte $90,$02,$a2,$90,$02,$82,$90,$02
    .byte $82,$90,$02,$82,$90,$00,$aa,$40
    .byte $00,$29,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$81

    ; 1
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $29,$00,$00,$29,$00,$00,$a9,$00
    .byte $02,$a9,$00,$00,$29,$00,$00,$29
    .byte $00,$00,$29,$00,$00,$29,$00,$00
    .byte $29,$00,$00,$29,$00,$02,$aa,$90
    .byte $02,$aa,$90,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$81

    ; 2
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $29,$00,$00,$aa,$40,$02,$92,$90
    .byte $02,$92,$90,$00,$02,$90,$00,$0a
    .byte $40,$00,$29,$00,$00,$a4,$00,$02
    .byte $90,$00,$02,$90,$00,$02,$aa,$90
    .byte $02,$aa,$90,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$81

    ; 3
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $29,$00,$00,$aa,$40,$02,$92,$90
    .byte $00,$02,$90,$00,$02,$90,$00,$2a
    .byte $40,$00,$2a,$40,$00,$02,$90,$00
    .byte $02,$90,$02,$92,$90,$00,$aa,$40
    .byte $00,$29,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$81

    ; 4
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$02
    .byte $92,$90,$02,$92,$90,$02,$92,$90
    .byte $02,$92,$90,$02,$92,$90,$02,$aa
    .byte $90,$02,$aa,$90,$00,$02,$90,$00
    .byte $02,$90,$00,$02,$90,$00,$02,$90
    .byte $00,$02,$90,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$81

    ; 5
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$02
    .byte $aa,$90,$02,$92,$90,$02,$90,$00
    .byte $02,$90,$00,$02,$90,$00,$02,$aa
    .byte $40,$00,$aa,$90,$00,$02,$90,$00
    .byte $02,$90,$02,$92,$90,$02,$9a,$40
    .byte $00,$a9,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$81

    ; 6
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $0a,$90,$00,$2a,$90,$00,$a4,$00
    .byte $02,$90,$00,$02,$99,$00,$02,$aa
    .byte $90,$02,$a6,$90,$02,$92,$90,$02
    .byte $92,$90,$02,$92,$90,$02,$92,$90
    .byte $00,$aa,$40,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$81

    ; 7
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $aa,$a4,$00,$00,$a4,$00,$00,$a4
    .byte $00,$02,$90,$00,$02,$90,$00,$0a
    .byte $40,$00,$0a,$40,$00,$29,$00,$00
    .byte $29,$00,$00,$29,$00,$00,$29,$00
    .byte $00,$29,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$81

    ; 8
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $29,$00,$00,$aa,$40,$02,$92,$90
    .byte $02,$92,$90,$02,$92,$90,$00,$aa
    .byte $40,$02,$92,$90,$02,$92,$90,$02
    .byte $92,$90,$02,$92,$90,$00,$aa,$40
    .byte $00,$29,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$81

    ; 9
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00
    .byte $aa,$40,$02,$92,$90,$02,$92,$90
    .byte $02,$92,$90,$02,$92,$90,$02,$9a
    .byte $90,$02,$aa,$90,$00,$26,$90,$00
    .byte $02,$90,$00,$0a,$40,$02,$a9,$00
    .byte $02,$a4,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$81

StartMessage:

    .byte 19, 5, 12, 5, 3, 20, 32, 12, 5, 22, 5, 12, 58, 32, 49, 32, 40, 6, 1, 19, 20, 41, 32, 45, 32, 53, 32, 40, 19, 12, 15, 23, 41
    .byte $00

TitleScreen:

    .byte 6, 15, 12, 12, 15, 23, 32, 13, 5, 32, 16, 3, 13
    .byte $00

MyTurn:

    .byte 23, 1, 20, 3, 8, 32, 1, 14, 4, 32, 12, 9, 19, 20, 5, 14, 32, 3, 1, 18, 5, 6, 21, 12, 12, 25, 33
    .byte $00

MyTurnColor:
    .byte vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE
    .byte vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE
    .byte vic::WHITE, vic::WHITE, vic::WHITE
    .byte $00

YourTurn:

    .byte 25, 15, 21, 18, 32, 20, 21, 18, 14, 33, 32, 19, 8, 15, 23, 32, 13, 5, 32, 23, 8, 1, 20, 32, 25, 1, 32, 7, 15, 20, 44, 32, 11, 9, 4, 33
    .byte $00

YourTurnColor:
    .byte vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE
    .byte vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE
    .byte vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE
    .byte $00

GameOver:

    .byte 7, 1, 13, 5, 32, 15, 22, 5, 18, 46, 32, 16, 12, 1, 25, 32, 1, 7, 1, 9, 14, 63, 32, 25, 47, 14
    .byte $00

GameOverColor:
    .byte vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE
    .byte vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE
    .byte $00

YouWin:

    .byte 25, 15, 21, 32, 23, 9, 14, 33, 32, 16, 12, 1, 25, 32, 1, 7, 1, 9, 14, 63, 32, 25, 47, 14
    .byte $00

SeeYa:

    .byte 20, 8, 1, 14, 11, 19, 32, 6, 15, 18, 32, 16, 12, 1, 25, 9, 14, 7, 33, 32, 19, 5, 5, 32, 25, 1, 33
    .byte $00

SeeYaColor:
    .byte vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE
    .byte vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE, vic::WHITE
    .byte vic::WHITE, vic::WHITE, vic::WHITE
    .byte $00


TitleScreenColor:
    .repeat 13, i
        .byte vic::WHITE
    .endrepeat
    .byte $00

StartMessageColors:
    .byte $00, $0b, $0c, $0f, $01, $0f, $0c, $0b

Buttons:
    .byte $55, $43, $43, $43, $43, $43, $43, $43, $43, $49, $55, $43, $43, $43, $43, $43, $43, $43, $43, $49, $55, $43, $43, $43, $43, $43, $43, $43, $43, $49, $55, $43, $43, $43, $43, $43, $43, $43, $43, $49
    .byte $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d
    .byte $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d
    .byte $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d
    .byte $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d
    .byte $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d
    .byte $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d
    .byte $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d
    .byte $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d
    .byte $4a, $43, $43, $43, $43, $43, $43, $43, $43, $4b, $4a, $43, $43, $43, $43, $43, $43, $43, $43, $4b, $4a, $43, $43, $43, $43, $43, $43, $43, $43, $4b, $4a, $43, $43, $43, $43, $43, $43, $43, $43, $4b
    .byte $00

ButtonColors:
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $01, $02, $02, $02, $02, $02, $02, $02, $02, $01, $01, $08, $08, $08, $08, $08, $08, $08, $08, $01, $01, $05, $05, $05, $05, $05, $05, $05, $05, $01, $01, $06, $06, $06, $06, $06, $06, $06, $06, $01
    .byte $01, $02, $02, $02, $02, $02, $02, $02, $02, $01, $01, $08, $08, $08, $08, $08, $08, $08, $08, $01, $01, $05, $05, $05, $05, $05, $05, $05, $05, $01, $01, $06, $06, $06, $06, $06, $06, $06, $06, $01
    .byte $01, $02, $02, $02, $02, $02, $02, $02, $02, $01, $01, $08, $08, $08, $08, $08, $08, $08, $08, $01, $01, $05, $05, $05, $05, $05, $05, $05, $05, $01, $01, $06, $06, $06, $06, $06, $06, $06, $06, $01
    .byte $01, $02, $02, $02, $02, $02, $02, $02, $02, $01, $01, $08, $08, $08, $08, $08, $08, $08, $08, $01, $01, $05, $05, $05, $05, $05, $05, $05, $05, $01, $01, $06, $06, $06, $06, $06, $06, $06, $06, $01
    .byte $01, $02, $02, $02, $02, $02, $02, $02, $02, $01, $01, $08, $08, $08, $08, $08, $08, $08, $08, $01, $01, $05, $05, $05, $05, $05, $05, $05, $05, $01, $01, $06, $06, $06, $06, $06, $06, $06, $06, $01
    .byte $01, $02, $02, $02, $02, $02, $02, $02, $02, $01, $01, $08, $08, $08, $08, $08, $08, $08, $08, $01, $01, $05, $05, $05, $05, $05, $05, $05, $05, $01, $01, $06, $06, $06, $06, $06, $06, $06, $06, $01
    .byte $01, $02, $02, $02, $02, $02, $02, $02, $02, $01, $01, $08, $08, $08, $08, $08, $08, $08, $08, $01, $01, $05, $05, $05, $05, $05, $05, $05, $05, $01, $01, $06, $06, $06, $06, $06, $06, $06, $06, $01
    .byte $01, $02, $02, $02, $02, $02, $02, $02, $02, $01, $01, $08, $08, $08, $08, $08, $08, $08, $08, $01, $01, $05, $05, $05, $05, $05, $05, $05, $05, $01, $01, $06, $06, $06, $06, $06, $06, $06, $06, $01
    .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
    .byte $00

CurrentStartMessageColor:
    .byte $00

CurrentTitleColor:
    .byte $00

GameMode:
    .byte $00

Clock:
    .word $0000

Score:
    .word $0000

GameSpeed:
    .byte $00

; The original Simon game tops out at 31 moves.
GamePattern:
    .repeat MAX_PATTERN, i
        .byte $00
    .endrepeat

PatternLength:
    .byte $00

InputStartedAt:
    .byte $00
