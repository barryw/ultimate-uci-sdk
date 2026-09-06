
; 8 timers of 8 bytes each
; struct is as follows:
; 0   - enabled/disabled
; 1   - type: oneshot or continuous
; 2,3 - current value
; 4,5 - frequency
; 6,7 - call location on fire
c64lib_timers = kernal::TBUFFER

ReturnAddress:
  .word $0000

;
; These routines can be used to create and fire single-shot and continuous timers. The UpdateTimers
; routine should be called 60 times a second.
;
; Each timer is comprised of 8 bytes:
;
; 0   - enabled/disabled (1 = enabled)
; 1   - single-shot/continuous (0 = single-shot)
; 2,3 - the timer's current value
; 4,5 - the timer's frequency (60 = 1 second)
; 6,7 - the address of the routine to call when the timer fires
;
; The 8 timers are stored in memory 'c64lib_timers'
;

;
; Clear memory used for timers
;
ClearTimers:
  M_FillMI $00, c64lib_timers, TIMER_STRUCT_BYTES
  rts

;
; Create a timer that fires either on a schedule or as a single shot
;
; r0 frequency in 60ths of a second (60 = wait 1 second)
; r1 location to call when timer fires
; r2L single shot or continuous (0 = single shot, 1 = continuous)
; r2H timer number (0 - 7)
; r3L enabled or disabled (0 = disabled, 1 = enabled)
;
CreateTimer:
  lda r2H
  asl a
  asl a
  asl a
  tax
  lda r3L ; enabled
  sta c64lib_timers, x
  lda r2L ; type
  sta c64lib_timers + $01, x
  lda r0L ; current value
  sta c64lib_timers + $02, x
  lda r0H
  sta c64lib_timers + $03, x
  lda r0L ; frequency
  sta c64lib_timers + $04, x
  lda r0H
  sta c64lib_timers + $05, x
  lda r1L ; address
  sta c64lib_timers + $06, x
  lda r1H
  sta c64lib_timers + $07, x

  rts


;
;  Call this every 1/60th of a second. It is responsible for updating timers and calling timer
;  targets when it's their time to run.
;
UpdateTimers:
  ldy #$00
local_timers_0:
  tya
  asl a
  asl a
  asl a
  sta r0L
  tax
  ; Is the timer enabled?
  lda c64lib_timers, x
  cmp #ENABLE
  bne local_timers_4
  inx
  lda c64lib_timers, x
  sta r3H
  inx
  stx r1H
  lda c64lib_timers, x ; current value
  bne local_timers_1
  dec c64lib_timers + $01, x
local_timers_1:
  dec c64lib_timers, x

  lda c64lib_timers, x
  bne local_timers_4
  lda c64lib_timers + $01, x
  bne local_timers_4

  ; Counter has hit 0 - reset it
  inx
  inx
  lda c64lib_timers, x
  sta r2L
  inx
  lda c64lib_timers, x
  sta r2H

  lda r1H
  tax

  lda r2L
  sta c64lib_timers, x
  inx
  lda r2H
  sta c64lib_timers, x

  inx
  inx
  inx
  tya
  pha

  ; Set up the vector to point at the timer's routine
  lda c64lib_timers, x
  sta r2L
  inx
  lda c64lib_timers, x
  sta r2H

  ; Call the timer's routine
  jsr local_timers_2
  jmp local_timers_3

local_timers_2:
  jmp (r2)

local_timers_3:
  pla
  tay

  ; If the timer is continuous, skip the disabling of it
  lda r3H
  cmp #TIMER_CONTINUOUS
  beq local_timers_4

  ; For single shot timers, disable it after the first execution
  ldx r0L
  lda #DISABLE
  sta c64lib_timers, x

local_timers_4:
  iny
  cpy #$07
  bne local_timers_0

  rts

;
; Enable or disable a timer
;
; r2H the timer to control
; r3L enable or disable (0 = disable, 1 = enable)
;
EnDisTimer:
  lda r2H
  asl a
  asl a
  asl a
  tax
  lda r3L
  sta c64lib_timers, x
  rts

;
;  Pause for the specified number of jiffies (1/60 seconds). Resolution is only a single
;  byte, so the max pause time is ~4.2seconds
;
;  Requires:
;  r7L: the number of jiffies to pause for
;
PauseJiffies:
  lda r7L
  clc
  adc Clock
  sta r7L
local_timers_5:
  lda Clock
  cmp r7L
  bne local_timers_5

  rts
