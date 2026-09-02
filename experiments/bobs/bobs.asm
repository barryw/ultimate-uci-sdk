// bobs.asm - software sprite ("bob") experiment for Ultimate 64 turbo.
//
// Multicolour bitmap, double-buffered across two VIC banks, a clean copy of the
// background under the KERNAL ROM, and N 16-pixel-wide multicolour bobs blitted
// with a mask every frame. Restore-from-clean then masked draw, exactly the
// Amiga blitter's D = (A & ~M) | B, done by the 6510 under turbo.
//
// Six colour modes, chosen at run time by the host, to show what the VIC-II
// allows (see the design doc):
//   0  one four-colour palette for the whole playfield (grid background)
//   1  every bob owns its 01/10 colours, written into screen RAM cells
//   2  mode 1 plus the 11 colour per bob, written into colour RAM after the flip
//   3  mode 1 plus eight hardware sprites on top
//   4  mode 1 with dithered shapes, five apparent shades from three colours
//   5  mode 1 plus palette animation through the SDK blob (fade, then cycling)
//
// The host drives it through a control block in the cassette buffer and reads
// the timing back over the Ultimate's REST API. No KERNAL. The SDK blob, when
// mode 5 wants it, is written to $3400 by the host. SPDX-License-Identifier: MIT

.const STATUS      = $033c        // control/status block, see layout below
.const MAXBOBS     = 200

.const BLOB        = $3400        // bindings/blob built with BASE=3400; variables at $9f00
.const BLOB_INIT   = BLOB + $1c   // ultimate_init
.const BLOB_PALGET = BLOB + $37   // ultimate_palette_get   A/X = 48-byte buffer
.const BLOB_PALSET = BLOB + $3a   // ultimate_palette_set   A/X = 48 bytes RGB
.const BLOB_PALRST = BLOB + $40   // ultimate_palette_reset

.const SCREEN_A    = $5c00        // bank 1: screen $5c00, bitmap $6000
.const BITMAP_A    = $6000
.const SCREEN_B    = $8000        // bank 2: screen $8000, bitmap $a000
.const BITMAP_B    = $a000
.const CLEAN       = $e000        // clean background, same layout as a bitmap
.const SPRDATA_A   = $5b00        // one 63-byte hardware sprite, in each bank
.const SPRDATA_B   = $9b00
.const SPRPTR      = (SPRDATA_A - $4000) / 64   // same pointer in both banks
.const D018_A      = $78          // screen at +$1c00, bitmap at +$2000
.const D018_B      = $08          // screen at +$0000, bitmap at +$2000

.const BOB_W       = 16           // multicolour pixels
.const BOB_H       = cmdLineVars.containsKey("BOB_H") ? cmdLineVars.get("BOB_H").asNumber() : 16
.const BOB_BYTES   = 5            // 16 px = 4 bytes, plus one for the shift
.const SHAPES      = 4            // ball, diamond, ring, dithered ball
.const IMG_BYTES   = BOB_BYTES * BOB_H
.const SHIFT_BYTES = IMG_BYTES * 2           // image then mask
.const SHAPE_BYTES = SHIFT_BYTES * 4         // four shifts
.const SEGS        = BOB_H / 8               // cell rows a cell-aligned bob spans

.const XMAX        = 160 - BOB_W
.const YMAX        = 200 - BOB_H

.const COL_BG      = $00          // mode 0: bit pair 00
.const COL_1       = $0b          // mode 0: 01 (grid)
.const COL_2       = $0e          // mode 0: 10 (bob body)
.const COL_3       = $01          // mode 0: 11 (bob light)
.const STAR_COL    = $01          // modes 1-5: colour RAM, stars and bob highlights
.const CLEAN_CELL  = $00          // modes 1-5: screen RAM under nothing

.const VBLANK_LINE = 250
.const NSPRITES    = 8

// zero page
.label zpB    = $02   // 16-bit: bob base address (base_0)
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
.label zpCr   = $12   // cell row of the bob being drawn
.label zpCb   = $13   // byte column
.label zpSoff = $14   // 16-bit: screen cell offset, cellrow*40 + column
.label zpSegs = $16
.label zpCnt  = $17

// ---------------------------------------------------------------------------
// Status block (host <-> C64). Offsets from STATUS.
//   +0..3   "BOBS"
//   +4      host: requested speed index 0-15, $ff = leave alone
//   +5      host: 1 = badlines off, 0 = on
//   +6      host: number of bobs 1..MAXBOBS
//   +7      c64:  $d031 as read back after applying
//   +8..9   c64:  frame counter (16-bit LE), one per rendered frame
//   +10..13 c64:  CIA cycles spent rendering the last frame (32-bit LE)
//   +14..17 c64:  CIA cycles for ten raster frames, measured at start
//   +18     c64:  bobs drawn in the last frame
//   +19     c64:  bank now on screen: 0 = bank 1, 1 = bank 2
//   +20     c64:  state: 1 = running
//   +21     host: 1 = run the copy micro-benchmarks once (needs the REU on)
//   +22..25 c64:  CIA cycles for a 4096-byte REU fetch (REU -> C64)
//   +26..29 c64:  CIA cycles for a 4096-byte CPU copy, lda/sta abs,x unrolled
//   +30..33 c64:  CIA cycles for a 4096-byte REU stash (C64 -> REU)
//   +34     host: colour mode 0-5
//   +35     c64:  mode in effect
//   +36     c64:  blob result: SDK code from the last palette call, $fe = no
//                 blob signature at $3400, $ff = not tried
//   +37     host: 1 = hold after the next flip until cleared, so the host can
//                 read a complete front buffer
// ---------------------------------------------------------------------------
.label ST_MAGIC   = STATUS + 0
.label ST_SPEED   = STATUS + 4
.label ST_NOBAD   = STATUS + 5
.label ST_NBOBS   = STATUS + 6
.label ST_D031    = STATUS + 7
.label ST_FRAMES  = STATUS + 8
.label ST_RENDER  = STATUS + 10
.label ST_TENFR   = STATUS + 14
.label ST_DRAWN   = STATUS + 18
.label ST_FRONT   = STATUS + 19
.label ST_STATE   = STATUS + 20
.label ST_TEST    = STATUS + 21
.label ST_REUFET  = STATUS + 22
.label ST_CPUCPY  = STATUS + 26
.label ST_REUSTA  = STATUS + 30
.label ST_MODE    = STATUS + 34
.label ST_MODEACK = STATUS + 35
.label ST_BLOB    = STATUS + 36
.label ST_PAUSE   = STATUS + 37
.label ST_PROBE   = STATUS + 38   // host: 1 = blob init then identify, 2 = identify only
.label ST_PINIT   = STATUS + 39   // c64: result of ultimate_init
.label ST_PIDENT  = STATUS + 40   // c64: result of ultimate_identify(control target)

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

    // status block
    lda #'B'
    sta ST_MAGIC+0
    sta ST_MAGIC+2
    lda #'O'
    sta ST_MAGIC+1
    lda #'S'
    sta ST_MAGIC+3
    lda #$ff
    sta ST_SPEED
    sta ST_BLOB
    lda #0
    sta ST_NOBAD
    sta ST_TEST
    sta ST_MODE
    sta ST_PAUSE
    sta ST_PROBE
    sta ST_FRAMES
    sta ST_FRAMES+1
    sta ST_STATE
    lda #16
    sta ST_NBOBS
    sta nbobs

    jsr init_bobs
    jsr init_sprites
    lda #0
    sta front
    jsr set_mode
    jsr measure_ten_frames

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
    lda #1
    sta ST_STATE

frame_loop:
    jsr apply_control
    jsr copy_benchmarks
    jsr uci_probe
    lda #COL_1
    sta $d020           // border shows the render time on a real display
    jsr timer_start
    jsr restore_back
    jsr move_bobs
    jsr draw_all
    jsr timer_stop
    lda drawn_now
    sta ST_DRAWN
    lda #COL_BG
    sta $d020
    jsr wait_vblank
    // flip
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
!:  jsr apply_colram    // mode 2: colour RAM follows the new front buffer
    jsr move_sprites    // mode 3
    jsr palette_frame   // mode 5
!:  lda ST_PAUSE        // the host wants a still frame
    bne !-
    jmp frame_loop

rti_handler:
    rti

// A GET_PALETTE on the control target, written straight to the registers,
// with every phase recorded: pal_out = data bytes (up to 48), pal_base =
// status bytes (up to 32), STATUS+41 = data count, +42 = status count,
// +43 = $df1c before the push, +44 = after the push, +45 = when the reply
// appeared, +46 = after the acknowledge, +47 = polls waited (high byte).
raw_command:
    lda $df1c
    sta STATUS + 43
    lda #$04
    sta $df1d
    lda #$51
    sta $df1d
    lda #$01
    sta $df1c
    lda $df1c
    sta STATUS + 44
    ldx #0
    ldy #0
!:  lda $df1c
    and #$30
    cmp #$10
    bne !+
    iny
    bne !-
    inx
    bne !-
!:  stx STATUS + 47
    lda $df1c
    sta STATUS + 45
    ldx #0
!:  lda $df1c
    bpl !+
    lda $df1e
    cpx #48
    bcs !-
    sta pal_out, x
    inx
    bne !-
!:  stx STATUS + 41
    ldx #0
!:  lda $df1c
    and #$40
    beq !+
    lda $df1f
    cpx #32
    bcs !-
    sta pal_base, x
    inx
    bne !-
!:  stx STATUS + 42
    lda #$02
    sta $df1c
    lda $df1c
    sta STATUS + 46
    rts

// UCI transport probes through the blob, at whatever speed the machine is at.
//   1 init then identify   2 identify only   3 palette_get only
//   4 init then palette_get (mode 5's own sequence)
//   5 init, then record $df1c and drain any status bytes into pal_out
//   6 init then a raw GET_PALETTE by hand   7 the raw command alone
uci_probe:
    lda ST_PROBE
    bne !+
    rts
!:  cmp #1
    beq p1
    cmp #2
    beq p2
    cmp #3
    beq p3
    cmp #4
    beq p4
    cmp #5
    beq p5
    cmp #6
    beq p6
    cmp #7
    beq p7
    jmp pdone
p1: jsr BLOB_INIT
    sta ST_PINIT
p2: lda #$04
    jsr BLOB + $25      // ultimate_identify(control)
    sta ST_PIDENT
    jmp pdone
p4: jsr BLOB_INIT
    sta ST_PINIT
p3: lda #<pal_base
    ldx #>pal_base
    jsr BLOB_PALGET
    sta ST_PIDENT
    jmp pdone
p5: jsr BLOB_INIT
    sta ST_PINIT
    lda $df1c
    sta ST_PIDENT
    ldx #0
!:  lda $df1c
    and #$40            // UCI_STAT_STAT_AV
    beq !+
    lda $df1f
    sta pal_out, x
    inx
    cpx #48
    bne !-
!:  stx STATUS + 41
    lda $df1c
    sta STATUS + 42
    jmp pdone
p6: jsr BLOB_INIT
    sta ST_PINIT
p7: jsr raw_command
pdone:
    lda #0
    sta ST_PROBE
    rts

dd00_for_front:  .byte %00000010, %00000001   // bank 1 ($4000), bank 2 ($8000)
d018_for_front:  .byte D018_A, D018_B
bitmap_hi_for_buf: .byte >BITMAP_A, >BITMAP_B
screen_lo_for_buf: .byte <SCREEN_A, <SCREEN_B
screen_hi_for_buf: .byte >SCREEN_A, >SCREEN_B
clean_delta_hi:  .byte >(CLEAN - BITMAP_A), >(CLEAN - BITMAP_B)

front:   .byte 0                 // buffer index on screen
nbobs:   .byte 0
ndirty:  .byte 0, 0              // dirty entries per buffer
mode:    .byte $ff
mode_cells:   .byte 0            // write bob colours into screen RAM cells
mode_colram:  .byte 0            // and the 11 colour into colour RAM
mode_sprites: .byte 0
mode_palette: .byte 0
shape_base:   .byte 0

// ---------------------------------------------------------------------------
// Host control. Speed is applied only when the turbo register answers.
apply_control:
    lda ST_NBOBS
    beq !+
    cmp #MAXBOBS+1
    bcs !+
    sta nbobs
!:  lda ST_MODE
    cmp mode
    beq !+
    cmp #6
    bcs !+
    jsr set_mode
!:  lda ST_SPEED
    cmp #$ff
    beq done
    and #$0f
    ldx ST_NOBAD
    beq !+
    ora #$80
!:  ldx $d031
    cpx #$ff
    beq done
    sta $d031
done:
    lda $d031
    sta ST_D031
    rts

// ---------------------------------------------------------------------------
// Mode switch: rebuild the background in both buffers, fill the colour cells,
// start or stop sprites and the palette. A = new mode.
set_mode:
    pha
    // leaving palette mode: put the machine's palette back
    lda mode_palette
    beq !+
    jsr BLOB_PALRST
    sta ST_BLOB
!:  pla
    sta mode
    sta ST_MODEACK
    ldx #0
    stx mode_cells
    stx mode_colram
    stx mode_sprites
    stx mode_palette
    stx shape_base
    stx ndirty
    stx ndirty+1
    cmp #0
    beq mode0
    inx
    stx mode_cells
    cmp #2
    bne !+
    stx mode_colram
!:  cmp #3
    bne !+
    stx mode_sprites
!:  cmp #4
    bne !+
    lda #3
    sta shape_base
!:  lda mode
    cmp #5
    bne !+
    jsr palette_start
!:  jsr build_stars
    jsr copy_background_to_both
    lda #CLEAN_CELL
    ldx #STAR_COL
    jsr fill_colour
    jmp sprites_on_off
mode0:
    jsr build_grid
    jsr copy_background_to_both
    lda #(COL_1 << 4) | COL_2
    ldx #COL_3
    jsr fill_colour
sprites_on_off:
    lda #0
    ldx mode_sprites
    beq !+
    jsr setup_sprites
    lda #$ff
!:  sta $d015
    rts

// ---------------------------------------------------------------------------
wait_vblank:
!:  lda $d012
    cmp #VBLANK_LINE
    beq !-
!:  lda $d012
    cmp #VBLANK_LINE
    bne !-
    rts

// CIA 2 timers A and B chained into one 32-bit down counter (see cycles.h).
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

measure_ten_frames:
    jsr wait_vblank
    jsr timer_start
    ldx #10
!:  jsr wait_vblank
    dex
    bne !-
    jsr timer_stop
    ldx #3
!:  lda ST_RENDER,x
    sta ST_TENFR,x
    dex
    bpl !-
    rts

// ---------------------------------------------------------------------------
// On request: how long does moving 4 KB take by REU DMA versus the CPU, at the
// speed the machine is at now. Answers where bob images should live.
.const BENCH_LEN = 4096
.const BENCH_SRC = $4000        // bank-1 spare RAM below the blob's variables
.const BENCH_DST = $8400        // bank-2 spare RAM, above screen B
copy_benchmarks:
    lda ST_TEST
    bne !+
    rts
!:  lda #0
    sta ST_TEST
    jsr reu_setup
    jsr timer_start
    lda #$90            // execute, $ff00 trigger off, stash
    sta $df01
    jsr timer_stop
    ldx #3
!:  lda ST_RENDER, x
    sta ST_REUSTA, x
    dex
    bpl !-
    jsr reu_setup
    lda #<BENCH_DST
    sta $df02
    lda #>BENCH_DST
    sta $df03
    jsr timer_start
    lda #$91            // execute, $ff00 trigger off, fetch
    sta $df01
    jsr timer_stop
    ldx #3
!:  lda ST_RENDER, x
    sta ST_REUFET, x
    dex
    bpl !-
    jsr timer_start
    ldx #0
cpy:
    .for (var p = 0; p < 16; p++) {
        lda BENCH_SRC + p*256, x
        sta BENCH_DST + p*256, x
    }
    inx
    beq !+
    jmp cpy
!:  jsr timer_stop
    ldx #3
!:  lda ST_RENDER, x
    sta ST_CPUCPY, x
    dex
    bpl !-
    rts

reu_setup:
    lda #<BENCH_SRC
    sta $df02
    lda #>BENCH_SRC
    sta $df03
    lda #0
    sta $df04
    sta $df05
    sta $df06
    sta $df0a
    lda #<BENCH_LEN
    sta $df07
    lda #>BENCH_LEN
    sta $df08
    rts

// ---------------------------------------------------------------------------
// Backgrounds, built into CLEAN.
// Grid: one byte is one multicolour cell row: $55 = four pixels of colour 1,
// $40 = the first pixel only. Mode 0 only, where 01 is free for the background.
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

// Stars: black, plus 240 single pixels of colour 11. Uses no 01 or 10, so a
// bob may own those in any cell it crosses without touching the background.
build_stars:
    lda #<CLEAN
    sta zpPtr
    lda #>CLEAN
    sta zpPtr+1
    ldy #0
    tya
    ldx #32
!:  sta (zpPtr),y
    iny
    bne !-
    inc zpPtr+1
    dex
    bne !-
    lda #$a7
    sta seed
    lda #240
    sta zpCnt
star:
    jsr lfsr
    jsr mod160
    sta zpCb            // x, 0..159
    jsr lfsr2           // an independent sequence, or x and y line up
    jsr mod200
    sta zpCr            // y, 0..199
    lsr
    lsr
    lsr
    tay
    lda row320_lo,y
    sta zpPtr
    lda row320_hi,y
    clc
    adc #>CLEAN
    sta zpPtr+1
    lda zpCr
    and #7
    sta zpTmp
    lda zpCb
    and #$fc
    asl                 // (x>>2)*8, may carry
    bcc !+
    inc zpPtr+1
!:  clc
    adc zpTmp
    tay                 // + line within the cell; never carries past a cell row
    bcc !+
    inc zpPtr+1
!:  lda zpCb
    and #3
    tax
    lda (zpPtr),y
    ora pixmask,x
    sta (zpPtr),y
    dec zpCnt
    bne star
    rts

pixmask: .byte $c0, $30, $0c, $03

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

// A = screen RAM byte for every cell of both screens, X = colour RAM nibble.
fill_colour:
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
    txa
!:  sta $d800, y
    sta $d900, y
    sta $da00, y
    sta $db00, y
    iny
    bne !-
    rts

// ---------------------------------------------------------------------------
// Bobs: position, velocity, shape, colours. Deterministic pseudo-random spread.
init_bobs:
    lda #$a7
    sta seed
    ldx #0
!:  jsr lfsr
    jsr mod_xmax
    sta bx, x
    jsr lfsr
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
    cmp #3
    bcc !+
    lda #0
!:  sta bshape, x
    txa
    and #7
    tay
    lda pairs_scr, y
    sta bcol, x
    lda pairs_c3, y
    sta bcol3, x
    inx
    cpx #MAXBOBS
    bne !--
    rts

vel_table: .byte 1, 2, -1, -2

// Eight colour schemes: screen byte = (01 colour << 4) | 10 colour, and the 11
// colour mode 2 gives the bob. Outline, body, light.
pairs_scr: .byte ($02<<4)|$0a, ($06<<4)|$0e, ($05<<4)|$0d, ($09<<4)|$08
           .byte ($08<<4)|$07, ($06<<4)|$03, ($04<<4)|$0a, ($0b<<4)|$0c
pairs_c3:  .byte $07, $03, $07, $07, $01, $01, $01, $01

// 8-bit maximal LFSR, x^8 + x^6 + x^5 + x^4 + 1: a 255-long spread of positions.
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

mod160:
!:  cmp #160
    bcc !+
    sbc #160
    jmp !-
!:  rts

mod200:
!:  cmp #200
    bcc !+
    sbc #200
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
// Bob address arithmetic. For a bob at (x, y) in the buffer whose bitmap is at
// BUF, row r of column c lives at
//     BUF + ((y+r)>>3)*320 + (x>>2 + c)*8 + ((y+r)&7)
// Rows that share a cell row are consecutive bytes, so with
//     base_j = BUF + y + (x>>2)*8 + (cellrow + j)*312
// the byte for row r in cell-row segment j is simply base_j + r, and one
// index register walks image, mask and destination together.
//
// compute_base: X = bob index -> zpB = base_0 (without BUF), zpYin, zpE0,
//               zpCr, zpCb, zpSoff (cell offset), zpSegs
compute_base:
    lda by, x
    sta zpTmp
    and #7
    sta zpYin
    lda #8
    sec
    sbc zpYin
    sta zpE0            // rows 0..E0-1 are in the first cell row; then 8 each
    lda #SEGS
    ldy zpYin
    beq !+
    lda #SEGS+1
!:  sta zpSegs
    lda zpTmp
    lsr
    lsr
    lsr
    sta zpCr
    tay
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
    sta zpCb
    tay
    lda xoff_lo, y      // + (x>>2)*8
    clc
    adc zpB
    sta zpB
    lda xoff_hi, y
    adc zpB+1
    sta zpB+1
    ldy zpCr
    lda row40_lo, y
    clc
    adc zpCb
    sta zpSoff
    lda row40_hi, y
    adc #0
    sta zpSoff+1
    rts

// ---------------------------------------------------------------------------
// Restore every rectangle drawn into the back buffer the last time it was
// drawn to. Whole 8-byte cell-row segments are copied: cheaper than exact rows
// and harmless, because every restore happens before any draw. In the cell
// modes the screen RAM under the bob goes back to CLEAN_CELL as well.
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
    lda screen_lo_for_buf, y
    sta rscr_lo
    lda screen_hi_for_buf, y
    sta rscr_hi
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
    lda dl_slo_tab, y
    sta rd_slo+1
    lda dl_slo_tab+1, y
    sta rd_slo+2
    lda dl_shi_tab, y
    sta rd_shi+1
    lda dl_shi_tab+1, y
    sta rd_shi+2
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
!:  lda mode_cells
    beq rnext
    // screen cells back to CLEAN_CELL
    ldx zpBob
rd_slo:
    lda $ffff, x
    clc
    adc rscr_lo
    sta zpPtr
rd_shi:
    lda $ffff, x
    adc rscr_hi
    sta zpPtr+1
    lda rsegs
    sta rseg
    lda #CLEAN_CELL
rcell:
    ldy #4
!:  sta (zpPtr), y
    dey
    bpl !-
    pha
    lda zpPtr
    clc
    adc #40
    sta zpPtr
    bcc !+
    inc zpPtr+1
!:  pla
    dec rseg
    bne rcell
rnext:
    ldx zpBob
    inx
    cpx zpN
    beq rdone
    jmp rloop
rdone:
    rts

rbuf_hi:   .byte 0
rdelta_hi: .byte 0
rscr_lo:   .byte 0
rscr_hi:   .byte 0
rsegs:     .byte 0
rseg:      .byte 0

// ---------------------------------------------------------------------------
// Draw every bob into the back buffer and record where, for the restore.
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
    lda screen_lo_for_buf, y
    sta dscr_lo
    lda screen_hi_for_buf, y
    sta dscr_hi
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
    lda dl_slo_tab, y
    sta dw_slo+1
    lda dl_slo_tab+1, y
    sta dw_slo+2
    lda dl_shi_tab, y
    sta dw_shi+1
    lda dl_shi_tab+1, y
    sta dw_shi+2
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
    lda zpSoff
dw_slo:
    sta $ffff, x
    lda zpSoff+1
dw_shi:
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
    lda shape_base      // a mode with its own shape set uses that shape for all
    bne !+
    lda bshape, x
!:  asl
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
!:  lda mode_cells
    beq dnext
    // the bob's 01/10 colours into every screen cell it covers
    ldx zpBob
    lda zpSoff
    clc
    adc dscr_lo
    sta zpPtr
    lda zpSoff+1
    adc dscr_hi
    sta zpPtr+1
    lda zpSegs
    sta dseg_n
    lda bcol, x
dcell:
    ldy #4
!:  sta (zpPtr), y
    dey
    bpl !-
    pha
    lda zpPtr
    clc
    adc #40
    sta zpPtr
    bcc !+
    inc zpPtr+1
!:  pla
    dec dseg_n
    bne dcell
dnext:
    ldx zpBob
    inx
    cpx zpN
    beq !+
    jmp dloop
!:  rts

dbuf_hi:   .byte 0
dscr_lo:   .byte 0
dscr_hi:   .byte 0
dseg_n:    .byte 0
drawn_now: .byte 0

// ---------------------------------------------------------------------------
// Mode 2: colour RAM is single-buffered and I/O speed, so it is written right
// after the flip, inside the non-display lines: first the cells of the frame
// that just left the screen back to STAR_COL, then the new front's bobs.
apply_colram:
    lda mode_colram
    bne !+
    rts
!:  lda front
    eor #1
    tay
    lda #STAR_COL
    sta cr_fixed
    lda #1
    sta cr_use_fixed
    jsr colram_list
    ldy front
    lda #0
    sta cr_use_fixed
    jsr colram_list
    rts

// Y = buffer index whose dirty list to walk
colram_list:
    lda ndirty, y
    bne !+
    rts
!:  sta zpN
    tya
    asl
    tay
    lda dl_slo_tab, y
    sta cr_slo+1
    lda dl_slo_tab+1, y
    sta cr_slo+2
    lda dl_shi_tab, y
    sta cr_shi+1
    lda dl_shi_tab+1, y
    sta cr_shi+2
    lda dl_yin_tab, y
    sta cr_yin+1
    lda dl_yin_tab+1, y
    sta cr_yin+2
    ldx #0
crloop:
cr_slo:
    lda $ffff, x
    sta zpPtr
cr_shi:
    lda $ffff, x
    clc
    adc #$d8
    sta zpPtr+1
cr_yin:
    lda $ffff, x
    tay
    lda #SEGS
    cpy #0
    beq !+
    lda #SEGS+1
!:  sta zpSegs
    lda cr_use_fixed
    bne !+
    lda bcol3, x
    jmp crcell
!:  lda cr_fixed
crcell:
    ldy #4
!:  sta (zpPtr), y
    dey
    bpl !-
    pha
    lda zpPtr
    clc
    adc #40
    sta zpPtr
    bcc !+
    inc zpPtr+1
!:  pla
    dec zpSegs
    bne crcell
    inx
    cpx zpN
    bne crloop
    rts

cr_fixed:     .byte 0
cr_use_fixed: .byte 0

// ---------------------------------------------------------------------------
// Mode 3: eight expanded hires hardware sprites, one colour each, bouncing.
init_sprites:
    ldx #0
!:  txa
    asl
    asl
    asl
    asl
    asl                 // x*32
    clc
    adc #40
    sta spx_lo, x
    lda #0
    sta spx_hi, x
    txa
    asl
    asl
    asl
    asl                 // x*16
    clc
    adc #60
    sta spy, x
    txa
    and #3
    tay
    lda vel_table, y
    sta spdx, x
    txa
    lsr
    and #3
    tay
    lda vel_table, y
    sta spdy, x
    inx
    cpx #NSPRITES
    bne !-
    rts

setup_sprites:
    ldx #0
!:  lda #SPRPTR
    sta SCREEN_A + $3f8, x
    sta SCREEN_B + $3f8, x
    lda spr_colours, x
    sta $d027, x
    inx
    cpx #NSPRITES
    bne !-
    ldx #62
!:  lda sprite_image, x
    sta SPRDATA_A, x
    sta SPRDATA_B, x
    dex
    bpl !-
    lda #$ff
    sta $d017
    sta $d01d
    lda #0
    sta $d01c
    sta $d01b
    rts

spr_colours: .byte $01, $07, $0a, $03, $0d, $08, $0f, $04

move_sprites:
    lda mode_sprites
    bne !+
    rts
!:  ldx #0
    stx zpTmp           // $d010 bits
sp: lda spdx, x
    bmi spneg
    // x += dx, bounce at 296
    clc
    adc spx_lo, x
    sta spx_lo, x
    bcc !+
    inc spx_hi, x
!:  lda spx_hi, x
    beq spxdone
    lda spx_lo, x
    cmp #<296
    bcc spxdone
    jsr spflipx
    jmp spxdone
spneg:
    // x += dx (negative), bounce below 24
    clc
    adc spx_lo, x
    sta spx_lo, x
    bcs !+
    dec spx_hi, x
!:  lda spx_hi, x
    bmi spflipx_j
    bne spxdone
    lda spx_lo, x
    cmp #24
    bcs spxdone
spflipx_j:
    jsr spflipx
spxdone:
    lda spy, x
    clc
    adc spdy, x
    cmp #50
    bcc spflipy
    cmp #208
    bcs spflipy
    jmp spystore
spflipy:
    lda spdy, x
    eor #$ff
    clc
    adc #1
    sta spdy, x
    lda spy, x
    clc
    adc spdy, x
spystore:
    sta spy, x
    // registers
    txa
    asl
    tay
    lda spx_lo, x
    sta $d000, y
    lda spy, x
    sta $d001, y
    lda spx_hi, x
    beq !+
    lda sp_bit, x
    ora zpTmp
    sta zpTmp
!:  inx
    cpx #NSPRITES
    beq !+
    jmp sp
!:  lda zpTmp
    sta $d010
    rts

spflipx:
    lda spdx, x
    eor #$ff
    clc
    adc #1
    sta spdx, x
    bmi !+
    clc
    adc spx_lo, x
    sta spx_lo, x
    bcc !++
    inc spx_hi, x
    rts
!:  clc
    adc spx_lo, x
    sta spx_lo, x
    bcs !+
    dec spx_hi, x
!:  rts

sp_bit: .byte 1, 2, 4, 8, 16, 32, 64, 128

// ---------------------------------------------------------------------------
// Mode 5: the Ultimate's live palette through the SDK blob at $3400. On entry
// the palette is read, then faded in from black over 32 frames, then colours
// 2-15 are cycled every 8 frames. palette_set is one UCI round trip.
palette_start:
    lda BLOB+0          // "UCI" in PETSCII, the blob's signature
    cmp #$d5
    bne nob
    lda BLOB+1
    cmp #$c3
    bne nob
    lda BLOB+2
    cmp #$c9
    bne nob
    jsr BLOB_INIT
    sta ST_BLOB
    cmp #0
    bne !+
    lda #<pal_base
    ldx #>pal_base
    jsr BLOB_PALGET
    sta ST_BLOB
    cmp #0
    bne !+
    lda #1
    sta mode_palette
    lda #0
    sta pal_fade
    sta pal_tick
!:  rts
nob:
    lda #$fe
    sta ST_BLOB
    rts

palette_frame:
    lda mode_palette
    bne !+
    rts
!:  inc pal_tick
    lda pal_fade
    cmp #8
    bcs cycling
    lda pal_tick
    and #3
    beq !+
    rts
!:  inc pal_fade
    // pal_out = pal_base * fade / 8
    ldx #47
fade:
    lda #0
    sta zpTmp
    sta zpTmp+1
    ldy pal_fade
!:  lda zpTmp
    clc
    adc pal_base, x
    sta zpTmp
    bcc !+
    inc zpTmp+1
!:  dey
    bne !--
    lsr zpTmp+1
    ror zpTmp
    lsr zpTmp+1
    ror zpTmp
    lsr zpTmp+1
    ror zpTmp
    lda zpTmp
    sta pal_out, x
    dex
    bpl fade
    lda #<pal_out
    ldx #>pal_out
    jsr BLOB_PALSET
    sta ST_BLOB
    rts
cycling:
    lda pal_tick
    and #7
    beq !+
    rts
!:  // rotate colours 2..15 (bytes 6..47) down by one colour (3 bytes)
    lda pal_base+6
    pha
    lda pal_base+7
    pha
    lda pal_base+8
    pha
    ldx #6
!:  lda pal_base+3, x
    sta pal_base, x
    inx
    cpx #45
    bne !-
    pla
    sta pal_base+47
    pla
    sta pal_base+46
    pla
    sta pal_base+45
    lda #<pal_base
    ldx #>pal_base
    jsr BLOB_PALSET
    sta ST_BLOB
    rts

pal_fade: .byte 0
pal_tick: .byte 0
pal_base: .fill 48, 0
pal_out:  .fill 48, 0

// ---------------------------------------------------------------------------
// Tables
dl_lo_tab:  .word dirtyA_lo, dirtyB_lo
dl_hi_tab:  .word dirtyA_hi, dirtyB_hi
dl_yin_tab: .word dirtyA_yin, dirtyB_yin
dl_slo_tab: .word dirtyA_slo, dirtyB_slo
dl_shi_tab: .word dirtyA_shi, dirtyB_shi

rowbase_lo: .fill 25, <(i*312)
rowbase_hi: .fill 25, >(i*312)
row320_lo:  .fill 25, <(i*320)
row320_hi:  .fill 25, >(i*320)
row40_lo:   .fill 25, <(i*40)
row40_hi:   .fill 25, >(i*40)
xoff_lo:    .fill 40, <(i*8)
xoff_hi:    .fill 40, >(i*8)
imgbase_lo: .fill SHAPES*4, <(bobdata + i*SHIFT_BYTES)
imgbase_hi: .fill SHAPES*4, >(bobdata + i*SHIFT_BYTES)

// A 24x21 hires diamond for the hardware sprites.
sprite_image:
    .for (var y = 0; y < 21; y++) {
        .for (var b = 0; b < 3; b++) {
            .var v = 0
            .for (var p = 0; p < 8; p++) {
                .var x = b*8 + p
                .if (abs(x - 11.5)/11.5 + abs(y - 10)/10.5 <= 1.0) .eval v = v | (128 >> p)
            }
            .byte v
        }
    }

.align $100
bx:         .fill MAXBOBS, 0
by:         .fill MAXBOBS, 0
bdx:        .fill MAXBOBS, 0
bdy:        .fill MAXBOBS, 0
bshape:     .fill MAXBOBS, 0
bcol:       .fill MAXBOBS, 0
bcol3:      .fill MAXBOBS, 0
dirtyA_lo:  .fill MAXBOBS, 0
dirtyA_hi:  .fill MAXBOBS, 0
dirtyA_yin: .fill MAXBOBS, 0
dirtyA_slo: .fill MAXBOBS, 0
dirtyA_shi: .fill MAXBOBS, 0
dirtyB_lo:  .fill MAXBOBS, 0
dirtyB_hi:  .fill MAXBOBS, 0
dirtyB_yin: .fill MAXBOBS, 0
dirtyB_slo: .fill MAXBOBS, 0
dirtyB_shi: .fill MAXBOBS, 0
spx_lo:     .fill NSPRITES, 0
spx_hi:     .fill NSPRITES, 0
spy:        .fill NSPRITES, 0
spdx:       .fill NSPRITES, 0
spdy:       .fill NSPRITES, 0

// ---------------------------------------------------------------------------
// Bob images, generated at assembly time. pix() returns the colour index
// (0 transparent, 1..3 = bit pairs 01, 10, 11) of a shape. Each shape is
// stored four times, pre-shifted by 0..3 multicolour pixels into a 5-byte-wide
// column-major image followed by its mask (11 where transparent).
//
// Shapes are defined on a unit square, so a ball is round in screen space
// whatever the pixel aspect: dx and dy run -8..8 across width and height.
// Shape 3 is the ball again with two dithered bands: checkerboards of 1/2 and
// 2/3 read as intermediate shades at multicolour pixel size.
.function pix(k, x, y) {
    .var dx = (x + 0.5) * 16 / BOB_W - 8
    .var dy = (y + 0.5) * 16 / BOB_H - 8
    .var d = sqrt(dx*dx + dy*dy)
    .var checker = mod(x + y, 2) == 0
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
    .if (k == 2) {                       // ring
        .if (d > 7.9) .return 0
        .if (d < 3.6) .return 0
        .if (d > 6.6 || d < 4.8) .return 1
        .if (dy < -2 && dx < 0) .return 3
        .return 2
    }
    // dithered ball: light from the top left, five bands
    .if (d > 7.9) .return 0
    .var h = sqrt((dx+3)*(dx+3) + (dy+3)*(dy+3))
    .if (h < 1.8) .return 3
    .if (h < 3.6) .return checker ? 3 : 2
    .if (h < 6.0) .return 2
    .if (h < 8.4) .return checker ? 2 : 1
    .return 1
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
