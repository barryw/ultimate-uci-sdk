; audio.s - the Ultimate Audio hardware PCM block.
;
; Ultimate Audio is not a UCI target. When the owner maps it in the machine's
; settings, seven write-only voice blocks appear at $DF20-$DFFF and fetch PCM
; from the same SDRAM window exposed as the REU. This module is the small,
; checked register layer; file streaming is composed from it and the existing
; DOS/REU services by the application.
;
; Configure pauses about a millisecond after stopping the channel and again
; after programming it: the engine reprogrammed on the fly plays noise.
;
; Multi-byte registers are big endian even though the public structure is
; naturally little endian on a 6502. Every byte is written explicitly here so
; callers never have to know that trap, nor that REU offset zero is SDRAM
; address $01.00.00.00 to the sampler.
;
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"
        .include "uci_seg.inc"
        .include "uci_zp.inc"

        .import ult_scratch, ult_audio_up

        .export ultimate_audio_init,      _ultimate_audio_init
        .export ultimate_audio_available, _ultimate_audio_available
        .export ultimate_audio_version,   _ultimate_audio_version
        .export ultimate_audio_configure, _ultimate_audio_configure
        .export ultimate_audio_start
        .export ultimate_audio_stop,      _ultimate_audio_stop
        .export ultimate_audio_irq_status, _ultimate_audio_irq_status
        .export ultimate_audio_irq_clear,  _ultimate_audio_irq_clear

        uci_code

; ---------------------------------------------------------------------------
; ultimate_audio_init -> A = ULTIMATE_OK or ULTIMATE_ERR_NOT_SUPPORTED
;
; `$DF21` alone is not a presence test: on current C64 Ultimate hardware it
; reads $10 even while the block is unmapped. Prove the engine by clearing its
; status, playing one silent byte on channel 6, and observing a stable end bit.
; Volume zero makes the probe inaudible. It deliberately borrows channel 6;
; initialization belongs before an application starts any voices.
; ---------------------------------------------------------------------------
ultimate_audio_init:
_ultimate_audio_init:
        lda #$00
        sta ult_audio_up

        lda UA_REG_VERSION
        and #$F0
        cmp #UA_VERSION_1_0
        beq :+
        jmp @absent
:

        php
        sei
        lda #(UA_CHANNELS - 1)
        jsr audio_channel_x

        lda #$00
        sta UA_REG_BASE + UA_REG_CONTROL,x
        sta UA_REG_BASE + UA_REG_VOLUME,x
        lda #UA_PAN_CENTER
        sta UA_REG_BASE + UA_REG_PAN,x

        lda #UA_REU_SDRAM_BANK
        sta UA_REG_BASE + UA_REG_START,x
        lda #$00
        sta UA_REG_BASE + UA_REG_START + 1,x
        sta UA_REG_BASE + UA_REG_START + 2,x
        sta UA_REG_BASE + UA_REG_START + 3,x
        sta UA_REG_BASE + UA_REG_LENGTH,x
        sta UA_REG_BASE + UA_REG_LENGTH + 1,x
        lda #$01
        sta UA_REG_BASE + UA_REG_LENGTH + 2,x
        lda #$00
        sta UA_REG_BASE + UA_REG_RATE,x
        lda #$01
        sta UA_REG_BASE + UA_REG_RATE + 1,x
        lda #$FF
        sta UA_REG_BASE + UA_REG_IRQ_CLEAR,x

        ; A mapped status register stays clear after the clear above. Open bus
        ; does not get one lucky read: it has to look right 256 times.
        ldy #$00
@clear: lda UA_REG_IRQ_STATUS
        and #((1 << UA_CHANNELS) - 1)
        bne @absent_stop
        dey
        bne @clear

        lda #(UA_CTRL_GATE | UA_CTRL_IRQ)
        sta UA_REG_BASE + UA_REG_CONTROL,x
        ldy #$00
@wait:  lda UA_REG_IRQ_STATUS
        and #(1 << (UA_CHANNELS - 1))
        bne @ended
        dey
        bne @wait
        beq @absent_stop

        ; The engine latches the bit until software clears it. Require sixteen
        ; consecutive reads so an open-bus coincidence cannot pass the probe.
@ended: ldy #$10
@hold:  lda UA_REG_IRQ_STATUS
        and #(1 << (UA_CHANNELS - 1))
        beq @absent_stop
        dey
        bne @hold

        lda #$00
        sta UA_REG_BASE + UA_REG_CONTROL,x
        lda #$01
        sta UA_REG_BASE + UA_REG_IRQ_CLEAR,x
        lda #$01
        sta ult_audio_up
        plp
        jmp audio_ok

@absent_stop:
        lda #$00
        sta UA_REG_BASE + UA_REG_CONTROL,x
        plp
@absent:
        ldx #$00
        lda #ULTIMATE_ERR_NOT_SUPPORTED
        rts

; ---------------------------------------------------------------------------
; ultimate_audio_version -> A = raw version byte
; ---------------------------------------------------------------------------
ultimate_audio_version:
_ultimate_audio_version:
        ldx #$00
        lda UA_REG_VERSION
        rts

; ---------------------------------------------------------------------------
; ultimate_audio_available -> A = cached result of ultimate_audio_init
; ---------------------------------------------------------------------------
ultimate_audio_available:
_ultimate_audio_available:
        ldx #$00
        lda ult_audio_up
        rts

; A = channel -> X = channel register offset, carry clear; carry set if bad.
audio_channel_x:
        cmp #UA_CHANNELS
        bcs @bad
        asl a
        asl a
        asl a
        asl a
        asl a
        tax
        clc
        rts
@bad:   sec
        rts

; Return NOT_SUPPORTED unless the known register block answers.
audio_require:
        lda ult_audio_up
        cmp #$01
        beq @yes
        ldx #$00
        lda #ULTIMATE_ERR_NOT_SUPPORTED
        sec
        rts
@yes:   clc
        rts

; Shared result tails.
audio_invalid:
        ldx #$00
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        rts

audio_ok:
        ldx #$00
        lda #ULTIMATE_OK
        rts

; About a millisecond at any CPU speed: I/O reads run at 1 MHz under Ultimate
; 64 turbo, so 1,024 of them take a millisecond at 48 MHz and nine at stock
; speed. Reprogramming a running channel without a pause leaves it playing
; noise (an Elite, firmware 3.15: intermittent from one launch to the next
; until the pause went in). Preserves X, which configure keeps the channel
; offset in.
audio_settle:
        txa
        pha
        ldx #$00
        ldy #$04
@loop:  lda $D012
        inx
        bne @loop
        dey
        bne @loop
        pla
        tax
        rts

; ---------------------------------------------------------------------------
; ultimate_audio_configure A/X = ultimate_audio_voice pointer -> A = result
;
; Writes every field but leaves gate clear. The validation is intentionally at
; this boundary: a bad length or loop point makes the FPGA read beyond the
; caller's sample and is not something hardware can report afterwards.
; ---------------------------------------------------------------------------
ultimate_audio_configure:
_ultimate_audio_configure:
        sta uci_ptr
        stx uci_ptr + 1
        ora uci_ptr + 1
        beq audio_invalid

        ldy #UA_VOICE_CHANNEL
        lda (uci_ptr),y
        cmp #UA_CHANNELS
        bcs audio_invalid

        ldy #UA_VOICE_FLAGS
        lda (uci_ptr),y
        and #($FF ^ UA_CTRL_FLAGS)
        bne audio_invalid

        ldy #UA_VOICE_VOLUME
        lda (uci_ptr),y
        cmp #UA_VOLUME_MAX + 1
        bcs audio_invalid

        ldy #UA_VOICE_PAN
        lda (uci_ptr),y
        cmp #UA_PAN_RIGHT + 1
        bcs audio_invalid

        ; All four public dwords must fit the hardware's 24-bit fields.
        ldy #UA_VOICE_REU + 3
        lda (uci_ptr),y
        bne audio_invalid
        ldy #UA_VOICE_LENGTH + 3
        lda (uci_ptr),y
        bne audio_invalid
        ldy #UA_VOICE_REPEAT_A + 3
        lda (uci_ptr),y
        bne audio_invalid
        ldy #UA_VOICE_REPEAT_B + 3
        lda (uci_ptr),y
        bne audio_invalid

        ; A zero byte count never has a useful meaning to this API.
        ldy #UA_VOICE_LENGTH
        lda (uci_ptr),y
        iny
        ora (uci_ptr),y
        iny
        ora (uci_ptr),y
        beq audio_invalid

        ; A zero divider would ask for the sampler's reference clock itself.
        ldy #UA_VOICE_RATE
        lda (uci_ptr),y
        iny
        ora (uci_ptr),y
        beq audio_invalid

        ; The sequencer compares the byte position only when it fetches a
        ; sample. A 16-bit sample advances by two bytes, and interleave skips
        ; every other 8-bit sample, so either feature requires an even length.
        ; Stereo 16-bit right channels commonly start at base+2 and therefore
        ; use total_length-2: requiring a multiple of four would reject them.
        ldy #UA_VOICE_FLAGS
        lda (uci_ptr),y
        and #(UA_CTRL_16BIT | UA_CTRL_INTERLEAVE)
        beq @aligned
        ldy #UA_VOICE_LENGTH
        lda (uci_ptr),y
        and #$01
        beq @aligned
        jmp audio_invalid

@aligned:
        ; reu_address + length may end at 16 MB, but may not wrap past it.
        clc
        ldy #UA_VOICE_REU
        lda (uci_ptr),y
        ldy #UA_VOICE_LENGTH
        adc (uci_ptr),y
        sta ult_scratch
        ldy #UA_VOICE_REU + 1
        lda (uci_ptr),y
        ldy #UA_VOICE_LENGTH + 1
        adc (uci_ptr),y
        sta ult_scratch + 1
        ldy #UA_VOICE_REU + 2
        lda (uci_ptr),y
        ldy #UA_VOICE_LENGTH + 2
        adc (uci_ptr),y
        sta ult_scratch + 2
        bcc @range_ok
        lda ult_scratch
        ora ult_scratch + 1
        ora ult_scratch + 2
        beq @range_ok
        jmp audio_invalid             ; wrapped to somewhere other than zero

@range_ok:
        ; When repeat is requested: A < B <= length.
        ldy #UA_VOICE_FLAGS
        lda (uci_ptr),y
        and #UA_CTRL_REPEAT
        beq @validated

        ldy #UA_VOICE_REPEAT_A + 2
        lda (uci_ptr),y
        ldy #UA_VOICE_REPEAT_B + 2
        cmp (uci_ptr),y
        bcc @a_lt_b
        beq :+
        jmp audio_invalid
:
        ldy #UA_VOICE_REPEAT_A + 1
        lda (uci_ptr),y
        ldy #UA_VOICE_REPEAT_B + 1
        cmp (uci_ptr),y
        bcc @a_lt_b
        beq :+
        jmp audio_invalid
:
        ldy #UA_VOICE_REPEAT_A
        lda (uci_ptr),y
        ldy #UA_VOICE_REPEAT_B
        cmp (uci_ptr),y
        bcc @a_lt_b
        jmp audio_invalid

@a_lt_b:
        ldy #UA_VOICE_REPEAT_B + 2
        lda (uci_ptr),y
        ldy #UA_VOICE_LENGTH + 2
        cmp (uci_ptr),y
        bcc @validated
        beq :+
        jmp audio_invalid
:
        ldy #UA_VOICE_REPEAT_B + 1
        lda (uci_ptr),y
        ldy #UA_VOICE_LENGTH + 1
        cmp (uci_ptr),y
        bcc @validated
        beq :+
        jmp audio_invalid
:
        ldy #UA_VOICE_REPEAT_B
        lda (uci_ptr),y
        ldy #UA_VOICE_LENGTH
        cmp (uci_ptr),y
        bcc @validated
        beq @validated
        jmp audio_invalid

@validated:
        jsr audio_require
        bcc :+
        rts
:

        ldy #UA_VOICE_CHANNEL
        lda (uci_ptr),y
        jsr audio_channel_x

        ; Stop first and let the engine actually stop, then replace every
        ; write-only register, then let it take those before the caller can
        ; open the gate.
        lda #$00
        sta UA_REG_BASE + UA_REG_CONTROL,x
        jsr audio_settle

        ldy #UA_VOICE_VOLUME
        lda (uci_ptr),y
        sta UA_REG_BASE + UA_REG_VOLUME,x
        ldy #UA_VOICE_PAN
        lda (uci_ptr),y
        sta UA_REG_BASE + UA_REG_PAN,x

        lda #UA_REU_SDRAM_BANK
        sta UA_REG_BASE + UA_REG_START,x
        ldy #UA_VOICE_REU + 2
        lda (uci_ptr),y
        sta UA_REG_BASE + UA_REG_START + 1,x
        dey
        lda (uci_ptr),y
        sta UA_REG_BASE + UA_REG_START + 2,x
        dey
        lda (uci_ptr),y
        sta UA_REG_BASE + UA_REG_START + 3,x

        ldy #UA_VOICE_LENGTH + 2
        lda (uci_ptr),y
        sta UA_REG_BASE + UA_REG_LENGTH,x
        dey
        lda (uci_ptr),y
        sta UA_REG_BASE + UA_REG_LENGTH + 1,x
        dey
        lda (uci_ptr),y
        sta UA_REG_BASE + UA_REG_LENGTH + 2,x

        ldy #UA_VOICE_RATE + 1
        lda (uci_ptr),y
        sta UA_REG_BASE + UA_REG_RATE,x
        dey
        lda (uci_ptr),y
        sta UA_REG_BASE + UA_REG_RATE + 1,x

        ldy #UA_VOICE_REPEAT_A + 2
        lda (uci_ptr),y
        sta UA_REG_BASE + UA_REG_REPEAT_A,x
        dey
        lda (uci_ptr),y
        sta UA_REG_BASE + UA_REG_REPEAT_A + 1,x
        dey
        lda (uci_ptr),y
        sta UA_REG_BASE + UA_REG_REPEAT_A + 2,x

        ldy #UA_VOICE_REPEAT_B + 2
        lda (uci_ptr),y
        sta UA_REG_BASE + UA_REG_REPEAT_B,x
        dey
        lda (uci_ptr),y
        sta UA_REG_BASE + UA_REG_REPEAT_B + 1,x
        dey
        lda (uci_ptr),y
        sta UA_REG_BASE + UA_REG_REPEAT_B + 2,x

        lda #$01
        sta UA_REG_BASE + UA_REG_IRQ_CLEAR,x
        jsr audio_settle
        ldy #UA_VOICE_FLAGS
        lda (uci_ptr),y
        sta UA_REG_BASE + UA_REG_CONTROL,x
        jmp audio_ok

; ---------------------------------------------------------------------------
; ultimate_audio_start A = channel, X = flags -> A = result
; ---------------------------------------------------------------------------
ultimate_audio_start:
        cmp #UA_CHANNELS
        bcc :+
        jmp audio_invalid
:
        pha
        txa
        and #($FF ^ UA_CTRL_FLAGS)
        bne @invalid_pop
        txa
        pha
        jsr audio_require
        bcs @unsupported_pop
        pla
        tay                             ; flags
        pla
        jsr audio_channel_x
        tya
        ora #UA_CTRL_GATE
        sta UA_REG_BASE + UA_REG_CONTROL,x
        jmp audio_ok

@unsupported_pop:
        pla                             ; flags
        pla                             ; channel
        ldx #$00
        lda #ULTIMATE_ERR_NOT_SUPPORTED
        rts
@invalid_pop:
        pla                             ; channel
        jmp audio_invalid

; ---------------------------------------------------------------------------
; ultimate_audio_stop A = channel -> A = result
; ---------------------------------------------------------------------------
ultimate_audio_stop:
_ultimate_audio_stop:
        cmp #UA_CHANNELS
        bcc :+
        jmp audio_invalid
:
        pha
        jsr audio_require
        bcs @pop
        pla
        jsr audio_channel_x
        lda #$00
        sta UA_REG_BASE + UA_REG_CONTROL,x
        jmp audio_ok
@pop:   pla
        ldx #$00
        lda #ULTIMATE_ERR_NOT_SUPPORTED
        rts

; ---------------------------------------------------------------------------
; ultimate_audio_irq_status -> A = channel mask, or zero when unavailable
; ---------------------------------------------------------------------------
ultimate_audio_irq_status:
_ultimate_audio_irq_status:
        jsr ultimate_audio_available
        cmp #$01
        bne @none
        ldx #$00
        lda UA_REG_IRQ_STATUS
        and #((1 << UA_CHANNELS) - 1)
        rts
@none:  lda #$00
        tax
        rts

; ---------------------------------------------------------------------------
; ultimate_audio_irq_clear A = channel -> A = result
; ---------------------------------------------------------------------------
ultimate_audio_irq_clear:
_ultimate_audio_irq_clear:
        cmp #UA_CHANNELS
        bcc :+
        jmp audio_invalid
:
        pha
        jsr audio_require
        bcs @pop
        pla
        jsr audio_channel_x
        lda #$01
        sta UA_REG_BASE + UA_REG_IRQ_CLEAR,x
        jmp audio_ok
@pop:   pla
        ldx #$00
        lda #ULTIMATE_ERR_NOT_SUPPORTED
        rts
