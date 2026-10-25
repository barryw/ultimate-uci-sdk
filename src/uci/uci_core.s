; uci_core.s - Layer 1: the UCI transport, in 6502.
;
; This is the canonical implementation of the Ultimate Command Interface
; protocol. Nothing else implements the handshake; every binding calls in here.
;
; The entry points use cc65's parameter convention - a pointer argument in A/X,
; low byte in A, a byte result back in A - so the same routine serves an
; assembly caller and a cc65 caller with no wrapper in between. Assembly callers
; need no C runtime: this file uses four bytes of zero page, its own BSS, and
; the 6502 stack. Nothing else.
;
; Register conventions, per routine:
;   in    A/X or A, as documented at each entry point
;   out   A = ULTIMATE_* result code (X = high byte where a word is returned)
;   uses  A, X, Y, flags, UCI_ZP..UCI_ZP+3
;
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"
        .include "uci_seg.inc"
        .include "uci_zp.inc"
        .include "uci_vars.inc"

; ---------------------------------------------------------------------------

        .export uci_exec,      _uci_exec
        .export uci_exec_first, _uci_exec_first
        .export uci_exec_next,  _uci_exec_next
        .export uci_more,      _uci_more_blocks
        .export uci_init,      _uci_init
        .export uci_abort,     _uci_abort
        .export uci_present,   _uci_signature_present
        .export uci_ident,     _uci_ident_register
        .export uci_set_timeout_a, _uci_set_timeout
        .export uci_get_timeout_a, _uci_get_timeout
        .export uci_last_code, _uci_last_device_code
        .export uci_status_fmt, _uci_status_format
        .export uci_decode
        .export uci_dec_target, uci_dec_ptr, uci_dec_len

        ; The service layer's storage lives in the same block; see below.
        .export ult_up, ult_buf, ult_buflen, ult_outlen, ult_caps
        .export ult_scratch, ult_req, ult_probe, ult_color
        .export ult_attrib, ult_dir, ult_num
        .export ult_fargs, ult_addr, ult_max, ult_end, ult_got
        .export ult_reu, ult_reulen
        .export ult_sock, ult_socklen, ult_iface, ult_port
        .export ult_url, ult_http, ult_body, ult_httplen
        .export ult_arg2, ult_stage, ult_stagelen, ult_val
        .export ult_audio_up
        .export uci_stat, uci_devcode

; ---------------------------------------------------------------------------
; Variables
;
; The core needs UCI_VARS_SIZE bytes of RAM, and where they live is the caller's
; decision, not this file's.
;
;   by default        they land in the BSS segment, which is what a cl65 link
;                     expects and what almost every program wants
;
;   UCI_VARS defined  they are laid out from that address instead, as plain
;                     equates - which is what a cartridge needs, where the code
;                     is in ROM and the RAM it may touch is the programmer's
;                     call, and what an assembler with no segment support needs
;                     regardless
;
;       ca65 -D UCI_VARS=$CF00 ...
;
; The same choice exists for the four zero page bytes, through UCI_ZP. Between
; them there is no address in this file that a cartridge author cannot move.
;
; A caller that wants its own request block does not need a knob at all:
; uci_exec takes the block by pointer, so it can live wherever you put it.
; ---------------------------------------------------------------------------

; Enough to hold "HTTP/1.1 NNN" and a little more; see uci_stat below.
UCI_STAT_KEEP = 16

; One field list owns both layouts. The logical offset includes the optional
; caller request block, which has separate BSS ownership in ultimate_asm.s.
uci_layout_offset .set 0
.ifndef UCI_VARS
        .bss
.endif

.macro uci_field name, size
    .ifdef UCI_VARS
        name = UCI_VARS + uci_layout_offset
    .else
name:   .res size
    .endif
    uci_layout_offset .set uci_layout_offset + size
.endmacro

.macro uci_padding size
    .ifndef UCI_VARS
        .res size
    .endif
    uci_layout_offset .set uci_layout_offset + size
.endmacro

uci_field uci_timeout,    1
uci_field uci_ready,      1
uci_field uci_devcode,    2
uci_field uci_trunc,      1
uci_field uci_cnt,        2
uci_field uci_tmp,        2
; Keep 16 bytes even when the caller's reply buffer is shorter. HTTP status
; lines need more than a numeric status prefix to decode correctly.
uci_field uci_stat,       UCI_STAT_KEEP
uci_field uci_statlen,    1
uci_field uci_dec_target, 1
uci_field uci_dec_ptr,    2
uci_field uci_dec_len,    1

; Shared SDK state and its private request block.
uci_field ult_up,         1
uci_field ult_buf,        2
uci_field ult_buflen,     2
uci_field ult_outlen,     2
uci_field ult_caps,       2
uci_field ult_scratch,    16
uci_field ult_req,        UCI_REQ_SIZE
uci_field ult_probe,      1

; Assembly callers link their own request block in default BSS mode. Placed
; builds reserve its address here so published blob offsets remain fixed.
.ifdef UCI_VARS
uci_req = UCI_VARS + uci_layout_offset
        .export uci_req
.endif
uci_layout_offset .set uci_layout_offset + UCI_REQ_SIZE

; Append fields after the caller block; old published offsets must not move.
uci_field ult_color,      4
uci_field uci_more,       1
uci_field ult_attrib,     1
uci_field ult_dir,        1
uci_field ult_num,        4
; SoftwareIEC argument: sec, verify, addr16, then an unused pair.
uci_field ult_fargs,      2
uci_field ult_addr,       2
uci_padding              2
uci_field ult_max,        2
uci_field ult_end,        2
uci_field ult_got,        2
uci_field ult_reu,        4
uci_field ult_reulen,     4
; Socket handle and length are consecutive bytes on the wire.
uci_field ult_sock,       1
uci_field ult_socklen,    2
uci_field ult_iface,      1
uci_field ult_port,       2
uci_field ult_url,        2
; HTTP verb and body handles are sent as one pair.
uci_field ult_http,       1
uci_field ult_body,       1
uci_field ult_httplen,    2
uci_field ult_arg2,       2
uci_field ult_stage,      ULT_STAGE_SIZE
uci_field ult_stagelen,   1
uci_field ult_val,        4
uci_field ult_audio_up,   1

.assert uci_layout_offset = UCI_VARS_SIZE, error, "UCI_VARS_SIZE no longer matches the layout"

; ---------------------------------------------------------------------------

        uci_code

; ---------------------------------------------------------------------------
; uci_ident  ->  A = the raw identification register
; ---------------------------------------------------------------------------
uci_ident:
_uci_ident_register:
        ldx #$00
        lda UCI_REG_IDENT
        rts

; ---------------------------------------------------------------------------
; uci_present  ->  A = 1 when the signature is on the bus, 0 otherwise
;
; $C9 when idle, $49 while an interrupt is pending: bit 7 is the inverted IRQ
; line, so it is masked off before comparing. Costs a load and a compare and
; never blocks - but it cannot tell a wedged Ultimate from a healthy one, which
; is what uci_init is for.
; ---------------------------------------------------------------------------
uci_present:
_uci_signature_present:
        lda UCI_REG_IDENT
        and #UCI_IDENT_MASK
        cmp #UCI_IDENT_VALUE
        bne @absent
        ldx #$00
        lda #$01
        rts
@absent:
        lda #$00
        tax
        rts

; ---------------------------------------------------------------------------
; uci_set_timeout_a   A = budget in units of 256 polls, 0 = wait forever
; uci_get_timeout_a  -> A
; ---------------------------------------------------------------------------
uci_set_timeout_a:
_uci_set_timeout:
        sta uci_timeout
        rts

uci_get_timeout_a:
_uci_get_timeout:
        ldx #$00
        lda uci_timeout
        rts

; ---------------------------------------------------------------------------
; uci_last_code  ->  A = low byte, X = high byte of the raw device status
; ---------------------------------------------------------------------------
uci_last_code:
_uci_last_device_code:
        lda uci_devcode
        ldx uci_devcode + 1
        rts

; ---------------------------------------------------------------------------
; Bounded waiting.
;
; uci_poll_idle   waits for STATE == idle
; uci_poll_reply  waits for STATE != busy (idle also ends the wait: a no-reply
;                 command goes busy and then straight back to idle)
;
; Both return with carry clear on success and the matching status byte in A, or
; carry set on timeout. The budget is uci_timeout * 256 polls; a budget of zero
; polls forever, which is a legitimate choice for a command whose duration
; cannot be bounded.
; ---------------------------------------------------------------------------
uci_poll_idle:
        ldx uci_timeout
@outer: ldy #$00
@inner: lda UCI_REG_STATUS
        and #UCI_STAT_STATE
        beq @hit
        dey
        bne @inner
        lda uci_timeout         ; zero means wait forever
        beq @outer
        dex
        bne @outer
        sec
        rts
@hit:   lda UCI_REG_STATUS
        clc
        rts

uci_poll_reply:
        ldx uci_timeout
@outer: ldy #$00
@inner: lda UCI_REG_STATUS
        and #UCI_STAT_STATE
        cmp #UCI_STATE_BUSY
        bne @hit
        dey
        bne @inner
        lda uci_timeout
        beq @outer
        dex
        bne @outer
        sec
        rts
@hit:   lda UCI_REG_STATUS
        clc
        rts

; ---------------------------------------------------------------------------
; uci_abort  ->  A = ULTIMATE_OK or ULTIMATE_ERR_TIMEOUT
;
; Abort does not touch the state machine directly. The Ultimate polls the flag
; and resets the protocol itself, so this waits for idle rather than assuming.
; ---------------------------------------------------------------------------
uci_abort:
_uci_abort:
        ; --- release whatever block the interface is holding, first ---
        ;
        ; **An abort is not serviced while a reply block is on the table.** The
        ; firmware is waiting for DATA_ACC, and until it gets one the state
        ; never leaves data-more, so the poll below times out and the interface
        ; stays exactly as stuck as it was. A program that walked half a
        ; directory and then gave up hits this, and so does one that died in
        ; the middle of any reply chain - which is the case abort exists for.
        ;
        ; Releasing without reading is what a drain wants: the block's queues
        ; are reset by DATA_ACC whether or not anything read them.
        ;
        ; Bounded like every other loop here, by the same budget: a directory
        ; of any size drains inside it, and a device that never leaves
        ; data-more cannot hold the CPU for ever.
        ldx uci_timeout
@drain: ldy #$00
@block: lda UCI_REG_STATUS
        and #UCI_STAT_STATE
        cmp #UCI_STATE_DATA_LAST
        bcc @clear                      ; idle or busy: nothing to release
        lda #UCI_CTRL_DATA_ACC
        sta UCI_REG_CONTROL
        dey
        bne @block
        lda uci_timeout                 ; zero means wait forever
        beq @drain
        dex
        bne @drain

@clear: lda #UCI_CTRL_ABORT
        sta UCI_REG_CONTROL

        ; **Wait for the firmware to service the abort, not just for idle.**
        ; The abort flag (UCI_STAT_ABORT_P) is set by the write above and
        ; cleared only by the Ultimate's software, which services it with a
        ; HANDSHAKE_RESET: state forced to idle *and the command pointer
        ; rewound*. On an interface that was already idle - every program's
        ; first init - the state test alone passes at once, the SDK pushes its
        ; first command, and the firmware's reset then destroys it: an empty
        ; block comes back and the caller sees ULTIMATE_ERR_PROTOCOL. Seen on
        ; an Elite running 3.15 at 10 MHz and above, where the push beats the
        ; firmware to it; tests/emulator/abort-latency.suite reproduces it at
        ; any speed with a slower simulated firmware.
        jsr uci_poll_aborted
        bcs @timeout
        and #UCI_STAT_ERROR
        beq @done
        lda #UCI_CTRL_CLR_ERR
        sta UCI_REG_CONTROL
@done:  ldx #$00
        lda #ULTIMATE_OK
        rts
@timeout:
        ldx #$00
        lda #ULTIMATE_ERR_TIMEOUT
        rts

; ---------------------------------------------------------------------------
; Internal: wait until the interface is idle and no abort is pending. Carry
; set on timeout, else A = the status register. The same loop as
; uci_poll_idle with a wider mask; see uci_abort for why both bits matter.
; ---------------------------------------------------------------------------
uci_poll_aborted:
        ldx uci_timeout
@outer: ldy #$00
@inner: lda UCI_REG_STATUS
        and #UCI_STAT_STATE | UCI_STAT_ABORT_P
        beq @hit
        dey
        bne @inner
        lda uci_timeout         ; zero means wait forever
        beq @outer
        dex
        bne @outer
        sec
        rts
@hit:   lda UCI_REG_STATUS
        clc
        rts

; ---------------------------------------------------------------------------
; uci_init  ->  A = ULTIMATE_OK, ULTIMATE_ERR_NO_DEVICE or ULTIMATE_ERR_TIMEOUT
;
; Recovers from whatever the previous program left behind. Abort is the only
; operation that fixes all three failure modes at once: when the Ultimate
; services it, it writes the reset handshake, which forces the protocol state
; back to idle *and* rewinds the command write pointer. That pointer matters -
; it only rewinds when a command is accepted, so a program that wrote command
; bytes and then crashed before pushing would otherwise leave them stuck at the
; front of our first command, and nothing in the status register exposes that.
;
; This mirrors what the Ultimate's own HyperSpeed kernal does on reset.
;
; It also installs the default timeout. Nothing else does, and the variables are
; not zeroed when UCI_VARS places them in RAM the caller owns - so without this
; the bounded-time guarantee would rest on whatever byte happened to be there.
; ---------------------------------------------------------------------------
uci_init:
_uci_init:
        lda #$00
        sta uci_ready
        lda #UCI_TIMEOUT_DEFAULT
        sta uci_timeout
        lda #$FF
        sta uci_devcode
        sta uci_devcode + 1

        jsr uci_present
        bne @probe              ; the ABI's promise: Z is set from the result
        ldx #$00
        lda #ULTIMATE_ERR_NO_DEVICE
        rts

@probe: jsr uci_abort
        cmp #ULTIMATE_OK
        beq @ok
        ldx #$00
        ora #$00                ; N and Z from A, not the ldx
        rts                     ; the abort already returned a timeout

@ok:    lda #UCI_CTRL_CLR_ERR
        sta UCI_REG_CONTROL
        lda #$01
        sta uci_ready
        ldx #$00
        lda #ULTIMATE_OK
        rts

; ---------------------------------------------------------------------------
; Internal: load a 16-bit request field into uci_tmp.
;   Y = field offset
; ---------------------------------------------------------------------------
uci_get_word:
        lda (uci_rq),y
        sta uci_tmp
        iny
        lda (uci_rq),y
        sta uci_tmp + 1
        rts

; ---------------------------------------------------------------------------
; Internal: load a request field into uci_ptr, the working pointer.
;   Y = field offset  ->  A = the high byte, so `ora uci_ptr` tests for null
; ---------------------------------------------------------------------------
uci_get_ptr:
        lda (uci_rq),y
        sta uci_ptr
        iny
        lda (uci_rq),y
        sta uci_ptr + 1
        rts

; ---------------------------------------------------------------------------
; Internal: is uci_tmp greater than UCI_MAX_COMMAND_USABLE?
; Returns carry set when it is.
; ---------------------------------------------------------------------------
uci_tmp_too_big:
        lda uci_tmp + 1
        cmp #>UCI_MAX_COMMAND_USABLE
        bcc @no
        bne @yes
        lda uci_tmp
        cmp #<UCI_MAX_COMMAND_USABLE
        beq @no                 ; equal is allowed
        bcs @yes
@no:    clc
        rts
@yes:   sec
        rts

; ---------------------------------------------------------------------------
; Internal: write uci_cnt bytes from (uci_ptr) into the command register.
; ---------------------------------------------------------------------------
uci_write_span:
        lda uci_cnt
        ora uci_cnt + 1
        beq @done
        ldy #$00
@loop:  lda (uci_ptr),y
        sta UCI_REG_CMDDATA
        iny
        bne @nohi
        inc uci_ptr + 1
@nohi:  lda uci_cnt
        bne @declo
        dec uci_cnt + 1
@declo: dec uci_cnt
        lda uci_cnt
        ora uci_cnt + 1
        bne @loop
@done:  rts

; ---------------------------------------------------------------------------
; uci_exec   A/X = pointer to a request block  ->  A = ULTIMATE_* result
; ---------------------------------------------------------------------------
; uci_exec runs the whole exchange: send, then drain every block of the reply
; into one buffer. That is what almost every command wants.
;
; uci_exec_first / uci_exec_next are the same exchange stopped at each block
; boundary, for the commands where the boundaries carry meaning. DOS_CMD_READ_DIR
; is the reason they exist: the firmware sends one directory entry per block, as
; <attrib> <name> with no terminator and no length, so stitching the blocks
; together destroys the only thing separating one entry from the next. A
; filename containing a space is genuinely indistinguishable from an entry
; boundary in the stitched stream - this is not a theoretical worry, it is why
; `readdir` could not be written against uci_exec.
uci_exec:
_uci_exec:
        jsr uci_exec_send
        cmp #ULTIMATE_OK
        bne @out
        lda uci_more
        beq @out_ok             ; fire-and-forget: no data phase, no status
@collect_all:
        jsr uci_collect_one
        cmp #ULTIMATE_OK
        bne @out
        lda uci_more
        bne @collect_all
        jmp uci_translate
@out_ok:
        lda #ULTIMATE_OK
@out:   ldx #$00
        ora #$00                ; N and Z from A, not the ldx
        rts

; ---------------------------------------------------------------------------
; uci_exec_first   A/X = pointer to a request block  ->  A = ULTIMATE_* result
; uci_exec_next                                      ->  A = ULTIMATE_* result
;
; One block per call. req.datalen is reset each time, so it is this block's
; length and nothing else; uci_more is 1 while another block follows. The call
; that returns with uci_more clear is the one that decodes the device status,
; so a caller loops until it clears and reads the result of that last call.
;
;       lda #<req
;       ldx #>req
;       jsr uci_exec_first
;   loop:
;       ...use req.data, req.datalen...
;       lda uci_more
;       beq done
;       jsr uci_exec_next
;       jmp loop
; ---------------------------------------------------------------------------
uci_exec_first:
_uci_exec_first:
        jsr uci_exec_send
        cmp #ULTIMATE_OK
        bne @out
        lda uci_more
        beq @out_ok
        jmp uci_block_fresh
@out_ok:
        lda #ULTIMATE_OK
@out:   ldx #$00
        ora #$00                ; N and Z from A, not the ldx
        rts

uci_exec_next:
_uci_exec_next:
        jmp uci_block_fresh

; uci_more_blocks  ->  A = 1 while another reply block follows
_uci_more_blocks:
        ldx #$00
        lda uci_more
        rts

; Internal: one block, into an empty buffer, decoding the status when it turns
; out to have been the last.
uci_block_fresh:
        lda #$00
        ldy #UCI_REQ_DATALEN
        sta (uci_rq),y
        iny
        sta (uci_rq),y
        jsr uci_collect_one
        cmp #ULTIMATE_OK
        bne @out
        lda uci_more
        bne @out_ok
        jmp uci_translate
@out_ok:
        lda #ULTIMATE_OK
@out:   ldx #$00
        ora #$00                ; N and Z from A, not the ldx
        rts

; ---------------------------------------------------------------------------
; Internal: validate the request, wait for idle, put the command on the wire.
;
; -> A = ULTIMATE_* result. On success uci_more is 1 when a data phase follows
;    and 0 when the command was fire-and-forget and there is nothing more to do.
; ---------------------------------------------------------------------------
uci_exec_send:
        sta uci_rq
        stx uci_rq + 1

        ; --- reset the reply fields and our own state ---
        lda #$00
        ldy #UCI_REQ_DATALEN
        sta (uci_rq),y
        iny
        sta (uci_rq),y
        ldy #UCI_REQ_STATUSLEN
        sta (uci_rq),y
        iny
        sta (uci_rq),y
        sta uci_statlen
        sta uci_trunc
        lda #$FF
        sta uci_devcode
        sta uci_devcode + 1

        ; --- validate before touching the hardware ---
        ldy #UCI_REQ_TARGET
        lda (uci_rq),y
        and #UCI_TARGET_MASK
        bne @chk_args
        jmp @invalid

@chk_args:
        ; a non-zero length with a null pointer is a caller bug, not an I/O error
        ldy #UCI_REQ_ARGLEN
        jsr uci_get_word
        lda uci_tmp
        ora uci_tmp + 1
        beq @chk_arglen
        ldy #UCI_REQ_ARGS
        lda (uci_rq),y
        iny
        ora (uci_rq),y
        bne @chk_arglen
        jmp @invalid

@chk_arglen:
        jsr uci_tmp_too_big
        bcc @save_arglen
        jmp @invalid
@save_arglen:
        lda uci_tmp
        sta uci_cnt             ; borrow uci_cnt to accumulate the total
        lda uci_tmp + 1
        sta uci_cnt + 1

        ldy #UCI_REQ_PAYLOADLEN
        jsr uci_get_word
        lda uci_tmp
        ora uci_tmp + 1
        beq @chk_paylen
        ldy #UCI_REQ_PAYLOAD
        lda (uci_rq),y
        iny
        ora (uci_rq),y
        bne @chk_paylen
        jmp @invalid

@chk_paylen:
        jsr uci_tmp_too_big
        bcs @invalid

        ; total = 2 + arglen + payloadlen, checked against the usable maximum.
        ; The command write pointer stops on the last byte of the buffer, so a
        ; 896th byte would overwrite the 895th and the Ultimate would be told
        ; the command was 895 bytes long. Refuse rather than send that.
        clc
        lda uci_cnt
        adc uci_tmp
        sta uci_tmp
        lda uci_cnt + 1
        adc uci_tmp + 1
        sta uci_tmp + 1
        clc
        lda uci_tmp
        adc #$02
        sta uci_tmp
        bcc @no_carry
        inc uci_tmp + 1
@no_carry:
        jsr uci_tmp_too_big
        bcc @ready_check

@invalid:
        ldx #$00
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        rts

@ready_check:
        lda uci_ready
        bne @wait_idle
        jsr uci_init
        cmp #ULTIMATE_OK
        beq @wait_idle
        ldx #$00
        ora #$00                ; N and Z from A, not the ldx
        rts

        ; --- wait for idle, then submit ---
@wait_idle:
        jsr uci_poll_idle
        bcc @idle
        ldx #$00
        lda #ULTIMATE_ERR_TIMEOUT
        rts
@idle:  and #UCI_STAT_ERROR
        beq @send
        lda #UCI_CTRL_CLR_ERR
        sta UCI_REG_CONTROL

@send:  ldy #UCI_REQ_TARGET
        lda (uci_rq),y
        sta UCI_REG_CMDDATA
        ldy #UCI_REQ_COMMAND
        lda (uci_rq),y
        sta UCI_REG_CMDDATA

        ldy #UCI_REQ_ARGS
        jsr uci_get_ptr
        ldy #UCI_REQ_ARGLEN
        jsr uci_get_word
        lda uci_tmp
        sta uci_cnt
        lda uci_tmp + 1
        sta uci_cnt + 1
        jsr uci_write_span

        ldy #UCI_REQ_PAYLOAD
        jsr uci_get_ptr
        ldy #UCI_REQ_PAYLOADLEN
        jsr uci_get_word
        lda uci_tmp
        sta uci_cnt
        lda uci_tmp + 1
        sta uci_cnt + 1
        jsr uci_write_span

        lda #UCI_CTRL_PUSH_CMD
        sta UCI_REG_CONTROL

        ; The state-error flag is set when a command is pushed while the
        ; interface was not idle. We checked, but an interrupt handler can race
        ; us, and silently losing a command is worse than saying so.
        lda UCI_REG_STATUS
        and #UCI_STAT_ERROR
        beq @sent
        lda #UCI_CTRL_CLR_ERR
        sta UCI_REG_CONTROL
        ldx #$00
        lda #ULTIMATE_ERR_PROTOCOL
        rts

@sent:  ; --- fire and forget ---
        lda #$01
        sta uci_more            ; a data phase follows unless told otherwise
        ldy #UCI_REQ_TARGET
        lda (uci_rq),y
        and #UCI_TARGET_NO_REPLY
        beq @ok_sent
        jsr uci_poll_idle
        bcc @ok_noreply
        ldx #$00
        lda #ULTIMATE_ERR_TIMEOUT
        rts
@ok_noreply:
        lda #$00
        sta uci_more            ; nothing to collect, and no status to decode
@ok_sent:
        ldx #$00
        lda #ULTIMATE_OK
        rts

; ---------------------------------------------------------------------------
; Internal: one block of the reply into the caller's buffer.
;
; -> A = ULTIMATE_* result, uci_more = 1 when another block follows.
;
; The block is released with DATA_ACC only after both queues have been read,
; because releasing it resets them.
; ---------------------------------------------------------------------------
uci_collect_one:
        lda #$00
        sta uci_more
        jsr uci_poll_reply
        bcc @have_state
        jsr uci_abort
        lda #ULTIMATE_ERR_TIMEOUT
        rts

@have_state:
        and #UCI_STAT_STATE
        bne @block
        lda #ULTIMATE_OK        ; back to idle with no data phase at all
        rts

@block: pha                     ; remember whether more blocks follow
        jsr uci_read_block
        lda #UCI_CTRL_DATA_ACC
        sta UCI_REG_CONTROL
        pla
        cmp #UCI_STATE_DATA_LAST
        beq @last
        lda #$01
        sta uci_more
@last:  lda #ULTIMATE_OK
        rts

; ---------------------------------------------------------------------------
; Internal: decode the captured status into an ULTIMATE_* result, folding in a
; truncation the data phase reported. The end of every exchange.
; ---------------------------------------------------------------------------
uci_translate:
        lda uci_statlen
        sta uci_dec_len
        lda #<uci_stat
        sta uci_dec_ptr
        lda #>uci_stat
        sta uci_dec_ptr + 1
        ldy #UCI_REQ_TARGET
        lda (uci_rq),y
        sta uci_dec_target
        jsr uci_decode

        cmp #ULTIMATE_OK
        bne @out
        lda uci_trunc
        beq @out_ok
        lda #ULTIMATE_ERR_TRUNCATED
@out:   ldx #$00
        ora #$00                ; N and Z from A, not the ldx
        rts
@out_ok:
        ldx #$00
        lda #ULTIMATE_OK
        rts

; ---------------------------------------------------------------------------
; Internal: drain one data block into the caller's buffers.
;
; Both queues are read before the block is released, because releasing it
; resets them.
;
; The byte counts are not belt and braces, they are required. Each queue pointer
; saturates on the last byte of its buffer instead of moving one past it, and
; the availability bit is computed as "pointer < length". A reply that exactly
; fills the 896-byte response queue therefore leaves DATA_AV set for ever, and
; re-reading $DF1E keeps returning that final byte. Looping until the bit clears
; - which is what the published protocol description implies - hangs the C64
; outright. Reading at most one queue's worth is both correct and terminating.
; ---------------------------------------------------------------------------
uci_read_block:
        ; How many bytes this block stored. It is counted here and added to the
        ; caller's datalen once, at @data_done, rather than being incremented
        ; through the request block on every byte: (uci_rq),y arithmetic on a
        ; 16-bit field costs about 30 cycles, which was a third of the whole
        ; per-byte cost of a read. Nothing reads datalen while the loop runs.
        lda #$00
        sta uci_tmp
        sta uci_tmp + 1

        ; uci_ptr = data buffer, advanced past whatever is already stored
        ldy #UCI_REQ_DATA
        jsr uci_get_ptr
        ora uci_ptr
        bne @have_buf
        jmp @discard_all        ; no buffer: read and drop, not truncation

@have_buf:
        ldy #UCI_REQ_DATALEN
        jsr uci_get_word
        clc
        lda uci_ptr
        adc uci_tmp
        sta uci_ptr
        lda uci_ptr + 1
        adc uci_tmp + 1
        sta uci_ptr + 1

        ; uci_cnt = datamax - datalen, the room that is left
        ldy #UCI_REQ_DATAMAX
        lda (uci_rq),y
        sec
        sbc uci_tmp
        sta uci_cnt
        iny
        lda (uci_rq),y
        sbc uci_tmp + 1
        sta uci_cnt + 1
        bcs @room_known         ; datalen > datamax cannot happen, but be safe
        lda #$00
        sta uci_cnt
        sta uci_cnt + 1

@room_known:
        lda #$00                ; uci_tmp is free again: it held datalen, and
        sta uci_tmp             ; that has been folded into uci_ptr and uci_cnt
        sta uci_tmp + 1

        ; --- fast path: room remains, so store ---
@store_loop:
        lda uci_cnt
        ora uci_cnt + 1
        beq @discard_all
        lda UCI_REG_STATUS
        bpl @data_done          ; bit 7 = DATA_AV
        lda UCI_REG_RESPDATA
        ldy #$00
        sta (uci_ptr),y
        inc uci_ptr
        bne @no_hi
        inc uci_ptr + 1
@no_hi: inc uci_tmp             ; one more byte stored
        bne @dec
        inc uci_tmp + 1
@dec:   lda uci_cnt
        bne @dec_lo
        dec uci_cnt + 1
@dec_lo:
        dec uci_cnt
        jmp @store_loop

        ; --- the caller's buffer is full: keep draining so the exchange can
        ;     finish cleanly, and report the truncation afterwards ---
@discard_all:
        lda #<UCI_MAX_RESPONSE
        sta uci_cnt
        lda #>UCI_MAX_RESPONSE
        sta uci_cnt + 1
@discard_loop:
        lda uci_cnt
        ora uci_cnt + 1
        beq @data_done
        lda UCI_REG_STATUS
        bpl @data_done
        lda UCI_REG_RESPDATA
        ldy #UCI_REQ_DATA       ; only a real buffer that filled up is truncation
        lda (uci_rq),y
        iny
        ora (uci_rq),y
        beq @no_trunc
        lda #$01
        sta uci_trunc
@no_trunc:
        lda uci_cnt
        bne @d_lo
        dec uci_cnt + 1
@d_lo:  dec uci_cnt
        jmp @discard_loop

@data_done:
        ; The block's stored bytes, added to the caller's count in one go. Both
        ; ways out of the loops above arrive here, and the discard loop leaves
        ; uci_tmp alone, so this runs once per block whichever path was taken.
        clc
        ldy #UCI_REQ_DATALEN
        lda (uci_rq),y
        adc uci_tmp
        sta (uci_rq),y
        iny
        lda (uci_rq),y
        adc uci_tmp + 1
        sta (uci_rq),y

        ; --- status queue ---
        lda #<UCI_MAX_STATUS
        sta uci_cnt
        lda #>UCI_MAX_STATUS
        sta uci_cnt + 1
@stat_loop:
        lda uci_cnt
        ora uci_cnt + 1
        beq @stat_done
        lda UCI_REG_STATUS
        and #UCI_STAT_STAT_AV
        beq @stat_done
        lda UCI_REG_STATDATA
        pha
        ldx uci_statlen         ; keep the prefix the decoder needs
        cpx #UCI_STAT_KEEP
        bcs @caller_copy
        sta uci_stat,x
        inc uci_statlen
@caller_copy:
        pla
        jsr uci_store_status
        lda uci_cnt
        bne @s_lo
        dec uci_cnt + 1
@s_lo:  dec uci_cnt
        jmp @stat_loop
@stat_done:
        rts

; ---------------------------------------------------------------------------
; Internal: append A to the caller's status buffer, if there is one and it has
; room. A status string that does not fit is not reported as truncation - the
; numeric code lives in the first bytes and has already been captured.
; ---------------------------------------------------------------------------
uci_store_status:
        pha
        ldy #UCI_REQ_STATUS
        jsr uci_get_ptr         ; free by now: the data phase has finished
        ora uci_ptr
        beq @drop

        ; room left?  statuslen < statusmax
        ldy #UCI_REQ_STATUSLEN
        lda (uci_rq),y
        sta uci_tmp
        iny
        lda (uci_rq),y
        sta uci_tmp + 1

        ; Subtract in the direction the answer is wanted: carry set means
        ; statuslen >= statusmax, which is the full case. Testing Z after the
        ; high byte of the opposite subtraction would only ask whether the high
        ; bytes match, and would drop every byte after the first whenever the
        ; low byte of statuslen passed the low byte of statusmax.
        lda uci_tmp
        ldy #UCI_REQ_STATUSMAX
        cmp (uci_rq),y
        lda uci_tmp + 1
        iny
        sbc (uci_rq),y
        bcs @drop

        clc
        lda uci_ptr
        adc uci_tmp
        sta uci_ptr
        lda uci_ptr + 1
        adc uci_tmp + 1
        sta uci_ptr + 1

        pla
        ldy #$00
        sta (uci_ptr),y

        ldy #UCI_REQ_STATUSLEN
        lda (uci_rq),y
        clc
        adc #$01
        sta (uci_rq),y
        iny
        lda (uci_rq),y
        adc #$00
        sta (uci_rq),y
        rts
@drop:  pla
        rts

; ---------------------------------------------------------------------------
; uci_status_fmt   A = target  ->  A = UCI_STATUS_FMT_*
;
; The encoding a target is *expected* to use. Documentation, not a decoding
; rule: at least one target does not keep to its own convention.
; ---------------------------------------------------------------------------
uci_status_fmt:
_uci_status_format:
        and #UCI_TARGET_MASK
        cmp #UCI_TARGET_SOFTIEC
        beq @binary
        cmp #UCI_TARGET_HTTP
        beq @dec3
        ldx #$00
        lda #UCI_STATUS_FMT_DECIMAL2
        rts
@binary:
        ldx #$00
        lda #UCI_STATUS_FMT_BINARY
        rts
@dec3:  ldx #$00
        lda #UCI_STATUS_FMT_DECIMAL3
        rts

; ---------------------------------------------------------------------------
; uci_decode  ->  A = ULTIMATE_* result
;
;   uci_dec_target  target id
;   uci_dec_ptr     status bytes
;   uci_dec_len     how many
;
; Decode by shape, not by target id. The published protocol presents the status
; encoding as a property of the target; firmware 3.15 does not honour that.
; SOFTIEC_CMD_IDENTIFY answers with the shared ASCII "00,OK" while every other
; command on that target answers in binary, so a decoder that trusts the target
; id reads the '0' of "00,OK" as binary $30 and fails the one command documented
; as unable to fail.
;
; The structured encodings are mutually exclusive on sight:
;   "HTTP/"                            -> response line and header block
;   three leading ASCII digits         -> "NNN TEXT"
;   two digits, third not a digit      -> "NN,TEXT"
;   one byte on SoftwareIEC            -> binary status
; Other nonnumeric target text is a device error without a numeric code.
;
; The binary codes in use are $00-$09 and $80, none of which is an ASCII digit,
; so no status can be read two ways. The target hint only decides whether a
; binary status is plausible at all.
; ---------------------------------------------------------------------------
uci_decode:
        ; The parameter block lives in BSS, but (abs),y is not a 6502 addressing
        ; mode - copy the pointer into the working zero page slot, which the
        ; data phase has finished with by the time anything decodes a status.
        lda uci_dec_ptr
        sta uci_ptr
        lda uci_dec_ptr + 1
        sta uci_ptr + 1

        lda #$FF
        sta uci_devcode
        sta uci_devcode + 1

        lda uci_dec_len
        bne @have
        ldx #$00
        lda #ULTIMATE_OK        ; silence is success
        rts

@have:  ; **"HTTP/1.0 200 OK" is a status too, and it is not a code.** An HTTP
        ; exchange answers with the response line itself - the whole header
        ; block, in fact - rather than with the NNN form the firmware uses for
        ; its own errors. It starts with a letter, so without this it reads as
        ; the binary form and a perfectly good 200 comes back as a device
        ; error. Measured on firmware 3.15; see docs/uci.md.
        jsr uci_http_line
        bcc @not_http
        jmp @http_code
@not_http:
        ldy #$00
        lda (uci_ptr),y
        jsr uci_is_digit
        bcs @two_digits
        jmp @binary_form

@bad:   jmp @malformed          ; trampoline: the real target is out of branch range

@two_digits:
        lda uci_dec_len
        cmp #$02
        bcc @bad                ; a lone digit matches no encoding

        ldy #$01
        lda (uci_ptr),y
        jsr uci_is_digit
        bcc @bad

        ; two digits so far; three means the HTTP form
        lda uci_dec_len
        cmp #$03
        bcc @dec2
        ldy #$02
        lda (uci_ptr),y
        jsr uci_is_digit
        bcc @dec2

; --- "NNN TEXT" ---
        ldy #$00
        lda (uci_ptr),y
        sec
        sbc #UCI_ASCII_ZERO
        tax
        lda uci_hundreds_lo,x
        sta uci_tmp
        lda uci_hundreds_hi,x
        sta uci_tmp + 1

        ldy #$01
        lda (uci_ptr),y
        sec
        sbc #UCI_ASCII_ZERO
        tax
        clc
        lda uci_tens,x
        adc uci_tmp
        sta uci_tmp
        bcc @d3_units
        inc uci_tmp + 1
@d3_units:
        ldy #$02
        lda (uci_ptr),y
        sec
        sbc #UCI_ASCII_ZERO
        clc
        adc uci_tmp
        sta uci_tmp
        bcc @d3_store
        inc uci_tmp + 1
@d3_store:
        lda uci_tmp
        sta uci_devcode
        lda uci_tmp + 1
        sta uci_devcode + 1

        ; Below 400 is success. This channel carries both the firmware's own
        ; errors and the response code a remote server sent - "400 BAD COMMAND"
        ; from the one and "404 NOT FOUND" from the other are the same shape -
        ; so a 404 from a web server is a device error with the code kept
        ; rather than an SDK misuse.
@d3_class:
        lda uci_tmp + 1
        cmp #>400
        bcc @d3_ok
        bne @d3_err
        lda uci_tmp
        cmp #<400
        bcc @d3_ok
@d3_err:
        ldx #$00
        lda #ULTIMATE_ERR_DEVICE
        rts

; Its own success return rather than the shared one: two encodings now land
; here and the shared @ok is no longer inside a relative branch of either.
@d3_ok: ldx #$00
        lda #ULTIMATE_OK
        rts

; --- "NN,TEXT" ---
@dec2:  ldy #$00
        lda (uci_ptr),y
        sec
        sbc #UCI_ASCII_ZERO
        tax
        lda uci_tens,x
        sta uci_tmp
        ldy #$01
        lda (uci_ptr),y
        sec
        sbc #UCI_ASCII_ZERO
        clc
        adc uci_tmp
        sta uci_devcode
        lda #$00
        sta uci_devcode + 1
        lda uci_devcode
        jmp uci_map_decimal2

; --- "HTTP/1.1 404 Not Found\r\nServer: ..." ---
;
; The code is the three digits after the first space, and everything past it is
; the server's own words plus the rest of the header block. Only the digits are
; read; the caller still has the whole thing in its status buffer, which is
; where a Content-Type or a Location has to come from.
@http_code:
        ldy #$05                ; past "HTTP/"
@sp:    cpy uci_dec_len
        bcs @http_bad
        lda (uci_ptr),y
        cmp #UCI_ASCII_SPACE
        beq @sp_found
        iny
        bne @sp
        beq @http_bad          ; a 256-byte version string is not one

; Three digits have to fit between here and the end.
@sp_found:
        iny
        tya
        clc
        adc #$02
        cmp uci_dec_len
        bcs @http_bad

        lda (uci_ptr),y         ; hundreds
        jsr uci_is_digit
        bcc @http_bad
        sec
        sbc #UCI_ASCII_ZERO
        tax
        lda uci_hundreds_lo,x
        sta uci_tmp
        lda uci_hundreds_hi,x
        sta uci_tmp + 1

        iny                     ; tens
        lda (uci_ptr),y
        jsr uci_is_digit
        bcc @http_bad
        sec
        sbc #UCI_ASCII_ZERO
        tax
        clc
        lda uci_tens,x
        adc uci_tmp
        sta uci_tmp
        bcc @http_units
        inc uci_tmp + 1

@http_units:
        iny
        lda (uci_ptr),y
        jsr uci_is_digit
        bcc @http_bad
        sec
        sbc #UCI_ASCII_ZERO
        clc
        adc uci_tmp
        sta uci_tmp
        bcc @http_store
        inc uci_tmp + 1

@http_store:
        lda uci_tmp
        sta uci_devcode
        lda uci_tmp + 1
        sta uci_devcode + 1
        jmp @d3_class           ; the same "below 400 is success" rule

@http_bad:
        jmp @malformed          ; trampoline: the real target is out of range

; --- a single binary byte ---
@binary_form:
        lda uci_dec_target
        jsr uci_status_fmt
        cmp #UCI_STATUS_FMT_BINARY
        beq @binary_ok

        ; Not a binary target, and it did not start with a digit. Two bytes or
        ; more of it is the firmware reporting a failure in words rather than
        ; in a code, which is a device error and not a transport violation.
        ;
        ; Ultimate DOS does this for every failure that comes back from the
        ; filesystem rather than from DOS itself: software/filemanager/dos.cc
        ; answers OPEN_FILE, WRITE_DATA, FILE_SEEK, DELETE_FILE, RENAME_FILE,
        ; COPY_FILE and CREATE_DIR with FileSystem::get_error_string(res), which
        ; is a bare "DISK IS FULL" or "FILE DOESN'T EXIST" with no "NN," in
        ; front of it. Only the canned DOS-level statuses carry a code.
        ;
        ; Seen on the wire, not deduced: a WRITE_DATA to a full USB stick on
        ; firmware 3.15 answers "DISK IS FULL", and reading that as a protocol
        ; error told the caller the SDK was broken when the disk was.
        ;
        ; The code is left as UCI_DEVICE_CODE_NONE because there is none; the
        ; text is in the caller's status buffer either way.
        lda uci_dec_len
        cmp #$02
        bcc @malformed          ; one byte is the binary shape, and this target
                                ; has no binary vocabulary to read it with
        ldx #$00
        lda #ULTIMATE_ERR_DEVICE
        rts

@binary_ok:
        ldy #$00
        lda (uci_ptr),y
        sta uci_devcode
        lda #$00
        sta uci_devcode + 1
        lda uci_devcode
        jmp uci_map_binary

@malformed:
        lda #$FF
        sta uci_devcode
        sta uci_devcode + 1
        ldx #$00
        lda #ULTIMATE_ERR_PROTOCOL
        rts

@ok:    ldx #$00
        lda #ULTIMATE_OK
        rts

; ---------------------------------------------------------------------------
; Digit weights. Three multiplies by a constant, done as lookups: smaller and
; faster than shift-and-add, and there are only ten possible digits.
; ---------------------------------------------------------------------------
        .rodata
uci_http_prefix:
        .byte $48, $54, $54, $50, $2F   ; "HTTP/"
uci_tens:
        .byte 0, 10, 20, 30, 40, 50, 60, 70, 80, 90
uci_hundreds_lo:
        .byte <0, <100, <200, <300, <400, <500, <600, <700, <800, <900
uci_hundreds_hi:
        .byte >0, >100, >200, >300, >400, >500, >600, >700, >800, >900
        uci_code

; ---------------------------------------------------------------------------
; Internal: carry set when A holds an ASCII digit.
;
; The bounds are numeric on purpose. An assembler charmap, or a compiler's idea
; of what character set the target uses, must not reach bytes that came off the
; wire - the status channel carries ASCII whatever the screen wants.
; ---------------------------------------------------------------------------
; "HTTP/1.1 NNN" is thirteen bytes, and the decoder only ever sees what the
; capture kept - so if that ever shrinks, this is what says so at assembly time
; rather than at the far end of a request that quietly reports a device error.
.assert UCI_STAT_KEEP >= 13, error, "uci_stat must hold HTTP/1.1 NNN"

; Carry set when the status begins "HTTP/". Five bytes is a cheap test and
; nothing else in any encoding can start that way: the other three begin with a
; digit or with a byte below $20.
uci_http_line:
        lda uci_dec_len
        cmp #$05
        bcc @no
        ldy #$04
@byte:  lda (uci_ptr),y
        cmp uci_http_prefix,y
        bne @no
        dey
        bpl @byte
        sec
        rts
@no:    clc
        rts

uci_is_digit:
        cmp #UCI_ASCII_ZERO
        bcc @no
        cmp #UCI_ASCII_NINE + 1
        bcs @no
        sec
        rts
@no:    clc
        rts

; ---------------------------------------------------------------------------
; Internal: map a decimal status code in A to an ULTIMATE_* result.
;
; 00 is success. 01 and 02 are advisory: the command did what was asked and has
; something to add (an empty directory, a truncated REU load, a socket the peer
; closed). Reporting them as failures would break working programs.
; ---------------------------------------------------------------------------
uci_map_decimal2:
        cmp #$03
        bcc @ok                 ; 00, 01, 02
        cmp #21
        beq @unsup
        cmp #98
        beq @unsup
        cmp #99
        beq @unsup
        cmp #81
        beq @badarg
        ldx #$00
        lda #ULTIMATE_ERR_DEVICE
        rts
@ok:    ldx #$00
        lda #ULTIMATE_OK
        rts
@unsup: ldx #$00
        lda #ULTIMATE_ERR_NOT_SUPPORTED
        rts
@badarg:
        ldx #$00
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        rts

; Internal: map a SoftwareIEC binary status byte in A.
uci_map_binary:
        cmp #SOFTIEC_ST_OK
        beq @ok
        cmp #SOFTIEC_ST_UNKNOWN_COMMAND
        beq @unsup
        cmp #SOFTIEC_ST_MODULE_NOT_LOADED
        beq @unsup
        cmp #SOFTIEC_ST_INVALID_PARAMS
        beq @badarg
        cmp #SOFTIEC_ST_INVALID_NAME
        beq @badarg
        cmp #SOFTIEC_ST_INVALID_PARTITION
        beq @badarg
        cmp #SOFTIEC_ST_SAVE_ERROR
        beq @io
        ldx #$00
        lda #ULTIMATE_ERR_DEVICE
        rts
@ok:    ldx #$00
        lda #ULTIMATE_OK
        rts
@unsup: ldx #$00
        lda #ULTIMATE_ERR_NOT_SUPPORTED
        rts
@badarg:
        ldx #$00
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        rts
@io:    ldx #$00
        lda #ULTIMATE_ERR_IO
        rts
