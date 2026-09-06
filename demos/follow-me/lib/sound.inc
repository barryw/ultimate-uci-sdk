
; Native SDK calls and an application-owned audio voice.
PCM_RATE = 25000
PCM_DIVIDER = 6250000 / PCM_RATE

;
;    Install the Simon palette and copy five tiny square-wave loops into REU.
;    The SID initialization remains as an emulator fallback.
;
InitSound:
    ldx #$18
    lda #$00
local_sound_0:
    sta sid::FRELO1, x
    dex
    bpl local_sound_0
    lda #$0f
    sta sid::SIGVOL
    lda #$22
    sta sid::ATDCY1
    lda #$80
    sta sid::SUREL1

    lda #$00
    sta AudioReady
    lda #$00
    sta PaletteSaved
    lda #$00
    sta PaletteReady
    lda #$00
    sta PaletteResult

    jsr ultimate_init
    cmp #ULTIMATE_OK
    beq local_sound_1
    jmp local_sound_8

local_sound_1:

    jsr PaletteDelay
    lda #$03
    sta PaletteRetries
local_sound_2:
    lda #<SavedPalette
    ldx #>SavedPalette
    jsr ultimate_palette_get
    cmp #ULTIMATE_OK
    beq local_sound_3
    jsr PaletteDelay
    dec PaletteRetries
    bne local_sound_2
    jmp local_sound_4

local_sound_3:
    lda #$01
    sta PaletteSaved

local_sound_4:
    lda #$03
    sta PaletteRetries
local_sound_5:
    lda #<SimonPalette
    ldx #>SimonPalette
    jsr ultimate_palette_set
    sta PaletteResult
    cmp #ULTIMATE_OK
    beq local_sound_6
    jsr PaletteDelay
    dec PaletteRetries
    bne local_sound_5
    jmp local_sound_7

local_sound_6:
    lda #$01
    sta PaletteReady

local_sound_7:
    jsr ultimate_audio_init
    cmp #ULTIMATE_OK
    bne local_sound_8
    jsr ultimate_reu_available
    cmp #$01
    bne local_sound_8

    lda #<ToneBank
    sta ult_addr
    lda #>ToneBank
    sta ult_addr + $01
    lda #$00
    sta ult_reu
    lda #$00
    sta ult_reu + $01
    lda #$00
    sta ult_reu + $02
    lda #$00
    sta ult_reu + $03
    lda #<(ToneBankEnd - ToneBank)
    sta ult_reulen
    lda #>(ToneBankEnd - ToneBank)
    sta ult_reulen + $01
    lda #$00
    sta ult_reulen + $02
    lda #$00
    sta ult_reulen + $03
    jsr ultimate_reu_stash
    cmp #ULTIMATE_OK
    bne local_sound_8
    lda #$01
    sta AudioReady

local_sound_8:
    rts

; The REST runner starts the C64 before every firmware service is ready.
PaletteDelay:
    ldx #$20
local_sound_9:
    ldy #$00
local_sound_10:
    dey
    bne local_sound_10
    dex
    bne local_sound_9
    rts

;
;    A = 0 for the losing buzz or 1-4 for red, yellow, green and blue.
;
PlaySound:
    sta CurrentNote
    lda AudioReady
    bne local_sound_11
    jmp PlaySid

local_sound_11:

    ldx CurrentNote
    lda #$00
    sta Voice + UA_VOICE_CHANNEL
    lda #UA_CTRL_REPEAT
    sta Voice + UA_VOICE_FLAGS
    lda #UA_VOLUME_MAX
    sta Voice + UA_VOICE_VOLUME
    lda #UA_PAN_CENTER
    sta Voice + UA_VOICE_PAN

    lda ToneOffsetsLo, x
    sta Voice + UA_VOICE_REU
    lda ToneOffsetsHi, x
    sta Voice + UA_VOICE_REU + $01
    lda #$00
    sta Voice + UA_VOICE_REU + $02
    lda #$00
    sta Voice + UA_VOICE_REU + $03

    lda ToneLengthsLo, x
    sta Voice + UA_VOICE_LENGTH
    sta Voice + UA_VOICE_REPEAT_B
    lda ToneLengthsHi, x
    sta Voice + UA_VOICE_LENGTH + $01
    sta Voice + UA_VOICE_REPEAT_B + $01
    lda #$00
    sta Voice + UA_VOICE_LENGTH + $02
    lda #$00
    sta Voice + UA_VOICE_LENGTH + $03
    lda #$00
    sta Voice + UA_VOICE_REPEAT_A
    lda #$00
    sta Voice + UA_VOICE_REPEAT_A + $01
    lda #$00
    sta Voice + UA_VOICE_REPEAT_A + $02
    lda #$00
    sta Voice + UA_VOICE_REPEAT_A + $03
    lda #$00
    sta Voice + UA_VOICE_REPEAT_B + $02
    lda #$00
    sta Voice + UA_VOICE_REPEAT_B + $03
    lda #<PCM_DIVIDER
    sta Voice + UA_VOICE_RATE
    lda #>PCM_DIVIDER
    sta Voice + UA_VOICE_RATE + $01

    lda #<Voice
    ldx #>Voice
    jsr ultimate_audio_configure
    cmp #ULTIMATE_OK
    bne local_sound_12
    lda #0
    ldx #UA_CTRL_REPEAT
    jsr ultimate_audio_start
    cmp #ULTIMATE_OK
    bne local_sound_12
    lda #sid::SOUND_PLAYING
    sta SoundPlaying
    rts

local_sound_12:
    lda #$00
    sta AudioReady

PlaySid:
    lda CurrentNote
    tax
    lda Waveforms, x
    sta CurrentWaveform
    txa
    asl a
    tax
    lda Notes, x
    sta sid::FREHI1
    lda Notes + 1, x
    sta sid::FRELO1
    lda CurrentWaveform
    sta sid::VCREG1
    lda #sid::SOUND_PLAYING
    sta SoundPlaying
    rts

StopSound:
    lda SoundPlaying
    cmp #sid::SOUND_PLAYING
    bne local_sound_15
    lda AudioReady
    beq local_sound_13
    lda #0
    jsr ultimate_audio_stop
    jmp local_sound_14

local_sound_13:
    dec CurrentWaveform
    lda CurrentWaveform
    sta sid::VCREG1

local_sound_14:
    lda #$00
    sta SoundPlaying
local_sound_15:
    rts

RestorePalette:
    jsr StopSound
    lda PaletteSaved
    beq local_sound_16
    lda #<SavedPalette
    ldx #>SavedPalette
    jsr ultimate_palette_set
local_sound_16:
    rts

; SID fallback for VICE. PCM uses the measured full-size Simon frequencies.
Notes:
    .byte $08,$61    ; Losing buzz
    .byte $14,$9e    ; Red
    .byte $10,$c3    ; Yellow
    .byte $1b,$9b    ; Green
    .byte $0d,$e7    ; Blue

Waveforms:
    .byte sid::WAVE_NOISE, sid::WAVE_TRIANGLE, sid::WAVE_TRIANGLE, sid::WAVE_TRIANGLE, sid::WAVE_TRIANGLE

ToneOffsetsLo:
    .byte <(ToneFail - ToneBank), <(ToneRed - ToneBank), <(ToneYellow - ToneBank), <(ToneGreen - ToneBank), <(ToneBlue - ToneBank)
ToneOffsetsHi:
    .byte >(ToneFail - ToneBank), >(ToneRed - ToneBank), >(ToneYellow - ToneBank), >(ToneGreen - ToneBank), >(ToneBlue - ToneBank)
ToneLengthsLo:
    .byte <(ToneRed - ToneFail), <(ToneYellow - ToneRed), <(ToneGreen - ToneYellow), <(ToneBlue - ToneGreen), <(ToneBankEnd - ToneBlue)
ToneLengthsHi:
    .byte >(ToneRed - ToneFail), >(ToneYellow - ToneRed), >(ToneGreen - ToneYellow), >(ToneBlue - ToneGreen), >(ToneBankEnd - ToneBlue)

; Signed 8-bit square waves at 25 kHz: 42, 312.5, 250, 416.7 and 208.3 Hz.
ToneBank:
ToneFail:
    .repeat 596, i
        .if i < 298
            .byte $48
        .else
            .byte $b8
        .endif
    .endrepeat
ToneRed:
    .repeat 80, i
        .if i < 40
            .byte $48
        .else
            .byte $b8
        .endif
    .endrepeat
ToneYellow:
    .repeat 100, i
        .if i < 50
            .byte $48
        .else
            .byte $b8
        .endif
    .endrepeat
ToneGreen:
    .repeat 60, i
        .if i < 30
            .byte $48
        .else
            .byte $b8
        .endif
    .endrepeat
ToneBlue:
    .repeat 120, i
        .if i < 60
            .byte $48
        .else
            .byte $b8
        .endif
    .endrepeat
ToneBankEnd:

; Palette entries 2/8/5/6 are unlit lenses; 10/7/13/14 are their glow.
SimonPalette:
    .byte   2,  3,  3, 232,226,210,  72,  8, 14,  86, 54, 66
    .byte  55, 32, 70,   8, 56, 26,   7, 24, 62, 255,216, 45
    .byte  96, 88,  8,  39, 20, 10, 255, 42, 58,  28, 29, 28
    .byte  70, 68, 63,  46,255,112,  54,126,255, 142,138,126

SavedPalette:
    .repeat UCI_PALETTE_BYTES, i
        .byte $00
    .endrepeat

CurrentNote:
    .byte $00
CurrentWaveform:
    .byte $00
SoundPlaying:
    .byte $00
AudioReady:
    .byte $00
PaletteSaved:
    .byte $00
PaletteReady:
    .byte $00
PaletteResult:
    .byte $00
PaletteRetries:
    .byte $00

Voice:
    .repeat UA_VOICE_SIZE, i
        .byte 0
    .endrepeat
