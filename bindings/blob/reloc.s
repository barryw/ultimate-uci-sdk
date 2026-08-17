; reloc.s - move a loaded SDK blob to a different address.
;
; Shipped as source rather than inside the blob, because a relocator inside the
; thing it relocates has to be position independent, and position independent
; 6502 costs more than the forty bytes this saves. Assemble it into whatever
; loads the blob.
;
; The table is a little-endian count followed by that many little-endian 16-bit
; offsets; see tools/gen_reloc.py. Every offset names a byte holding the high
; half of an absolute address, so relocating is an add.
;
;   blob_relocate   A/X = where the blob was loaded (low/high)
;                   Y   = pages to add
;
; Uses six bytes of zero page at RELOC_ZP, which defaults out of the way of
; both the SDK and the cc65 runtime.
;
; SPDX-License-Identifier: MIT

; Six bytes of zero page, at an address the caller can move. The default
; overlaps the SDK's own default block at $FB-$FE, and that is harmless:
; relocation finishes before anything in the blob is called, so the two are
; never live at the same time. Move it with -D RELOC_ZP=... if your program
; wants those bytes for something that is.
.ifndef RELOC_ZP
RELOC_ZP = $F7
.endif

rl_blob = RELOC_ZP + 0          ; pointer into the blob
rl_tbl  = RELOC_ZP + 2          ; pointer into the relocation table
rl_ptr  = RELOC_ZP + 4          ; working pointer; must be zero page for (zp),y

        .export blob_relocate
        .import blob_table      ; the caller supplies the loaded .reloc file

        .code

blob_relocate:
        sta rl_blob
        stx rl_blob + 1
        sty rl_pages

        lda #<blob_table
        sta rl_tbl
        lda #>blob_table
        sta rl_tbl + 1

        ldy #$00                ; count, little-endian
        lda (rl_tbl),y
        sta rl_count
        iny
        lda (rl_tbl),y
        sta rl_count + 1

        clc                     ; step the table pointer past the count
        lda rl_tbl
        adc #$02
        sta rl_tbl
        bcc @loop
        inc rl_tbl + 1

@loop:  lda rl_count
        ora rl_count + 1
        beq @done

        ldy #$00                ; next offset, little-endian
        lda (rl_tbl),y
        sta rl_off
        iny
        lda (rl_tbl),y
        sta rl_off + 1

        clc                     ; blob + offset
        lda rl_blob
        adc rl_off
        sta rl_ptr
        lda rl_blob + 1
        adc rl_off + 1
        sta rl_ptr + 1

        ldy #$00
        lda (rl_ptr),y
        clc
        adc rl_pages
        sta (rl_ptr),y

        clc                     ; step the table pointer
        lda rl_tbl
        adc #$02
        sta rl_tbl
        bcc @dec
        inc rl_tbl + 1

@dec:   lda rl_count
        bne @lo
        dec rl_count + 1
@lo:    dec rl_count
        jmp @loop

@done:  rts

        .bss
rl_pages: .res 1
rl_count: .res 2
rl_off:   .res 2
