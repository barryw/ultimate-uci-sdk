; cc65 dosinfo adapters. One service per archive member keeps unrelated
; services out of C programs. Register-compatible entries live in src/uci.
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"
        .include "uci_zp.inc"

        .import incsp2
        .import ultimate_stat
        .import ultimate_fstat
        .import ultimate_rename
        .import ultimate_copy
        .import ult_arg2
        .import cc_ptr_at_y
        .export _ultimate_stat
        .export _ultimate_fstat
        .export _ultimate_rename
        .export _ultimate_copy

; ---------------------------------------------------------------------------
; dosinfo.s, disk.s, clock.s and control.s. The same unpacking as everything
; above: cc65's stacked arguments into the shared variable block, then the
; entry point.
; ---------------------------------------------------------------------------



; uint8_t ultimate_stat(const char *name, ultimate_fileinfo *info);
;
; A/X holds info; the C stack holds name at 0..1.
_ultimate_stat:
        sta ult_arg2
        stx ult_arg2 + 1
        ldy #$00
        jsr cc_ptr_at_y
        jsr incsp2
        jsr ultimate_stat
        ldx #$00
        rts

; uint8_t ultimate_fstat(ultimate_fileinfo *info);
_ultimate_fstat:
        sta ult_arg2
        stx ult_arg2 + 1
        jsr ultimate_fstat
        ldx #$00
        rts

; uint8_t ultimate_rename(const char *from, const char *to);
; uint8_t ultimate_copy  (const char *name, const char *destination_path);
;
; A/X holds the second name; the C stack holds the first at 0..1.
_ultimate_rename:
        jsr cc_two_names
        jsr ultimate_rename
        ldx #$00
        rts

_ultimate_copy:
        jsr cc_two_names
        jsr ultimate_copy
        ldx #$00
        rts

cc_two_names:
        sta ult_arg2
        stx ult_arg2 + 1
        ldy #$00
        jsr cc_ptr_at_y
        jmp incsp2
