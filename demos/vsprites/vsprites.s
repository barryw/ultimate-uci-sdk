; vsprites.s - software sprites on an Ultimate 64, an SDK demo.
;
; Balls, diamonds and rings, 32 x 32 hires pixels each, drawn as masked vsprites
; into a double-buffered multicolour bitmap: restore the background under each
; one, move it, draw it again with D = (D AND mask) OR image, wait for the
; raster, flip. Similar to Amiga blitter objects, but done by the 6510 without
; a blitter.
;
; The SDK's part is small and the point: ultimate_turbo_available() says
; whether the machine has turbo registers, ultimate_turbo_set() asks for the
; top speed, ultimate_turbo_badlines() stops the VIC stealing cycles, and
; ultimate_vsprite_draw() does the restore and masked compositing. The demo
; adds vsprites until the frame is about seven-eighths full and takes them away
; when it overflows, so the same program shows one vsprite on a stock
; 1 MHz C64 and 39 on the tested 48 MHz Elite.
; The border turns grey while the frame is being drawn: that band is the
; render time, the black below it what is left.
;
; Runs from the Ultimate's file browser like any PRG. No KERNAL, no UCI
; commands: a machine with Turbo Control off simply runs at 1 MHz.
;
; Part of the Ultimate SDK. SPDX-License-Identifier: MIT

.include "ultimate.inc"
.segment "LOADADDR"
.word $0801
.segment "STARTUP"
.word $080b, 10
.byte $9e, "2304", 0
.word 0
.segment "DEMO"

STATUS = $033c        ; cassette buffer: the host can watch, see below
MAXBOBS = 128

BITMAP_A = $4000        ; bank 1: bitmap $4000, screen $6000
SCREEN_A = $6000
SCREEN_B = $c000        ; bank 3: screen $c000, bitmap $e000. Not bank
BITMAP_B = $e000        ;   2: the VIC sees character ROM at $9000-$9fff
CLEAN = $a000        ; clean background, same layout as a bitmap;
                                  ;   CPU-only RAM under BASIC
D018_A = $80          ; screen at +$2000, bitmap at +$0000
D018_B = $08          ; screen at +$0000, bitmap at +$2000

BOB_W = 16           ; multicolour pixels
BOB_H = 32           ; lines
BOB_BYTES = 5            ; 16 px = 4 bytes, plus one for the shift
SHAPES = 3
IMG_BYTES = BOB_BYTES * BOB_H
SHIFT_BYTES = IMG_BYTES * 2           ; image then mask
XMAX = 160 - BOB_W
YMAX = 200 - BOB_H

COL_BG = $00          ; bit pair 00: $d021
COL_1 = $0b          ; 01: dark grey, grid and vsprite outlines
COL_2 = $0e          ; 10: light blue, vsprite bodies
COL_3 = $01          ; 11: white, the highlights

VBLANK_LINE = 250
START_BOBS = 4

; zero page
zpBob = $0c
zpPtr = $0d   ; 16-bit scratch pointer
zpTmp = $0f
zpN = $10

; ---------------------------------------------------------------------------
; Status block, for a host watching over the REST API. Offsets from STATUS.
;   +0..3   "VSPR"
;   +4..5   frame counter (16-bit LE), one per rendered frame
;   +6..9   CIA cycles spent rendering the last frame (32-bit LE)
;   +10..11 CIA cycles in one raster frame, measured at start (16-bit LE)
;   +12     vsprites drawn in the last frame
;   +13     bank on screen: 0 = bank 1, 1 = bank 3
;   +14     state: 1 = running
;   +15     $d031 as read at start: $ff when the machine has no turbo
;   +16     host: 1 = hold after the next flip until cleared (still frame)
; ---------------------------------------------------------------------------
ST_MAGIC = STATUS + 0
ST_FRAMES = STATUS + 4
ST_RENDER = STATUS + 6
ST_FRAME = STATUS + 10
ST_DRAWN = STATUS + 12
ST_FRONT = STATUS + 13
ST_STATE = STATUS + 14
ST_TURBO = STATUS + 15
ST_PAUSE = STATUS + 16


; ---------------------------------------------------------------------------
main:
    sei
    lda #$7f
    sta $dc0d
    sta $dd0d
    lda $dc0d
    lda $dd0d
    lda #$00
    sta $d01a
    sta $d015
    lda #$35            ; no BASIC, no KERNAL, I/O on: $a000 and $e000 are RAM
    sta $01
    lda #<rti_handler
    sta $fffa
    sta $fffe
    lda #>rti_handler
    sta $fffb
    sta $ffff

    lda #'V'
    sta ST_MAGIC+0
    lda #'S'
    sta ST_MAGIC+1
    lda #'P'
    sta ST_MAGIC+2
    lda #'R'
    sta ST_MAGIC+3
    lda #0
    sta ST_FRAMES
    sta ST_FRAMES+1
    sta ST_STATE
    sta ST_PAUSE
    sta front
    sta ndirty
    sta ndirty+1
    lda #START_BOBS
    sta nbobs

    ; The SDK: is there turbo, and if so, all of it, with badlines off.
    jsr ultimate_turbo_available
    beq local_vsprites_0
    lda #U64_SPEED_MAX
    jsr ultimate_turbo_set
    lda #0
    jsr ultimate_turbo_badlines
local_vsprites_0:  lda $d031
    sta ST_TURBO

    jsr build_grid
    jsr copy_background_to_both
    jsr fill_colour
    jsr init_bobs

    ; VIC: multicolour bitmap, bank 1 in front, bank 3 as the back buffer
    lda $dd02
    ora #$03
    sta $dd02
    lda #$3b
    sta $d011
    lda #$d8
    sta $d016
    lda #D018_A
    sta $d018
    lda #COL_BG
    sta $d020
    sta $d021
    lda #%00000010      ; bank 1 = $4000
    sta $dd00

    jsr measure_frame
    lda #1
    sta ST_STATE

frame_loop:
    lda #COL_1
    sta $d020           ; the border shows the render time
    jsr timer_start
    jsr restore_back
    jsr move_bobs
    jsr draw_all
    jsr timer_stop
    lda drawn_now
    sta ST_DRAWN
    jsr scale_bobs
    lda #COL_BG
    sta $d020
    jsr wait_vblank
    lda front
    eor #1
    sta front
    sta ST_FRONT
    tax
    lda dd00_for_front,x
    sta $dd00
    lda d018_for_front,x
    sta $d018
    inc ST_FRAMES
    bne local_vsprites_1
    inc ST_FRAMES+1
local_vsprites_1:  lda ST_PAUSE        ; the host wants a still frame
    bne local_vsprites_1
    jmp frame_loop

rti_handler:
    rti

dd00_for_front:  .byte %00000010, %00000000   ; bank 1 ($4000), bank 3 ($c000)
d018_for_front:  .byte D018_A, D018_B
bitmap_hi_for_buf: .byte >BITMAP_A, >BITMAP_B

front:     .byte 0               ; buffer index on screen
nbobs:     .byte 0
ndirty:    .byte 0, 0            ; dirty entries per buffer
drawn_now: .byte 0

; ---------------------------------------------------------------------------
; Fill the frame: one more vsprite when the last render used under three
; quarters of a frame, one fewer when it used more than seven eighths.
scale_bobs:
    lda ST_RENDER+2
    ora ST_RENDER+3
    bne fewer           ; past 65535 cycles: several frames, certainly too many
    lda ST_RENDER+1
    cmp hi_thresh+1
    bcc local_vsprites_2
    bne fewer
    lda ST_RENDER
    cmp hi_thresh
    bcs fewer
local_vsprites_2:  lda ST_RENDER+1
    cmp lo_thresh+1
    bcc more
    bne local_vsprites_3
    lda ST_RENDER
    cmp lo_thresh
    bcc more
local_vsprites_3:  rts
more:
    lda nbobs
    cmp #MAXBOBS
    bcs local_vsprites_4
    inc nbobs
local_vsprites_4:  rts
fewer:
    lda nbobs
    cmp #2
    bcc local_vsprites_5
    dec nbobs
local_vsprites_5:  rts

; One raster frame in CIA cycles, then the two thresholds from it.
measure_frame:
    jsr wait_vblank
    jsr timer_start
    jsr wait_vblank
    jsr timer_stop
    lda ST_RENDER
    sta ST_FRAME
    sta zpTmp
    lda ST_RENDER+1
    sta ST_FRAME+1
    sta zpTmp+1
    lsr zpTmp+1         ; frame / 8
    ror zpTmp
    lsr zpTmp+1
    ror zpTmp
    lsr zpTmp+1
    ror zpTmp
    lda ST_FRAME        ; high = frame - frame/8
    sec
    sbc zpTmp
    sta hi_thresh
    lda ST_FRAME+1
    sbc zpTmp+1
    sta hi_thresh+1
    lda hi_thresh       ; low = high - frame/8
    sec
    sbc zpTmp
    sta lo_thresh
    lda hi_thresh+1
    sbc zpTmp+1
    sta lo_thresh+1
    rts

hi_thresh: .word 0
lo_thresh: .word 0

; ---------------------------------------------------------------------------
wait_vblank:
local_vsprites_6:  lda $d012
    cmp #VBLANK_LINE
    beq local_vsprites_6
local_vsprites_7:  lda $d012
    cmp #VBLANK_LINE
    bne local_vsprites_7
    rts

; CIA 2 timers A and B chained into one 32-bit down counter. The CIA keeps
; counting at 1 MHz whatever the CPU does, so these are microseconds.
timer_start:
    lda #0
    sta $dd0e
    sta $dd0f
    lda #$ff
    sta $dd04
    sta $dd05
    sta $dd06
    sta $dd07
    lda #$51
    sta $dd0f
    lda #$11
    sta $dd0e
    rts

timer_stop:
    lda #0
    sta $dd0e
    sta $dd0f
    lda #$ff
    sec
    sbc $dd04
    sta ST_RENDER+0
    lda #$ff
    sbc $dd05
    sta ST_RENDER+1
    lda #$ff
    sec
    sbc $dd06
    sta ST_RENDER+2
    lda #$ff
    sbc $dd07
    sta ST_RENDER+3
    rts

; ---------------------------------------------------------------------------
; Background: an 8x8 grid in colour 1. One byte is one multicolour cell row:
; $55 = four pixels of colour 1, $40 = the first pixel only.
build_grid:
    lda #<CLEAN
    sta zpPtr
    lda #>CLEAN
    sta zpPtr+1
    ldx #0              ; 1000 cells = 4 * 250
    stx zpTmp
cell:
    ldy #0
    lda #$55
    sta (zpPtr),y
    lda #$40
    iny
local_vsprites_8:  sta (zpPtr),y
    iny
    cpy #8
    bne local_vsprites_8
    lda zpPtr
    clc
    adc #8
    sta zpPtr
    bcc local_vsprites_9
    inc zpPtr+1
local_vsprites_9:  inc zpTmp
    lda zpTmp
    cmp #250
    bne cell
    lda #0
    sta zpTmp
    inx
    cpx #4
    bne cell
    rts

copy_background_to_both:
    ldx #0
cb: .repeat 32, p

        lda CLEAN + p*256, x
        sta BITMAP_A + p*256, x
        sta BITMAP_B + p*256, x
    .endrepeat
    inx
    beq local_vsprites_10
    jmp cb
local_vsprites_10:  rts

fill_colour:
    lda #(COL_1 << 4) | COL_2
    ldy #0
local_vsprites_11:  sta SCREEN_A, y
    sta SCREEN_A+$100, y
    sta SCREEN_A+$200, y
    sta SCREEN_A+$300, y
    sta SCREEN_B, y
    sta SCREEN_B+$100, y
    sta SCREEN_B+$200, y
    sta SCREEN_B+$300, y
    iny
    bne local_vsprites_11
    lda #COL_3
local_vsprites_12:  sta $d800, y
    sta $d900, y
    sta $da00, y
    sta $db00, y
    iny
    bne local_vsprites_12
    rts

; ---------------------------------------------------------------------------
; Vsprites: position, velocity, shape. Every slot is set up at the start, so a
; vsprite that scale_bobs brings in later is already somewhere sensible.
init_bobs:
    ldx #0
local_vsprites_13:  jsr lfsr
    jsr mod_xmax
    sta bx, x
    jsr lfsr2
    jsr mod_ymax
    sta by, x
    txa
    and #3
    tay
    lda vel_table, y
    sta bdx, x
    txa
    lsr a
    and #3
    tay
    lda vel_table, y
    sta bdy, x
    txa
    lsr a
    lsr a
    and #3
    cmp #SHAPES
    bcc local_vsprites_14
    lda #0
local_vsprites_14:  sta bshape, x
    inx
    cpx #MAXBOBS
    bne local_vsprites_13
    rts

vel_table: .byte 1, 2, $ff, $fe

; Two 8-bit maximal LFSRs: x^8+x^6+x^5+x^4+1 and x^8+x^6+x^4+x^2+1.
lfsr:
    lda seed
    asl a
    bcc local_vsprites_15
    eor #$1d
local_vsprites_15:  sta seed
    rts
seed: .byte $a7

lfsr2:
    lda seed2
    asl a
    bcc local_vsprites_16
    eor #$2b
local_vsprites_16:  sta seed2
    rts
seed2: .byte $3c

mod_xmax:
local_vsprites_17:  cmp #XMAX
    bcc local_vsprites_18
    sbc #XMAX
    jmp local_vsprites_17
local_vsprites_18:  rts

mod_ymax:
local_vsprites_19:  cmp #YMAX
    bcc local_vsprites_20
    sbc #YMAX
    jmp local_vsprites_19
local_vsprites_20:  rts

move_bobs:
    ldx #0
mv: lda bx, x
    clc
    adc bdx, x
    cmp #XMAX           ; a wrapped negative is >= 254, so this catches both edges
    bcc storex
    lda bdx, x
    eor #$ff
    clc
    adc #1
    sta bdx, x
    lda bx, x
    clc
    adc bdx, x
storex:
    sta bx, x
    lda by, x
    clc
    adc bdy, x
    cmp #YMAX
    bcc storey
    lda bdy, x
    eor #$ff
    clc
    adc #1
    sta bdy, x
    lda by, x
    clc
    adc bdy, x
storey:
    sta by, x
    inx
    cpx nbobs
    bne mv
    rts

; ---------------------------------------------------------------------------
; Restore and draw through the SDK's reusable software-vsprite primitive.
; Movement, buffering and the object list remain demo policy.
restore_back:
    lda front
    eor #1
    tay
    lda ndirty, y
    bne local_vsprites_21
    rts
local_vsprites_21:  sta zpN
    lda bitmap_hi_for_buf, y
    sta vs_desc + VSPRITE_BITMAP + 1
    lda #<CLEAN
    sta vs_desc + VSPRITE_SOURCE
    lda #>CLEAN
    sta vs_desc + VSPRITE_SOURCE + 1
    tya
    asl a
    tay
    lda dirty_x_tab, y
    sta rd_x+1
    lda dirty_x_tab+1, y
    sta rd_x+2
    lda dirty_y_tab, y
    sta rd_y+1
    lda dirty_y_tab+1, y
    sta rd_y+2
    lda #VSPRITE_F_COPY
    sta vs_desc + VSPRITE_FLAGS
    ldx #0
rloop:
    stx zpBob
rd_x:
    lda $ffff, x
    sta vs_desc + VSPRITE_X
rd_y:
    lda $ffff, x
    pha
    and #$f8
    sta vs_desc + VSPRITE_Y
    pla
    and #7
    beq local_vsprites_22
    lda #BOB_H+8
    bne set_restore_height
local_vsprites_22:  lda #BOB_H
set_restore_height:
    sta vs_desc + VSPRITE_HEIGHT
    lda #<vs_desc
    ldx #>vs_desc
    jsr ultimate_vsprite_draw
    ldx zpBob
    inx
    cpx zpN
    beq local_vsprites_23
    jmp rloop
local_vsprites_23:
    rts

draw_all:
    lda front
    eor #1
    tay
    lda nbobs
    sta ndirty, y
    sta drawn_now
    sta zpN
    lda bitmap_hi_for_buf, y
    sta vs_desc + VSPRITE_BITMAP + 1
    tya
    asl a
    tay
    lda dirty_x_tab, y
    sta dw_x+1
    lda dirty_x_tab+1, y
    sta dw_x+2
    lda dirty_y_tab, y
    sta dw_y+1
    lda dirty_y_tab+1, y
    sta dw_y+2
    lda #BOB_H
    sta vs_desc + VSPRITE_HEIGHT
    lda #VSPRITE_F_MASKED
    sta vs_desc + VSPRITE_FLAGS
    ldx #0
dloop:
    stx zpBob
    lda bx, x
    and #3
    sta zpTmp
    lda bx, x
    lsr a
    lsr a
    sta vs_desc + VSPRITE_X
dw_x:
    sta $ffff, x
    lda by, x
    sta vs_desc + VSPRITE_Y
dw_y:
    sta $ffff, x
    lda bshape, x
    asl a
    asl a
    ora zpTmp
    tay
    lda imgbase_lo, y
    sta vs_desc + VSPRITE_SOURCE
    clc
    adc #<IMG_BYTES
    sta vs_desc + VSPRITE_MASK
    lda imgbase_hi, y
    sta vs_desc + VSPRITE_SOURCE + 1
    adc #>IMG_BYTES
    sta vs_desc + VSPRITE_MASK + 1
    lda #<vs_desc
    ldx #>vs_desc
    jsr ultimate_vsprite_draw
    ldx zpBob
    inx
    cpx zpN
    beq local_vsprites_24
    jmp dloop
local_vsprites_24:  rts

; ---------------------------------------------------------------------------
; Tables
dirty_x_tab: .word dirtyA_x, dirtyB_x
dirty_y_tab: .word dirtyA_y, dirtyB_y
imgbase_lo: .repeat SHAPES*4, i
.byte <(bobdata + i*SHIFT_BYTES)
    .endrepeat
imgbase_hi: .repeat SHAPES*4, i
.byte >(bobdata + i*SHIFT_BYTES)
    .endrepeat

vs_desc:
    .word BITMAP_A
    .word CLEAN
    .word 0
    .word 0
    .byte 0, 0, BOB_BYTES, BOB_H, 0, 0

.align $100
bx:         .repeat MAXBOBS, i
.byte 0
    .endrepeat
by:         .repeat MAXBOBS, i
.byte 0
    .endrepeat
bdx:        .repeat MAXBOBS, i
.byte 0
    .endrepeat
bdy:        .repeat MAXBOBS, i
.byte 0
    .endrepeat
bshape:     .repeat MAXBOBS, i
.byte 0
    .endrepeat
dirtyA_x:   .repeat MAXBOBS, i
.byte 0
    .endrepeat
dirtyA_y:   .repeat MAXBOBS, i
.byte 0
    .endrepeat
dirtyB_x:   .repeat MAXBOBS, i
.byte 0
    .endrepeat
dirtyB_y:   .repeat MAXBOBS, i
.byte 0
    .endrepeat

; Pre-shifted shapes generated by gen_shapes.py.
bobdata:
.incbin "build/shapes.bin"
