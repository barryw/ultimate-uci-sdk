
;
; These are generic memory copy and fill routines.
;

;
; Fill a chunk of memory with a byte value.
;
; r0L value to store
; r1 target memory
; r2 number of bytes to store
;
FillMemory:
  ldy #$00
local_memory_0:
  lda r0L
  sta (r1), y
  M_Dec16 r2
  M_CmpWI r2, $0000
  beq local_memory_1
  iny
  bne local_memory_0
  inc r1H
  jmp local_memory_0

local_memory_1:
  rts

;
; Copy a chunk of memory
;
; r0 source memory
; r1 target memory
; r2 number of bytes to transfer
;
; Borrowed from https://github.com/mist64/geos/blob/2090bca64fc2627beef5c8232aafaec61f1f5a53/kernal/memory/memory2.s#L123
;
CopyMemory:
  lda r2L
  ora r2H
  beq local_memory_8
  M_PushW r0
  M_PushB r1H
  M_PushB r2H
  M_PushB r3L
local_memory_2:
  M_CmpW r0, r1
local_memory_3:
  bcs local_memory_4
  bcc local_memory_9
local_memory_4:
  ldy #0
  lda r2H
  beq local_memory_6
local_memory_5:
  lda (r0), y
  sta (r1), y
  iny
  bne local_memory_5
  inc r0H
  inc r1H
  dec r2H
  bne local_memory_5
local_memory_6:
  cpy r2L
  beq local_memory_7
  lda (r0), y
  sta (r1), y
  iny
  clv
  bvc local_memory_6
local_memory_7:
  M_PopB r3L
  M_PopB r2H
  M_PopB r1H
  M_PopW r0
local_memory_8:
  rts

local_memory_9:
  clc
  lda r2H
  adc r0H
  sta r0H
  clc
  lda r2H
  adc r1H
  sta r1H
  ldy r2L
  beq local_memory_11
local_memory_10:
  dey
  lda (r0), y
  sta (r1), y
  tya
  bne local_memory_10
local_memory_11:
  dec r0H
  dec r1H
  lda r2H
  beq local_memory_7
local_memory_12:
  dey
  lda (r0), y
  sta (r1), y
  tya
  bne local_memory_12
  dec r2H
  clv
  bvc local_memory_11
