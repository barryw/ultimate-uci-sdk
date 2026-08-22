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
        setptr ult_buf, buffer
        setptr ult_arg2, fileinfo
        jsr ultimate_stat
        jsr ultimate_fstat
        jsr ultimate_rename
        jsr ultimate_copy
        jsr ultimate_mkdir
        jsr ultimate_home
        lda #8
        jsr ultimate_mount
        lda #ULTIMATE_DRIVE_LAST
        jsr ultimate_mount
        lda #8
        jsr ultimate_unmount
        lda #8
        jsr ultimate_swap
        setword ult_buflen, ULTIMATE_TIME_BUFFER
        lda #ULTIMATE_TIME_PLAIN
        jsr ultimate_get_time
        lda #ULTIMATE_TIME_WEEKDAY
        jsr ultimate_get_time
        lda #126
        sta ult_stage + 0
        jsr ultimate_set_time
        lda #<drives
        ldx #>drives
        jsr ultimate_drive_info
        lda #<ramdisk
        ldx #>ramdisk
        jsr ultimate_ramdisk_info
        lda #ULTIMATE_DRIVE_A
        ldx #1
        jsr ultimate_drive_enable
        lda #ULTIMATE_DRIVE_B
        ldx #0
        jsr ultimate_drive_enable
        lda #ULTIMATE_DRIVE_A
        jsr ultimate_drive_power
        lda ult_stage
        jsr ultimate_freeze
        jsr ultimate_reboot
        jsr ultimate_net_ifcount
        jsr ultimate_net_macaddr
        jsr ultimate_net_ipconfig
        jsr ultimate_net_setip
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
        lda #HTTP_BODY_JSON_OBJECT
        jsr ultimate_http_body
        setptr ult_url, buffer
        setptr ult_buf, buffer
        jsr ultimate_http_body_string
        setword ult_val, 4200
        lda #0
        sta ult_val + 2
        sta ult_val + 3
        jsr ultimate_http_body_int
        jsr ultimate_http_body_bool
        jsr ultimate_http_body_object
        jsr ultimate_http_body_array
        jsr ultimate_http_body_up
        setword ult_buflen, 4
        jsr ultimate_http_body_binary
        jsr ultimate_http_body_clear
        jsr ultimate_http_body_free
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
fileinfo: .res ULTIMATE_FILEINFO_SIZE
drives:   .res CTRL_DRVINFO_BYTES
ramdisk:  .res CTRL_RAMDISK_BYTES
