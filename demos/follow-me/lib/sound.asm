#importonce

// Stable entry points and parameter locations in the SDK blob at $7000.
.label ULTIMATE_INIT       = $701c
.label PALETTE_GET         = $7037
.label PALETTE_SET         = $703a
.label REU_AVAILABLE       = $7076
.label REU_STASH           = $7079
.label AUDIO_INIT          = $72e8
.label AUDIO_CONFIGURE     = $72f1
.label AUDIO_START         = $72f4
.label AUDIO_STOP          = $72f7
.label BP_ADDR             = $7103
.label BP_REU              = $7256
.label BP_REULEN           = $725a
.label BP_AUDIO            = $719a

.label ULTIMATE_OK         = uci.ULTIMATE_OK
.label UA_CTRL_REPEAT      = uci.UA_CTRL_REPEAT
.label UA_VOLUME_MAX       = uci.UA_VOLUME_MAX
.label UA_PAN_CENTER       = uci.UA_PAN_CENTER
.label UA_VOICE_CHANNEL    = uci.UA_VOICE_CHANNEL
.label UA_VOICE_FLAGS      = uci.UA_VOICE_FLAGS
.label UA_VOICE_VOLUME     = uci.UA_VOICE_VOLUME
.label UA_VOICE_PAN        = uci.UA_VOICE_PAN
.label UA_VOICE_REU        = uci.UA_VOICE_REU
.label UA_VOICE_LENGTH     = uci.UA_VOICE_LENGTH
.label UA_VOICE_REPEAT_A   = uci.UA_VOICE_REPEAT_A
.label UA_VOICE_REPEAT_B   = uci.UA_VOICE_REPEAT_B
.label UA_VOICE_RATE       = uci.UA_VOICE_RATE
.label UCI_PALETTE_BYTES   = uci.UCI_PALETTE_BYTES

.const PCM_RATE = 25000
.const PCM_DIVIDER = 6250000 / PCM_RATE

/*
    Install the Simon palette and copy five tiny square-wave loops into REU.
    The SID initialization remains as an emulator fallback.
*/
InitSound:
    ldx #$18
    lda #$00
!:
    sta sid.FRELO1, x
    dex
    bpl !-
    stb #$0f:sid.SIGVOL
    stb #$22:sid.ATDCY1
    stb #$80:sid.SUREL1

    stb #$00:AudioReady
    stb #$00:PaletteSaved
    stb #$00:PaletteReady
    stb #$00:PaletteResult

    jsr ULTIMATE_INIT
    cmp #ULTIMATE_OK
    beq !ultimate+
    jmp !done+

!ultimate:

    jsr PaletteDelay
    stb #$03:PaletteRetries
!save:
    lda #<SavedPalette
    ldx #>SavedPalette
    jsr PALETTE_GET
    cmp #ULTIMATE_OK
    beq !saved+
    jsr PaletteDelay
    dec PaletteRetries
    bne !save-
    jmp !palette+

!saved:
    stb #$01:PaletteSaved

!palette:
    stb #$03:PaletteRetries
!set:
    lda #<SimonPalette
    ldx #>SimonPalette
    jsr PALETTE_SET
    sta PaletteResult
    cmp #ULTIMATE_OK
    beq !set_ok+
    jsr PaletteDelay
    dec PaletteRetries
    bne !set-
    jmp !audio+

!set_ok:
    stb #$01:PaletteReady

!audio:
    jsr AUDIO_INIT
    cmp #ULTIMATE_OK
    bne !done+
    jsr REU_AVAILABLE
    cmp #$01
    bne !done+

    stb #<ToneBank:BP_ADDR
    stb #>ToneBank:BP_ADDR + $01
    stb #$00:BP_REU
    stb #$00:BP_REU + $01
    stb #$00:BP_REU + $02
    stb #$00:BP_REU + $03
    stb #<(ToneBankEnd - ToneBank):BP_REULEN
    stb #>(ToneBankEnd - ToneBank):BP_REULEN + $01
    stb #$00:BP_REULEN + $02
    stb #$00:BP_REULEN + $03
    jsr REU_STASH
    cmp #ULTIMATE_OK
    bne !done+
    stb #$01:AudioReady

!done:
    rts

// The REST runner starts the C64 before every firmware service is ready.
PaletteDelay:
    ldx #$20
!outer:
    ldy #$00
!inner:
    dey
    bne !inner-
    dex
    bne !outer-
    rts

/*
    A = 0 for the losing buzz or 1-4 for red, yellow, green and blue.
*/
PlaySound:
    sta CurrentNote
    lda AudioReady
    bne !pcm+
    jmp PlaySid

!pcm:

    ldx CurrentNote
    stb #$00:BP_AUDIO + UA_VOICE_CHANNEL
    stb #UA_CTRL_REPEAT:BP_AUDIO + UA_VOICE_FLAGS
    stb #UA_VOLUME_MAX:BP_AUDIO + UA_VOICE_VOLUME
    stb #UA_PAN_CENTER:BP_AUDIO + UA_VOICE_PAN

    lda ToneOffsetsLo, x
    sta BP_AUDIO + UA_VOICE_REU
    lda ToneOffsetsHi, x
    sta BP_AUDIO + UA_VOICE_REU + $01
    stb #$00:BP_AUDIO + UA_VOICE_REU + $02
    stb #$00:BP_AUDIO + UA_VOICE_REU + $03

    lda ToneLengthsLo, x
    sta BP_AUDIO + UA_VOICE_LENGTH
    sta BP_AUDIO + UA_VOICE_REPEAT_B
    lda ToneLengthsHi, x
    sta BP_AUDIO + UA_VOICE_LENGTH + $01
    sta BP_AUDIO + UA_VOICE_REPEAT_B + $01
    stb #$00:BP_AUDIO + UA_VOICE_LENGTH + $02
    stb #$00:BP_AUDIO + UA_VOICE_LENGTH + $03
    stb #$00:BP_AUDIO + UA_VOICE_REPEAT_A
    stb #$00:BP_AUDIO + UA_VOICE_REPEAT_A + $01
    stb #$00:BP_AUDIO + UA_VOICE_REPEAT_A + $02
    stb #$00:BP_AUDIO + UA_VOICE_REPEAT_A + $03
    stb #$00:BP_AUDIO + UA_VOICE_REPEAT_B + $02
    stb #$00:BP_AUDIO + UA_VOICE_REPEAT_B + $03
    stb #<PCM_DIVIDER:BP_AUDIO + UA_VOICE_RATE
    stb #>PCM_DIVIDER:BP_AUDIO + UA_VOICE_RATE + $01

    jsr AUDIO_CONFIGURE
    cmp #ULTIMATE_OK
    bne !fallback+
    jsr AUDIO_START
    cmp #ULTIMATE_OK
    bne !fallback+
    stb #sid.SOUND_PLAYING:SoundPlaying
    rts

!fallback:
    stb #$00:AudioReady

PlaySid:
    lda CurrentNote
    tax
    lda Waveforms, x
    sta CurrentWaveform
    txa
    asl
    tax
    lda Notes, x
    sta sid.FREHI1
    lda Notes + 1, x
    sta sid.FRELO1
    lda CurrentWaveform
    sta sid.VCREG1
    stb #sid.SOUND_PLAYING:SoundPlaying
    rts

StopSound:
    lda SoundPlaying
    cmp #sid.SOUND_PLAYING
    bne !done+
    lda AudioReady
    beq !sid+
    jsr AUDIO_STOP
    jmp !clear+

!sid:
    dec CurrentWaveform
    lda CurrentWaveform
    sta sid.VCREG1

!clear:
    stb #$00:SoundPlaying
!done:
    rts

RestorePalette:
    jsr StopSound
    lda PaletteSaved
    beq !done+
    lda #<SavedPalette
    ldx #>SavedPalette
    jsr PALETTE_SET
!done:
    rts

// SID fallback for VICE. PCM uses the measured full-size Simon frequencies.
Notes:
    .byte $08,$61    // Losing buzz
    .byte $14,$9e    // Red
    .byte $10,$c3    // Yellow
    .byte $1b,$9b    // Green
    .byte $0d,$e7    // Blue

Waveforms:
    .byte sid.WAVE_NOISE, sid.WAVE_TRIANGLE, sid.WAVE_TRIANGLE, sid.WAVE_TRIANGLE, sid.WAVE_TRIANGLE

ToneOffsetsLo:
    .byte <(ToneFail - ToneBank), <(ToneRed - ToneBank), <(ToneYellow - ToneBank), <(ToneGreen - ToneBank), <(ToneBlue - ToneBank)
ToneOffsetsHi:
    .byte >(ToneFail - ToneBank), >(ToneRed - ToneBank), >(ToneYellow - ToneBank), >(ToneGreen - ToneBank), >(ToneBlue - ToneBank)
ToneLengthsLo:
    .byte <(ToneRed - ToneFail), <(ToneYellow - ToneRed), <(ToneGreen - ToneYellow), <(ToneBlue - ToneGreen), <(ToneBankEnd - ToneBlue)
ToneLengthsHi:
    .byte >(ToneRed - ToneFail), >(ToneYellow - ToneRed), >(ToneGreen - ToneYellow), >(ToneBlue - ToneGreen), >(ToneBankEnd - ToneBlue)

// Signed 8-bit square waves at 25 kHz: 42, 312.5, 250, 416.7 and 208.3 Hz.
ToneBank:
ToneFail:
    .fill 596, i < 298 ? $48 : $b8
ToneRed:
    .fill 80, i < 40 ? $48 : $b8
ToneYellow:
    .fill 100, i < 50 ? $48 : $b8
ToneGreen:
    .fill 60, i < 30 ? $48 : $b8
ToneBlue:
    .fill 120, i < 60 ? $48 : $b8
ToneBankEnd:

// Palette entries 2/8/5/6 are unlit lenses; 10/7/13/14 are their glow.
SimonPalette:
    .byte   2,  3,  3, 232,226,210,  72,  8, 14,  86, 54, 66
    .byte  55, 32, 70,   8, 56, 26,   7, 24, 62, 255,216, 45
    .byte  96, 88,  8,  39, 20, 10, 255, 42, 58,  28, 29, 28
    .byte  70, 68, 63,  46,255,112,  54,126,255, 142,138,126

SavedPalette:
    .fill UCI_PALETTE_BYTES, $00

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
