#importonce

.macro SetBank(number) {
  lda #%11-number
  sta $dd00
}

.macro SetScreenAndCharLocation(screen, charset) {
  lda #[[screen & $3fff] / 64] | [[charset & $3fff] / 1024]
  sta $d018
}

.macro KernalOff() {
  lda #$7f
  sta $dc0d
  sta $dd0d

  lda #$35
  sta $01
}

.macro BlankScreen() {
  lda vic.SCROLY
  and #%11101111
  sta vic.SCROLY
}

.macro ShowScreen() {
  lda vic.SCROLY
  ora #%00010000
  sta vic.SCROLY
}

.macro ClearScreen(screen, clearByte) {
  lda #clearByte
  ldx #0
!:
  sta screen, x
  sta screen + $100, x
  sta screen + $200, x
  sta screen + $300, x
  inx
  bne !-
}

.macro ClearColorRam(clearByte) {
  lda #clearByte
  ldx #0
!:
  sta $d800, x
  sta $d800 + $100, x
  sta $d800 + $200, x
  sta $d800 + $300, x
  inx
  bne !-
}

.macro SetIrq(address, line) {
  lda #<address
  sta $fffe
  lda #>address
  sta $ffff
  lda #line
  sta $d012
}

.macro WriteString(screen, address) {
  stb #<screen:r5L
  stb #>screen:r5H
  stb #<address:r6L
  stb #>address:r6H
  jsr WriteString
}

/*
Store a 16 bit word
*/
.macro StoreWord(address, word) {
  pha
  lda #<word
  sta address
  lda #>word
  sta address + $01
  pla
}

/*
Toggle a flag
*/
.macro Toggle(address) {
  lda address
  eor #ENABLE
  sta address
}

/*
Disable a flag
*/
.macro Disable(address) {
  stb #DISABLE:address
}

/*
Enable a flag
*/
.macro Enable(address) {
  stb #ENABLE:address
}

/*
Copy the contents of the source address to the target address
*/
.macro CpyW(source, target) {
  stb source:target
  stb source + $01:target + $01
}

/*
Load a word into a target address
*/
.macro CpyWI(word, target) {
  stb #<word:target
  stb #>word:target + $01
}

/*
Copy a block of memory
*/
.macro CpyM(source, target, length) {
  CpyWI(source, r0)
  CpyWI(target, r1)
  CpyWI(length, r2)

  jsr CopyMemory
}

/*
Fill a chunk of memory with an immediate value
*/
.macro FillMI(value, target, length) {
  stb #value:r0L
  CpyWI(target, r1)
  CpyWI(length, r2)

  jsr FillMemory
}

/*
Fill a chunk of memory with a value from memory
*/
.macro FillM(value, target, length) {
  stb value:r0L
  CpyWI(target, r1)
  CpyWI(length, r2)

  jsr FillMemory
}

/*
Do a 16-bit increment of a memory location
*/
.macro Inc16(word) {
  inc word
  bne !+
  inc word + $01
!:
}

/*
Do a 16-bit decrement of a memory location
*/
.macro Dec16(word) {
  lda word
  bne !+
  dec word + $01
!:
  dec word
}

/*
Compare 2 bytes
*/
.macro CmpB(byte1, byte2) {
  lda byte1
  cmp byte2
}

/*
Compare a byte in memory with an immediate value
*/
.macro CmpBI(byte1, byte2) {
  lda byte1
  cmp #byte2
}

/*
Compare a word in memory to an immediate word value
*/
.macro CmpWI(word1, word2) {
  CmpBI(word1 + $01, >word2)
  bne !+
  CmpBI(word1 + $00, <word2)
!:
}

/*
Compare 2 memory words
*/
.macro CmpW(word1, word2) {
  CmpB(word1 + $01, word2 + $01)
  bne !+
  CmpB(word1 + $00, word2 + $00)
!:
}

/*
Push everything onto the stack. This lets us do whatever we want with the
registers and put it back the way it was before returning. This is mostly
used by the raster interrupt routine, but can be used anywhere.
*/
.macro PushStack() {
  php
  pha
  txa
  pha
  tya
  pha
}

/*
Sets the registers and processor status back to the way they were
*/
.macro PopStack() {
  pla
  tay
  pla
  tax
  pla
  plp
}

/*
Load a byte and push it onto the stack
*/
.macro PushB(address) {
  lda address
  pha
}

/*
Load a word and push it onto the stack
*/
.macro PushW(address) {
  PushB(address + $01)
  PushB(address + $00)
}

/*
Pop a byte from the stack and store it
*/
.macro PopB(address) {
  pla
  sta address
}

/*
Pop a word from the stack and store it
*/
.macro PopW(address) {
  PopB(address + $00)
  PopB(address + $01)
}

/*
Create a timer
*/
.macro CreateTimer(number, enabled, type, frequency, location) {
  CpyWI(frequency, r0)
  CpyWI(location, r1)
  stb #type:r2L
  stb #number:r2H
  stb #enabled:r3L

  jsr CreateTimer
}

/*
Disable a timer
*/
.macro DisableTimer(number) {
  stb #number:r2H
  stb #DISABLE:r3L

  jsr EnDisTimer
}

/*
Enable a timer
*/
.macro EnableTimer(number) {
  stb #number:r2H
  stb #ENABLE:r3L

  jsr EnDisTimer
}

