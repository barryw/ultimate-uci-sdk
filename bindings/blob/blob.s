; blob.s - the SDK as a standalone binary with a stable entry table.
;
; Toolchains cannot link each other's objects, so this is the delivery form for
; everything that is not cc65: KickAssembler, ACME, 64tass, Oscar64, llvm-mos,
; KickC, and BASIC through POKE/SYS. It is the same object files, linked
; differently - there is no second implementation.
;
; The table grows only at the end. Entries are never reordered or removed, so a
; program built against version 1 keeps working against version 5.
;
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"

        .import uci_init, uci_exec_block, uci_abort
        .import uci_present, uci_ident
        .import uci_set_timeout_a, uci_get_timeout_a, uci_last_code
        .import ultimate_init, ultimate_available, ultimate_detect
        .import ultimate_identify, ultimate_get_model, ultimate_strerror
        .import ultimate_legacy_get_sid_info
        .import uci_req_clear, uci_decode, uci_status_fmt
        .import ultimate_palette_get, ultimate_palette_set
        .import ultimate_palette_set_color, ultimate_palette_reset
        .import ultimate_turbo_available, ultimate_turbo_get
        .import ultimate_turbo_set, ultimate_turbo_badlines
        .import ultimate_stat, ultimate_fstat, ultimate_rename
        .import ultimate_copy, ultimate_mkdir, ultimate_home
        .import ultimate_mount, ultimate_unmount, ultimate_swap
        .import ultimate_get_time, ultimate_set_time
        .import ultimate_reboot, ultimate_freeze
        .import ultimate_drive_enable, ultimate_drive_power
        .import ultimate_drive_info, ultimate_ramdisk_info
        .import ultimate_net_setip
        .import ultimate_http_body, ultimate_http_body_free
        .import ultimate_http_body_clear, ultimate_http_body_int
        .import ultimate_http_body_bool, ultimate_http_body_string
        .import ultimate_http_body_binary
        .import ult_arg2, ult_stage, ult_val
        .import ultimate_chdir, ultimate_getpath
        .import ultimate_opendir, ultimate_readdir
        .import ultimate_open, ultimate_close, ultimate_read
        .import ultimate_write, ultimate_seek, ultimate_delete
        .import ultimate_load, ultimate_bload, ultimate_save
        .import ultimate_reu_available, ultimate_reu_size
        .import ultimate_reu_stash, ultimate_reu_fetch
        .import ultimate_reu_load, ultimate_reu_save
        .import ultimate_audio_init, ultimate_audio_available
        .import ultimate_audio_version
        .import ultimate_audio_configure, ultimate_audio_start
        .import ultimate_audio_stop, ultimate_audio_irq_status
        .import ultimate_audio_irq_clear
        .import ultimate_audio_load_wav
        .import ultimate_net_ifcount, ultimate_net_macaddr
        .import ultimate_net_ipconfig, ultimate_net_connect
        .import ultimate_net_udp, ultimate_net_close
        .import ultimate_net_read, ultimate_net_write
        .import ult_buf, ult_buflen, ult_outlen, ult_attrib, ult_num
        .import ult_addr, ult_max, ult_end, ult_reu, ult_reulen
        .import ult_sock, ult_socklen, ult_iface, ult_port
        .import ultimate_http_get, ultimate_http_open, ultimate_http_header
        .import ultimate_http_exchange, ultimate_http_close
        .import ultimate_http_free_all
        .import ult_url, ult_http, ult_body, ult_httplen

        .export blob_start

BLOB_VERSION = 1

        .segment "BLOBHDR"

blob_start:
        .byte "UCI", BLOB_VERSION       ; +$00 identification and version

        jmp uci_init                    ; +$04
        jmp uci_exec_block              ; +$07
        jmp uci_abort                   ; +$0A
        jmp uci_present                 ; +$0D
        jmp uci_ident                   ; +$10
        jmp uci_set_timeout_a           ; +$13
        jmp uci_get_timeout_a           ; +$16
        jmp uci_last_code               ; +$19
        jmp ultimate_init               ; +$1C
        jmp ultimate_available          ; +$1F
        jmp ultimate_detect             ; +$22
        jmp ultimate_identify           ; +$25
        jmp ultimate_get_model          ; +$28
        jmp ultimate_strerror           ; +$2B

        jmp uci_req_clear               ; +$2E
        jmp uci_decode                  ; +$31
        jmp uci_status_fmt              ; +$34

        jmp ultimate_palette_get        ; +$37
        jmp ultimate_palette_set        ; +$3A
        jmp ultimate_palette_set_color  ; +$3D
        jmp ultimate_palette_reset      ; +$40

        jmp ultimate_turbo_available    ; +$43
        jmp ultimate_turbo_get          ; +$46
        jmp ultimate_turbo_set          ; +$49
        jmp ultimate_turbo_badlines     ; +$4C

; The parameter-block services. A blob caller cannot pass a filename in A/X,
; so these take their arguments from the page-aligned block below and put the
; result back in it - which is also the only calling convention a BASIC program
; driving the blob with POKE and SYS can express.
        jmp blob_chdir                  ; +$4F
        jmp blob_getpath                ; +$52
        jmp blob_opendir                ; +$55
        jmp blob_readdir                ; +$58
        jmp blob_open                   ; +$5B
        jmp blob_close                  ; +$5E
        jmp blob_read                   ; +$61
        jmp blob_write                  ; +$64
        jmp blob_seek                   ; +$67
        jmp blob_delete                 ; +$6A
        jmp blob_load                   ; +$6D
        jmp blob_bload                  ; +$70
        jmp blob_save                   ; +$73
        jmp blob_reu_available          ; +$76
        jmp blob_reu_stash              ; +$79
        jmp blob_reu_fetch              ; +$7C
        jmp blob_reu_load               ; +$7F
        jmp blob_reu_save               ; +$82

; The sockets. A blob caller gets the same three answers ultimate_net_read
; gives anyone: bp_result of ULTIMATE_OK with bp_len set is data, ULTIMATE_OK
; with bp_len zero means nothing pending yet, and ULTIMATE_END means the peer
; hung up. Poll - a read never waits for the wire.
        jmp blob_net_ifcount            ; +$85
        jmp blob_net_macaddr            ; +$88
        jmp blob_net_ipconfig           ; +$8B
        jmp blob_net_connect            ; +$8E
        jmp blob_net_udp                ; +$91
        jmp blob_net_close              ; +$94
        jmp blob_net_read               ; +$97
        jmp blob_net_write              ; +$9A

; HTTP. bp_result of ULTIMATE_OK means the server answered below 400; the
; number it answered with is in bp_devcode either way, so a 404 is
; ULTIMATE_ERR_DEVICE with 404 there and the error page in the buffer.
        jmp blob_http_get               ; +$9D
        jmp blob_http_open              ; +$A0
        jmp blob_http_header            ; +$A3
        jmp blob_http_exchange          ; +$A6
        jmp blob_http_close             ; +$A9
        jmp blob_http_free_all          ; +$AC
        jmp blob_reu_size               ; +$AF
        jmp blob_legacy_sid_info        ; +$B2

; The rest of the Ultimate DOS command set, the disk images, the clock, the
; machine, and HTTP request bodies.
;
; **These twenty-five fill the header page.** The table starts at the base
; address and the parameter block starts $100 bytes after it, so +$FD is the
; last entry there is room for; anything added later needs somewhere else to
; live. What did not fit is listed in bindings/blob/README.md, and every one of
; those is still reachable through uci_exec_block at +$07.
        jmp blob_stat                   ; +$B5
        jmp blob_fstat                  ; +$B8
        jmp blob_rename                 ; +$BB
        jmp blob_copy                   ; +$BE
        jmp blob_mkdir                  ; +$C1
        jmp blob_home                   ; +$C4
        jmp blob_mount                  ; +$C7
        jmp blob_unmount                ; +$CA
        jmp blob_swap                   ; +$CD
        jmp blob_get_time               ; +$D0
        jmp blob_set_time               ; +$D3
        jmp blob_reboot                 ; +$D6
        jmp blob_freeze                 ; +$D9
        jmp blob_drive_enable           ; +$DC
        jmp blob_drive_power            ; +$DF
        jmp blob_drive_info             ; +$E2
        jmp blob_ramdisk_info           ; +$E5
        jmp blob_net_setip              ; +$E8
        jmp blob_http_body              ; +$EB
        jmp blob_http_body_free         ; +$EE
        jmp blob_http_body_clear        ; +$F1
        jmp blob_http_body_int          ; +$F4
        jmp blob_http_body_bool         ; +$F7
        jmp blob_http_body_string       ; +$FA
        jmp blob_http_body_binary       ; +$FD

; ---------------------------------------------------------------------------
; The parameter block.
;
; Page-aligned so that a BASIC program driving the SDK with POKE and SYS needs
; no address arithmetic: POKE UCI+256+n, v. That is the only calling convention
; BASIC can express without a wedge, and it costs assembly and C nothing.
; ---------------------------------------------------------------------------

        .segment "BLOBPARM"

        .export blob_params
        .export bp_result, bp_devcode, bp_addr, bp_len, bp_end
        .export bp_status, bp_name, bp_reply
        .export bp_attrib, bp_pos, bp_reu, bp_reulen
        .export bp_sock, bp_iface, bp_port
        .export bp_http, bp_body, bp_verb
        .export bp_name2, bp_drive, bp_format, bp_flag, bp_val, bp_time
        .export bp_audio, blob_audio_table

BP_STATUS_MAX = 32
BP_NAME_MAX   = 40
BP_REPLY_MAX  = 256

blob_params:
bp_result:  .res 1                  ; +$00  ULTIMATE_* result
bp_devcode: .res 2                  ; +$01  raw device code
bp_addr:    .res 2                  ; +$03  address argument
bp_len:     .res 2                  ; +$05  length argument
bp_end:     .res 2                  ; +$07  end address after a load
bp_status:  .res BP_STATUS_MAX      ; +$09
bp_name:    .res BP_NAME_MAX        ; +$29
bp_reply:   .res BP_REPLY_MAX       ; +$51

; Appended when the DOS, file and REU services reached the table. The block is
; a fixed 512 bytes, so this costs a caller nothing and moves nothing.
bp_attrib:  .res 1                  ; +$151 open's DOS_FA_* mask in,
                                    ;       readdir's attributes out
bp_pos:     .res 4                  ; +$152 seek's 32-bit position
bp_reu:     .res 4                  ; +$156 address in the RAM expansion
bp_reulen:  .res 4                  ; +$15A and how many bytes to move

; Appended again when the sockets reached the table, on the end for the same
; reason: the offsets above are published and do not move.
bp_sock:    .res 1                  ; +$15E socket handle, in and out
bp_iface:   .res 1                  ; +$15F interface index in, count out
bp_port:    .res 2                  ; +$160 TCP or UDP port

; And again for HTTP, on the end for the same reason as everything above it.
bp_http:    .res 1                  ; +$162 header handle, in and out
bp_body:    .res 1                  ; +$163 body handle, or HTTP_BODY_NONE
bp_verb:    .res 1                  ; +$164 HTTP_VERB_* for open

; And again for the DOS, disk, clock, machine and HTTP body entries. The block
; is a fixed 512 bytes and had 155 of them spare, so this moves nothing.
;
; bp_name2 exists because three commands take two caller strings where every
; earlier one took at most a name: rename, copy, and a JSON string value.
bp_name2:   .res BP_NAME_MAX        ; +$165 second name, or a string value
bp_drive:   .res 1                  ; +$18D drive A or B, or an IEC device number
bp_format:  .res 1                  ; +$18E HTTP body format, or the time format
bp_flag:    .res 1                  ; +$18F on or off, in and out
bp_val:     .res 4                  ; +$190 a 32-bit value, little-endian
bp_time:    .res 6                  ; +$194 year less 1900, month, day, h, m, s

; Ultimate Audio takes the same structure as the linked C and assembly APIs.
bp_audio:   .res UA_VOICE_SIZE      ; +$19A ultimate_audio_voice

; The original jump-table page is full. Keep the audio entry points stable in
; the otherwise-unused tail of the fixed parameter block.
        .res $1E8 - (* - blob_params)
blob_audio_table:                   ; +$2E8 from the blob base
        jmp ultimate_audio_init         ; +$2E8
        jmp ultimate_audio_available    ; +$2EB
        jmp ultimate_audio_version      ; +$2EE
        jmp blob_audio_configure        ; +$2F1
        jmp blob_audio_start            ; +$2F4
        jmp blob_audio_stop             ; +$2F7
        jmp ultimate_audio_irq_status   ; +$2FA
        jmp blob_audio_irq_clear        ; +$2FD

        .assert (* - blob_params) = $200, error, "audio table must end with the parameter block"

; The parameter block is full and the audio table with it. Entries from here
; on live in a third table at +$300, the first thing in the code area: it can
; grow without moving anything published before it, and nothing below it is
; published by offset.
        .segment "BLOBEXT"
blob_ext_table:                     ; +$300 from the blob base
        jmp blob_audio_load_wav         ; +$300

; ---------------------------------------------------------------------------
; The shims.
;
; Each one moves the parameter block into the SDK's own variables, calls the
; entry point, and puts the result back. Nothing is copied that does not have
; to be: the name and the reply buffer are pointed at, not duplicated.
; ---------------------------------------------------------------------------

        .segment "CODE"

blob_chdir:
        jsr blob_set_name
        jsr ultimate_chdir
        jmp blob_done

blob_getpath:
        jsr blob_set_reply
        jsr ultimate_getpath
        jmp blob_done

blob_opendir:
        jsr ultimate_opendir
        jmp blob_done

; The name lands in the reply buffer and the attributes in bp_attrib, so a
; caller walking a directory reads both from the block it already knows.
blob_readdir:
        jsr blob_set_reply
        jsr ultimate_readdir
        pha
        lda ult_attrib
        sta bp_attrib
        pla
        jmp blob_done

blob_audio_configure:
        lda #<bp_audio
        ldx #>bp_audio
        jsr ultimate_audio_configure
        jmp blob_done

blob_audio_start:
        lda bp_audio + UA_VOICE_CHANNEL
        ldx bp_audio + UA_VOICE_FLAGS
        jsr ultimate_audio_start
        jmp blob_done

blob_audio_stop:
        lda bp_audio + UA_VOICE_CHANNEL
        jsr ultimate_audio_stop
        jmp blob_done

blob_audio_irq_clear:
        lda bp_audio + UA_VOICE_CHANNEL
        jsr ultimate_audio_irq_clear
        jmp blob_done

; The WAV's name in bp_name, the REU address in bp_reu; bp_audio comes back
; with the address, length, divider and flags filled.
blob_audio_load_wav:
        jsr blob_set_name
        jsr blob_set_reu
        lda #<bp_audio
        ldx #>bp_audio
        jsr ultimate_audio_load_wav
        jmp blob_done

blob_open:
        jsr blob_set_name
        lda bp_attrib
        jsr ultimate_open
        jmp blob_done

blob_close:
        jsr ultimate_close
        jmp blob_done

; bp_len goes in as how many bytes to ask for and comes back as how many
; arrived: fewer than asked for is the end of the file, not an error.
blob_read:
        jsr blob_set_addr_buf
        lda #<bp_len
        sta ult_outlen
        lda #>bp_len
        sta ult_outlen + 1
        jsr ultimate_read
        jmp blob_done

blob_write:
        jsr blob_set_addr_buf
        jsr ultimate_write
        jmp blob_done

blob_seek:
        ldx #$03
@copy:  lda bp_pos,x
        sta ult_num,x
        dex
        bpl @copy
        jsr ultimate_seek
        jmp blob_done

blob_delete:
        jsr blob_set_name
        jsr ultimate_delete
        jmp blob_done

; bp_addr of zero means the file's own load address, exactly as it does for
; ultimate_load. bp_end holds the address after the last byte either way.
blob_load:
        jsr blob_set_name
        jsr blob_set_addr_len
        jsr ultimate_load
        jmp blob_loaded

blob_bload:
        jsr blob_set_name
        jsr blob_set_addr_len
        jsr ultimate_bload
        jmp blob_loaded

blob_save:
        jsr blob_set_name
        jsr blob_set_addr_len
        jsr ultimate_save
        jmp blob_done

blob_reu_available:
        jmp ultimate_reu_available

; The size in 64K banks, into bp_len, because 16 MB is 256 banks and will not
; fit a single byte of the block.
blob_reu_size:
        jsr ultimate_reu_size
        sta bp_len
        stx bp_len + 1
        lda #ULTIMATE_OK
        jmp blob_done

; The deprecated HWINFO command's count-prefixed SID records fit in bp_reply.
; A blob caller reads the same layout as a linked caller without a pointer.
blob_legacy_sid_info:
        lda #<bp_reply
        ldx #>bp_reply
        jsr ultimate_legacy_get_sid_info
        jmp blob_done

blob_reu_stash:
        jsr blob_set_reu
        jsr ultimate_reu_stash
        jmp blob_done

blob_reu_fetch:
        jsr blob_set_reu
        jsr ultimate_reu_fetch
        jmp blob_done

blob_reu_load:
        jsr blob_set_reu
        jsr ultimate_reu_load
        jmp blob_done

blob_reu_save:
        jsr blob_set_reu
        jsr ultimate_reu_save
        jmp blob_done

; --- the sockets ---

blob_net_ifcount:
        jsr ultimate_net_ifcount
        pha
        lda ult_iface
        sta bp_iface
        pla
        jmp blob_done

blob_net_macaddr:
        jsr blob_set_iface_reply
        jsr ultimate_net_macaddr
        jmp blob_done

blob_net_ipconfig:
        jsr blob_set_iface_reply
        jsr ultimate_net_ipconfig
        jmp blob_done

; The host goes in bp_name like every other name, and the handle comes back in
; bp_sock whether the open worked or not - $FF when it did not, which is what
; the SDK leaves and is not a handle.
blob_net_connect:
        jsr blob_set_host_port
        jsr ultimate_net_connect
        jmp blob_opened

blob_net_udp:
        jsr blob_set_host_port
        jsr ultimate_net_udp
        jmp blob_opened

blob_net_close:
        lda bp_sock
        sta ult_sock
        jsr ultimate_net_close
        jmp blob_done

; bp_len goes in as the size of the buffer at bp_addr and comes back as how
; many bytes are in it - which for a read is at most two fewer than asked for,
; because the firmware's own count is stripped off the front.
blob_net_read:
        jsr blob_set_sock_buf
        lda bp_len
        sta ult_socklen
        lda bp_len + 1
        sta ult_socklen + 1
        jsr ultimate_net_read
        jmp blob_moved

blob_net_write:
        jsr blob_set_sock_buf
        lda bp_len
        sta ult_buflen
        lda bp_len + 1
        sta ult_buflen + 1
        jsr ultimate_net_write
        jmp blob_moved

; --- http ---
;
; The URL goes in bp_name like every other name, and the reply in bp_addr with
; bp_len as its size going in and what arrived coming out.

blob_http_get:
        jsr blob_set_url
        jsr blob_set_addr_buf
        jsr ultimate_http_get
        jmp blob_http_done

blob_http_open:
        jsr blob_set_url
        lda bp_verb
        jsr ultimate_http_open
        pha
        lda ult_http
        sta bp_http
        pla
        jmp blob_done

; The header line goes in bp_name too - it is a string the caller supplies, and
; there is only ever one of them in flight.
blob_http_header:
        jsr blob_set_url
        lda bp_http
        sta ult_http
        jsr ultimate_http_header
        jmp blob_done

blob_http_exchange:
        lda bp_http
        sta ult_http
        lda bp_body
        sta ult_body
        jsr blob_set_addr_buf
        jsr ultimate_http_exchange
        jmp blob_http_done

blob_http_close:
        lda bp_http
        jsr ultimate_http_close
        jmp blob_done

blob_http_free_all:
        jsr ultimate_http_free_all
        jmp blob_done

blob_http_done:
        pha
        lda ult_httplen
        sta bp_len
        lda ult_httplen + 1
        sta bp_len + 1
        pla
        jmp blob_done

blob_set_url:
        lda #<bp_name
        sta ult_url
        lda #>bp_name
        sta ult_url + 1
        rts

; --- the rest of Ultimate DOS ---

blob_stat:
        jsr blob_set_name
        jsr blob_set_arg2_reply
        jsr ultimate_stat
        jmp blob_done

blob_fstat:
        jsr blob_set_arg2_reply
        jsr ultimate_fstat
        jmp blob_done

blob_rename:
        jsr blob_set_two_names
        jsr ultimate_rename
        jmp blob_done

blob_copy:
        jsr blob_set_two_names
        jsr ultimate_copy
        jmp blob_done

blob_mkdir:
        jsr blob_set_name
        jsr ultimate_mkdir
        jmp blob_done

blob_home:
        jsr ultimate_home
        jmp blob_done

; --- disk images ---

blob_mount:
        jsr blob_set_name
        lda bp_drive
        jsr ultimate_mount
        jmp blob_done

blob_unmount:
        lda bp_drive
        jsr ultimate_unmount
        jmp blob_done

blob_swap:
        lda bp_drive
        jsr ultimate_swap
        jmp blob_done

; --- the clock ---

blob_get_time:
        jsr blob_set_reply
        lda bp_format
        jsr ultimate_get_time
        jmp blob_done

blob_set_time:
        ldx #$05
@copy:  lda bp_time,x
        sta ult_stage,x
        dex
        bpl @copy
        jsr ultimate_set_time
        jmp blob_done

; --- the machine ---

blob_reboot:
        jsr ultimate_reboot
        jmp blob_done

blob_freeze:
        jsr ultimate_freeze
        jmp blob_done

blob_drive_enable:
        ldx bp_flag
        lda bp_drive
        jsr ultimate_drive_enable
        jmp blob_done

blob_drive_power:
        lda bp_drive
        jsr ultimate_drive_power
        pha
        lda ult_stage
        sta bp_flag
        pla
        jmp blob_done

blob_drive_info:
        lda #<bp_reply
        ldx #>bp_reply
        jsr ultimate_drive_info
        jmp blob_done

blob_ramdisk_info:
        lda #<bp_reply
        ldx #>bp_reply
        jsr ultimate_ramdisk_info
        jmp blob_done

; The twelve bytes go in bp_reply, which is where ipconfig puts them coming the
; other way, so reading a configuration and writing it back needs no copying.
blob_net_setip:
        jsr blob_set_iface_reply
        jsr ultimate_net_setip
        jmp blob_done

; --- HTTP request bodies ---

blob_http_body:
        lda bp_format
        jsr ultimate_http_body
        pha
        lda ult_body
        sta bp_body
        pla
        jmp blob_done

blob_http_body_free:
        jsr blob_set_body
        jsr ultimate_http_body_free
        jmp blob_done

blob_http_body_clear:
        jsr blob_set_body
        jsr ultimate_http_body_clear
        jmp blob_done

blob_http_body_int:
        jsr blob_set_body_key
        ldx #$03
@copy:  lda bp_val,x
        sta ult_val,x
        dex
        bpl @copy
        jsr ultimate_http_body_int
        jmp blob_done

blob_http_body_bool:
        jsr blob_set_body_key
        lda bp_flag
        sta ult_val
        jsr ultimate_http_body_bool
        jmp blob_done

; The key is bp_name, as every caller string is, and the value is bp_name2.
blob_http_body_string:
        jsr blob_set_body_key
        lda #<bp_name2
        sta ult_buf
        lda #>bp_name2
        sta ult_buf + 1
        jsr ultimate_http_body_string
        jmp blob_done

blob_http_body_binary:
        jsr blob_set_body
        jsr blob_set_addr_buf
        jsr ultimate_http_body_binary
        jmp blob_done

blob_set_body:
        lda bp_body
        sta ult_body
        rts

blob_set_body_key:
        jsr blob_set_body
        jmp blob_set_url                ; the key travels where a URL does

; bp_reply as the block a stat reply is received into.
blob_set_arg2_reply:
        lda #<bp_reply
        sta ult_arg2
        lda #>bp_reply
        sta ult_arg2 + 1
        rts

blob_set_two_names:
        jsr blob_set_name
        lda #<bp_name2
        sta ult_arg2
        lda #>bp_name2
        sta ult_arg2 + 1
        rts

; --- moving the block in and out ---

blob_done:
        sta bp_result
        rts

blob_loaded:
        pha
        lda ult_end
        sta bp_end
        lda ult_end + 1
        sta bp_end + 1
        pla
        jmp blob_done

blob_set_name:
        lda #<bp_name
        sta ult_buf
        lda #>bp_name
        sta ult_buf + 1
        rts

; The reply buffer as the caller's output, with its own size, for the entry
; points that answer with a string.
blob_set_reply:
        lda #<bp_reply
        sta ult_buf
        lda #>bp_reply
        sta ult_buf + 1
        lda #<BP_REPLY_MAX
        sta ult_buflen
        lda #>BP_REPLY_MAX
        sta ult_buflen + 1
        lda #$00
        sta ult_outlen
        sta ult_outlen + 1
        rts

; bp_addr and bp_len as a buffer: what read fills and what write sends.
blob_set_addr_buf:
        lda bp_addr
        sta ult_buf
        lda bp_addr + 1
        sta ult_buf + 1
        lda bp_len
        sta ult_buflen
        lda bp_len + 1
        sta ult_buflen + 1
        lda #$00
        sta ult_outlen
        sta ult_outlen + 1
        rts

; bp_addr and bp_len as a region: where a load puts it, or a save takes it from.
blob_set_addr_len:
        lda bp_addr
        sta ult_addr
        lda bp_addr + 1
        sta ult_addr + 1
        lda bp_len
        sta ult_max
        lda bp_len + 1
        sta ult_max + 1
        rts

blob_opened:
        pha
        lda ult_sock
        sta bp_sock
        pla
        jmp blob_done

blob_moved:
        pha
        lda ult_socklen
        sta bp_len
        lda ult_socklen + 1
        sta bp_len + 1
        pla
        jmp blob_done

blob_set_iface_reply:
        lda bp_iface
        sta ult_iface
        lda #<bp_reply
        sta ult_buf
        lda #>bp_reply
        sta ult_buf + 1
        rts

blob_set_host_port:
        jsr blob_set_name
        lda bp_port
        sta ult_port
        lda bp_port + 1
        sta ult_port + 1
        rts

blob_set_sock_buf:
        lda bp_sock
        sta ult_sock
        lda bp_addr
        sta ult_buf
        lda bp_addr + 1
        sta ult_buf + 1
        rts

; The expansion's two numbers, and the C64 end for the DMA pair.
blob_set_reu:
        ldx #$03
@copy:  lda bp_reu,x
        sta ult_reu,x
        lda bp_reulen,x
        sta ult_reulen,x
        dex
        bpl @copy
        lda bp_addr
        sta ult_addr
        lda bp_addr + 1
        sta ult_addr + 1
        rts
