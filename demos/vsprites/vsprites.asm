// vsprites.asm - software sprites on an Ultimate 64, an SDK demo.
//
// Balls, diamonds and rings, 32 x 32 hires pixels each, drawn as masked vsprites
// into a double-buffered multicolour bitmap: restore the background under each
// one, move it, draw it again with D = (D AND mask) OR image, wait for the
// raster, flip. Similar to Amiga blitter objects, but done by the 6510 without
// a blitter.
//
// The SDK's part is small and the point: ultimate_turbo_available() says
// whether the machine has turbo registers, ultimate_turbo_set() asks for the
// top speed and ultimate_turbo_badlines() stops the VIC stealing cycles. The
// demo then adds vsprites until the frame is about seven-eighths full and takes
// them away when it overflows, so the same program shows two vsprites on a stock
// 1 MHz C64, 60 on the tested 48 MHz Elite, and more on a 64 MHz machine.
// The border turns grey while the frame is being drawn: that band is the
// render time, the black below it what is left.
//
// Runs from the Ultimate's file browser like any PRG. No KERNAL, no UCI
// commands: a machine with Turbo Control off simply runs at 1 MHz.
//
// Part of the Ultimate SDK. SPDX-License-Identifier: MIT

#import "../../bindings/kickass/uci_protocol.asm"

.const BLOB                = $7000            // bindings/blob, default build
.const ULT_TURBO_AVAILABLE = BLOB + uci.BLOB_ULTIMATE_TURBO_AVAILABLE
.const ULT_TURBO_SET       = BLOB + uci.BLOB_ULTIMATE_TURBO_SET
.const ULT_TURBO_BADLINES  = BLOB + uci.BLOB_ULTIMATE_TURBO_BADLINES

.const STATUS      = $033c        // cassette buffer: the host can watch, see below
.const MAXBOBS     = 128

.const BITMAP_A    = $4000        // bank 1: bitmap $4000, screen $6000
.const SCREEN_A    = $6000
.const SCREEN_B    = $c000        // bank 3: screen $c000, bitmap $e000. Not bank
.const BITMAP_B    = $e000        //   2: the VIC sees character ROM at $9000-$9fff
.const CLEAN       = $a000        // clean background, same layout as a bitmap;
                                  //   CPU-only RAM under BASIC, above the blob
.const D018_A      = $80          // screen at +$2000, bitmap at +$0000
.const D018_B      = $08          // screen at +$0000, bitmap at +$2000

.const BOB_W       = 16           // multicolour pixels
.const BOB_H       = 32           // lines
.const BOB_BYTES   = 5            // 16 px = 4 bytes, plus one for the shift
.const SHAPES      = 3
.const IMG_BYTES   = BOB_BYTES * BOB_H
.const SHIFT_BYTES = IMG_BYTES * 2           // image then mask
.const SEGS        = BOB_H / 8               // cell rows a cell-aligned vsprite spans

.const XMAX        = 160 - BOB_W
.const YMAX        = 200 - BOB_H

.const COL_BG      = $00          // bit pair 00: $d021
.const COL_1       = $0b          // 01: dark grey, grid and vsprite outlines
.const COL_2       = $0e          // 10: light blue, vsprite bodies
.const COL_3       = $01          // 11: white, the highlights

.const VBLANK_LINE = 250
.const START_BOBS  = 4

// zero page
.label zpB    = $02   // 16-bit: vsprite base address (base_0)
.label zpD    = $04   // 16-bit: current dst operand
.label zpS    = $06   // 16-bit: current src (image) operand
.label zpYin  = $08
.label zpE0   = $09
.label zpCol  = $0b
.label zpBob  = $0c
.label zpPtr  = $0d   // 16-bit scratch pointer
.label zpTmp  = $0f
.label zpN    = $10
.label zpEnd  = $11

// ---------------------------------------------------------------------------
// Status block, for a host watching over the REST API. Offsets from STATUS.
//   +0..3   "VSPR"
//   +4..5   frame counter (16-bit LE), one per rendered frame
//   +6..9   CIA cycles spent rendering the last frame (32-bit LE)
//   +10..11 CIA cycles in one raster frame, measured at start (16-bit LE)
//   +12     vsprites drawn in the last frame
//   +13     bank on screen: 0 = bank 1, 1 = bank 2
//   +14     state: 1 = running
//   +15     $d031 as read at start: $ff when the machine has no turbo
//   +16     host: 1 = hold after the next flip until cleared (still frame)
// ---------------------------------------------------------------------------
.label ST_MAGIC   = STATUS + 0
.label ST_FRAMES  = STATUS + 4
.label ST_RENDER  = STATUS + 6
.label ST_FRAME   = STATUS + 10
.label ST_DRAWN   = STATUS + 12
.label ST_FRONT   = STATUS + 13
.label ST_STATE   = STATUS + 14
.label ST_TURBO   = STATUS + 15
.label ST_PAUSE   = STATUS + 16

BasicUpstart2(main)

// ---------------------------------------------------------------------------
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
    lda #$35            // no BASIC, no KERNAL, I/O on: $a000 and $e000 are RAM
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

    // The SDK: is there turbo, and if so, all of it, with badlines off.
    jsr ULT_TURBO_AVAILABLE
    beq !+
    lda #uci.U64_SPEED_MAX
    jsr ULT_TURBO_SET
    lda #0
    jsr ULT_TURBO_BADLINES
!:  lda $d031
    sta ST_TURBO

    jsr build_grid
    jsr copy_background_to_both
    jsr fill_colour
    jsr init_bobs

    // VIC: multicolour bitmap, bank 1 in front, bank 2 as the back buffer
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
    lda #%00000010      // bank 1 = $4000
    sta $dd00

    jsr measure_frame
    lda #1
    sta ST_STATE

frame_loop:
    lda #COL_1
    sta $d020           // the border shows the render time
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
    bne !+
    inc ST_FRAMES+1
!:  lda ST_PAUSE        // the host wants a still frame
    bne !-
    jmp frame_loop

rti_handler:
    rti

dd00_for_front:  .byte %00000010, %00000000   // bank 1 ($4000), bank 3 ($c000)
d018_for_front:  .byte D018_A, D018_B
bitmap_hi_for_buf: .byte >BITMAP_A, >BITMAP_B
clean_delta_hi:  .byte >((CLEAN - BITMAP_A) & $ffff), >((CLEAN - BITMAP_B) & $ffff)

front:     .byte 0               // buffer index on screen
nbobs:     .byte 0
ndirty:    .byte 0, 0            // dirty entries per buffer
drawn_now: .byte 0

// ---------------------------------------------------------------------------
// Fill the frame: one more vsprite when the last render used under three
// quarters of a frame, one fewer when it used more than seven eighths. A
// vsprite is about one per cent of a 48 MHz frame, so this settles in a second.
scale_bobs:
    lda ST_RENDER+2
    ora ST_RENDER+3
    bne fewer           // past 65535 cycles: several frames, certainly too many
    lda ST_RENDER+1
    cmp hi_thresh+1
    bcc !+
    bne fewer
    lda ST_RENDER
    cmp hi_thresh
    bcs fewer
!:  lda ST_RENDER+1
    cmp lo_thresh+1
    bcc more
    bne !+
    lda ST_RENDER
    cmp lo_thresh
    bcc more
!:  rts
more:
    lda nbobs
    cmp #MAXBOBS
    bcs !+
    inc nbobs
!:  rts
fewer:
    lda nbobs
    cmp #2
    bcc !+
    dec nbobs
!:  rts

// One raster frame in CIA cycles, then the two thresholds from it.
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
    lsr zpTmp+1         // frame / 8
    ror zpTmp
    lsr zpTmp+1
    ror zpTmp
    lsr zpTmp+1
    ror zpTmp
    lda ST_FRAME        // high = frame - frame/8
    sec
    sbc zpTmp
    sta hi_thresh
    lda ST_FRAME+1
    sbc zpTmp+1
    sta hi_thresh+1
    lda hi_thresh       // low = high - frame/8
    sec
    sbc zpTmp
    sta lo_thresh
    lda hi_thresh+1
    sbc zpTmp+1
    sta lo_thresh+1
    rts

hi_thresh: .word 0
lo_thresh: .word 0

// ---------------------------------------------------------------------------
wait_vblank:
!:  lda $d012
    cmp #VBLANK_LINE
    beq !-
!:  lda $d012
    cmp #VBLANK_LINE
    bne !-
    rts

// CIA 2 timers A and B chained into one 32-bit down counter. The CIA keeps
// counting at 1 MHz whatever the CPU does, so these are microseconds.
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

// ---------------------------------------------------------------------------
// Background: an 8x8 grid in colour 1. One byte is one multicolour cell row:
// $55 = four pixels of colour 1, $40 = the first pixel only.
build_grid:
    lda #<CLEAN
    sta zpPtr
    lda #>CLEAN
    sta zpPtr+1
    ldx #0              // 1000 cells = 4 * 250
    stx zpTmp
cell:
    ldy #0
    lda #$55
    sta (zpPtr),y
    lda #$40
    iny
!:  sta (zpPtr),y
    iny
    cpy #8
    bne !-
    lda zpPtr
    clc
    adc #8
    sta zpPtr
    bcc !+
    inc zpPtr+1
!:  inc zpTmp
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
cb: .for (var p = 0; p < 32; p++) {
        lda CLEAN + p*256, x
        sta BITMAP_A + p*256, x
        sta BITMAP_B + p*256, x
    }
    inx
    beq !+
    jmp cb
!:  rts

fill_colour:
    lda #(COL_1 << 4) | COL_2
    ldy #0
!:  sta SCREEN_A, y
    sta SCREEN_A+$100, y
    sta SCREEN_A+$200, y
    sta SCREEN_A+$300, y
    sta SCREEN_B, y
    sta SCREEN_B+$100, y
    sta SCREEN_B+$200, y
    sta SCREEN_B+$300, y
    iny
    bne !-
    lda #COL_3
!:  sta $d800, y
    sta $d900, y
    sta $da00, y
    sta $db00, y
    iny
    bne !-
    rts

// ---------------------------------------------------------------------------
// Vsprites: position, velocity, shape. Every slot is set up at the start, so a
// vsprite that scale_bobs brings in later is already somewhere sensible.
init_bobs:
    ldx #0
!:  jsr lfsr
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
    lsr
    and #3
    tay
    lda vel_table, y
    sta bdy, x
    txa
    lsr
    lsr
    and #3
    cmp #SHAPES
    bcc !+
    lda #0
!:  sta bshape, x
    inx
    cpx #MAXBOBS
    bne !--
    rts

vel_table: .byte 1, 2, -1, -2

// Two 8-bit maximal LFSRs: x^8+x^6+x^5+x^4+1 and x^8+x^6+x^4+x^2+1.
lfsr:
    lda seed
    asl
    bcc !+
    eor #$1d
!:  sta seed
    rts
seed: .byte $a7

lfsr2:
    lda seed2
    asl
    bcc !+
    eor #$2b
!:  sta seed2
    rts
seed2: .byte $3c

mod_xmax:
!:  cmp #XMAX
    bcc !+
    sbc #XMAX
    jmp !-
!:  rts

mod_ymax:
!:  cmp #YMAX
    bcc !+
    sbc #YMAX
    jmp !-
!:  rts

move_bobs:
    ldx #0
mv: lda bx, x
    clc
    adc bdx, x
    cmp #XMAX           // a wrapped negative is >= 254, so this catches both edges
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

// ---------------------------------------------------------------------------
// Vsprite address arithmetic. For a vsprite at (x, y) in the buffer at
// BUF, row r of column c lives at
//     BUF + ((y+r)>>3)*320 + (x>>2 + c)*8 + ((y+r)&7)
// Rows that share a cell row are consecutive bytes, so with
//     base_j = BUF + y + (x>>2)*8 + (cellrow + j)*312
// the byte for row r in cell-row segment j is simply base_j + r, and one
// index register walks image, mask and destination together.
//
// compute_base: X = vsprite index -> zpB = base_0 (without BUF), zpYin, zpE0
compute_base:
    lda by, x
    sta zpTmp
    and #7
    sta zpYin
    lda #8
    sec
    sbc zpYin
    sta zpE0            // rows 0..E0-1 are in the first cell row; then 8 each
    lda zpTmp
    lsr
    lsr
    lsr
    tay                 // cell row
    lda rowbase_lo, y
    clc
    adc zpTmp           // + y
    sta zpB
    lda rowbase_hi, y
    adc #0
    sta zpB+1
    lda bx, x
    lsr
    lsr
    tay
    lda xoff_lo, y      // + (x>>2)*8
    clc
    adc zpB
    sta zpB
    lda xoff_hi, y
    adc zpB+1
    sta zpB+1
    rts

// ---------------------------------------------------------------------------
// Restore every rectangle drawn into the back buffer the last time it was
// drawn to. Whole 8-byte cell-row segments are copied: cheaper than exact rows
// and harmless, because every restore happens before any draw.
restore_back:
    lda front
    eor #1
    tay                 // back buffer index
    lda ndirty, y
    bne !+
    rts
!:  sta zpN
    lda bitmap_hi_for_buf, y
    sta rbuf_hi
    lda clean_delta_hi, y
    sta rdelta_hi
    tya
    asl
    tay
    lda dl_lo_tab, y
    sta rd_lo+1
    lda dl_lo_tab+1, y
    sta rd_lo+2
    lda dl_hi_tab, y
    sta rd_hi+1
    lda dl_hi_tab+1, y
    sta rd_hi+2
    lda dl_yin_tab, y
    sta rd_yin+1
    lda dl_yin_tab+1, y
    sta rd_yin+2
    ldx #0
rloop:
    stx zpBob
rd_lo:
    lda $ffff, x
    sta zpD
rd_hi:
    lda $ffff, x
    sta zpD+1
rd_yin:
    lda $ffff, x
    sta zpYin
    // aligned start = base_0 - yin + BUF
    lda zpD
    sec
    sbc zpYin
    sta zpD
    bcs !+
    dec zpD+1
!:  lda zpD+1
    clc
    adc rbuf_hi
    sta zpD+1
    lda #SEGS
    ldy zpYin
    beq !+
    lda #SEGS+1
!:  sta rsegs
    lda #BOB_BYTES
    sta zpCol
rcol:
    lda zpD
    sta zpS
    lda zpD+1
    sta zpS+1
    lda rsegs
    sta rseg
rseg_loop:
    lda zpS
    sta rs0+1
    sta rd0+1
    lda zpS+1
    sta rd0+2
    clc
    adc rdelta_hi
    sta rs0+2
    ldy #7
rcopy:
rs0:
    lda $ffff, y
rd0:
    sta $ffff, y
    dey
    bpl rcopy
    lda zpS
    clc
    adc #<320
    sta zpS
    lda zpS+1
    adc #>320
    sta zpS+1
    dec rseg
    bne rseg_loop
    lda zpD
    clc
    adc #8
    sta zpD
    bcc !+
    inc zpD+1
!:  dec zpCol
    beq !+
    jmp rcol
!:  ldx zpBob
    inx
    cpx zpN
    beq rdone
    jmp rloop
rdone:
    rts

rbuf_hi:   .byte 0
rdelta_hi: .byte 0
rsegs:     .byte 0
rseg:      .byte 0

// ---------------------------------------------------------------------------
// Draw every vsprite into the back buffer and record where, for the restore.
draw_all:
    lda front
    eor #1
    tay
    lda nbobs
    sta ndirty, y
    sta drawn_now
    sta zpN
    lda bitmap_hi_for_buf, y
    sta dbuf_hi
    tya
    asl
    tay
    lda dl_lo_tab, y
    sta dw_lo+1
    lda dl_lo_tab+1, y
    sta dw_lo+2
    lda dl_hi_tab, y
    sta dw_hi+1
    lda dl_hi_tab+1, y
    sta dw_hi+2
    lda dl_yin_tab, y
    sta dw_yin+1
    lda dl_yin_tab+1, y
    sta dw_yin+2
    ldx #0
dloop:
    stx zpBob
    jsr compute_base
    lda zpB
dw_lo:
    sta $ffff, x
    lda zpB+1
dw_hi:
    sta $ffff, x
    lda zpYin
dw_yin:
    sta $ffff, x
    // dst = base_0 + BUF
    lda zpB+1
    clc
    adc dbuf_hi
    sta zpB+1
    // src = image for this shape and shift
    lda bx, x
    and #3
    sta zpTmp
    lda bshape, x
    asl
    asl
    ora zpTmp
    tay
    lda imgbase_lo, y
    sta zpS
    lda imgbase_hi, y
    sta zpS+1
    lda #BOB_BYTES
    sta zpCol
dcol:
    lda zpS
    sta dimg+1
    clc
    adc #IMG_BYTES
    sta dmsk+1
    lda zpS+1
    sta dimg+2
    adc #0
    sta dmsk+2
    lda zpB
    sta zpD
    sta dld+1
    sta dst+1
    lda zpB+1
    sta zpD+1
    sta dld+2
    sta dst+2
    lda zpE0
    sta zpEnd
    ldx #0
dseg:
dld:
    lda $ffff, x
dmsk:
    and $ffff, x
dimg:
    ora $ffff, x
dst:
    sta $ffff, x
    inx
    cpx zpEnd
    bne dseg
    cpx #BOB_H
    beq dcol_done
    lda zpD
    clc
    adc #<312
    sta zpD
    sta dld+1
    sta dst+1
    lda zpD+1
    adc #>312
    sta zpD+1
    sta dld+2
    sta dst+2
    lda zpEnd
    clc
    adc #8
    cmp #BOB_H
    bcc !+
    lda #BOB_H
!:  sta zpEnd
    jmp dseg
dcol_done:
    lda zpB
    clc
    adc #8
    sta zpB
    bcc !+
    inc zpB+1
!:  lda zpS
    clc
    adc #BOB_H
    sta zpS
    bcc !+
    inc zpS+1
!:  dec zpCol
    beq !+
    jmp dcol
!:  ldx zpBob
    inx
    cpx zpN
    beq !+
    jmp dloop
!:  rts

dbuf_hi: .byte 0

// ---------------------------------------------------------------------------
// Tables
dl_lo_tab:  .word dirtyA_lo, dirtyB_lo
dl_hi_tab:  .word dirtyA_hi, dirtyB_hi
dl_yin_tab: .word dirtyA_yin, dirtyB_yin

rowbase_lo: .fill 25, <(i*312)
rowbase_hi: .fill 25, >(i*312)
xoff_lo:    .fill 40, <(i*8)
xoff_hi:    .fill 40, >(i*8)
imgbase_lo: .fill SHAPES*4, <(bobdata + i*SHIFT_BYTES)
imgbase_hi: .fill SHAPES*4, >(bobdata + i*SHIFT_BYTES)

.align $100
bx:         .fill MAXBOBS, 0
by:         .fill MAXBOBS, 0
bdx:        .fill MAXBOBS, 0
bdy:        .fill MAXBOBS, 0
bshape:     .fill MAXBOBS, 0
dirtyA_lo:  .fill MAXBOBS, 0
dirtyA_hi:  .fill MAXBOBS, 0
dirtyA_yin: .fill MAXBOBS, 0
dirtyB_lo:  .fill MAXBOBS, 0
dirtyB_hi:  .fill MAXBOBS, 0
dirtyB_yin: .fill MAXBOBS, 0

// ---------------------------------------------------------------------------
// Vsprite images, generated at assembly time. pix() returns the colour index
// (0 transparent, 1..3 = bit pairs 01, 10, 11) of a shape. Each shape is
// stored four times, pre-shifted by 0..3 multicolour pixels into a 5-byte-wide
// column-major image followed by its mask (11 where transparent).
//
// Shapes are defined on a unit square, so a ball is round in screen space
// whatever the pixel aspect: dx and dy run -8..8 across width and height.
.function pix(k, x, y) {
    .var dx = (x + 0.5) * 16 / BOB_W - 8
    .var dy = (y + 0.5) * 16 / BOB_H - 8
    .var d = sqrt(dx*dx + dy*dy)
    .if (k == 0) {                       // shaded ball
        .if (d > 7.9) .return 0
        .if (sqrt((dx+2.7)*(dx+2.7) + (dy+2.7)*(dy+2.7)) < 2.3) .return 3
        .if (d > 6.4) .return 1
        .return 2
    }
    .if (k == 1) {                       // diamond
        .var m = abs(dx) + abs(dy)
        .if (m > 7.9) .return 0
        .if (m > 6.2) .return 1
        .if (m < 2.6) .return 3
        .return 2
    }
    .if (d > 7.9) .return 0              // ring
    .if (d < 3.6) .return 0
    .if (d > 6.6 || d < 4.8) .return 1
    .if (dy < -2 && dx < 0) .return 3
    .return 2
}

.function imgByte(k, s, i, isMask) {
    .var col = floor(i / BOB_H)
    .var row = mod(i, BOB_H)
    .var b = 0
    .for (var p = 0; p < 4; p++) {
        .var px = col*4 + p - s
        .var v = 0
        .if (px >= 0 && px < 16) .eval v = pix(k, px, row)
        .if (isMask) {
            .if (v == 0) .eval b = b | (3 << (6 - 2*p))
        } else {
            .eval b = b | (v << (6 - 2*p))
        }
    }
    .return b
}

bobdata:
.for (var k = 0; k < SHAPES; k++) {
    .for (var s = 0; s < 4; s++) {
        .fill IMG_BYTES, imgByte(k, s, i, false)
        .fill IMG_BYTES, imgByte(k, s, i, true)
    }
}

// ---------------------------------------------------------------------------
// The SDK, as the standalone blob, at its default address.
.pc = BLOB "Ultimate SDK"
.import binary "../../bindings/blob/build/ultimate-7000.bin"
