
.scope kernal
  LSTX = $c5
  CINV = $0314
  IRQVEC = $0314

  CBINV = $0316
  NMINV = $0318

  ; KERNAL vectors
  IOPEN = $031a
  ICLOSE = $031c
  ICHKIN = $031e
  ICKOUT = $0320
  ICLRCH = $0322
  IBASIN = $0324
  IBSOUT = $0326
  ISTOP = $0328
  IGETIN = $032a
  ICLALL = $032c
  USRCMD = $032e
  ILOAD = $0330
  ISAVE = $0332

  FREE1 = $0334 ; 8 free bytes (0334 - 033b)
  TBUFFER = $033c ; cassette buffer (033c - 03fb)
  FREE2 = $03fc ; 4 free bytes (03fc - 03ff)

  POLY1 = $e043
  POLY2 = $e059
  RMULC = $e08d
  RADDC = $e092
  RND = $e097
  SYS = $e12a
  SAVE = $e156
  VERIFY = $e165
  LOAD = $e168
  OPEN = $e1be
  CLOSE = $e1c7

  CLRSCR = $e544
  HOME = $e566

  IRQNOR = $ea31

  ; KERNAL jump Table
  VEC_CINT = $ff81
  VEC_IOINIT = $ff84
  VEC_RAMTAS = $ff87
  VEC_RESTOR = $ff8a
  VEC_VECTOR = $ff8d
  VEC_SETMSG = $ff90
  VEC_SECOND = $ff93
  VEC_TKSA = $ff96
  VEC_MEMBOT = $ff99
  VEC_MEMTOP = $ff9c
  VEC_SCNKEY = $ff9f
  VEC_SETTMO = $ffa2
  VEC_ACPTR = $ffa5
  VEC_CIOUT = $ffa8
  VEC_UNTLK = $ffab
  VEC_UNLSN = $ffae
  VEC_LISTEN = $ffb1
  VEC_TALK = $ffb4
  VEC_READST = $ffb7
  VEC_SETLFS = $ffba
  VEC_SETNAM = $ffbd
  VEC_OPEN = $ffc0
  VEC_CLOSE = $ffc3
  VEC_CHKIN = $ffc6
  VEC_CHKOUT = $ffc9
  VEC_CLRCHN = $ffcc
  VEC_CHRIN = $ffcf
  VEC_CHROUT = $ffd2 ; https://www.c64-wiki.com/wiki/CHROUT
  VEC_LOAD = $ffd5
  VEC_SAVE = $ffd8
  VEC_SETTIM = $ffdb
  VEC_RDTIM = $ffde
  VEC_STOP = $ffe1
  VEC_GETIN = $ffe4
  VEC_CLALL = $ffe7
  VEC_UDTIM = $ffea
  VEC_SCREEN = $ffed
  VEC_PLOT = $fff0 ; https://www.c64-wiki.com/wiki/PLOT_(KERNAL)
  VEC_IOBASE = $fff3

  VEC_NMI = $fffa ; NMI vector
  VEC_RESET = $fffc ; Hardware reset vector
  VEC_IRQ = $fffe ; IRQ / BRK vector
.endscope
