; vsprite.s - masked software sprites in a C64 bitmap.
;
; One small primitive shared by the vsprites and Boing demos. It knows the
; VIC-II's 40-column bitmap layout and nothing about movement, frame timing,
; buffering or where a clean background lives. Those policies stay with the
; caller.
;
; The image format is column-major: `height` bytes for byte column 0, then
; `height` bytes for byte column 1, and so on. VSPRITE_F_COPY instead treats
; source as another C64 bitmap base. VSPRITE_F_COLOR writes the supplied screen
; byte only for cells containing a nonzero source byte.
;
; This routine patches its own absolute operands. It must execute from RAM and
; is not reentrant.
;
; Part of the Ultimate SDK. SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"
        .include "uci_zp.inc"
        .include "uci_seg.inc"

        .export ultimate_vsprite_draw, _ultimate_vsprite_draw

        .rodata
vs_row312_lo: .repeat 25, I
        .byte <(I * 312)
        .endrepeat
vs_row312_hi: .repeat 25, I
        .byte >(I * 312)
        .endrepeat
        uci_code

; A/X = ultimate_vsprite descriptor. A = ULTIMATE_* result.
ultimate_vsprite_draw:
_ultimate_vsprite_draw:
        sta uci_ptr
        stx uci_ptr + 1
        ora uci_ptr + 1
        bne @pointer_ok
        jmp @invalid
@pointer_ok:
        ldy #VSPRITE_FLAGS
        lda (uci_ptr),y
        sta vs_flags
        and #<~VSPRITE_F_ALL
        beq :+
        jmp @invalid
:
        lda vs_flags
        and #(VSPRITE_F_MASKED | VSPRITE_F_COPY)
        cmp #(VSPRITE_F_MASKED | VSPRITE_F_COPY)
        bne :+
        jmp @invalid
:
        lda vs_flags
        and #VSPRITE_F_COLOR
        beq @operation_ok
        lda vs_flags
        and #(VSPRITE_F_MASKED | VSPRITE_F_COPY)
        beq :+
        jmp @invalid
:
@operation_ok:

        ldy #VSPRITE_BITMAP
        lda (uci_ptr),y
        sta vs_dst_col
        iny
        lda (uci_ptr),y
        sta vs_dst_col + 1
        lda vs_dst_col
        ora vs_dst_col + 1
        bne :+
        jmp @invalid
:

        ldy #VSPRITE_SOURCE
        lda (uci_ptr),y
        sta vs_src_col
        iny
        lda (uci_ptr),y
        sta vs_src_col + 1
        lda vs_src_col
        ora vs_src_col + 1
        bne :+
        jmp @invalid
:

        ldy #VSPRITE_MASK
        lda (uci_ptr),y
        sta vs_mask_col
        iny
        lda (uci_ptr),y
        sta vs_mask_col + 1
        lda vs_flags
        and #VSPRITE_F_MASKED
        beq @mask_ok
        lda vs_mask_col
        ora vs_mask_col + 1
        bne :+
        jmp @invalid
:
@mask_ok:

        ldy #VSPRITE_SCREEN
        lda (uci_ptr),y
        sta vs_screen_col
        iny
        lda (uci_ptr),y
        sta vs_screen_col + 1
        lda vs_flags
        and #VSPRITE_F_COLOR
        beq @screen_ok
        lda vs_screen_col
        ora vs_screen_col + 1
        bne :+
        jmp @invalid
:
@screen_ok:

        ldy #VSPRITE_X
        lda (uci_ptr),y
        sta vs_x
        cmp #40
        bcc :+
        jmp @invalid
:
        iny
        lda (uci_ptr),y
        sta vs_y
        cmp #200
        bcc :+
        jmp @invalid
:
        iny
        lda (uci_ptr),y
        bne :+
        jmp @invalid
:
        sta vs_width
        clc
        adc vs_x
        bcc :+
        jmp @invalid
:
        cmp #41
        bcc :+
        jmp @invalid
:
        iny
        lda (uci_ptr),y
        bne :+
        jmp @invalid
:
        sta vs_height
        clc
        adc vs_y
        bcc :+
        jmp @invalid
:
        cmp #201
        bcc :+
        jmp @invalid
:
        iny
        lda (uci_ptr),y
        sta vs_color

        ; row = y >> 3, yin = y & 7, first segment end = 8 - yin.
        lda vs_y
        and #$07
        sta vs_yin
        lda #$08
        sec
        sbc vs_yin
        cmp vs_height
        bcc @first_end
        lda vs_height
@first_end:
        sta vs_first_end
        lda vs_y
        lsr
        lsr
        lsr
        tax

        ; offset = row * 312 + y + x * 8.
        lda vs_row312_lo,x
        clc
        adc vs_y
        sta vs_off
        lda vs_row312_hi,x
        adc #$00
        sta vs_off + 1
        lda #$00
        sta vs_tmp
        lda vs_x
        asl
        rol vs_tmp
        asl
        rol vs_tmp
        asl
        rol vs_tmp
        clc
        adc vs_off
        sta vs_off
        lda vs_tmp
        adc vs_off + 1
        sta vs_off + 1

        clc
        lda vs_dst_col
        adc vs_off
        sta vs_dst_col
        lda vs_dst_col + 1
        adc vs_off + 1
        sta vs_dst_col + 1

        lda vs_flags
        and #VSPRITE_F_COPY
        beq @source_ready
        clc
        lda vs_src_col
        adc vs_off
        sta vs_src_col
        lda vs_src_col + 1
        adc vs_off + 1
        sta vs_src_col + 1
@source_ready:

        lda vs_flags
        and #VSPRITE_F_COLOR
        beq @screen_ready
        lda vs_off
        sec
        sbc vs_yin
        sta vs_off
        lda vs_off + 1
        sbc #$00
        sta vs_off + 1
        lsr vs_off + 1
        ror vs_off
        lsr vs_off + 1
        ror vs_off
        lsr vs_off + 1
        ror vs_off
        clc
        lda vs_screen_col
        adc vs_off
        sta vs_screen_col
        lda vs_screen_col + 1
        adc vs_off + 1
        sta vs_screen_col + 1
@screen_ready:

@column:
        lda vs_dst_col
        sta vs_dst_work
        lda vs_dst_col + 1
        sta vs_dst_work + 1
        lda vs_src_col
        sta vs_src_work
        lda vs_src_col + 1
        sta vs_src_work + 1
        lda vs_src_col
        sta @mask_src + 1
        sta @or_src + 1
        sta @color_src + 1
        lda vs_src_col + 1
        sta @mask_src + 2
        sta @or_src + 2
        sta @color_src + 2
        lda vs_mask_col
        sta @mask_mask + 1
        lda vs_mask_col + 1
        sta @mask_mask + 2
        lda vs_screen_col
        sta vs_screen_work
        lda vs_screen_col + 1
        sta vs_screen_work + 1
        lda vs_first_end
        sta vs_end
        ldx #$00

@segment:
        lda vs_flags
        and #VSPRITE_F_COPY
        bne @copy_patch
        lda vs_flags
        and #VSPRITE_F_MASKED
        bne @masked_patch
        lda vs_flags
        and #VSPRITE_F_COLOR
        bne @color_patch

        lda vs_dst_work
        sta @or_load + 1
        sta @or_store + 1
        lda vs_dst_work + 1
        sta @or_load + 2
        sta @or_store + 2
        jmp @or_loop

@copy_patch:
        lda vs_dst_work
        sta @copy_dst + 1
        lda vs_dst_work + 1
        sta @copy_dst + 2
        lda vs_src_work
        sta @copy_src + 1
        lda vs_src_work + 1
        sta @copy_src + 2
        jmp @copy_loop

@masked_patch:
        lda vs_dst_work
        sta @mask_load + 1
        sta @mask_store + 1
        lda vs_dst_work + 1
        sta @mask_load + 2
        sta @mask_store + 2
        jmp @masked_loop

@color_patch:
        lda vs_dst_work
        sta @color_load + 1
        sta @color_store + 1
        lda vs_dst_work + 1
        sta @color_load + 2
        sta @color_store + 2
        jmp @color_loop

@or_loop:
@or_src:
        lda $ffff,x
@or_load:
        ora $ffff,x
@or_store:
        sta $ffff,x
        inx
        cpx vs_end
        bne @or_loop
        jmp @segment_done

@copy_loop:
@copy_src:
        lda $ffff,x
@copy_dst:
        sta $ffff,x
        inx
        cpx vs_end
        bne @copy_loop
        jmp @segment_done

@masked_loop:
@mask_load:
        lda $ffff,x
@mask_mask:
        and $ffff,x
@mask_src:
        ora $ffff,x
@mask_store:
        sta $ffff,x
        inx
        cpx vs_end
        bne @masked_loop
        jmp @segment_done

@color_loop:
        lda #$00
        sta vs_coverage
@color_byte:
@color_src:
        lda $ffff,x
        sta vs_value
        ora vs_coverage
        sta vs_coverage
        lda vs_value
@color_load:
        ora $ffff,x
@color_store:
        sta $ffff,x
        inx
        cpx vs_end
        bne @color_byte
        lda vs_coverage
        beq @segment_done
        lda vs_screen_work
        sta @color_screen + 1
        lda vs_screen_work + 1
        sta @color_screen + 2
        lda vs_color
@color_screen:
        sta $ffff

@segment_done:
        cpx vs_height
        beq @column_done
        clc
        lda vs_dst_work
        adc #<312
        sta vs_dst_work
        lda vs_dst_work + 1
        adc #>312
        sta vs_dst_work + 1
        lda vs_flags
        and #VSPRITE_F_COPY
        beq @no_source_step
        clc
        lda vs_src_work
        adc #<312
        sta vs_src_work
        lda vs_src_work + 1
        adc #>312
        sta vs_src_work + 1
@no_source_step:
        lda vs_flags
        and #VSPRITE_F_COLOR
        beq @no_screen_step
        clc
        lda vs_screen_work
        adc #40
        sta vs_screen_work
        bcc @no_screen_step
        inc vs_screen_work + 1
@no_screen_step:
        lda vs_end
        clc
        adc #8
        cmp vs_height
        bcc @set_end
        lda vs_height
@set_end:
        sta vs_end
        jmp @segment

@column_done:
        clc
        lda vs_dst_col
        adc #8
        sta vs_dst_col
        bcc @dst_col_ok
        inc vs_dst_col + 1
@dst_col_ok:
        lda vs_flags
        and #VSPRITE_F_COPY
        beq @image_col
        clc
        lda vs_src_col
        adc #8
        sta vs_src_col
        bcc @source_col_ok
        inc vs_src_col + 1
        jmp @source_col_ok
@image_col:
        clc
        lda vs_src_col
        adc vs_height
        sta vs_src_col
        bcc @source_col_ok
        inc vs_src_col + 1
@source_col_ok:
        lda vs_flags
        and #VSPRITE_F_MASKED
        beq @mask_col_ok
        clc
        lda vs_mask_col
        adc vs_height
        sta vs_mask_col
        bcc @mask_col_ok
        inc vs_mask_col + 1
@mask_col_ok:
        lda vs_flags
        and #VSPRITE_F_COLOR
        beq @screen_col_ok
        inc vs_screen_col
        bne @screen_col_ok
        inc vs_screen_col + 1
@screen_col_ok:
        dec vs_width
        beq @ok
        jmp @column

@ok:    ldx #$00
        lda #ULTIMATE_OK
        rts
@invalid:
        ldx #$00
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        rts

; Working bytes live with the self-modifying code, not in the SDK's shared
; variable block. That keeps UCI_VARS_SIZE and placed builds unchanged.
vs_dst_col:     .word 0
vs_src_col:     .word 0
vs_mask_col:    .word 0
vs_screen_col:  .word 0
vs_dst_work:    .word 0
vs_src_work:    .word 0
vs_screen_work: .word 0
vs_off:         .word 0
vs_x:           .byte 0
vs_y:           .byte 0
vs_width:       .byte 0
vs_height:      .byte 0
vs_color:       .byte 0
vs_flags:       .byte 0
vs_yin:         .byte 0
vs_first_end:   .byte 0
vs_end:         .byte 0
vs_coverage:    .byte 0
vs_value:       .byte 0
vs_tmp:         .byte 0
