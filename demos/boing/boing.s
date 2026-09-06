; boing.s - the Amiga Boing ball out of multiplexed hardware sprites, with a
; software-composited vsprite shadow, a perspective floor, and the boing as PCM.
;
; The ball is 2 sprite columns by 4 sprite rows, every position drawn twice:
; a white sprite with the white tiles and a red sprite with the red ones.
; Sixteen sprites a frame, so the eight hardware sprites are multiplexed:
; sprites 0-3 draw rows 0 and 2, sprites 4-7 rows 1 and 3, and two raster
; interrupts move them down once a row has been displayed. Only the white
; layer is stored per rotation frame; red = disc AND NOT white, built at run
; time into one of two live sprite sets and flipped at vblank.
;
; The shadow is a vsprite similar to an Amiga blitter object, but composited
; by the 6510 without a blitter: an ellipse ORed into the hires bitmap to the
; ball's lower right, with covered cells recoloured dark grey. One bitmap, so
; each frame restores what the shadow covered last time from a clean copy of
; the background held in the REU, then draws it again - done right after the
; vblank sync, and the ball's sprites float over it. The boing plays through
; the Ultimate's PCM engine from the REU on every bounce.
;
; The SDK (selectively linked at $8000, its RAM at $5900): turbo, REU,
; software-vsprite drawing,
; stash/fetch, audio init/configure/start/stop. UCI and turbo are mandatory;
; without either the SYS returns to BASIC. REU and audio remain optional.
;
; Status block at $033c: "BONG", frames (16-bit) +4, x lo/hi +6, y +8,
; rotation frame +9, flags +10 (1 turbo, 2 REU and shadow, 4 audio), bounces
; +11, last SDK result +12, host: +13 = 1 turns the shadow off.
; SPDX-License-Identifier: MIT

.include "ultimate.inc"
.segment "LOADADDR"
.word $0801
.segment "STARTUP"
.word $080b, 10
.byte $9e, "2304", 0
.word 0
.segment "DEMO"

STATUS = $033c
SCREEN = $4000
LIVE_A = $4400        ; 16 sprites x 64 bytes
LIVE_B = $4800
BITMAP = $6000
SHADOW = $4c00        ; 12 x 84 ellipse, row-major, from shadow.bin
SCRATCH = $5000        ; 13 x 84, the ellipse shifted, column-major
SCR_CLEAN = $5500       ; the 1000 screen RAM bytes, restored per cell
PCM = $ad30        ; boing.pcm, stashed to the REU at start
PCM2 = $e000        ; second piece, under the KERNAL ($01 = $35)
PTR_A = (LIVE_A - $4000) / 64   ; 16
PTR_B = (LIVE_B - $4000) / 64   ; 32

REU_BG = $0000        ; clean background in the REU, 8000 bytes
REU_PCM = $4000
.include "boing_pcm.inc"     ; PCM_LEN and PCM_RATE, written by mkpcm.py

XMAX = 320 - 96     ; ball x, relative to the visible left edge
YMAX = 96           ; ball bottom 4 px below the wall/floor line at 176
GRAV = 20           ; 1/256 px per frame per frame
VBLANK = 250
COL_BG = $0c          ; grey field
SHADOW_CELL = ($0b << 4) | COL_BG   ; dark grey foreground
SHX = 12           ; shadow offset from the ball: just off the wall
SHY = 0
SH_ROWS = 84
SH_COLS = 13

zpS = $02
zpN = $06
zpScr = $10
zpRow = $13
zpSeg = $14
zpOut = $20             ; 13 bytes, one shifted ellipse row

ST_FRAMES = STATUS + 4
ST_X = STATUS + 6
ST_Y = STATUS + 8
ST_ROT = STATUS + 9
ST_FLAGS = STATUS + 10
ST_BOUNCE = STATUS + 11
ST_RESULT = STATUS + 12
ST_NOSHADOW = STATUS + 13
ST_PROBE = STATUS + 15   ; host: 1 = fetch REU $4000..$43ff to $b900, then clear


main:
    jsr require_uci_turbo
    cmp #ULTIMATE_OK
    beq start
no_ultimate:
    rts

start:
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
    lda #1
    sta ST_FLAGS

    jsr clear_live
    ; the PRG loaded the background straight into SCREEN and BITMAP; keep a
    ; clean copy of the 1000 screen bytes for the shadow's cell restore
    ldx #0
local_boing_0:  lda SCREEN, x
    sta SCR_CLEAN, x
    lda SCREEN+$100, x
    sta SCR_CLEAN+$100, x
    lda SCREEN+$200, x
    sta SCR_CLEAN+$200, x
    lda SCREEN+$300, x
    sta SCR_CLEAN+$300, x
    inx
    bne local_boing_0

    jsr sdk_init

    ; sprites: colours, expansion, all on, over the bitmap
    ldx #0
local_boing_1:  lda spr_colour, x
    sta $d027, x
    inx
    cpx #8
    bne local_boing_1
    lda #$ff
    sta $d01d          ; X expanded
    sta $d015
    lda #0
    sta $d017
    sta $d01c
    sta $d01b

    ; ball state
    lda #64
    sta ball_x
    lda #1
    sta vx
    lda #0
    sta ball_y
    sta ball_y+1
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
    jsr build_set      ; frame 0 into the set next_base names
    jsr next_positions

    ; VIC: hires bitmap, bank 1, raster IRQ at vblank
    lda $dd02
    ora #3
    sta $dd02
    lda #%00000010
    sta $dd00
    lda #$08           ; screen +$0000, bitmap +$2000
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
    jsr shadow_frame   ; restore then draw, in the frame that just started
    jsr physics
    jsr next_positions
    lda bounce
    beq local_boing_2
    lda #0
    sta bounce
    inc ST_BOUNCE
    inc STATUS + 16     ; trigger counter, for the host
    lda #1
    sta snd             ; the vblank IRQ plays it, as the first version did
local_boing_2:  lda rot
    cmp built_rot
    beq loop
    ; the other set is free until the next flip
    lda #PTR_A
    ldx cur_base
    cpx #PTR_A
    bne local_boing_3
    lda #PTR_B
local_boing_3:  sta next_base
    jsr build_set
    jmp loop

rti_only:
    rti

; ---------------------------------------------------------------------------
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
    ; rows 0 and 1 from the values the main loop prepared
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
local_boing_4:  clc
    adc #0
    sta SCREEN + $3f8, x
    clc
    adc #1
    inx
    cpx #8
    bne local_boing_4
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
    ; row 2: sprites 0-3 again, one row lower
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
    ; row 3: sprites 4-7 again
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
    lda snd             ; a bounce this frame: play it from interrupt context,
    beq done_nosnd      ; as the first version did
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

; ---------------------------------------------------------------------------
; Refuse to start without a working UCI and max turbo. This runs before main
; changes the C64's interrupt and memory configuration, so failure can return
; directly to BASIC.
require_uci_turbo:
    jsr ultimate_init
    cmp #ULTIMATE_OK
    bne local_boing_5
    jsr ultimate_turbo_available
    cmp #1
    bne no_turbo
    lda #U64_SPEED_MAX
    jsr ultimate_turbo_set
    cmp #ULTIMATE_OK
    bne local_boing_5
    lda #0
    jsr ultimate_turbo_badlines
local_boing_5:  rts
no_turbo:
    lda #ULTIMATE_ERR_NOT_SUPPORTED
    rts

; REU (clean background and the sample stashed) and audio (a configured
; channel) are optional. A failure leaves their flags clear.
sdk_init:
    jsr ultimate_reu_available
    cmp #1
    beq local_boing_6
    rts
local_boing_6:  lda #<BITMAP
    sta ult_addr
    lda #>BITMAP
    sta ult_addr+1
    lda #0
    sta ult_reu
    sta ult_reu+1
    sta ult_reu+2
    sta ult_reu+3
    sta ult_reulen+2
    sta ult_reulen+3
    lda #<8000
    sta ult_reulen
    lda #>8000
    sta ult_reulen+1
    jsr ultimate_reu_stash
    ora #0
    sta ST_RESULT
    beq local_boing_7
    rts
local_boing_7:  lda #<PCM
    sta ult_addr
    lda #>PCM
    sta ult_addr+1
    lda #<REU_PCM
    sta ult_reu
    lda #>REU_PCM
    sta ult_reu+1
    lda #<PCM_A
    sta ult_reulen
    lda #>PCM_A
    sta ult_reulen+1
    jsr ultimate_reu_stash
    ora #0
    sta ST_RESULT
    beq local_boing_8
    rts
local_boing_8:  lda #<PCM2          ; the second piece, straight after the first in the REU
    sta ult_addr
    lda #>PCM2
    sta ult_addr+1
    lda #<(REU_PCM + PCM_A)
    sta ult_reu
    lda #>(REU_PCM + PCM_A)
    sta ult_reu+1
    lda #<PCM_B
    sta ult_reulen
    lda #>PCM_B
    sta ult_reulen+1
    jsr ultimate_reu_stash
    ora #0
    sta ST_RESULT
    beq local_boing_9
    rts
local_boing_9:  lda ST_FLAGS
    ora #2
    sta ST_FLAGS
    jsr ultimate_audio_init
    sta ST_RESULT
    cmp #0
    beq local_boing_10
    rts
local_boing_10:  jsr voice_setup
    lda #<voice
    ldx #>voice
    jsr ultimate_audio_configure
    ora #0
    sta ST_RESULT
    beq local_boing_11
    rts
local_boing_11:  lda ST_FLAGS
    ora #4
    sta ST_FLAGS
    rts

; ---------------------------------------------------------------------------
; Ball motion: x at one pixel a frame between the walls, y with gravity and an
; elastic floor, rotation one frame every other screen frame, following x.
; Every wall or floor hit sets `bounce`.
physics:
    lda ball_x
    clc
    adc vx
    sta ball_x
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
    lda ball_y
    clc
    adc vy
    sta ball_y
    lda ball_y+1
    adc vy+1
    sta ball_y+1
    lda vy
    clc
    adc #GRAV
    sta vy
    bcc local_boing_12
    inc vy+1
local_boing_12:  lda ball_y+1
    bmi above_top
    cmp #YMAX
    bcc ydone
    lda #YMAX
    sta ball_y+1
    lda #0
    sta ball_y
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
    sta ball_y
    sta ball_y+1
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
    lda ball_x
    sta ST_X
    lda #0
    sta ST_X+1
    lda ball_y+1
    sta ST_Y
    lda rot
    sta ST_ROT
    rts

next_positions:
    lda ball_x
    clc
    adc #24
    sta next_x0
    lda ball_x
    clc
    adc #72
    sta next_x1
    lda #0
    bcc local_boing_13
    lda #%11001100     ; column 1 sprites: 2, 3, 6, 7
local_boing_13:  sta next_msb
    lda ball_y+1
    clc
    adc #50
    sta next_y
    rts

; ---------------------------------------------------------------------------
; Copy rotation frame `rot` into the set next_base names: white as is, red =
; disc AND NOT white. 8 positions, 63 bytes each.
build_set:
    lda rot
    sta built_rot
    asl a
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
    beq local_boing_14
    lda #>LIVE_B
local_boing_14:  sta bdw+2
    sta bdr+2
    lda bdw+1
    clc
    adc #64
    sta bdr+1
    bcc local_boing_15
    inc bdr+2
local_boing_15:  ldx #8
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
    bcc local_boing_16
    inc bsrc+2
local_boing_16:  lda bdisc+1
    clc
    adc #64
    sta bdisc+1
    bcc local_boing_17
    inc bdisc+2
local_boing_17:  lda bdw+1
    clc
    adc #128
    sta bdw+1
    bcc local_boing_18
    inc bdw+2
local_boing_18:  lda bdr+1
    clc
    adc #128
    sta bdr+1
    bcc local_boing_19
    inc bdr+2
local_boing_19:  dex
    bne bpos
    rts

clear_live:
    lda #0
    ldx #0
local_boing_20:  .repeat 8, p

        sta LIVE_A + p*256, x
    .endrepeat
    inx
    bne local_boing_20
    rts

; ---------------------------------------------------------------------------
; The shadow. Restore what the last one covered (bitmap from the REU clean
; copy, cells from SCR_CLEAN), then OR the shifted ellipse in and recolour
; every cell it touches dark grey.
shadow_frame:
    lda ST_FLAGS
    and #2
    bne local_boing_21
    rts
local_boing_21:  lda ST_NOSHADOW
    beq local_boing_22
    rts
local_boing_22:  lda sh_valid
    beq shnew
    jsr shadow_restore
shnew:
    lda ball_x
    clc
    adc #SHX
    sta sh_sx
    lda #0
    rol a; the ninth bit: x + SHX passes 255 near the right wall
    sta sh_hi
    lda sh_sx
    and #7
    cmp last_shift
    beq local_boing_23
    sta last_shift
    jsr shift_silhouette
local_boing_23:  lda sh_sx
    lsr a
    lsr a
    lsr a
    ldx sh_hi
    beq local_boing_24
    clc
    adc #32             ; columns 32..39; the clip below trims the count
local_boing_24:  sta sh_c0
    lda #40
    sec
    sbc sh_c0
    cmp #SH_COLS
    bcc local_boing_25
    lda #SH_COLS
local_boing_25:  sta sh_ncols
    lda ball_y+1
    clc
    adc #SHY
    sta sh_sy
    and #7
    sta sh_yin
    lda sh_sy
    lsr a
    lsr a
    lsr a
    sta sh_cr0
    lda #SH_ROWS + 7
    clc
    adc sh_yin
    lsr a
    lsr a
    lsr a
    sta sh_nseg
    lda #25
    sec
    sbc sh_cr0
    cmp sh_nseg
    bcs local_boing_26
    sta sh_nseg
local_boing_26:  jsr shadow_draw
shadow_done:
    lda #1
    sta sh_valid
    rts

; Restore: one 8-line run of ncols*8 bytes per covered cell row from the REU,
; and the covered cells from SCR_CLEAN. Uses the sh_r_* record the last draw
; left, so a moving shadow leaves no trail.
shadow_restore:
    lda sh_r_cr0
    sta zpN
    lda sh_r_nseg
    sta zpSeg
    lda #0
    sta ult_reu+2
    sta ult_reu+3
    sta ult_reulen+1
    sta ult_reulen+2
    sta ult_reulen+3
rrow:
    ldy zpN
    lda row320_lo, y
    clc
    adc sh_r_c0x8
    sta ult_reu
    sta ult_addr
    lda row320_hi, y
    adc sh_r_c0x8h
    sta ult_reu+1
    clc
    adc #>BITMAP
    sta ult_addr+1
    lda sh_r_ncols
    asl a
    asl a
    asl a
    sta ult_reulen
    jsr ultimate_reu_fetch
    ora #0
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
local_boing_27:  lda (zpS), y
    sta (zpScr), y
    dey
    bpl local_boing_27
    inc zpN
    dec zpSeg
    bne rrow
    rts

; The ellipse shifted right by (sx & 7) into SCRATCH, column-major: byte c of
; row r at SCRATCH + c*84 + r.
shift_silhouette:
    lda #<SHADOW
    sta zpS
    lda #>SHADOW
    sta zpS+1
    lda #0
    sta zpRow
srow:
    ldy #11
local_boing_28:  lda (zpS), y
    sta zpOut, y
    dey
    bpl local_boing_28
    lda #0
    sta zpOut+12
    ldx last_shift
    beq sstore
sshift:
    clc
    .repeat 13, i

        ror zpOut + i
    .endrepeat
    dex
    bne sshift
sstore:
    ldy zpRow
    .repeat 13, c

        lda zpOut + c
        sta SCRATCH + c*84, y
    .endrepeat
    lda zpS
    clc
    adc #12
    sta zpS
    bcc local_boing_29
    inc zpS+1
local_boing_29:  inc zpRow
    lda zpRow
    cmp #SH_ROWS
    beq local_boing_30
    jmp srow
local_boing_30:  rts

; Draw the shifted ellipse into the bitmap and recolour the cells; remember
; what was covered so the next restore can undo exactly this.
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
    asl a
    asl a
    asl a
    sta sh_r_c0x8
    lda #0
    rol a; column 32 and up: c0*8 needs a ninth bit
    sta sh_r_c0x8h
    lda sh_c0
    sta vs_desc + VSPRITE_X
    lda sh_sy
    sta vs_desc + VSPRITE_Y
    lda sh_ncols
    sta vs_desc + VSPRITE_WIDTH
    lda #<vs_desc
    ldx #>vs_desc
    jsr ultimate_vsprite_draw
    ora #0
    sta ST_RESULT
    rts

; ---------------------------------------------------------------------------
; The boing: channel 0, 8-bit mono, one shot, from the REU. Reconfigured on
; every bounce so a boing still playing starts over.
voice_setup:
    ldx #UA_VOICE_SIZE - 1
    lda #0
local_boing_31:  sta voice, x
    dex
    bpl local_boing_31
    lda #UA_VOLUME_MAX
    sta voice + UA_VOICE_VOLUME
    lda #UA_PAN_CENTER
    sta voice + UA_VOICE_PAN
    lda #<REU_PCM
    sta voice + UA_VOICE_REU
    lda #>REU_PCM
    sta voice + UA_VOICE_REU + 1
    lda #<PCM_LEN
    sta voice + UA_VOICE_LENGTH
    sta voice + UA_VOICE_REPEAT_B
    lda #>PCM_LEN
    sta voice + UA_VOICE_LENGTH + 1
    sta voice + UA_VOICE_REPEAT_B + 1
    lda #<PCM_RATE
    sta voice + UA_VOICE_RATE
    lda #>PCM_RATE
    sta voice + UA_VOICE_RATE + 1
    rts

; Host probe: pull the first 1 KB of the stashed sample back out of the REU
; so the host can compare it with the file it came from.
reu_probe:
    lda ST_PROBE
    bne local_boing_32
    rts
local_boing_32:  cmp #2
    bne local_boing_33
    lda #0
    sta ult_reu
    sta ult_reu+1
    jmp local_boing_34
local_boing_33:  lda #<REU_PCM
    sta ult_reu
    lda #>REU_PCM
    sta ult_reu+1
local_boing_34:  lda #$00
    sta ult_addr
    lda #$b9
    sta ult_addr+1
    lda #0
    sta ult_reu+2
    sta ult_reu+3
    sta ult_reulen
    sta ult_reulen+2
    sta ult_reulen+3
    lda #4
    sta ult_reulen+1
    jsr ultimate_reu_fetch
    ora #0
    sta ST_RESULT
    lda #0
    sta ST_PROBE
    rts

play_boing:
    lda ST_FLAGS
    and #4
    bne local_boing_35
    rts
local_boing_35:
    lda #0
    jsr ultimate_audio_stop
    lda #<voice
    ldx #>voice
    jsr ultimate_audio_configure
    lda #0
    ldx #0
    jsr ultimate_audio_start
    ora #0
    sta ST_RESULT
    rts

; ---------------------------------------------------------------------------
spr_colour: .byte $01, $02, $01, $02, $01, $02, $01, $02

row320_lo:  .repeat 25, i
.byte <(i*320)
    .endrepeat
row320_hi:  .repeat 25, i
.byte >(i*320)
    .endrepeat
row40_lo:   .repeat 25, i
.byte <(i*40)
    .endrepeat
row40_hi:   .repeat 25, i
.byte >(i*40)
    .endrepeat

ball_x:          .byte 0
vx:         .byte 0
ball_y:          .word 0
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
sh_r_c0:    .byte 0     ; what the last draw covered, for the restore
sh_r_c0x8:  .byte 0
sh_r_c0x8h: .byte 0
sh_r_ncols: .byte 0
sh_r_cr0:   .byte 0
sh_r_nseg:  .byte 0

vs_desc:
    .word BITMAP
    .word SCRATCH
    .word 0
    .word SCREEN
    .byte 0, 0, SH_COLS, SH_ROWS, SHADOW_CELL, VSPRITE_F_COLOR

voice: .repeat UA_VOICE_SIZE, i
.byte 0
    .endrepeat

.align $100
disc:
.incbin "disc.bin"
.align $100
ball:
.incbin "ball.bin"

; ---------------------------------------------------------------------------
; Loaded in place: the background into screen and bitmap, the shadow, the
; linked SDK, and sample. The sample skips the I/O area at $d000-$dfff.
.segment "SCREEN"
.incbin "bgscr.bin"
.segment "SHADOW"
.incbin "shadow.bin"
.segment "BITMAP"
.incbin "bg.bin"
.segment "PCM"
.incbin "boing.pcm", 0, PCM_A
.segment "PCM2"
.incbin "boing.pcm", PCM_A, PCM_B
