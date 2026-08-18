; relocharness.s - load the blob at one address, move it to another, call it.
;
; The blob is built for $8000 and lives at $8000 in the test image. This moves
; it to $6000 and exposes both t_reloc (the move) and t_call_init (a call
; through the moved jump table) to the suite. Completeness is proved there,
; not here: blob-relocated.suite compares the moved blob byte-for-byte against
; a second blob the linker built directly for $6000, which is what actually
; catches a missing or wrongly-included relocation entry.
;
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"
; BLOB_SIZE, written by tests/emulator/Makefile from the binary it just built.
; The copy below used to be twelve unrolled pages, hard-wired: the blob reached
; 3060 bytes the moment the palette service landed, twelve bytes short of
; silently copying less than the whole thing.
        .include "blobsize.inc"

        .forceimport __STARTUP__
        .export _main

        .import blob_relocate
        .export blob_table
        .export t_reloc, t_call_init, result

BLOB_SRC = $8000
BLOB_DST = $6000
BLOB_PAGES = (BLOB_SIZE + $FF) / $100

        .bss
result: .res 1

        .rodata
; Assembled from tests/emulator, so the path is relative to there.
blob_table:
        .incbin "../../bindings/blob/build/ultimate-8000.reloc"

        .code

_main:  rts

; Copy the whole blob down to $8000, then fix up the addresses. One unrolled
; page per page of the built binary, rounded up, so this cannot fall behind the
; SDK the way a fixed count did.
;
; The loop closes with beq/jmp rather than bne, because the body is six bytes
; per page of blob and a relative branch stopped reaching over it once the SDK
; passed twenty-one pages. A jmp keeps the "one page per page" property from
; having a size limit of its own.
t_reloc:
        ldx #$00
@page:
        .repeat BLOB_PAGES, page
        lda BLOB_SRC + page * $100,x
        sta BLOB_DST + page * $100,x
        .endrepeat
        inx
        beq @copied
        jmp @page
@copied:

        lda #<BLOB_DST
        ldx #>BLOB_DST
        ldy #$E0                ; $60 - $80 = -$20 pages, as a byte add
        jsr blob_relocate
        rts

t_call_init:
        jsr BLOB_DST + $04
        sta result
        rts
