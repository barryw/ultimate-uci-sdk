; cc65 net adapters. One service per archive member keeps unrelated
; services out of C programs. Register-compatible entries live in src/uci.
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"
        .include "uci_zp.inc"

        .importzp sp
        .import ultimate_net_ifcount
        .import ultimate_net_macaddr
        .import ultimate_net_ipconfig
        .import ultimate_net_connect
        .import ultimate_net_udp
        .import ultimate_net_read
        .import ultimate_net_write
        .import ult_sock
        .import ult_socklen
        .import ult_iface
        .import ult_port
        .import ult_buf
        .import ult_buflen
        .import incsp1
        .import incsp4
        .import incsp5
        .import ultimate_net_setip
        .import cc_ptr_at_y
        .import cc_hold_out
        .import cc_out_byte
        .import cc_out_ptr
        .export _ultimate_net_ifcount
        .export _ultimate_net_macaddr
        .export _ultimate_net_ipconfig
        .export _ultimate_net_connect
        .export _ultimate_net_udp
        .export _ultimate_net_read
        .export _ultimate_net_write
        .export _ultimate_net_setip

; ---------------------------------------------------------------------------
; net.s.
;
; Four of these have an out-parameter, and the pointer to it rides in on
; ult_outlen - "where to write the length, 0 for nowhere" - exactly as
; _ultimate_readdir's attribute pointer does. The shared block is the only
; place a pointer can wait while uci_exec runs: the zero page slots do not
; survive the call, which is the whole reason that convention exists.
;
; A null out-pointer stores nothing rather than faulting, so a caller that only
; wants the result code can pass one.
; ---------------------------------------------------------------------------

; uint8_t ultimate_net_ifcount(uint8_t *count);
_ultimate_net_ifcount:
        jsr cc_hold_out
        jsr ultimate_net_ifcount
        ldx ult_iface
        jmp cc_out_byte

; uint8_t ultimate_net_macaddr(uint8_t iface, uint8_t *mac);
; uint8_t ultimate_net_ipconfig(uint8_t iface, uint8_t *ipconfig);
;
; A/X holds the buffer; the C stack holds iface at 0. The reply is a fixed size
; the caller is told about in the header, so there is no length to pass and
; nothing to write back.
_ultimate_net_macaddr:
        jsr cc_iface_buf
        jsr ultimate_net_macaddr
        ldx #$00
        rts

_ultimate_net_ipconfig:
        jsr cc_iface_buf
        jsr ultimate_net_ipconfig
        ldx #$00
        rts

cc_iface_buf:
        sta ult_buf
        stx ult_buf + 1
        ldy #$00
        lda (sp),y
        sta ult_iface
        jmp incsp1

; uint8_t ultimate_net_connect(const char *host, uint16_t port, uint8_t *handle);
; uint8_t ultimate_net_udp    (const char *host, uint16_t port, uint8_t *handle);
;
; A/X holds handle; the C stack holds port at 0..1 and host at 2..3.
_ultimate_net_connect:
        jsr cc_host_port
        jsr ultimate_net_connect
        ldx ult_sock
        jmp cc_out_byte

_ultimate_net_udp:
        jsr cc_host_port
        jsr ultimate_net_udp
        ldx ult_sock
        jmp cc_out_byte

cc_host_port:
        jsr cc_hold_out
        ldy #$00
        lda (sp),y
        sta ult_port
        iny
        lda (sp),y
        sta ult_port + 1
        iny
        jsr cc_ptr_at_y
        jmp incsp4

; uint8_t ultimate_net_read (uint8_t handle, uint8_t *buf, uint16_t bufsize,
;                            uint16_t *got);
; uint8_t ultimate_net_write(uint8_t handle, const uint8_t *buf, uint16_t len,
;                            uint16_t *sent);
;
; A/X holds the out-parameter; the C stack holds the length at 0..1, the buffer
; at 2..3 and the handle at 4. The two differ only in which variable the length
; belongs in: a read is given the size of the buffer, a write the number of
; bytes to send.
_ultimate_net_read:
        jsr cc_hold_out
        ldy #$00
        lda (sp),y
        sta ult_socklen
        iny
        lda (sp),y
        sta ult_socklen + 1
        iny
        jsr cc_sock_buf
        jsr ultimate_net_read
        jmp cc_out_word

_ultimate_net_write:
        jsr cc_hold_out
        ldy #$00
        lda (sp),y
        sta ult_buflen
        iny
        lda (sp),y
        sta ult_buflen + 1
        iny
        jsr cc_sock_buf
        jsr ultimate_net_write
        jmp cc_out_word

; Y points at the buffer pointer; the handle is the two bytes past it.
cc_sock_buf:
        jsr cc_ptr_at_y
        iny
        lda (sp),y
        sta ult_sock
        jmp incsp5

; A = the result to hand back; ult_socklen is what gets stored.
cc_out_word:
        pha
        jsr cc_out_ptr
        bcc @none
        ldy #$00
        lda ult_socklen
        sta (uci_ptr),y
        iny
        lda ult_socklen + 1
        sta (uci_ptr),y
@none:  pla
        ldx #$00
        rts

; uint8_t ultimate_net_setip(uint8_t iface, const uint8_t *ipconfig);
_ultimate_net_setip:
        jsr cc_iface_buf
        jsr ultimate_net_setip
        ldx #$00
        rts
