; ultimate_cc65.s - the one place cc65's calling convention needs unpacking.
;
; Most of the SDK's entry points take a pointer in A/X and return a byte in A,
; which is exactly cc65's convention for a one-argument function - so the core
; exports its C names directly and costs a C caller nothing.
;
; uci_decode_status takes three arguments, so cc65 passes the first two on its
; software stack. Unpacking that belongs here, in the binding, and not in the
; core: assembly callers use uci_decode with its parameter block and never touch
; a C runtime.
;
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"
        .include "uci_zp.inc"

        .import uci_decode, uci_dec_target, uci_dec_ptr, uci_dec_len
        .importzp c_sp
        .import incsp3

        .export _uci_decode_status

; uint8_t uci_decode_status(uint8_t target, const uint8_t *status,
;                           uint16_t statuslen);
;
; On entry A/X holds statuslen; the C stack holds the status pointer at offset
; 0..1 and the target at offset 2.
_uci_decode_status:
        sta uci_dec_len         ; a status longer than 255 bytes cannot exist:
                                ; the queue is 256 and only the prefix matters
        ldy #$00
        lda (c_sp),y
        sta uci_dec_ptr
        iny
        lda (c_sp),y
        sta uci_dec_ptr + 1
        iny
        lda (c_sp),y
        sta uci_dec_target

        jsr incsp3
        jsr uci_decode
        ldx #$00
        rts

; ---------------------------------------------------------------------------
; The service layer takes its wider parameters in the shared variable block,
; which is natural from assembly and cheap from C. These two wrappers move
; cc65's stacked arguments into it.
; ---------------------------------------------------------------------------

        .import ultimate_identify, ultimate_get_model
        .import ultimate_palette_set_color
        .import ultimate_getpath, ultimate_readdir, ultimate_open
        .import ultimate_read, ultimate_write, ultimate_seek
        .import ultimate_load, ultimate_bload, ultimate_save
        .import ultimate_reu_stash, ultimate_reu_fetch
        .import ultimate_reu_load, ultimate_reu_save
        .import ultimate_net_ifcount, ultimate_net_macaddr
        .import ultimate_net_ipconfig, ultimate_net_connect
        .import ultimate_net_udp, ultimate_net_read, ultimate_net_write
        .import ult_sock, ult_socklen, ult_iface, ult_port
        .import ult_addr, ult_max, ult_reu, ult_reulen
        .import ult_buf, ult_buflen, ult_outlen, ult_color
        .import ult_attrib, ult_num
        .import incsp1, incsp2, incsp4, incsp5, incsp6
        .importzp sreg

        .export _ultimate_identify
        .export _ultimate_get_model
        .export _ultimate_palette_set_color
        .export _ultimate_getpath, _ultimate_readdir, _ultimate_open
        .export _ultimate_read, _ultimate_write, _ultimate_seek
        .export _ultimate_load, _ultimate_bload, _ultimate_save
        .export _ultimate_reu_stash, _ultimate_reu_fetch
        .export _ultimate_reu_load, _ultimate_reu_save
        .export _ultimate_net_ifcount, _ultimate_net_macaddr
        .export _ultimate_net_ipconfig, _ultimate_net_connect
        .export _ultimate_net_udp, _ultimate_net_read, _ultimate_net_write

; uint8_t ultimate_identify(uint8_t target, char *buf, uint16_t buflen,
;                           uint16_t *outlen);
;
; A/X holds outlen; the C stack holds buflen at 0..1, buf at 2..3, target at 4.
_ultimate_identify:
        sta ult_outlen
        stx ult_outlen + 1
        ldy #$00
        lda (c_sp),y
        sta ult_buflen
        iny
        lda (c_sp),y
        sta ult_buflen + 1
        iny
        jsr cc_ptr_at_y
        iny
        lda (c_sp),y
        pha                     ; target
        jsr incsp5
        pla
        jsr ultimate_identify
        ldx #$00
        rts

; uint8_t ultimate_get_model(char *buf, uint16_t buflen, uint16_t *outlen);
;
; A/X holds outlen; the C stack holds buflen at 0..1 and buf at 2..3.
_ultimate_get_model:
        sta ult_outlen
        stx ult_outlen + 1
        ldy #$00
        lda (c_sp),y
        sta ult_buflen
        iny
        lda (c_sp),y
        sta ult_buflen + 1
        iny
        jsr cc_ptr_at_y
        jsr incsp4
        jsr ultimate_get_model
        ldx #$00
        rts

; uint8_t ultimate_palette_set_color(uint8_t index, uint8_t r, uint8_t g,
;                                    uint8_t b);
;
; A holds b; cc65 pushes the other three as single bytes, so the C stack holds
; g at 0, r at 1 and index at 2. The other three palette entry points take one
; argument or none, which is already cc65's convention, so they export their C
; names straight out of palette.s and cost nothing here.
_ultimate_palette_set_color:
        sta ult_color + 3       ; b
        ldy #$00
        lda (c_sp),y
        sta ult_color + 2       ; g
        iny
        lda (c_sp),y
        sta ult_color + 1       ; r
        iny
        lda (c_sp),y
        sta ult_color           ; index
        jsr incsp3
        jsr ultimate_palette_set_color
        ldx #$00
        rts

; ---------------------------------------------------------------------------
; The DOS service. Its wide parameters go in the same shared block as the rest
; of the service layer, so these move cc65's stacked arguments into it and get
; out of the way.
; ---------------------------------------------------------------------------

; Internal: A/X = the last argument, stack = <word> <pointer>. Leaves the
; pointer in ult_buf, the word in ult_buflen and the last argument in
; ult_outlen, which is the shape ultimate_identify already established.
cc_buf_len_out:
        sta ult_outlen
        stx ult_outlen + 1
        ldy #$00
        lda (c_sp),y
        sta ult_buflen
        iny
        lda (c_sp),y
        sta ult_buflen + 1
        iny
        jsr cc_ptr_at_y
        jmp incsp4

; uint8_t ultimate_getpath(char *buf, uint16_t buflen, uint16_t *outlen);
_ultimate_getpath:
        jsr cc_buf_len_out
        jsr ultimate_getpath
        ldx #$00
        rts

; uint8_t ultimate_read(uint8_t *buf, uint16_t len, uint16_t *outlen);
_ultimate_read:
        jsr cc_buf_len_out
        jsr ultimate_read
        ldx #$00
        rts

; uint8_t ultimate_readdir(char *name, uint16_t namelen, uint8_t *attrib);
;
; attrib rides in on ult_outlen only to be borrowed as a pointer here: readdir
; itself reports the attributes in ult_attrib, and this writes them through.
_ultimate_readdir:
        jsr cc_buf_len_out
        jsr ultimate_readdir
        pha
        lda ult_outlen
        ora ult_outlen + 1
        beq @none
        lda ult_outlen
        sta uci_ptr
        lda ult_outlen + 1
        sta uci_ptr + 1
        ldy #$00
        lda ult_attrib
        sta (uci_ptr),y
@none:  pla
        ldx #$00
        rts

; uint8_t ultimate_open(const char *name, uint8_t attrib);
;
; A holds attrib; the C stack holds the name pointer at 0..1.
_ultimate_open:
        pha
        ldy #$00
        jsr cc_ptr_at_y
        jsr incsp2
        pla
        jsr ultimate_open
        ldx #$00
        rts

; uint8_t ultimate_write(const uint8_t *buf, uint16_t len);
;
; A/X holds len; the C stack holds the buffer pointer at 0..1.
_ultimate_write:
        sta ult_buflen
        stx ult_buflen + 1
        ldy #$00
        jsr cc_ptr_at_y
        jsr incsp2
        jsr ultimate_write
        ldx #$00
        rts

; uint8_t ultimate_seek(uint32_t pos);
;
; cc65 passes a long in A/X plus sreg: A is bits 0-7, X bits 8-15, and sreg the
; high word.
_ultimate_seek:
        sta ult_num
        stx ult_num + 1
        lda sreg
        sta ult_num + 2
        lda sreg + 1
        sta ult_num + 3
        jsr ultimate_seek
        ldx #$00
        rts

; ---------------------------------------------------------------------------
; file.s. The address and the limit are two more of the shared block's fields,
; so these are the same unpacking as everything above.
; ---------------------------------------------------------------------------

; uint8_t ultimate_load(const char *name, uint16_t addr);
;
; A/X holds addr; the C stack holds the name pointer at 0..1.
_ultimate_load:
        sta ult_addr
        stx ult_addr + 1
        jsr cc_name_only
        jsr ultimate_load
        ldx #$00
        rts

; uint8_t ultimate_bload(const char *name, uint16_t addr, uint16_t max);
; uint8_t ultimate_save (const char *name, uint16_t start, uint16_t len);
;
; The same three arguments in the same places: A/X holds the last one, the C
; stack holds the address at 0..1 and the name at 2..3.
_ultimate_bload:
        jsr cc_name_addr_max
        jsr ultimate_bload
        ldx #$00
        rts

_ultimate_save:
        jsr cc_name_addr_max
        jsr ultimate_save
        ldx #$00
        rts

cc_name_addr_max:
        sta ult_max
        stx ult_max + 1
        ldy #$00
        lda (c_sp),y
        sta ult_addr
        iny
        lda (c_sp),y
        sta ult_addr + 1
        iny
        jsr cc_ptr_at_y
        jmp incsp4

cc_name_only:
        ldy #$00
        jsr cc_ptr_at_y
        jmp incsp2

; The two bytes at (c_sp),y into ult_buf. Seven of the unpackers here do exactly
; this, at four different stack offsets, so the offset stays the caller's
; business in Y and the copy is written once.
cc_ptr_at_y:
        lda (c_sp),y
        sta ult_buf
        iny
        lda (c_sp),y
        sta ult_buf + 1
        rts

; ---------------------------------------------------------------------------
; reu.s. Both pairs put the REU address and the length in the same two
; variables, so the two unpackers differ only in what else they take and in how
; wide the length arrives.
; ---------------------------------------------------------------------------

; uint8_t ultimate_reu_stash(uint16_t addr, uint32_t reuaddr, uint16_t len);
; uint8_t ultimate_reu_fetch(uint16_t addr, uint32_t reuaddr, uint16_t len);
;
; A/X holds len; the C stack holds reuaddr at 0..3 and addr at 4..5.
_ultimate_reu_stash:
        jsr cc_reu_dma
        jmp ultimate_reu_stash

_ultimate_reu_fetch:
        jsr cc_reu_dma
        jmp ultimate_reu_fetch

cc_reu_dma:
        sta ult_reulen          ; a DMA transfer is 16 bits wide, so the top
        stx ult_reulen + 1      ; half of the shared length is zero
        lda #$00
        sta ult_reulen + 2
        sta ult_reulen + 3
        ldy #$00
        lda (c_sp),y
        sta ult_reu
        iny
        lda (c_sp),y
        sta ult_reu + 1
        iny
        lda (c_sp),y
        sta ult_reu + 2
        iny
        lda (c_sp),y
        sta ult_reu + 3
        iny
        lda (c_sp),y
        sta ult_addr
        iny
        lda (c_sp),y
        sta ult_addr + 1
        jmp incsp6

; uint8_t ultimate_reu_load(uint32_t reuaddr, uint32_t len);
; uint8_t ultimate_reu_save(uint32_t reuaddr, uint32_t len);
;
; A/X plus sreg holds len - cc65 passes a long that way - and the C stack holds
; reuaddr at 0..3.
_ultimate_reu_load:
        jsr cc_reu_file
        jmp ultimate_reu_load

_ultimate_reu_save:
        jsr cc_reu_file
        jmp ultimate_reu_save

cc_reu_file:
        sta ult_reulen
        stx ult_reulen + 1
        lda sreg
        sta ult_reulen + 2
        lda sreg + 1
        sta ult_reulen + 3
        ldy #$00
        lda (c_sp),y
        sta ult_reu
        iny
        lda (c_sp),y
        sta ult_reu + 1
        iny
        lda (c_sp),y
        sta ult_reu + 2
        iny
        lda (c_sp),y
        sta ult_reu + 3
        jmp incsp4

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
        lda (c_sp),y
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
        lda (c_sp),y
        sta ult_port
        iny
        lda (c_sp),y
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
        lda (c_sp),y
        sta ult_socklen
        iny
        lda (c_sp),y
        sta ult_socklen + 1
        iny
        jsr cc_sock_buf
        jsr ultimate_net_read
        jmp cc_out_word

_ultimate_net_write:
        jsr cc_hold_out
        ldy #$00
        lda (c_sp),y
        sta ult_buflen
        iny
        lda (c_sp),y
        sta ult_buflen + 1
        iny
        jsr cc_sock_buf
        jsr ultimate_net_write
        jmp cc_out_word

; Y points at the buffer pointer; the handle is the two bytes past it.
cc_sock_buf:
        jsr cc_ptr_at_y
        iny
        lda (c_sp),y
        sta ult_sock
        jmp incsp5

cc_hold_out:
        sta ult_outlen
        stx ult_outlen + 1
        rts

; A = the result to hand back, X = the byte to store through ult_outlen.
cc_out_byte:
        pha
        jsr cc_out_ptr
        bcc @none
        txa
        ldy #$00
        sta (uci_ptr),y
@none:  pla
        ldx #$00
        rts

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

; ult_outlen into uci_ptr. Carry set when there is somewhere to write.
cc_out_ptr:
        lda ult_outlen
        sta uci_ptr
        ora ult_outlen + 1
        beq @null
        lda ult_outlen + 1
        sta uci_ptr + 1
        sec
        rts
@null:  clc
        rts
