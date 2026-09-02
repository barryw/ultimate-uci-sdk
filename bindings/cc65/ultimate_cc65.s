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
; cc65 renamed its software stack pointer to `c_sp` after 2.18 and kept `sp`
; working in both. Ubuntu ships 2.18, which is what CI builds with, so `sp` is
; the spelling that links on either - deliberate rather than dated.
        .importzp sp
        .import incsp3

        .export _uci_decode_status

; uint8_t uci_decode_status(uint8_t target, const uint8_t *status,
;                           uint16_t statuslen);
;
; On entry A/X holds statuslen; the C stack holds the status pointer at offset
; 0..1 and the target at offset 2.
_uci_decode_status:
        ; The decoder counts in bytes. The status queue is 256 bytes, so a
        ; length of exactly 256 is reachable and would arrive here as a low
        ; byte of zero - which the decoder reads as an empty status, and an
        ; empty status is success. Clamp instead: only the first four bytes
        ; decide the encoding, so 255 decodes the same as 256 would.
        cpx #$00
        beq @fits
        lda #$FF
@fits:  sta uci_dec_len
        ldy #$00
        lda (sp),y
        sta uci_dec_ptr
        iny
        lda (sp),y
        sta uci_dec_ptr + 1
        iny
        lda (sp),y
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
        .import ultimate_audio_start
        .import ultimate_net_ifcount, ultimate_net_macaddr
        .import ultimate_net_ipconfig, ultimate_net_connect
        .import ultimate_net_udp, ultimate_net_read, ultimate_net_write
        .import ult_sock, ult_socklen, ult_iface, ult_port
        .import ultimate_http_open, ultimate_http_header
        .import ultimate_http_exchange, ultimate_http_get
        .import ult_url, ult_http, ult_body, ult_httplen
        .import ult_addr, ult_max, ult_reu, ult_reulen
        .import ult_buf, ult_buflen, ult_outlen, ult_color
        .import ult_attrib, ult_num
        .import incsp1, incsp2, incsp3, incsp4, incsp5, incsp6
        .importzp sreg

        .export _ultimate_identify
        .export _ultimate_get_model
        .export _ultimate_palette_set_color
        .export _ultimate_getpath, _ultimate_readdir, _ultimate_open
        .export _ultimate_read, _ultimate_write, _ultimate_seek
        .export _ultimate_load, _ultimate_bload, _ultimate_save
        .export _ultimate_reu_stash, _ultimate_reu_fetch
        .export _ultimate_reu_load, _ultimate_reu_save
        .export _ultimate_audio_start
        .export _ultimate_net_ifcount, _ultimate_net_macaddr
        .export _ultimate_net_ipconfig, _ultimate_net_connect
        .export _ultimate_net_udp, _ultimate_net_read, _ultimate_net_write
        .export _ultimate_http_open, _ultimate_http_header
        .export _ultimate_http_exchange, _ultimate_http_get

; uint8_t ultimate_identify(uint8_t target, char *buf, uint16_t buflen,
;                           uint16_t *outlen);
;
; A/X holds outlen; the C stack holds buflen at 0..1, buf at 2..3, target at 4.
_ultimate_identify:
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
        lda (sp),y
        sta ult_buflen
        iny
        lda (sp),y
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
        lda (sp),y
        sta ult_color + 2       ; g
        iny
        lda (sp),y
        sta ult_color + 1       ; r
        iny
        lda (sp),y
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
        lda (sp),y
        sta ult_buflen
        iny
        lda (sp),y
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
        lda (sp),y
        sta ult_addr
        iny
        lda (sp),y
        sta ult_addr + 1
        iny
        jsr cc_ptr_at_y
        jmp incsp4

cc_name_only:
        ldy #$00
        jsr cc_ptr_at_y
        jmp incsp2

; The two bytes at (sp),y into ult_buf. Seven of the unpackers here do exactly
; this, at four different stack offsets, so the offset stays the caller's
; business in Y and the copy is written once.
cc_ptr_at_y:
        lda (sp),y
        sta ult_buf
        iny
        lda (sp),y
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
        lda (sp),y
        sta ult_reu
        iny
        lda (sp),y
        sta ult_reu + 1
        iny
        lda (sp),y
        sta ult_reu + 2
        iny
        lda (sp),y
        sta ult_reu + 3
        iny
        lda (sp),y
        sta ult_addr
        iny
        lda (sp),y
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

; uint8_t ultimate_audio_start(uint8_t channel, uint8_t flags);
;
; A holds flags; the C stack holds channel. The assembly entry takes A/X so it
; remains pleasant to call without dragging the C stack into the core.
_ultimate_audio_start:
        pha                             ; flags
        ldy #$00
        lda (sp),y
        pha                             ; channel
        jsr incsp1
        pla
        tay                             ; channel
        pla
        tax                             ; flags
        tya
        jmp ultimate_audio_start

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
        lda (sp),y
        sta ult_reu
        iny
        lda (sp),y
        sta ult_reu + 1
        iny
        lda (sp),y
        sta ult_reu + 2
        iny
        lda (sp),y
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

; ---------------------------------------------------------------------------
; http.s. Same convention as the net shims above: the out-parameter waits in
; ult_outlen while uci_exec runs, because the zero page slots do not survive it.
; ---------------------------------------------------------------------------

; uint8_t ultimate_http_get(const char *url, uint8_t *buf, uint16_t bufsize,
;                           uint16_t *got);
;
; A/X holds got; the C stack holds bufsize at 0..1, buf at 2..3, url at 4..5.
_ultimate_http_get:
        jsr cc_hold_out
        ldy #$00
        lda (sp),y
        sta ult_buflen
        iny
        lda (sp),y
        sta ult_buflen + 1
        iny
        jsr cc_ptr_at_y                 ; buf -> ult_buf
        iny
        jsr cc_url_at_y                 ; url -> ult_url
        jsr incsp6
        jsr ultimate_http_get
        jmp cc_out_http

; uint8_t ultimate_http_exchange(uint8_t handle, uint8_t body, uint8_t *buf,
;                                uint16_t bufsize, uint16_t *got);
;
; A/X holds got; the C stack holds bufsize at 0..1, buf at 2..3, body at 4 and
; the handle at 5.
_ultimate_http_exchange:
        jsr cc_hold_out
        ldy #$00
        lda (sp),y
        sta ult_buflen
        iny
        lda (sp),y
        sta ult_buflen + 1
        iny
        jsr cc_ptr_at_y                 ; buf -> ult_buf
        iny
        lda (sp),y
        sta ult_body
        iny
        lda (sp),y
        sta ult_http
        jsr incsp6
        jsr ultimate_http_exchange
        jmp cc_out_http

; uint8_t ultimate_http_open(uint8_t verb, const char *url, uint8_t *handle);
;
; A/X holds handle; the C stack holds url at 0..1 and the verb at 2.
_ultimate_http_open:
        jsr cc_hold_out
        ldy #$00
        jsr cc_url_at_y
        iny
        lda (sp),y
        pha                             ; the verb, past the stack adjustment
        jsr incsp3
        pla
        jsr ultimate_http_open
        ldx ult_http
        jmp cc_out_byte

; uint8_t ultimate_http_header(uint8_t handle, const char *line);
;
; A/X holds the line; the C stack holds the handle at 0.
_ultimate_http_header:
        sta ult_url
        stx ult_url + 1
        ldy #$00
        lda (sp),y
        sta ult_http
        jsr incsp1
        jsr ultimate_http_header
        ldx #$00
        rts

; The two bytes at (sp),y into ult_url, which is cc_ptr_at_y for the other
; pointer this layer passes.
cc_url_at_y:
        lda (sp),y
        sta ult_url
        iny
        lda (sp),y
        sta ult_url + 1
        rts

; A = the result to hand back; ult_httplen is what gets stored.
cc_out_http:
        pha
        jsr cc_out_ptr
        bcc @none
        ldy #$00
        lda ult_httplen
        sta (uci_ptr),y
        iny
        lda ult_httplen + 1
        sta (uci_ptr),y
@none:  pla
        ldx #$00
        rts

; ---------------------------------------------------------------------------
; dosinfo.s, disk.s, clock.s and control.s. The same unpacking as everything
; above: cc65's stacked arguments into the shared variable block, then the
; entry point.
; ---------------------------------------------------------------------------

        .import ultimate_stat, ultimate_fstat
        .import ultimate_rename, ultimate_copy
        .import ultimate_mount, ultimate_get_time, ultimate_set_time
        .import ultimate_drive_enable, ultimate_drive_power
        .import ultimate_net_setip
        .import ultimate_http_body, ultimate_http_body_int
        .import ultimate_http_body_bool, ultimate_http_body_string
        .import ultimate_http_body_object, ultimate_http_body_array
        .import ultimate_http_body_binary
        .import ult_arg2, ult_stage, ult_val

        .export _ultimate_stat, _ultimate_fstat
        .export _ultimate_rename, _ultimate_copy
        .export _ultimate_mount, _ultimate_get_time, _ultimate_set_time
        .export _ultimate_drive_enable, _ultimate_drive_power
        .export _ultimate_net_setip
        .export _ultimate_http_body, _ultimate_http_body_int
        .export _ultimate_http_body_bool, _ultimate_http_body_string
        .export _ultimate_http_body_object, _ultimate_http_body_array
        .export _ultimate_http_body_binary

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
; uint8_t ultimate_copy  (const char *from, const char *to);
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

; uint8_t ultimate_mount(uint8_t device, const char *image);
;
; A/X holds the image name; the C stack holds the device number at 0.
_ultimate_mount:
        sta ult_buf
        stx ult_buf + 1
        ldy #$00
        lda (sp),y
        pha                             ; the device, past the stack adjustment
        jsr incsp1
        pla
        jsr ultimate_mount
        ldx #$00
        rts

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

; uint8_t ultimate_drive_enable(uint8_t drive, uint8_t on);
;
; A holds on; the C stack holds the drive at 0. The entry point wants the drive
; in A and the flag in X.
_ultimate_drive_enable:
        tax
        ldy #$00
        lda (sp),y
        pha
        jsr incsp1
        pla
        jsr ultimate_drive_enable
        ldx #$00
        rts

; uint8_t ultimate_drive_power(uint8_t drive, uint8_t *on);
;
; A/X holds the out-pointer; the C stack holds the drive at 0. The answer waits
; in ult_stage while uci_exec runs, as every other out-parameter here does.
_ultimate_drive_power:
        jsr cc_hold_out
        ldy #$00
        lda (sp),y
        pha
        jsr incsp1
        pla
        jsr ultimate_drive_power
        ldx ult_stage
        jmp cc_out_byte

; uint8_t ultimate_net_setip(uint8_t iface, const uint8_t *ipconfig);
_ultimate_net_setip:
        jsr cc_iface_buf
        jsr ultimate_net_setip
        ldx #$00
        rts

; ---------------------------------------------------------------------------
; httpbody.s.
; ---------------------------------------------------------------------------

; uint8_t ultimate_http_body(uint8_t format, uint8_t *handle);
;
; A/X holds handle; the C stack holds the format at 0.
_ultimate_http_body:
        jsr cc_hold_out
        ldy #$00
        lda (sp),y
        pha                             ; the format
        jsr incsp1
        pla
        jsr ultimate_http_body
        ldx ult_body
        jmp cc_out_byte

; uint8_t ultimate_http_body_int(uint8_t handle, const char *key, int32_t value);
;
; A/X plus sreg holds the value - cc65 passes a long that way - and the C stack
; holds the key at 0..1 and the handle at 2.
_ultimate_http_body_int:
        sta ult_val
        stx ult_val + 1
        lda sreg
        sta ult_val + 2
        lda sreg + 1
        sta ult_val + 3
        jsr cc_body_key
        jsr ultimate_http_body_int
        ldx #$00
        rts

; uint8_t ultimate_http_body_bool(uint8_t handle, const char *key, uint8_t value);
_ultimate_http_body_bool:
        sta ult_val
        jsr cc_body_key
        jsr ultimate_http_body_bool
        ldx #$00
        rts

; uint8_t ultimate_http_body_string(uint8_t handle, const char *key,
;                                   const char *value);
;
; A/X holds the value; the C stack holds the key at 0..1 and the handle at 2.
_ultimate_http_body_string:
        sta ult_buf
        stx ult_buf + 1
        jsr cc_body_key
        jsr ultimate_http_body_string
        ldx #$00
        rts

; The key at 0..1 and the handle at 2, which is the shape the three keyed
; commands taking a value all have.
cc_body_key:
        ldy #$00
        jsr cc_url_at_y                 ; key -> ult_url
        iny
        lda (sp),y
        sta ult_body
        jmp incsp3

; uint8_t ultimate_http_body_object(uint8_t handle, const char *key);
; uint8_t ultimate_http_body_array (uint8_t handle, const char *key);
;
; A/X holds the key; the C stack holds the handle at 0.
_ultimate_http_body_object:
        jsr cc_body_handle_key
        jsr ultimate_http_body_object
        ldx #$00
        rts

_ultimate_http_body_array:
        jsr cc_body_handle_key
        jsr ultimate_http_body_array
        ldx #$00
        rts

cc_body_handle_key:
        sta ult_url
        stx ult_url + 1
        ldy #$00
        lda (sp),y
        sta ult_body
        jmp incsp1

; uint8_t ultimate_http_body_binary(uint8_t handle, const uint8_t *data,
;                                   uint16_t len);
;
; A/X holds len; the C stack holds data at 0..1 and the handle at 2.
_ultimate_http_body_binary:
        sta ult_buflen
        stx ult_buflen + 1
        ldy #$00
        jsr cc_ptr_at_y                 ; data -> ult_buf
        iny
        lda (sp),y
        sta ult_body
        jsr incsp3
        jsr ultimate_http_body_binary
        ldx #$00
        rts
