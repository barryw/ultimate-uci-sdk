; Keep Machine Yearning's shared zero-page state separate from cc65 and the SDK.
;
; The PSID player uses cc65's full $02-$1B zero-page workspace and the SDK's
; $FB-$FE workspace. Swap all 30 bytes, then snapshot the player's masked SID
; shadows while its zero-page state is active.
;
; SPDX-License-Identifier: MIT

        .export _music_init, _music_irq, _music_meter_reset, _music_play
        .export _music_render_bars
        .export _music_gate_state
        .export _music_brightness, _music_energy_peak, _music_regs
        .export _music_ticks, _music_trigger_seen
        .export _visualizer_level
        .export _machine_reset

        .segment "BSS"
music_low: .res 26
c_low:     .res 26
music_high:.res 4
c_high:    .res 4
_music_regs:.res 50
_music_gate_state:.res 6
_music_trigger_seen:.res 6
_music_envelope:.res 6
_music_energy_peak:.res 6
_music_brightness:.res 6
_music_bar_height:.res 6
_music_ticks:.res 1
_visualizer_level: .res 6
meter_step:.res 1
meter_sustain:.res 1
meter_color:.res 1

        .segment "CODE"

; void __fastcall__ music_init(uint8_t tune)
_music_init:
        pha
        ldx #25
@save_low:
        lda $02,x
        sta c_low,x
        dex
        bpl @save_low
        ldx #3
@save_high:
        lda $FB,x
        sta c_high,x
        dex
        bpl @save_high
        pla
        jsr $1000
        ldx #25
@keep_low:
        lda $02,x
        sta music_low,x
        lda c_low,x
        sta $02,x
        dex
        bpl @keep_low
        ldx #3
@keep_high:
        lda $FB,x
        sta music_high,x
        lda c_high,x
        sta $FB,x
        dex
        bpl @keep_high
        rts

; void music_play(void)
_music_play:
        ldx #25
@in_low:
        lda $02,x
        sta c_low,x
        lda music_low,x
        sta $02,x
        dex
        bpl @in_low
        ldx #3
@in_high:
        lda $FB,x
        sta c_high,x
        lda music_high,x
        sta $FB,x
        dex
        bpl @in_high
        ; Snapshot the values this player tick is about to write. Doing this
        ; here is both faster than 36 C calls and keeps sound and visuals on
        ; the same tick.
        ldx #24
@regs:
        lda $58,x
        and $08,x
        sta _music_regs,x
        lda $89,x
        and $39,x
        sta _music_regs+25,x
        dex
        bpl @regs
        .macro latch_gate voice, reg
        .local unchanged, falling
        lda _music_regs+reg
        and #$01
        cmp _music_gate_state+voice
        beq unchanged
        sta _music_gate_state+voice
        beq falling
        lda #$01
        sta _music_trigger_seen+voice
falling:
unchanged:
        .endmacro

        .macro meter_voice voice, reg, volume
        .local no_trigger, release, decay_done, decay_store
        .local envelope_done, release_store, silent, peak_done, done
        .local bright_done, brightness_store
        lda _music_trigger_seen+voice
        beq no_trigger
        lda #$00
        sta _music_trigger_seen+voice
        lda #$FF
        sta _music_envelope+voice
        jmp envelope_done
no_trigger:
        lda _music_regs+reg+4
        and #$01
        beq release
        lda _music_regs+reg+6
        and #$F0
        sta meter_sustain
        lsr
        lsr
        lsr
        lsr
        ora meter_sustain
        sta meter_sustain
        lda _music_envelope+voice
        cmp meter_sustain
        bcc decay_done
        beq envelope_done
        lda _music_envelope+voice
        sec
        sbc #$08
        bcc decay_done
        cmp meter_sustain
        bcs decay_store
decay_done:
        lda meter_sustain
decay_store:
        sta _music_envelope+voice
        jmp envelope_done
release:
        lda _music_envelope+voice
        sec
        sbc #$0C
        bcs release_store
        lda #$00
release_store:
        sta _music_envelope+voice
envelope_done:
        lda _music_regs+reg+4
        and #$F0
        beq silent
        lda _music_regs+reg+4
        and #$08
        bne silent
        lda _music_regs+volume
        and #$0F
        beq silent
        lda _music_envelope+voice
        cmp _music_energy_peak+voice
        bcc peak_done
        sta _music_energy_peak+voice
peak_done:
        lda _music_regs+reg+1
        sta meter_step
        lsr
        lsr
        sta meter_sustain
        lda meter_step
        sec
        sbc meter_sustain
        clc
        adc #80
        bcs bright_done
        sta meter_step
        lda _music_regs+reg
        lsr
        lsr
        lsr
        lsr
        lsr
        clc
        adc meter_step
        bcc brightness_store
bright_done:
        lda #$FF
brightness_store:
        sta _music_brightness+voice
        jmp done
silent:
        lda #$00
        sta _music_brightness+voice
done:
        .endmacro
        latch_gate 0, 4
        latch_gate 1, 11
        latch_gate 2, 18
        latch_gate 3, 29
        latch_gate 4, 36
        latch_gate 5, 43
        meter_voice 0, 0, 24
        meter_voice 1, 7, 24
        meter_voice 2, 14, 24
        meter_voice 3, 25, 49
        meter_voice 4, 32, 49
        meter_voice 5, 39, 49
        jsr $1003
        ldx #25
@out_low:
        lda $02,x
        sta music_low,x
        lda c_low,x
        sta $02,x
        dex
        bpl @out_low
        ldx #3
@out_high:
        lda $FB,x
        sta music_high,x
        lda c_high,x
        sta $FB,x
        dex
        bpl @out_high
        rts

_music_irq:
        lda $DC0D
        jsr _music_play
        lda _music_ticks
        cmp #2
        bcs @counted
        inc _music_ticks
@counted:
        inc $0342
        jmp $EA81

_music_meter_reset:
        lda #$00
        ldx #$05
@clear:
        sta _music_gate_state,x
        sta _music_trigger_seen,x
        sta _music_envelope,x
        sta _music_energy_peak,x
        sta _music_brightness,x
        sta _music_bar_height,x
        dex
        bpl @clear
        sta _music_ticks
        rts

; Paint one five-character row. A is the colour, X is the one-based height,
; and $FB/$FC points at this voice's bottom row.
paint_meter_row:
        sta meter_color
        dex
        beq @paint
@up:
        lda $FB
        sec
        sbc #40
        sta $FB
        bcs @next
        dec $FC
@next:
        dex
        bne @up
@paint:
        lda meter_color
        ldy #4
@cell:
        sta ($FB),y
        dey
        bpl @cell
        rts

_music_render_bars:
        .macro render_voice voice, color, base
        .local have_target, no_mid, no_high, down, done
        lda _music_energy_peak+voice
        sta meter_step
        lda #$00
        sta _music_energy_peak+voice
        lda meter_step
        lsr
        lsr
        lsr
        lsr
        sta meter_sustain
        lda meter_step
        beq have_target
        inc meter_sustain
        cmp #128
        bcc no_mid
        inc meter_sustain
no_mid:
        cmp #224
        bcc no_high
        inc meter_sustain
no_high:
have_target:
        lda meter_sustain
        cmp _music_bar_height+voice
        beq done
        bcc down
        inc _music_bar_height+voice
        lda #<base
        sta $FB
        lda #>base
        sta $FC
        ldx _music_bar_height+voice
        lda #color
        jsr paint_meter_row
        jmp done
down:
        lda #<base
        sta $FB
        lda #>base
        sta $FC
        ldx _music_bar_height+voice
        lda #$00
        jsr paint_meter_row
        dec _music_bar_height+voice
done:
        lda _music_bar_height+voice
        sta $034B+voice
        .endmacro
        render_voice 0, 1, $DB22
        render_voice 1, 2, $DB28
        render_voice 2, 3, $DB2E
        render_voice 3, 4, $DB34
        render_voice 4, 5, $DB3A
        render_voice 5, 6, $DB40
        rts

_machine_reset:
        jmp $FCE2
