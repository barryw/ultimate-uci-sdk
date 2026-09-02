        .export _mux_irq, _prepare_multiplexer, _sort_virtual_sprites
        .import _virtual_sprites, _virtual_count, _mux_ready_raster
        .import _mux_event_count, _mux_event_index
        .import _mux_event_line, _mux_event_slot
        .import _mux_event_x, _mux_event_y, _mux_event_xmsb
        .import _mux_event_pointer, _mux_event_color

        .segment "RODATA"

sprite_offsets:
        .byte 0, 6, 12, 18, 24, 30, 36, 42, 48, 54, 60, 66
sprite_bits:
        .byte $01, $02, $04, $08, $10, $20, $40, $80
sprite_enable_masks:
        .byte $00, $01, $03, $07, $0f, $1f, $3f, $7f, $ff

        .segment "BSS"

mux_order:       .res 12
mux_sort_key:    .res 1
mux_sort_y:      .res 1
mux_sort_front:  .res 1
mux_sort_i:      .res 1
mux_sort_j:      .res 1
mux_initial:     .res 1
mux_xmsb:        .res 1
mux_slot:        .res 1
mux_value:       .res 1
mux_event_i:     .res 1
mux_trigger:     .res 1
mux_required:    .res 1
mux_dropped:     .res 1

        .segment "CODE"

_sort_virtual_sprites:
        ldx #$00
@order:
        cpx _virtual_count
        bcs @sort_start
        lda sprite_offsets,x
        sta mux_order,x
        inx
        bne @order

@sort_start:
        ldx #$01
@sort_outer:
        cpx _virtual_count
        bcs @sort_done
        stx mux_sort_i
        lda mux_order,x
        sta mux_sort_key
        tay
        lda _virtual_sprites+2,y
        sta mux_sort_y
        lda _virtual_sprites+5,y
        sta mux_sort_front
        stx mux_sort_j

@sort_inner:
        ldx mux_sort_j
        beq @sort_place
        lda mux_order-1,x
        tay
        lda _virtual_sprites+2,y
        cmp mux_sort_y
        bcc @sort_place
        bne @sort_shift
        lda _virtual_sprites+5,y
        cmp mux_sort_front
        bcs @sort_place

@sort_shift:
        lda mux_order-1,x
        sta mux_order,x
        dec mux_sort_j
        jmp @sort_inner

@sort_place:
        ldx mux_sort_j
        lda mux_sort_key
        sta mux_order,x
        ldx mux_sort_i
        inx
        bne @sort_outer

@sort_done:
        rts

_prepare_multiplexer:
        lda $d01a
        and #$fe
        sta $d01a

@initial:
        lda _virtual_count
        cmp #$08
        bcc @initial_count
        lda #$08
@initial_count:
        sta mux_initial
        lda #$00
        sta mux_xmsb
        ldx #$00

@initial_loop:
        cpx mux_initial
        bcs @initial_done
        stx mux_slot
        lda mux_order,x
        tay
        lda _virtual_sprites,y
        sta mux_value
        txa
        asl
        tax
        lda mux_value
        sta $d000,x
        lda _virtual_sprites+2,y
        sta $d001,x
        ldx mux_slot
        lda _virtual_sprites+3,y
        sta $87f8,x
        lda _virtual_sprites+4,y
        sta $d027,x
        lda _virtual_sprites+1,y
        beq @initial_xlo
        lda mux_xmsb
        ora sprite_bits,x
        sta mux_xmsb
        jmp @initial_next
@initial_xlo:
        lda sprite_bits,x
        eor #$ff
        and mux_xmsb
        sta mux_xmsb
@initial_next:
        ldx mux_slot
        inx
        bne @initial_loop

@initial_done:
        lda mux_xmsb
        sta $d010
        ldx mux_initial
        lda sprite_enable_masks,x
        sta $d015
        lda #$00
        sta _mux_event_count
        sta _mux_event_index
        sta mux_dropped
        ldx #$08

@event_loop:
        cpx _virtual_count
        bcc :+
        jmp @events_done
:
        stx mux_event_i
        lda mux_order-8,x
        tay
        lda _virtual_sprites+2,y
        clc
        adc #22
        bcs @event_drop
        cmp #246
        bcs @event_drop
        sta mux_trigger
        clc
        adc #7
        sta mux_required
        ldx mux_event_i
        lda mux_order,x
        tay
        lda _virtual_sprites+2,y
        cmp mux_required
        bcc @event_drop
        lda mux_event_i
        and #$07
        sta mux_slot
        tax
        lda _virtual_sprites+1,y
        beq @event_xlo
        lda mux_xmsb
        ora sprite_bits,x
        sta mux_xmsb
        jmp @event_store
@event_xlo:
        lda sprite_bits,x
        eor #$ff
        and mux_xmsb
        sta mux_xmsb

@event_store:
        ldx _mux_event_count
        lda mux_trigger
        sta _mux_event_line,x
        lda mux_slot
        sta _mux_event_slot,x
        lda _virtual_sprites,y
        sta _mux_event_x,x
        lda _virtual_sprites+2,y
        sta _mux_event_y,x
        lda mux_xmsb
        sta _mux_event_xmsb,x
        lda _virtual_sprites+3,y
        sta _mux_event_pointer,x
        lda _virtual_sprites+4,y
        sta _mux_event_color,x
        inc _mux_event_count
        jmp @event_next

@event_drop:
        inc mux_dropped
@event_next:
        ldx mux_event_i
        inx
        jmp @event_loop

@events_done:
        lda mux_dropped
        beq @quiet_border
        lda #$02
        bne @set_border
@quiet_border:
        lda #$0b
@set_border:
        sta $d020
        lda _mux_event_count
        beq @ready
        lda $d011
        and #$7f
        sta $d011
        lda _mux_event_line
        sta $d012
        lda #$01
        sta $d019
        lda $d01a
        ora #$01
        sta $d01a
@ready:
        lda $d012
        sta _mux_ready_raster
        rts

_mux_irq:
        lda $d019
        and #$01
        beq @kernal
        sta $d019
        ldy _mux_event_index

@load:
        cpy _mux_event_count
        bcs @disable
        lda _mux_event_slot,y
        tax
        lda _mux_event_xmsb,y
        sta $d010
        lda _mux_event_pointer,y
        sta $87f8,x
        lda _mux_event_color,y
        sta $d027,x
        txa
        asl
        tax
        lda _mux_event_x,y
        sta $d000,x
        lda _mux_event_y,y
        sta $d001,x
        iny
        sty _mux_event_index
        cpy _mux_event_count
        bcs @disable
        lda $d012
        cmp _mux_event_line,y
        bcs @load
        lda _mux_event_line,y
        sta $d012
        jmp $ea81

@disable:
        lda $d01a
        and #$fe
        sta $d01a
        jmp $ea81

@kernal:
        jmp $ea31
