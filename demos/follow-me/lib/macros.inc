
.macro M_SetBank number

  lda #%11-number
  sta $dd00
.endmacro

.macro M_SetScreenAndCharLocation screen, charset

  lda #((screen & $3fff) / 64) | ((charset & $3fff) / 1024)
  sta $d018
.endmacro

.macro M_KernalOff

  lda #$7f
  sta $dc0d
  sta $dd0d

  lda #$35
  sta $01
.endmacro

.macro M_BlankScreen

  lda vic::SCROLY
  and #%11101111
  sta vic::SCROLY
.endmacro

.macro M_ShowScreen

  lda vic::SCROLY
  ora #%00010000
  sta vic::SCROLY
.endmacro

.macro M_ClearScreen screen, clearByte
 .local local_macros_0

  lda #clearByte
  ldx #0
local_macros_0:
  sta screen, x
  sta screen + $100, x
  sta screen + $200, x
  sta screen + $300, x
  inx
  bne local_macros_0
.endmacro

.macro M_ClearColorRam clearByte
 .local local_macros_1

  lda #clearByte
  ldx #0
local_macros_1:
  sta $d800, x
  sta $d800 + $100, x
  sta $d800 + $200, x
  sta $d800 + $300, x
  inx
  bne local_macros_1
.endmacro

.macro M_SetIrq address, line

  lda #<(address)
  sta $fffe
  lda #>(address)
  sta $ffff
  lda #line
  sta $d012
.endmacro

.macro M_WriteString screen, address

  lda #<(screen)
  sta r5L
  lda #>(screen)
  sta r5H
  lda #<(address)
  sta r6L
  lda #>(address)
  sta r6H
  jsr WriteString
.endmacro

;
;Store a 16 bit word
;
.macro M_StoreWord address, word

  pha
  lda #<(word)
  sta address
  lda #>(word)
  sta address + $01
  pla
.endmacro

;
;Toggle a flag
;
.macro M_Toggle address

  lda address
  eor #ENABLE
  sta address
.endmacro

;
;Disable a flag
;
.macro M_Disable address

  lda #DISABLE
  sta address
.endmacro

;
;Enable a flag
;
.macro M_Enable address

  lda #ENABLE
  sta address
.endmacro

;
;Copy the contents of the source address to the target address
;
.macro M_CpyW source, target

  lda source
  sta target
  lda source + $01
  sta target + $01
.endmacro

;
;Load a word into a target address
;
.macro M_CpyWI word, target

  lda #<(word)
  sta target
  lda #>(word)
  sta target + $01
.endmacro

;
;Copy a block of memory
;
.macro M_CpyM source, target, length

  M_CpyWI source, r0
  M_CpyWI target, r1
  M_CpyWI length, r2

  jsr CopyMemory
.endmacro

;
;Fill a chunk of memory with an immediate value
;
.macro M_FillMI value, target, length

  lda #value
  sta r0L
  M_CpyWI target, r1
  M_CpyWI length, r2

  jsr FillMemory
.endmacro

;
;Fill a chunk of memory with a value from memory
;
.macro M_FillM value, target, length

  lda value
  sta r0L
  M_CpyWI target, r1
  M_CpyWI length, r2

  jsr FillMemory
.endmacro

;
;Do a 16-bit increment of a memory location
;
.macro M_Inc16 word
 .local local_macros_2

  inc word
  bne local_macros_2
  inc word + $01
local_macros_2:
.endmacro

;
;Do a 16-bit decrement of a memory location
;
.macro M_Dec16 word
 .local local_macros_3

  lda word
  bne local_macros_3
  dec word + $01
local_macros_3:
  dec word
.endmacro

;
;Compare 2 bytes
;
.macro M_CmpB byte1, byte2

  lda byte1
  cmp byte2
.endmacro

;
;Compare a byte in memory with an immediate value
;
.macro M_CmpBI byte1, byte2

  lda byte1
  cmp #byte2
.endmacro

;
;Compare a word in memory to an immediate word value
;
.macro M_CmpWI word1, word2
 .local local_macros_4

  M_CmpBI word1 + $01, >(word2)
  bne local_macros_4
  M_CmpBI word1 + $00, <(word2)
local_macros_4:
.endmacro

;
;Compare 2 memory words
;
.macro M_CmpW word1, word2
 .local local_macros_5

  M_CmpB word1 + $01, word2 + $01
  bne local_macros_5
  M_CmpB word1 + $00, word2 + $00
local_macros_5:
.endmacro

;
;Push everything onto the stack. This lets us do whatever we want with the
;registers and put it back the way it was before returning. This is mostly
;used by the raster interrupt routine, but can be used anywhere.
;
.macro M_PushStack

  php
  pha
  txa
  pha
  tya
  pha
.endmacro

;
;Sets the registers and processor status back to the way they were
;
.macro M_PopStack

  pla
  tay
  pla
  tax
  pla
  plp
.endmacro

;
;Load a byte and push it onto the stack
;
.macro M_PushB address

  lda address
  pha
.endmacro

;
;Load a word and push it onto the stack
;
.macro M_PushW address

  M_PushB address + $01
  M_PushB address + $00
.endmacro

;
;Pop a byte from the stack and store it
;
.macro M_PopB address

  pla
  sta address
.endmacro

;
;Pop a word from the stack and store it
;
.macro M_PopW address

  M_PopB address + $00
  M_PopB address + $01
.endmacro

;
;Create a timer
;
.macro M_CreateTimer number, enabled, type, frequency, location

  M_CpyWI frequency, r0
  M_CpyWI location, r1
  lda #type
  sta r2L
  lda #number
  sta r2H
  lda #enabled
  sta r3L

  jsr CreateTimer
.endmacro

;
;Disable a timer
;
.macro M_DisableTimer number

  lda #number
  sta r2H
  lda #DISABLE
  sta r3L

  jsr EnDisTimer
.endmacro

;
;Enable a timer
;
.macro M_EnableTimer number

  lda #number
  sta r2H
  lda #ENABLE
  sta r3L

  jsr EnDisTimer
.endmacro
