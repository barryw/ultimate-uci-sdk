#importonce

/*

KickAssembler has a cool feature called 'pseudocommands' that let you build
your own pseudo instructions. They're similar to macros, but the calling
syntax very much resembles standard 6502 instructions.

*/


/* BFS: branch if flag set */
.pseudocommand bfs flag:location {
  lda flag
  bmi location
}

/* BFC: branch if flag clear */
.pseudocommand bfc flag:location {
  lda flag
  bpl location
}

/* CLF: clear flag */
.pseudocommand clf flag {
  Disable(flag)
}

/* SEF: set flag */
.pseudocommand sef flag {
  Enable(flag)
}

/* TGF: toggle flag */
.pseudocommand tgf flag {
  Toggle(flag)
}

/* WFS: wait for flag set */
.pseudocommand wfs flag {
!:
  bfc flag:!-
}

/* WFC: wait for flag clear */
.pseudocommand wfc flag {
!:
  bfs flag:!-
}

.pseudocommand vblank {
!:
  bit vic.SCROLY
  bpl !-
!:
  bit vic.SCROLY
  bmi !-
}

/* WFV: wait for value */
.pseudocommand wfv address:value {
!:
  jne address:value:!-
}

/* JNE: jump if not equal */
.pseudocommand jne address:value:location {
  lda address
  cmp value
  bne location
}

/* JEQ: jump if equal */
.pseudocommand jeq address:value:location {
  lda address
  cmp value
  beq location
}

/* STB: store byte */
.pseudocommand stb value:address {
  lda value
  sta address
}

/* MULT2: multiply the accumulator by 2 */
.pseudocommand mult2 {
  asl
}

/* DIV2: divide the accumulator by 2 */
.pseudocommand div2 {
  lsr
}

/* MULT4: multiply the accumulator by 4 */
.pseudocommand mult4 {
  asl
  asl
}

/* DIV4: divide the accumulator by 4 */
.pseudocommand div4 {
  lsr
  lsr
}

/* DIV8: divide the accumulator by 8 */
.pseudocommand div8 {
  div4
  lsr
}

/* DIV16: divide the accumulator by 16 */
.pseudocommand div16 {
  div4
  div4
}

/* MULT8: multiply the accumulator by 8 */
.pseudocommand mult8 {
  mult4
  asl
}

/* MULT16: multiply the accumulator by 16 */
.pseudocommand mult16 {
  mult4
  mult4
}

/* BRA: branch always */
.pseudocommand bra address {
  clv
  bvc address
}

