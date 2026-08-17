; relocharness.s - load the blob at one address, move it to another, call it.
;
; The blob is built for $C000 and lives at $C000 in the test image. This moves
; it to $8000 and exposes both t_reloc (the move) and t_call_init (a call
; through the moved jump table) to the suite. Completeness is proved there,
; not here: blob-relocated.suite compares the moved blob byte-for-byte against
; a second blob the linker built directly for $8000, which is what actually
; catches a missing or wrongly-included relocation entry.
;
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"

        .forceimport __STARTUP__
        .export _main

        .import blob_relocate
        .export blob_table
        .export t_reloc, t_call_init, result

BLOB_SRC = $C000
BLOB_DST = $8000

        .bss
result: .res 1

        .rodata
; Assembled from tests/emulator, so the path is relative to there.
blob_table:
        .incbin "../../bindings/blob/build/ultimate-c000.reloc"

        .code

_main:  rts

; Copy $C000..$CFFF down to $8000, then fix up the addresses.
t_reloc:
        ldx #$00
@page:  lda BLOB_SRC,x
        sta BLOB_DST,x
        lda BLOB_SRC + $100,x
        sta BLOB_DST + $100,x
        lda BLOB_SRC + $200,x
        sta BLOB_DST + $200,x
        lda BLOB_SRC + $300,x
        sta BLOB_DST + $300,x
        lda BLOB_SRC + $400,x
        sta BLOB_DST + $400,x
        lda BLOB_SRC + $500,x
        sta BLOB_DST + $500,x
        lda BLOB_SRC + $600,x
        sta BLOB_DST + $600,x
        lda BLOB_SRC + $700,x
        sta BLOB_DST + $700,x
        lda BLOB_SRC + $800,x
        sta BLOB_DST + $800,x
        lda BLOB_SRC + $900,x
        sta BLOB_DST + $900,x
        lda BLOB_SRC + $A00,x
        sta BLOB_DST + $A00,x
        lda BLOB_SRC + $B00,x
        sta BLOB_DST + $B00,x
        inx
        bne @page

        lda #<BLOB_DST
        ldx #>BLOB_DST
        ldy #$C0                ; $80 - $C0 = -$40 pages, as a byte add
        jsr blob_relocate
        rts

t_call_init:
        jsr BLOB_DST + $04
        sta result
        rts
