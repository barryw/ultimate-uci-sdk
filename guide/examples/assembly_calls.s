        .include "ultimate.inc"

.macro setptr location, value
        lda #<value
        sta location
        lda #>value
        sta location + 1
.endmacro

.macro setword location, value
        lda #<value
        sta location
        lda #>value
        sta location + 1
.endmacro

        .segment "CODE"

; Assemble every public entry point printed in the assembly chapter.
guide_assembly_calls:
        jsr ultimate_init
        jsr ultimate_available
        lda #<buffer
        ldx #>buffer
        jsr ultimate_detect
        setptr ult_buf, buffer
        setword ult_buflen, 64
        setptr ult_outlen, word_out
        lda #UCI_TARGET_DOS1
        jsr ultimate_identify
        jsr ultimate_get_model
        lda #<sid_info
        ldx #>sid_info
        jsr ultimate_legacy_get_sid_info
        lda #ULTIMATE_ERR_IO
        jsr ultimate_strerror
        lda #<palette
        ldx #>palette
        jsr ultimate_palette_get
        jsr ultimate_palette_set
        jsr ultimate_palette_set_color
        jsr ultimate_palette_reset
        jsr ultimate_turbo_available
        jsr ultimate_turbo_get
        lda #U64_SPEED_4MHZ
        jsr ultimate_turbo_set
        lda #0
        jsr ultimate_turbo_badlines
        jsr ultimate_chdir
        jsr ultimate_getpath
        jsr ultimate_opendir
        jsr ultimate_readdir
        lda #DOS_FA_READ
        jsr ultimate_open
        jsr ultimate_close
        jsr ultimate_read
        jsr ultimate_write
        jsr ultimate_seek
        jsr ultimate_delete
        jsr ultimate_load
        jsr ultimate_bload
        jsr ultimate_save
        jsr ultimate_last_end
        jsr ultimate_reu_available
        jsr ultimate_reu_size
        jsr ultimate_reu_stash
        jsr ultimate_reu_fetch
        jsr ultimate_reu_load
        jsr ultimate_reu_save
        jsr ultimate_net_ifcount
        jsr ultimate_net_macaddr
        jsr ultimate_net_ipconfig
        jsr ultimate_net_connect
        jsr ultimate_net_udp
        jsr ultimate_net_close
        jsr ultimate_net_read
        jsr ultimate_net_write
        jsr ultimate_http_get
        lda #HTTP_VERB_GET
        jsr ultimate_http_open
        jsr ultimate_http_header
        jsr ultimate_http_exchange
        jsr ultimate_http_close
        jsr ultimate_http_free_all
        jsr uci_present
        jsr uci_ident
        jsr uci_req_clear
        setptr uci_req + UCI_REQ_DATA, buffer
        setword uci_req + UCI_REQ_DATAMAX, 64
        jsr uci_exec_block
        lda #<request
        ldx #>request
        jsr uci_exec
        jsr uci_exec_first
        lda uci_more
        jsr uci_exec_next
        jsr uci_abort
        jsr uci_get_timeout_a
        jsr uci_set_timeout_a
        jsr uci_last_code
        rts

        .segment "BSS"

buffer:   .res 512
palette:  .res UCI_PALETTE_BYTES
word_out: .res 2
request:  .res UCI_REQ_SIZE
sid_info: .res ULTIMATE_SID_INFO_SIZE
