; harness.s - entry points for driving the SDK from a sim6502 test suite.
;
; This runs the SDK's *assembled 6502 code* against a simulated Ultimate, which
; is the only place the shipping binary gets exercised at all. Each entry point
; runs one SDK call and leaves its result in a labelled byte the suite can
; assert on.
;
; Two calling conventions are deliberately mixed. A few entry points go the long
; way round through cc65's software stack (`t_identify_dos1`, `t_detect`) to
; prove the C entry points are callable at all; the rest call the assembly ABI
; directly, which is what an assembly program does and what nothing else tested
; before.
;
; Build:  make
; Run:    see tests/emulator/README.md
;
; SPDX-License-Identifier: MIT

        .include "ultimate.inc"

        .forceimport __STARTUP__
        .export _main

        ; --- C ABI, through cc65's software stack ---
        .import _ultimate_init
        .import _ultimate_detect
        .import _ultimate_identify
        .import pusha, pushax
        .importzp sp

        ; --- assembly ABI, called directly ---
        .import uci_exec
        .import uci_present, uci_ident
        .import uci_decode, uci_dec_target, uci_dec_ptr, uci_dec_len
        .import uci_status_fmt
        .import uci_set_timeout_a, uci_get_timeout_a
        .import uci_abort
        .import uci_last_code
        .import ultimate_available, ultimate_identify, ultimate_get_model
        .import ultimate_legacy_get_sid_info
        .import ultimate_strerror
        .import ultimate_palette_get, ultimate_palette_set
        .import ultimate_palette_set_color, ultimate_palette_reset
        .import ultimate_turbo_available, ultimate_turbo_get
        .import ultimate_turbo_set, ultimate_turbo_badlines
        .import ultimate_vsprite_draw
        .import ultimate_chdir, ultimate_getpath
        .import ultimate_opendir, ultimate_readdir
        .import ultimate_open, ultimate_close, ultimate_read
        .import ultimate_write, ultimate_seek, ultimate_delete
        .import ultimate_stat, ultimate_fstat, ultimate_rename
        .import ultimate_copy, ultimate_mkdir, ultimate_home
        .import ultimate_mount, ultimate_unmount, ultimate_swap
        .import ultimate_get_time, ultimate_set_time
        .import ultimate_reboot, ultimate_freeze
        .import ultimate_drive_enable, ultimate_drive_power
        .import ultimate_drive_info, ultimate_ramdisk_info
        .import ctrl_drvinfo_reply, ult_req
        .import ultimate_net_setip
        .import ultimate_http_body, ultimate_http_body_free
        .import ultimate_http_body_clear, ultimate_http_body_up
        .import ultimate_http_body_int, ultimate_http_body_bool
        .import ultimate_http_body_string, ultimate_http_body_object
        .import ultimate_http_body_array, ultimate_http_body_binary
        .import ult_arg2, ult_stage, ult_val, ult_body
        .import ult_attrib, ult_addr, ult_max, ult_end, ult_num
        .import ultimate_load, ultimate_bload, ultimate_save
        .import ultimate_reu_available, ultimate_reu_stash, ultimate_reu_fetch
        .import ultimate_reu_load, ultimate_reu_save
        .import ult_reu, ult_reulen
        .import wav_sign_pass, ult_scratch
        .import ultimate_net_ifcount, ultimate_net_ipconfig
        .import ultimate_net_connect, ultimate_net_read, ultimate_net_write
        .import ult_sock, ult_socklen, ult_iface, ult_port
        .import ult_buf, ult_buflen, ult_outlen, ult_color

        ; --- entry points ---
        .export boot
        .export t_break_cstack
        .export t_init
        .export t_present
        .export t_ident_reg
        .export t_available
        .export t_identify_dos1
        .export t_identify_absent
        .export t_detect
        .export t_identify
        .export t_get_model
        .export t_sid_info, t_sid_info_null
        .export t_palette_get, t_palette_set
        .export t_palette_color, t_palette_reset
        .export t_palette_get_null, t_palette_set_null
        .export t_turbo_available, t_turbo_get
        .export t_turbo_set, t_turbo_badlines
        .export t_vsprite_draw, t_vsprite_null
        .export t_chdir, t_getpath, t_opendir, t_readdir
        .export t_open, t_close, t_read
        .export t_create, t_write, t_seek, t_delete
        .export t_stat, t_fstat, t_rename, t_copy, t_mkdir, t_home
        .export t_mount, t_unmount, t_swap
        .export t_get_time, t_set_time
        .export t_reboot, t_freeze
        .export t_drive_enable, t_drive_power
        .export t_drive_info, t_ramdisk_info, t_drvinfo_reply, drvinfo_len
        .export t_net_setip
        .export t_body, t_body_free, t_body_clear, t_body_up
        .export t_body_int, t_body_bool, t_body_string
        .export t_body_object, t_body_array, t_body_binary
        .export name2, finfo, drive_arg, flag_arg, body_arg
        .export time_arg, val_arg
        .export wr_len, seek_pos
        .export t_load, t_bload, t_save, load_addr, load_max, load_end
        .export t_reu_avail, t_reu_stash, t_reu_fetch
        .export t_reu_load, t_reu_save, reu_at, reu_len
        .export t_flags_init, t_flags_reu_avail, t_flags_audio_avail
        .export t_audio_load_wav, voice
        .export t_wav_sign_pass
        .export t_net_ifcount, t_net_ipconfig
        .export t_net_connect, t_net_connect_null
        .export t_net_read_null, t_net_read_tiny, t_net_write_null
        .export net_iface, net_sock, net_got
        .export dir_attrib
        .export t_req_reset
        .export t_abort, t_status_reg
        .export t_exec
        .export t_decode
        .export t_status_fmt
        .export t_strerror
        .export t_set_timeout
        .export t_get_timeout
        .export t_wedge

        ; --- results ---
        .export result
        .export devcode
        .export reply
        .export reply_len
        .export caps
        .export sid_info

        ; --- parameters ---
        .export ident_target, ident_buflen
        .export dec_target, dec_buf, dec_len
        .export fmt_target
        .export err_code, err_text
        .export timeout_val
        .export pal_index
        .export turbo_arg
        .export vsprite, vs_bitmap, vs_source, vs_mask, vs_screen
        .export vs_x, vs_y, vs_width, vs_height, vs_color, vs_flags

        ; --- the request block and the buffers it points at ---
        .export req
        .export req_target, req_command
        .export req_args, req_arglen
        .export req_payload, req_payloadlen
        .export req_data, req_datamax, req_datalen
        .export req_status, req_statusmax, req_statuslen
        .export buf_args, buf_payload, buf_data, buf_status

        ; A few individual bytes get their own labels so a suite can name them
        ; without address arithmetic.
        .export reply0, reply1, reply2, reply3
        .export caps_present, caps_ident, caps_targets_lo, caps_targets_hi

REPLY_MAX    = 64
ARGS_MAX     = 896      ; UCI_MAX_COMMAND_USABLE, rounded up
PAYLOAD_MAX  = 256
DATA_MAX     = 1024     ; room for the largest reply the SDK can provoke
STATUS_MAX   = 256
ERR_TEXT_MAX = 32

STACK_TOP    = $CF00    ; well clear of the harness, below the I/O area

; ---------------------------------------------------------------------------

        .bss

result:     .res 1
devcode:    .res 2
reply_len:  .res 2
caps:       .res 4      ; ultimate_capabilities: present, ident, targets(2)
reply:      .res REPLY_MAX
sid_info:   .res ULTIMATE_SID_INFO_SIZE

net_iface:  .res 1
net_sock:   .res 1
net_got:    .res 2

ident_target: .res 1
ident_buflen: .res 2
dec_target:   .res 1
dec_len:      .res 1
dec_buf:      .res 8
fmt_target:   .res 1
err_code:     .res 1
err_text:     .res ERR_TEXT_MAX
timeout_val:  .res 1
pal_index:    .res 1
turbo_arg:    .res 1
dir_attrib:   .res 1
load_addr:    .res 2
load_max:     .res 2
load_end:     .res 2
wr_len:       .res 2      ; how many bytes t_write sends from buf_data
seek_pos:     .res 4      ; t_seek's 32-bit position, little endian
reu_at:       .res 4      ; the REU address a transfer uses
reu_len:      .res 4      ; and how many bytes it moves
voice:        .res UA_VOICE_SIZE  ; the ultimate_audio_voice t_audio_load_wav fills
vsprite:      .res VSPRITE_SIZE

vs_bitmap = vsprite + VSPRITE_BITMAP
vs_source = vsprite + VSPRITE_SOURCE
vs_mask   = vsprite + VSPRITE_MASK
vs_screen = vsprite + VSPRITE_SCREEN
vs_x      = vsprite + VSPRITE_X
vs_y      = vsprite + VSPRITE_Y
vs_width  = vsprite + VSPRITE_WIDTH
vs_height = vsprite + VSPRITE_HEIGHT
vs_color  = vsprite + VSPRITE_COLOR
vs_flags  = vsprite + VSPRITE_FLAGS

; The second name rename and copy take, and the block a stat reply is received
; into. `reply` holds the first name, as it does for every other DOS entry
; point, so these two are what the pair of them needs beyond it.
name2:        .res REPLY_MAX
finfo:        .res ULTIMATE_FILEINFO_SIZE

drive_arg:    .res 1      ; an IEC device number, or drive A or B
drvinfo_len:  .res 1      ; the reply length t_drvinfo_reply hands the parser
flag_arg:     .res 1      ; on or off, in and out
body_arg:     .res 1      ; an HTTP body format going in, its handle coming out
time_arg:     .res 6      ; year less 1900, month, day, hour, minute, second
val_arg:      .res 4      ; the 32-bit value an HTTP body integer carries

req:         .res UCI_REQ_SIZE
buf_args:    .res ARGS_MAX
buf_payload: .res PAYLOAD_MAX
buf_data:    .res DATA_MAX
buf_status:  .res STATUS_MAX

reply0          = reply
reply1          = reply + 1
reply2          = reply + 2
reply3          = reply + 3
caps_present    = caps
caps_ident      = caps + 1
caps_targets_lo = caps + 2
caps_targets_hi = caps + 3

req_target      = req + UCI_REQ_TARGET
req_command     = req + UCI_REQ_COMMAND
req_args        = req + UCI_REQ_ARGS
req_arglen      = req + UCI_REQ_ARGLEN
req_payload     = req + UCI_REQ_PAYLOAD
req_payloadlen  = req + UCI_REQ_PAYLOADLEN
req_data        = req + UCI_REQ_DATA
req_datamax     = req + UCI_REQ_DATAMAX
req_datalen     = req + UCI_REQ_DATALEN
req_status      = req + UCI_REQ_STATUS
req_statusmax   = req + UCI_REQ_STATUSMAX
req_statuslen   = req + UCI_REQ_STATUSLEN

; ---------------------------------------------------------------------------

        .code

; The suite loads this program rather than running it, so the normal start-up
; never executes. boot does the one thing the C entry points need from it: a
; valid C stack pointer. Call it once, from each test.
boot:
        lda #<STACK_TOP
        sta sp
        lda #>STACK_TOP
        sta sp + 1
        rts

; The opposite of boot: leave the cc65 software stack pointer null, so that
; anything on the assembly path which reaches for it writes through a null
; pointer into the 6510's port registers at $00/$01 and takes the machine with
; it. That is how "the assembly ABI needs no C runtime" gets tested rather than
; asserted.
t_break_cstack:
        lda #$00
        sta sp
        sta sp + 1
        rts

; Nothing to do when run as a program; the suite calls the entry points below.
_main:
        rts

; --------------------------------------------------------------- bring-up ---

t_init:
        jsr _ultimate_init
        sta result
        rts

t_present:
        jsr uci_present
        sta result
        rts

t_ident_reg:
        jsr uci_ident
        sta result
        rts

; The raw status register, for a suite that wants to see the interface's own
; view of itself: abort pending, state, error.
t_status_reg:
        lda UCI_REG_STATUS
        sta result
        rts

t_available:
        jsr ultimate_available
        sta result
        rts

; --------------------------------------------------------------- identity ---

; ultimate_identify(target, buf, buflen, outlen) through the C ABI - four
; arguments, so the first three go on the C stack and the last arrives in A/X.
.macro identify_call target
        lda #target
        jsr pusha
        lda #<reply
        ldx #>reply
        jsr pushax
        lda #<REPLY_MAX
        ldx #>REPLY_MAX
        jsr pushax
        lda #<reply_len
        ldx #>reply_len
        jsr _ultimate_identify
.endmacro

t_identify_dos1:
        identify_call UCI_TARGET_DOS1
        sta result
        rts

t_identify_absent:
        identify_call $07               ; no firmware implements target $07
        sta result
        rts

t_detect:
        lda #<caps
        ldx #>caps
        jsr _ultimate_detect
        sta result
        rts

; The same call through the assembly ABI, with the buffer length under the
; suite's control so a deliberately short buffer can be tested.
t_identify:
        jsr set_ult_buf
        lda ident_target
        jsr ultimate_identify
        sta result
        rts

t_get_model:
        jsr set_ult_buf
        jsr ultimate_get_model
        sta result
        rts

t_sid_info:
        lda #<sid_info
        ldx #>sid_info
        jsr ultimate_legacy_get_sid_info
        sta result
        rts

t_sid_info_null:
        lda #$00
        ldx #$00
        jsr ultimate_legacy_get_sid_info
        sta result
        rts

; --- the palette service ---
;
; The simulated Ultimate does not implement these four commands, so what can be
; proved here is the half that does not need firmware: the argument checks, and
; that a firmware which rejects the command is reported as unsupported rather
; than hanging or being mistaken for success. `reply` is 64 bytes, comfortably
; the 48 a palette needs. The rest is hardware only - tests/hardware/ucitest.c.

t_palette_get:
        lda #<reply
        ldx #>reply
        jsr ultimate_palette_get
        sta result
        rts

t_palette_set:
        lda #<reply
        ldx #>reply
        jsr ultimate_palette_set
        sta result
        rts

; A null buffer is a caller bug, and must be refused before anything reaches
; the wire rather than read from page zero.
t_palette_get_null:
        lda #$00
        ldx #$00
        jsr ultimate_palette_get
        sta result
        rts

t_palette_set_null:
        lda #$00
        ldx #$00
        jsr ultimate_palette_set
        sta result
        rts

t_palette_color:
        lda pal_index
        sta ult_color
        lda #$11
        sta ult_color + 1
        lda #$22
        sta ult_color + 2
        lda #$33
        sta ult_color + 3
        jsr ultimate_palette_set_color
        sta result
        rts

t_palette_reset:
        jsr ultimate_palette_reset
        sta result
        rts

; --- turbo ---
;
; A simulated C64 has no Ultimate turbo, and $D031 reads $FF there for the same
; reason it does on a real machine with turbo switched off in its settings: an
; unimplemented VIC register. So this is not a stand-in for the hardware test -
; it is the no-turbo case itself, which is what every program shipping to other
; people has to survive. The speed really changing is proved in
; tests/hardware/ucitest.c, on a machine that has one.

t_turbo_available:
        jsr ultimate_turbo_available
        sta result
        rts

t_turbo_get:
        jsr ultimate_turbo_get
        sta result
        rts

t_turbo_set:
        lda turbo_arg
        jsr ultimate_turbo_set
        sta result
        rts

t_turbo_badlines:
        lda turbo_arg
        jsr ultimate_turbo_badlines
        sta result
        rts

; --- software vsprites ---

t_vsprite_draw:
        lda #<vsprite
        ldx #>vsprite
        jsr ultimate_vsprite_draw
        sta result
        rts

t_vsprite_null:
        lda #$00
        ldx #$00
        jsr ultimate_vsprite_draw
        sta result
        rts

; --- the DOS service ---
;
; u64sim implements the read-only half of Ultimate DOS against a real directory
; tree (tests/emulator/fixtures/usb0), so unlike the palette these run for real
; in CI rather than proving only that a rejection is reported cleanly.
;
; `reply` is the buffer throughout, and ident_buflen sizes it, so the suite sets
; the same two fields it already sets for identify.

t_chdir:
        jsr set_ult_buf
        lda #<reply             ; the path was put in `reply` by the suite
        sta ult_buf
        lda #>reply
        sta ult_buf + 1
        jsr ultimate_chdir
        sta result
        rts

t_getpath:
        jsr set_ult_buf
        jsr ultimate_getpath
        sta result
        rts

t_opendir:
        jsr ultimate_opendir
        sta result
        rts

t_readdir:
        jsr set_ult_buf
        jsr ultimate_readdir
        sta result
        lda ult_attrib
        sta dir_attrib
        rts

t_open:
        jsr set_ult_buf
        lda #<reply             ; the name was put in `reply` by the suite
        sta ult_buf
        lda #>reply
        sta ult_buf + 1
        lda #DOS_FA_READ
        jsr ultimate_open
        sta result
        rts

t_close:
        jsr ultimate_close
        sta result
        rts

t_read:
        jsr set_ult_buf
        jsr ultimate_read
        sta result
        rts

; The write half of the same service. The name goes in `reply`, as it does for
; t_open; the data is whatever the suite poked into buf_data, and wr_len says
; how much of it to send.
t_create:
        jsr set_ult_buf
        lda #<reply
        sta ult_buf
        lda #>reply
        sta ult_buf + 1
        lda #DOS_FA_CREATE_ALWAYS | DOS_FA_WRITE | DOS_FA_READ
        jsr ultimate_open
        sta result
        rts

t_write:
        lda #<buf_data
        sta ult_buf
        lda #>buf_data
        sta ult_buf + 1
        lda wr_len
        sta ult_buflen
        lda wr_len + 1
        sta ult_buflen + 1
        jsr ultimate_write
        sta result
        rts

t_seek:
        ldx #$03
@copy:  lda seek_pos,x
        sta ult_num,x
        dex
        bpl @copy
        jsr ultimate_seek
        sta result
        rts

t_delete:
        lda #<reply
        sta ult_buf
        lda #>reply
        sta ult_buf + 1
        jsr ultimate_delete
        sta result
        rts

; --- stat, rename, copy, and make directory ---
;
; The name goes in `reply` like every other DOS name; the second name goes in
; `name2` and the stat reply lands in `finfo`, whose layout is DOS_INFO_* -
; the suite asserts on the size field there, which is the one a program
; actually reads.

t_stat:
        jsr set_name_and_info
        jsr ultimate_stat
        sta result
        rts

t_fstat:
        jsr set_info
        jsr ultimate_fstat
        sta result
        rts

t_rename:
        jsr set_two_names
        jsr ultimate_rename
        sta result
        rts

t_copy: jsr set_two_names
        jsr ultimate_copy
        sta result
        rts

t_mkdir:
        lda #<reply
        sta ult_buf
        lda #>reply
        sta ult_buf + 1
        jsr ultimate_mkdir
        sta result
        rts

set_info:
        lda #<finfo
        sta ult_arg2
        lda #>finfo
        sta ult_arg2 + 1
        rts

set_name_and_info:
        jsr set_info
        lda #<reply
        sta ult_buf
        lda #>reply
        sta ult_buf + 1
        rts

set_two_names:
        lda #<reply
        sta ult_buf
        lda #>reply
        sta ult_buf + 1
        lda #<name2
        sta ult_arg2
        lda #>name2
        sta ult_arg2 + 1
        rts

; --- disk images, the clock, and the machine ---
;
; Every one of these answers ULTIMATE_ERR_NOT_SUPPORTED against the simulated
; Ultimate, which does not implement them: the DOS ones answer "99,FUNCTION NOT
; IMPLEMENTED" and the control ones "21,UNKNOWN COMMAND". That is the case a
; program meets on older firmware, and the suite pins it here for the same
; reason it pins the palette commands.

t_home: jsr ultimate_home
        sta result
        rts

t_mount:
        lda #<reply             ; the image name, put in `reply` by the suite
        sta ult_buf
        lda #>reply
        sta ult_buf + 1
        lda drive_arg
        jsr ultimate_mount
        sta result
        rts

t_unmount:
        lda drive_arg
        jsr ultimate_unmount
        sta result
        rts

t_swap: lda drive_arg
        jsr ultimate_swap
        sta result
        rts

t_get_time:
        jsr set_ult_buf
        lda flag_arg            ; the format byte
        jsr ultimate_get_time
        sta result
        rts

; The six numbers reach the SDK through its staging buffer, which is where an
; assembly caller puts them.
t_set_time:
        ldx #$05
@copy:  lda time_arg,x
        sta ult_stage,x
        dex
        bpl @copy
        jsr ultimate_set_time
        sta result
        rts

t_reboot:
        jsr ultimate_reboot
        sta result
        rts

t_freeze:
        jsr ultimate_freeze
        sta result
        rts

t_drive_enable:
        ldx flag_arg
        lda drive_arg
        jsr ultimate_drive_enable
        sta result
        rts

t_drive_power:
        lda drive_arg
        jsr ultimate_drive_power
        sta result
        lda ult_stage
        sta flag_arg
        rts

t_drive_info:
        lda #<reply
        ldx #>reply
        jsr ultimate_drive_info
        sta result
        rts

t_ramdisk_info:
        lda #<reply
        ldx #>reply
        jsr ultimate_ramdisk_info
        sta result
        rts

; The GET_DRVINFO reply parser on its own, with a reply the suite wrote into
; `reply` and a length in `drvinfo_len`. u64sim does not implement GET_DRVINFO,
; so this is the only way to run the parser against the reply a machine with an
; IEC bus slot in use really sends. It calls the shipping routine rather than
; repeating what it does, so a change to the parser changes what is asserted.
t_drvinfo_reply:
        lda #<reply
        sta ult_buf
        lda #>reply
        sta ult_buf + 1
        lda drvinfo_len
        sta ult_req + UCI_REQ_DATALEN
        lda #$00
        sta ult_req + UCI_REQ_DATALEN + 1
        jsr ctrl_drvinfo_reply
        sta result
        rts

t_net_setip:
        lda #<reply             ; the twelve bytes, put in `reply` by the suite
        sta ult_buf
        lda #>reply
        sta ult_buf + 1
        jsr ultimate_net_setip
        sta result
        rts

; --- HTTP request bodies ---
;
; The key goes in `reply` and a string value in `name2`, which is how the two
; caller strings reach every other entry point that takes a pair of them.

t_body: lda body_arg            ; the format going in
        jsr ultimate_http_body
        sta result
        lda ult_body            ; and the handle coming back
        sta body_arg
        rts

t_body_free:
        jsr set_body
        jsr ultimate_http_body_free
        sta result
        rts

t_body_clear:
        jsr set_body
        jsr ultimate_http_body_clear
        sta result
        rts

t_body_up:
        jsr set_body
        jsr ultimate_http_body_up
        sta result
        rts

t_body_int:
        jsr set_body_key
        ldx #$03
@copy:  lda val_arg,x
        sta ult_val,x
        dex
        bpl @copy
        jsr ultimate_http_body_int
        sta result
        rts

t_body_bool:
        jsr set_body_key
        lda flag_arg
        sta ult_val
        jsr ultimate_http_body_bool
        sta result
        rts

t_body_string:
        jsr set_body_key
        lda #<name2
        sta ult_buf
        lda #>name2
        sta ult_buf + 1
        jsr ultimate_http_body_string
        sta result
        rts

t_body_object:
        jsr set_body_key
        jsr ultimate_http_body_object
        sta result
        rts

t_body_array:
        jsr set_body_key
        jsr ultimate_http_body_array
        sta result
        rts

t_body_binary:
        jsr set_body
        lda #<buf_data
        sta ult_buf
        lda #>buf_data
        sta ult_buf + 1
        lda wr_len
        sta ult_buflen
        lda wr_len + 1
        sta ult_buflen + 1
        jsr ultimate_http_body_binary
        sta result
        rts

set_body:
        lda body_arg
        sta ult_body
        rts

set_body_key:
        jsr set_body
        lda #<reply
        sta ult_url
        lda #>reply
        sta ult_url + 1
        rts

; --- load and save ---
;
; The simulator has no SoftwareIEC target, so ultimate_load's fast path always
; fails here and the DOS fallback always runs. That is not a gap: falling back
; correctly is the half that every machine without an IEC drive depends on, and
; it is the half a hardware test cannot reach at all once the fast path works.

t_load: jsr set_load_args
        jsr ultimate_load
        sta result
        jsr save_load_end
        rts

t_bload:
        jsr set_load_args
        jsr ultimate_bload
        sta result
        jsr save_load_end
        rts

; save takes the same three arguments in the same places, so it shares the
; setter: the name in `reply`, the start address in load_addr, the length in
; load_max.
t_save: jsr set_load_args
        jsr ultimate_save
        sta result
        rts

; --- the RAM expansion ---
;
; The simulator has plain RAM at $DF00-$DF0A rather than a REU, which is enough
; to prove the registers are programmed with the right bytes in the right order
; and not enough to move anything. The suite pokes the done bit itself to say
; which outcome it is testing; hardware does the real transfer.

; The recovery hatch, as a caller reaches it: abandon whatever the interface is
; holding and put it back to idle.
t_abort:
        jsr uci_abort
        sta result
        rts

t_reu_avail:
        jsr ultimate_reu_available
        sta result
        rts

t_reu_stash:
        jsr set_reu_args
        jsr ultimate_reu_stash
        sta result
        rts

t_reu_fetch:
        jsr set_reu_args
        jsr ultimate_reu_fetch
        sta result
        rts

t_reu_load:
        jsr set_reu_args
        jsr ultimate_reu_load
        sta result
        rts

t_reu_save:
        jsr set_reu_args
        jsr ultimate_reu_save
        sta result
        rts

; The C64 end comes from load_addr, which every other transfer in this harness
; already uses for "where in memory".
set_reu_args:
        ldx #$03
@copy:  lda reu_at,x
        sta ult_reu,x
        lda reu_len,x
        sta ult_reulen,x
        dex
        bpl @copy
        lda load_addr
        sta ult_addr
        lda load_addr + 1
        sta ult_addr + 1
        rts

; --- byte results set the flags ---
;
; The ABI promises that a byte result in A leaves Z set from A, so that a
; caller can write `jsr entry` / `beq ok`. Each of these stores the Z bit of
; the status register exactly as the call left it: $02 when the result was
; zero, $00 when it was not.
t_flags_init:
        jsr ultimate_init
        jmp store_z

t_flags_reu_avail:
        jsr ultimate_reu_available
        jmp store_z

t_flags_audio_avail:
        jsr ultimate_audio_available
        jmp store_z

store_z:
        php
        pla
        and #$02
        sta result
        rts

; A WAV into the REU: the name is in `reply`, the REU address in reu_at, and
; the voice comes back in `voice`.
t_audio_load_wav:
        lda #<reply
        sta ult_buf
        lda #>reply
        sta ult_buf + 1
        ldx #$03
@copy:  lda reu_at,x
        sta ult_reu,x
        dex
        bpl @copy
        lda #<voice
        ldx #>voice
        jsr ultimate_audio_load_wav
        sta result
        rts

; The 8-bit sign pass on its own: the REU address from reu_at, the byte count
; from reu_len into WAV_LEN (ult_scratch+8), and afterwards ult_reu copied back
; into reu_at so the suite can see it was restored. result = 0 on success,
; else the error the pass returned.
t_wav_sign_pass:
        ldx #$03
@copy:  lda reu_at,x
        sta ult_reu,x
        lda reu_len,x
        sta ult_scratch + 8,x
        dex
        bpl @copy
        jsr wav_sign_pass
        bcs @failed
        lda #$00
@failed:
        sta result
        ldx #$03
@back:  lda ult_reu,x
        sta reu_at,x
        dex
        bpl @back
        rts

; The name is in `reply`, put there by the suite; the address and the limit come
; from labelled bytes so a test can name them.
set_load_args:
        lda #<reply
        sta ult_buf
        lda #>reply
        sta ult_buf + 1
        lda load_addr
        sta ult_addr
        lda load_addr + 1
        sta ult_addr + 1
        lda load_max
        sta ult_max
        lda load_max + 1
        sta ult_max + 1
        rts

save_load_end:
        lda ult_end
        sta load_end
        lda ult_end + 1
        sta load_end + 1
        rts

set_ult_buf:
        lda #<reply
        sta ult_buf
        lda #>reply
        sta ult_buf + 1
        lda ident_buflen
        sta ult_buflen
        lda ident_buflen + 1
        sta ult_buflen + 1
        lda #<reply_len
        sta ult_outlen
        lda #>reply_len
        sta ult_outlen + 1
        rts

; -------------------------------------------------------------- exchanges ---

; Put the request block back to a known state: every field zero, the four
; pointers aimed at the harness buffers, and those buffers cleared so no
; assertion can pass on a byte left by the previous test.
t_req_reset:
        lda #$00
        ldx #UCI_REQ_SIZE - 1
@zero:  sta req,x
        dex
        bpl @zero

        lda #<buf_args
        sta req_args
        lda #>buf_args
        sta req_args + 1
        lda #<buf_payload
        sta req_payload
        lda #>buf_payload
        sta req_payload + 1
        lda #<buf_data
        sta req_data
        lda #>buf_data
        sta req_data + 1
        lda #<DATA_MAX
        sta req_datamax
        lda #>DATA_MAX
        sta req_datamax + 1
        lda #<buf_status
        sta req_status
        lda #>buf_status
        sta req_status + 1
        lda #<STATUS_MAX
        sta req_statusmax
        lda #>STATUS_MAX
        sta req_statusmax + 1

        lda #$00
        tay
@clr:   sta buf_data,y
        sta buf_data + $100,y
        sta buf_data + $200,y
        sta buf_data + $300,y
        sta buf_status,y
        iny
        bne @clr
        rts

t_exec:
        lda #<req
        ldx #>req
        jsr uci_exec
        sta result
        jsr uci_last_code
        sta devcode
        stx devcode + 1
        rts

; Leave the interface wedged the way a program that died mid-exchange leaves
; it: a command pushed, its reply waiting, and nothing acknowledged. The next
; ultimate_init has to recover from this.
t_wedge:
        lda #UCI_TARGET_DOS1
        sta UCI_REG_CMDDATA
        lda #UCI_CMD_IDENTIFY
        sta UCI_REG_CMDDATA
        lda #UCI_CTRL_PUSH_CMD
        sta UCI_REG_CONTROL
@wait:  lda UCI_REG_STATUS
        and #UCI_STAT_STATE
        cmp #UCI_STATE_BUSY
        beq @wait
        rts

; ----------------------------------------------------------------- status ---

t_decode:
        lda dec_target
        sta uci_dec_target
        lda #<dec_buf
        sta uci_dec_ptr
        lda #>dec_buf
        sta uci_dec_ptr + 1
        lda dec_len
        sta uci_dec_len
        jsr uci_decode
        sta result
        jsr uci_last_code
        sta devcode
        stx devcode + 1
        rts

t_status_fmt:
        lda fmt_target
        jsr uci_status_fmt
        sta result
        rts

; The string is copied through a patched absolute address rather than an
; indirect: every zero page location the harness could borrow is spoken for by
; either the cc65 runtime or the SDK, and UCI_ZP moves between the two builds
; this suite runs against.
t_strerror:
        lda err_code
        jsr ultimate_strerror
        sta @src + 1
        stx @src + 2
        ldy #$00
@src:   lda $FFFF,y
        sta err_text,y
        beq @done
        iny
        cpy #ERR_TEXT_MAX - 1
        bcc @src
        lda #$00
        sta err_text + ERR_TEXT_MAX - 1
@done:  rts

; ---------------------------------------------------------------- timeout ---

; --------------------------------------------------------------------- net ---
;
; u64sim implements no network command at all, so what these can prove is the
; half of net.s that never reaches the wire: the argument checks, and that a
; command aimed at a target this device does not have comes back as
; ULTIMATE_ERR_NOT_SUPPORTED rather than as a hang or a wrong success.
;
; The other half - sockets that actually carry bytes - is in tests/hardware,
; against the Ultimate's own web server. See docs/uci.md.

t_net_ifcount:
        jsr ultimate_net_ifcount
        sta result
        lda ult_iface
        sta net_iface
        rts

t_net_ipconfig:
        lda net_iface
        sta ult_iface
        lda #<reply
        sta ult_buf
        lda #>reply
        sta ult_buf + 1
        jsr ultimate_net_ipconfig
        sta result
        rts

; The host name is put in `reply` by the suite, like every other name here -
; which is also how the empty-name case is reached, with a single zero byte.
t_net_connect:
        lda #<reply
        sta ult_buf
        lda #>reply
        sta ult_buf + 1
        lda #<8080
        sta ult_port
        lda #>8080
        sta ult_port + 1
        jsr ultimate_net_connect
        sta result
        lda ult_sock
        sta net_sock
        rts

; A null host pointer is a caller bug, refused before anything is sent.
t_net_connect_null:
        lda #$00
        sta ult_buf
        sta ult_buf + 1
        jsr ultimate_net_connect
        sta result
        lda ult_sock
        sta net_sock
        rts

t_net_read_null:
        lda #$00
        sta ult_buf
        sta ult_buf + 1
        lda #$40
        sta ult_socklen
        lda #$00
        sta ult_socklen + 1
        jsr ultimate_net_read
        sta result
        lda ult_socklen
        sta net_got
        lda ult_socklen + 1
        sta net_got + 1
        rts

; A buffer with no room for the firmware's own count and a byte of data can
; carry nothing, so it is refused here rather than asked for and truncated.
t_net_read_tiny:
        lda #<reply
        sta ult_buf
        lda #>reply
        sta ult_buf + 1
        lda #UCI_NET_READ_PREFIX
        sta ult_socklen
        lda #$00
        sta ult_socklen + 1
        jsr ultimate_net_read
        sta result
        rts

t_net_write_null:
        lda #$00
        sta ult_buf
        sta ult_buf + 1
        lda #$10
        sta ult_buflen
        lda #$00
        sta ult_buflen + 1
        jsr ultimate_net_write
        sta result
        rts

t_set_timeout:
        lda timeout_val
        jsr uci_set_timeout_a
        rts

t_get_timeout:
        jsr uci_get_timeout_a
        sta result
        rts
