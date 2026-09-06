; cc65 clock adapters. One service per archive member keeps unrelated
; services out of C programs. Register-compatible entries live in src/uci.
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"
        .include "uci_zp.inc"

        .importzp sp
        .import ult_buflen
        .import ult_outlen
        .import incsp5
        .import ultimate_get_time
        .import ultimate_set_time
        .import ult_stage
        .import cc_ptr_at_y
        .export _ultimate_get_time
        .export _ultimate_set_time

; uint8_t ultimate_get_time(uint8_t format, char *buf, uint16_t buflen,
;                           uint16_t *outlen);
;
; A/X holds outlen; the C stack holds buflen at 0..1, buf at 2..3, format at 4.
_ultimate_get_time:
        sta ult_outlen
        stx ult_outlen + 1
        ldy #$00
        lda (sp),y
        sta ult_buflen
        iny
        lda (sp),y
        sta ult_buflen + 1
        iny
        jsr cc_ptr_at_y
        iny
        lda (sp),y
        pha                             ; the format byte
        jsr incsp5
        pla
        jsr ultimate_get_time
        ldx #$00
        rts

; uint8_t ultimate_set_time(uint8_t year_1900, uint8_t month, uint8_t day,
;                           uint8_t hour, uint8_t minute, uint8_t second);
;
; A holds second; cc65 pushes the other five as single bytes, so the C stack
; holds minute at 0, hour at 1, day at 2, month at 3 and the year at 4. They go
; into the staging buffer in the order the firmware reads them, which is the
; reverse of the order they come off the stack.
_ultimate_set_time:
        sta ult_stage + 5               ; second
        ldy #$00
        lda (sp),y
        sta ult_stage + 4               ; minute
        iny
        lda (sp),y
        sta ult_stage + 3               ; hour
        iny
        lda (sp),y
        sta ult_stage + 2               ; day
        iny
        lda (sp),y
        sta ult_stage + 1               ; month
        iny
        lda (sp),y
        sta ult_stage + 0               ; year, less 1900
        jsr incsp5
        jsr ultimate_set_time
        ldx #$00
        rts
