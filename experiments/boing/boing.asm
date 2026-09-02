// boing.asm - the Amiga Boing ball out of multiplexed hardware sprites, with a
// blitter shadow, a perspective floor, and the boing as PCM.
//
// The ball is 2 sprite columns by 4 sprite rows, every position drawn twice:
// a white sprite with the white tiles and a red sprite with the red ones.
// Sixteen sprites a frame, so the eight hardware sprites are multiplexed:
// sprites 0-3 draw rows 0 and 2, sprites 4-7 rows 1 and 3, and two raster
// interrupts move them down once a row has been displayed. Only the white
// layer is stored per rotation frame; red = disc AND NOT white, built at run
// time into one of two live sprite sets and flipped at vblank.
//
// The shadow is a blitter bob: an ellipse ORed into the hires bitmap to the
// ball's lower right, the covered cells recoloured dark grey. One bitmap, so
// each frame restores what the shadow covered last time from a clean copy of
// the background held in the REU, then draws it again - done right after the
// vblank sync, and the ball's sprites float over it. The boing plays through
// the Ultimate's PCM engine from the REU on every bounce.
//
// The SDK (the standalone blob at $8000, its RAM at $a800): turbo, REU
// stash/fetch, audio init/configure/start/stop. All optional: no REU means no
// shadow and no sound, no turbo means it all just runs slower.
//
// Status block at $033c: "BONG", frames (16-bit) +4, x lo/hi +6, y +8,
// rotation frame +9, flags +10 (1 turbo, 2 REU and shadow, 4 audio), bounces
// +11, last SDK result +12, host: +13 = 1 turns the shadow off.
// SPDX-License-Identifier: MIT

#import "../../bindings/kickass/uci_protocol.asm"

.const STATUS   = $033c
.const SCREEN   = $4000
.const LIVE_A   = $4400        // 16 sprites x 64 bytes
.const LIVE_B   = $4800
.const BITMAP   = $6000
.const SHADOW   = $4c00        // 12 x 84 ellipse, row-major, from shadow.bin
.const SCRATCH  = $5000        // 13 x 84, the ellipse shifted, column-major
.const SCR_CLEAN = $5500       // the 1000 screen RAM bytes, restored per cell
.const PCM      = $aa00        // boing.pcm, stashed to the REU at start
.const PCM2     = $e000        // second piece, under the KERNAL ($01 = $35)
.const PTR_A    = (LIVE_A - $4000) / 64   // 16
.const PTR_B    = (LIVE_B - $4000) / 64   // 32

.const BLOB          = $8000
.const ULT_INIT      = BLOB + $1c
.const TURBO_AVAIL   = BLOB + $43
.const TURBO_SET     = BLOB + $49
.const TURBO_BADLINES = BLOB + $4c
.const REU_AVAIL     = BLOB + $76
.const REU_STASH     = BLOB + $79
.const REU_FETCH     = BLOB + $7c
.const AUDIO_INIT    = BLOB + $2e8
.const AUDIO_CONF    = BLOB + $2f1
.const AUDIO_START   = BLOB + $2f4
.const AUDIO_STOP    = BLOB + $2f7
.const BP            = BLOB + $100
.const BP_RESULT     = BP + $00
.const BP_ADDR       = BP + $03
.const BP_REU        = BP + $156
.const BP_REULEN     = BP + $15a
.const BP_AUDIO      = BP + $19a

.const REU_BG   = $0000        // clean background in the REU, 8000 bytes
.const REU_PCM  = $4000
#import "boing_pcm.inc"     // PCM_LEN and PCM_RATE, written by mkpcm.py

.const XMAX     = 320 - 96     // ball x, relative to the visible left edge
.const YMAX     = 96           // ball bottom 4 px below the wall/floor line at 176
.const GRAV     = 20           // 1/256 px per frame per frame
.const VBLANK   = 250
.const COL_BG   = $0c          // grey field
.const SHADOW_CELL = ($0b << 4) | COL_BG   // dark grey foreground
.const SHX      = 12           // shadow offset from the ball: just off the wall
.const SHY      = 0
.const SH_ROWS  = 84
.const SH_COLS  = 13

.label zpS   = $02
.label zpP   = $04
.label zpN   = $06
.label zpD   = $08
.label zpSrc = $0a
.label zpEnd = $0c
.label zpCov = $0d
.label zpCol = $0e
.label zpScr = $10
.label zpRow = $13
.label zpSeg = $14
.label zpOut = $20             // 13 bytes, one shifted ellipse row

.label ST_FRAMES = STATUS + 4
.label ST_X      = STATUS + 6
.label ST_Y      = STATUS + 8
.label ST_ROT    = STATUS + 9
.label ST_FLAGS  = STATUS + 10
.label ST_BOUNCE = STATUS + 11
.label ST_RESULT = STATUS + 12
.label ST_NOSHADOW = STATUS + 13
.label ST_PROBE    = STATUS + 15   // host: 1 = fetch REU $4000..$43ff to $b900, then clear

BasicUpstart2(main)

main:
    sei
    lda #$7f
    sta $dc0d
    sta $dd0d
    lda $dc0d
    lda $dd0d
    lda #$35
    sta $01
    lda #<rti_only
    sta $fffa
    lda #>rti_only
    sta $fffb
    lda #<irq
    sta $fffe
    lda #>irq
    sta $ffff

    lda #'B'
    sta STATUS
    lda #'O'
    sta STATUS+1
    lda #'N'
    sta STATUS+2
    lda #'G'
    sta STATUS+3
    lda #0
    sta ST_FRAMES
    sta ST_FRAMES+1
    sta ST_FLAGS
    sta ST_BOUNCE
    sta ST_RESULT
    sta ST_NOSHADOW

    jsr clear_live
    // the PRG loaded the background straight into SCREEN and BITMAP; keep a
    // clean copy of the 1000 screen bytes for the shadow's cell restore
    ldx #0
!:  lda SCREEN, x
    sta SCR_CLEAN, x
    lda SCREEN+$100, x
    sta SCR_CLEAN+$100, x
    lda SCREEN+$200, x
    sta SCR_CLEAN+$200, x
    lda SCREEN+$300, x
    sta SCR_CLEAN+$300, x
    inx
    bne !-

    jsr sdk_init

    // sprites: colours, expansion, all on, over the bitmap
    ldx #0
!:  lda spr_colour, x
    sta $d027, x
    inx
    cpx #8
    bne !-
    lda #$ff
    sta $d01d          // X expanded
    sta $d015
    lda #0
    sta $d017
    sta $d01c
    sta $d01b

    // ball state
    lda #64
    sta x
    lda #1
    sta vx
    lda #0
    sta y
    sta y+1
    sta vy
    sta vy+1
    sta rot
    sta rotdiv
    sta phase
    sta vbl
    sta bounce
    sta sh_valid
    lda #$ff
    sta last_shift
    sta built_rot
    lda #PTR_A
    sta cur_base
    sta next_base
    jsr build_set      // frame 0 into the set next_base names
    jsr next_positions

    // VIC: hires bitmap, bank 1, raster IRQ at vblank
    lda $dd02
    ora #3
    sta $dd02
    lda #%00000010
    sta $dd00
    lda #$08           // screen +$0000, bitmap +$2000
    sta $d018
    lda #COL_BG
    sta $d020
    sta $d021
    lda #$3b
    sta $d011
    lda #$c8
    sta $d016
    lda #VBLANK
    sta $d012
    lda #$01
    sta $d01a
    sta $d019
    cli

loop:
    jsr reu_probe
    lda vbl
    beq loop
    lda #0
    sta vbl
    jsr shadow_frame   // restore then draw, in the frame that just started
    jsr physics
    jsr next_positions
    lda bounce
    beq !+
    lda #0
    sta bounce
    inc ST_BOUNCE
    inc STATUS + 16     // trigger counter, for the host
    lda #1
    sta snd             // the vblank IRQ plays it, as the first version did
!:  lda rot
    cmp built_rot
    beq loop
    // the other set is free until the next flip
    lda #PTR_A
    ldx cur_base
    cpx #PTR_A
    bne !+
    lda #PTR_B
!:  sta next_base
    jsr build_set
    jmp loop

rti_only:
    rti

// ---------------------------------------------------------------------------
irq:
    pha
    txa
    pha
    tya
    pha
    lda $d019
    sta $d019
    lda phase
    bne not_vbl

irq_vbl:
    // rows 0 and 1 from the values the main loop prepared
    lda next_x0
    sta cur_x0
    sta $d000
    sta $d002
    sta $d008
    sta $d00a
    lda next_x1
    sta $d004
    sta $d006
    sta $d00c
    sta $d00e
    lda next_msb
    sta $d010
    lda next_y
    sta cur_y
    sta $d001
    sta $d003
    sta $d005
    sta $d007
    clc
    adc #21
    sta $d009
    sta $d00b
    sta $d00d
    sta $d00f
    lda next_base
    sta cur_base
    ldx #0
!:  clc
    adc #0
    sta SCREEN + $3f8, x
    clc
    adc #1
    inx
    cpx #8
    bne !-
    lda cur_y
    clc
    adc #22
    sta $d012
    lda #1
    sta phase
    sta vbl
    inc ST_FRAMES
    bne irq_done
    inc ST_FRAMES+1
    jmp irq_done

not_vbl:
    cmp #1
    bne irq_row3
    // row 2: sprites 0-3 again, one row lower
    lda cur_y
    clc
    adc #42
    sta $d001
    sta $d003
    sta $d005
    sta $d007
    lda cur_base
    clc
    adc #8
    sta SCREEN + $3f8
    adc #1
    sta SCREEN + $3f9
    adc #1
    sta SCREEN + $3fa
    adc #1
    sta SCREEN + $3fb
    lda cur_y
    clc
    adc #43
    sta $d012
    lda #2
    sta phase
    jmp irq_done

irq_row3:
    // row 3: sprites 4-7 again
    lda cur_y
    clc
    adc #63
    sta $d009
    sta $d00b
    sta $d00d
    sta $d00f
    lda cur_base
    clc
    adc #12
    sta SCREEN + $3fc
    adc #1
    sta SCREEN + $3fd
    adc #1
    sta SCREEN + $3fe
    adc #1
    sta SCREEN + $3ff
    lda #VBLANK
    sta $d012
    lda #0
    sta phase

irq_done:
    lda snd             // a bounce this frame: play it from interrupt context,
    beq done_nosnd      // as the first version did
    lda #0
    sta snd
    jsr play_boing
done_nosnd:
    pla
    tay
    pla
    tax
    pla
    rti

// ---------------------------------------------------------------------------
// SDK bring-up: turbo (best speed, badlines off), REU (clean background and
// the sample stashed), audio (a channel configured). Each guarded; a failure
// leaves the flags as they are and the demo does without.
sdk_init:
    jsr ULT_INIT           // fails without a UCI (VICE); nothing below needs it
    jsr TURBO_AVAIL
    cmp #0                 // test A: the entry returns with Z from a trailing ldx
    beq !+
    lda #uci.U64_SPEED_MAX
    jsr TURBO_SET
    lda #0
    jsr TURBO_BADLINES
    lda ST_FLAGS
    ora #1
    sta ST_FLAGS
!:  jsr REU_AVAIL
    cmp #1
    beq !+
    rts
!:  lda #<BITMAP
    sta BP_ADDR
    lda #>BITMAP
    sta BP_ADDR+1
    lda #0
    sta BP_REU
    sta BP_REU+1
    sta BP_REU+2
    sta BP_REU+3
    sta BP_REULEN+2
    sta BP_REULEN+3
    lda #<8000
    sta BP_REULEN
    lda #>8000
    sta BP_REULEN+1
    jsr REU_STASH
    lda BP_RESULT
    sta ST_RESULT
    beq !+
    rts
!:  lda #<PCM
    sta BP_ADDR
    lda #>PCM
    sta BP_ADDR+1
    lda #<REU_PCM
    sta BP_REU
    lda #>REU_PCM
    sta BP_REU+1
    lda #<PCM_A
    sta BP_REULEN
    lda #>PCM_A
    sta BP_REULEN+1
    jsr REU_STASH
    lda BP_RESULT
    sta ST_RESULT
    beq !+
    rts
!:  lda #<PCM2          // the second piece, straight after the first in the REU
    sta BP_ADDR
    lda #>PCM2
    sta BP_ADDR+1
    lda #<(REU_PCM + PCM_A)
    sta BP_REU
    lda #>(REU_PCM + PCM_A)
    sta BP_REU+1
    lda #<PCM_B
    sta BP_REULEN
    lda #>PCM_B
    sta BP_REULEN+1
    jsr REU_STASH
    lda BP_RESULT
    sta ST_RESULT
    beq !+
    rts
!:  lda ST_FLAGS
    ora #2
    sta ST_FLAGS
    jsr AUDIO_INIT
    sta ST_RESULT
    cmp #0
    beq !+
    rts
!:  jsr voice_setup
    jsr AUDIO_CONF
    lda BP_RESULT
    sta ST_RESULT
    beq !+
    rts
!:  lda ST_FLAGS
    ora #4
    sta ST_FLAGS
    rts

// ---------------------------------------------------------------------------
// Ball motion: x at one pixel a frame between the walls, y with gravity and an
// elastic floor, rotation one frame every other screen frame, following x.
// Every wall or floor hit sets `bounce`.
physics:
    lda x
    clc
    adc vx
    sta x
    beq flipx
    cmp #XMAX
    bne xdone
flipx:
    lda vx
    eor #$ff
    clc
    adc #1
    sta vx
    lda #1
    sta bounce
xdone:
    lda y
    clc
    adc vy
    sta y
    lda y+1
    adc vy+1
    sta y+1
    lda vy
    clc
    adc #GRAV
    sta vy
    bcc !+
    inc vy+1
!:  lda y+1
    bmi above_top
    cmp #YMAX
    bcc ydone
    lda #YMAX
    sta y+1
    lda #0
    sta y
    sec
    sbc vy
    sta vy
    lda #0
    sbc vy+1
    sta vy+1
    lda #1
    sta bounce
    jmp ydone
above_top:
    lda #0
    sta y
    sta y+1
    sta vy
    sta vy+1
ydone:
    lda rotdiv
    eor #1
    sta rotdiv
    bne rotdone
    lda vx
    bmi rotback
    inc rot
    jmp rotwrap
rotback:
    dec rot
rotwrap:
    lda rot
    and #15
    sta rot
rotdone:
    lda x
    sta ST_X
    lda #0
    sta ST_X+1
    lda y+1
    sta ST_Y
    lda rot
    sta ST_ROT
    rts

next_positions:
    lda x
    clc
    adc #24
    sta next_x0
    lda x
    clc
    adc #72
    sta next_x1
    lda #0
    bcc !+
    lda #%11001100     // column 1 sprites: 2, 3, 6, 7
!:  sta next_msb
    lda y+1
    clc
    adc #50
    sta next_y
    rts

// ---------------------------------------------------------------------------
// Copy rotation frame `rot` into the set next_base names: white as is, red =
// disc AND NOT white. 8 positions, 63 bytes each.
build_set:
    lda rot
    sta built_rot
    asl
    clc
    adc #>ball
    sta bsrc+2
    lda #<ball
    sta bsrc+1
    lda #<disc
    sta bdisc+1
    lda #>disc
    sta bdisc+2
    lda #<LIVE_A
    sta bdw+1
    sta bdr+1
    lda #>LIVE_A
    ldx next_base
    cpx #PTR_A
    beq !+
    lda #>LIVE_B
!:  sta bdw+2
    sta bdr+2
    lda bdw+1
    clc
    adc #64
    sta bdr+1
    bcc !+
    inc bdr+2
!:  ldx #8
bpos:
    ldy #62
bbyte:
bsrc:
    lda $ffff, y
bdw:
    sta $ffff, y
    eor #$ff
bdisc:
    and $ffff, y
bdr:
    sta $ffff, y
    dey
    bpl bbyte
    lda bsrc+1
    clc
    adc #64
    sta bsrc+1
    bcc !+
    inc bsrc+2
!:  lda bdisc+1
    clc
    adc #64
    sta bdisc+1
    bcc !+
    inc bdisc+2
!:  lda bdw+1
    clc
    adc #128
    sta bdw+1
    bcc !+
    inc bdw+2
!:  lda bdr+1
    clc
    adc #128
    sta bdr+1
    bcc !+
    inc bdr+2
!:  dex
    bne bpos
    rts

clear_live:
    lda #0
    ldx #0
!:  .for (var p = 0; p < 8; p++) {
        sta LIVE_A + p*256, x
    }
    inx
    bne !-
    rts

// ---------------------------------------------------------------------------
// The shadow. Restore what the last one covered (bitmap from the REU clean
// copy, cells from SCR_CLEAN), then OR the shifted ellipse in and recolour
// every cell it touches dark grey.
shadow_frame:
    lda ST_FLAGS
    and #2
    bne !+
    rts
!:  lda ST_NOSHADOW
    beq !+
    rts
!:  lda sh_valid
    beq shnew
    jsr shadow_restore
shnew:
    lda x
    clc
    adc #SHX
    sta sh_sx
    lda #0
    rol                 // the ninth bit: x + SHX passes 255 near the right wall
    sta sh_hi
    lda sh_sx
    and #7
    cmp last_shift
    beq !+
    sta last_shift
    jsr shift_silhouette
!:  lda sh_sx
    lsr
    lsr
    lsr
    ldx sh_hi
    beq !+
    clc
    adc #32             // columns 32..39; the clip below trims the count
!:  sta sh_c0
    lda #40
    sec
    sbc sh_c0
    cmp #SH_COLS
    bcc !+
    lda #SH_COLS
!:  sta sh_ncols
    lda y+1
    clc
    adc #SHY
    sta sh_sy
    and #7
    sta sh_yin
    lda sh_sy
    lsr
    lsr
    lsr
    sta sh_cr0
    lda #SH_ROWS + 7
    clc
    adc sh_yin
    lsr
    lsr
    lsr
    sta sh_nseg
    lda #25
    sec
    sbc sh_cr0
    cmp sh_nseg
    bcs !+
    sta sh_nseg
!:  jsr shadow_draw
    lda #1
    sta sh_valid
    rts

// Restore: one 8-line run of ncols*8 bytes per covered cell row from the REU,
// and the covered cells from SCR_CLEAN. Uses the sh_r_* record the last draw
// left, so a moving shadow leaves no trail.
shadow_restore:
    lda sh_r_cr0
    sta zpN
    lda sh_r_nseg
    sta zpSeg
    lda #0
    sta BP_REU+2
    sta BP_REU+3
    sta BP_REULEN+1
    sta BP_REULEN+2
    sta BP_REULEN+3
rrow:
    ldy zpN
    lda row320_lo, y
    clc
    adc sh_r_c0x8
    sta BP_REU
    sta BP_ADDR
    lda row320_hi, y
    adc sh_r_c0x8h
    sta BP_REU+1
    clc
    adc #>BITMAP
    sta BP_ADDR+1
    lda sh_r_ncols
    asl
    asl
    asl
    sta BP_REULEN
    jsr REU_FETCH
    lda BP_RESULT
    sta ST_RESULT
    ldy zpN
    lda row40_lo, y
    clc
    adc sh_r_c0
    sta zpScr
    sta zpS
    lda row40_hi, y
    adc #>SCREEN
    sta zpScr+1
    lda row40_hi, y
    adc #>SCR_CLEAN
    sta zpS+1
    ldy sh_r_ncols
    dey
!:  lda (zpS), y
    sta (zpScr), y
    dey
    bpl !-
    inc zpN
    dec zpSeg
    bne rrow
    rts

// The ellipse shifted right by (sx & 7) into SCRATCH, column-major: byte c of
// row r at SCRATCH + c*84 + r.
shift_silhouette:
    lda #<SHADOW
    sta zpS
    lda #>SHADOW
    sta zpS+1
    lda #0
    sta zpRow
srow:
    ldy #11
!:  lda (zpS), y
    sta zpOut, y
    dey
    bpl !-
    lda #0
    sta zpOut+12
    ldx last_shift
    beq sstore
sshift:
    clc
    .for (var i = 0; i < 13; i++) {
        ror zpOut + i
    }
    dex
    bne sshift
sstore:
    ldy zpRow
    .for (var c = 0; c < 13; c++) {
        lda zpOut + c
        sta SCRATCH + c*84, y
    }
    lda zpS
    clc
    adc #12
    sta zpS
    bcc !+
    inc zpS+1
!:  inc zpRow
    lda zpRow
    cmp #SH_ROWS
    beq !+
    jmp srow
!:  rts

// Draw the shifted ellipse into the bitmap and recolour the cells; remember
// what was covered so the next restore can undo exactly this.
shadow_draw:
    lda sh_c0
    sta sh_r_c0
    lda sh_ncols
    sta sh_r_ncols
    lda sh_cr0
    sta sh_r_cr0
    lda sh_nseg
    sta sh_r_nseg
    lda sh_c0
    asl
    asl
    asl
    sta sh_r_c0x8
    lda #0
    rol                 // column 32 and up: c0*8 needs a ninth bit
    sta sh_r_c0x8h
    ldy sh_cr0
    lda row312_lo, y
    clc
    adc sh_sy
    sta zpD
    lda row312_hi, y
    adc #0
    sta zpD+1
    lda zpD
    clc
    adc sh_r_c0x8
    sta zpD
    lda zpD+1
    adc sh_r_c0x8h
    clc
    adc #>BITMAP
    sta zpD+1
    lda row40_lo, y
    clc
    adc sh_c0
    sta zpScr
    lda row40_hi, y
    adc #>SCREEN
    sta zpScr+1
    lda #<SCRATCH
    sta zpSrc
    lda #>SCRATCH
    sta zpSrc+1
    lda #0
    sta zpCol
dcol:
    lda zpSrc
    sta dsrc1+1
    sta dsrc2+1
    lda zpSrc+1
    sta dsrc1+2
    sta dsrc2+2
    lda zpD
    sta dld+1
    sta dst+1
    sta zpP
    lda zpD+1
    sta dld+2
    sta dst+2
    sta zpP+1
    lda zpScr
    sta zpS
    lda zpScr+1
    sta zpS+1
    lda #8
    sec
    sbc sh_yin
    sta zpEnd
    lda sh_nseg
    sta zpN
    ldx #0
dseg:
    lda #0
    sta zpCov
dbyte:
dsrc1:
    lda $ffff, x
    ora zpCov
    sta zpCov
dsrc2:
    lda $ffff, x
dld:
    ora $ffff, x
dst:
    sta $ffff, x
    inx
    cpx zpEnd
    bne dbyte
    lda zpCov
    beq !+
    ldy #0
    lda #SHADOW_CELL
    sta (zpS), y
!:  dec zpN
    beq dcol_done
    cpx #SH_ROWS
    beq dcol_done
    lda zpP
    clc
    adc #<312
    sta zpP
    sta dld+1
    sta dst+1
    lda zpP+1
    adc #>312
    sta zpP+1
    sta dld+2
    sta dst+2
    lda zpS
    clc
    adc #40
    sta zpS
    bcc !+
    inc zpS+1
!:  lda zpEnd
    clc
    adc #8
    cmp #SH_ROWS
    bcc !+
    lda #SH_ROWS
!:  sta zpEnd
    jmp dseg
dcol_done:
    lda zpD
    clc
    adc #8
    sta zpD
    bcc !+
    inc zpD+1
!:  lda zpSrc
    clc
    adc #SH_ROWS
    sta zpSrc
    bcc !+
    inc zpSrc+1
!:  inc zpScr
    bne !+
    inc zpScr+1
!:  inc zpCol
    lda zpCol
    cmp sh_ncols
    beq !+
    jmp dcol
!:  rts

// ---------------------------------------------------------------------------
// The boing: channel 0, 8-bit mono, one shot, from the REU. Reconfigured on
// every bounce so a boing still playing starts over.
voice_setup:
    ldx #uci.UA_VOICE_SIZE - 1
    lda #0
!:  sta BP_AUDIO, x
    dex
    bpl !-
    lda #uci.UA_VOLUME_MAX
    sta BP_AUDIO + uci.UA_VOICE_VOLUME
    lda #uci.UA_PAN_CENTER
    sta BP_AUDIO + uci.UA_VOICE_PAN
    lda #<REU_PCM
    sta BP_AUDIO + uci.UA_VOICE_REU
    lda #>REU_PCM
    sta BP_AUDIO + uci.UA_VOICE_REU + 1
    lda #<PCM_LEN
    sta BP_AUDIO + uci.UA_VOICE_LENGTH
    sta BP_AUDIO + uci.UA_VOICE_REPEAT_B
    lda #>PCM_LEN
    sta BP_AUDIO + uci.UA_VOICE_LENGTH + 1
    sta BP_AUDIO + uci.UA_VOICE_REPEAT_B + 1
    lda #<PCM_RATE
    sta BP_AUDIO + uci.UA_VOICE_RATE
    lda #>PCM_RATE
    sta BP_AUDIO + uci.UA_VOICE_RATE + 1
    rts

// Host probe: pull the first 1 KB of the stashed sample back out of the REU
// so the host can compare it with the file it came from.
reu_probe:
    lda ST_PROBE
    bne !+
    rts
!:  cmp #2
    bne !+
    lda #0
    sta BP_REU
    sta BP_REU+1
    jmp !++
!:  lda #<REU_PCM
    sta BP_REU
    lda #>REU_PCM
    sta BP_REU+1
!:  lda #$00
    sta BP_ADDR
    lda #$b9
    sta BP_ADDR+1
    lda #0
    sta BP_REU+2
    sta BP_REU+3
    sta BP_REULEN
    sta BP_REULEN+2
    sta BP_REULEN+3
    lda #4
    sta BP_REULEN+1
    jsr REU_FETCH
    lda BP_RESULT
    sta ST_RESULT
    lda #0
    sta ST_PROBE
    rts

play_boing:
    lda ST_FLAGS
    and #4
    bne !+
    rts
!:  jsr AUDIO_STOP
    jsr AUDIO_CONF
    jsr AUDIO_START
    lda BP_RESULT
    sta ST_RESULT
    rts

// ---------------------------------------------------------------------------
spr_colour: .byte $01, $02, $01, $02, $01, $02, $01, $02

row312_lo:  .fill 25, <(i*312)
row312_hi:  .fill 25, >(i*312)
row320_lo:  .fill 25, <(i*320)
row320_hi:  .fill 25, >(i*320)
row40_lo:   .fill 25, <(i*40)
row40_hi:   .fill 25, >(i*40)

x:          .byte 0
vx:         .byte 0
y:          .word 0
vy:         .word 0
rot:        .byte 0
snd:        .byte 0
rotdiv:     .byte 0
built_rot:  .byte $ff
phase:      .byte 0
vbl:        .byte 0
bounce:     .byte 0
cur_base:   .byte 0
next_base:  .byte 0
cur_x0:     .byte 0
cur_y:      .byte 0
next_x0:    .byte 0
next_x1:    .byte 0
next_msb:   .byte 0
next_y:     .byte 0

sh_valid:   .byte 0
sh_sx:      .byte 0
sh_sy:      .byte 0
sh_yin:     .byte 0
sh_c0:      .byte 0
sh_hi:      .byte 0
sh_ncols:   .byte 0
sh_cr0:     .byte 0
sh_nseg:    .byte 0
last_shift: .byte $ff
sh_r_c0:    .byte 0     // what the last draw covered, for the restore
sh_r_c0x8:  .byte 0
sh_r_c0x8h: .byte 0
sh_r_ncols: .byte 0
sh_r_cr0:   .byte 0
sh_r_nseg:  .byte 0

.align $100
disc:
.import binary "disc.bin"
.align $100
ball:
.import binary "ball.bin"

// ---------------------------------------------------------------------------
// Loaded in place: the background into screen and bitmap, the shadow, the
// blob, the sample. One contiguous PRG from $0801, never crossing I/O.
.pc = SCREEN "screen (background colours)"
.import binary "bgscr.bin"
.pc = SHADOW "shadow silhouette"
.import binary "shadow.bin"
.pc = BITMAP "bitmap (background)"
.import binary "bg.bin"
.pc = BLOB "Ultimate SDK"
.import binary "../../bindings/blob/build-boing/ultimate-8000.bin"
.pc = PCM "boing sample, first piece"
.import binary "boing.pcm", 0, PCM_A
.pc = PCM2 "boing sample, second piece"
.import binary "boing.pcm", PCM_A, PCM_B
