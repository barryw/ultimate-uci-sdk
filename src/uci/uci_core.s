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
        .include "uci_zp.inc"

; ---------------------------------------------------------------------------

        .export uci_exec,      _uci_exec
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
        .export ult_scratch, ult_req

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

.ifdef UCI_VARS

uci_timeout     = UCI_VARS + 0  ; budget, in units of 256 status polls
uci_ready       = UCI_VARS + 1  ; uci_init has succeeded
uci_devcode     = UCI_VARS + 2  ; last raw device status code (word)
uci_trunc       = UCI_VARS + 4  ; the reply did not fit the caller's buffer
uci_cnt         = UCI_VARS + 5  ; 16-bit loop counter
uci_tmp         = UCI_VARS + 7  ; 16-bit scratch
uci_stat        = UCI_VARS + 9  ; captured status prefix, 4 bytes
uci_statlen     = UCI_VARS + 13
uci_dec_target  = UCI_VARS + 14 ; parameters for uci_decode, which takes more
uci_dec_ptr     = UCI_VARS + 15 ; than fits in registers
uci_dec_len     = UCI_VARS + 17

; --- service layer (src/uci/ultimate.s) ---
; One block for the whole SDK, so a cartridge places one thing, not two.
ult_up          = UCI_VARS + 18 ; ultimate_init has succeeded
ult_buf         = UCI_VARS + 19 ; caller buffer for identify / model
ult_buflen      = UCI_VARS + 21
ult_outlen      = UCI_VARS + 23 ; where to write the length, 0 for nowhere
ult_caps        = UCI_VARS + 25 ; caller capability block
ult_scratch     = UCI_VARS + 27 ; probe buffer, see ultimate.s for why 16
ult_req         = UCI_VARS + 43 ; the service layer's own request block

.assert (43 + UCI_REQ_SIZE) = UCI_VARS_SIZE, error, "UCI_VARS_SIZE no longer matches the layout"

.else

        .bss

uci_timeout:    .res 1
uci_ready:      .res 1
uci_devcode:    .res 2
uci_trunc:      .res 1
uci_cnt:        .res 2
uci_tmp:        .res 2

; The status prefix, always captured whatever the caller asked for. Four bytes
; is the widest numeric prefix any encoding uses ("NNN " for HTTP), and the SDK
; decides which encoding a status is in by looking at exactly these bytes - so
; decoding from a caller buffer that might be shorter would change the answer.
uci_stat:       .res 4
uci_statlen:    .res 1

uci_dec_target: .res 1
uci_dec_ptr:    .res 2
uci_dec_len:    .res 1

; --- service layer (src/uci/ultimate.s) ---
ult_up:         .res 1
ult_buf:        .res 2
ult_buflen:     .res 2
ult_outlen:     .res 2
ult_caps:       .res 2
ult_scratch:    .res 16
ult_req:        .res UCI_REQ_SIZE

.endif

; ---------------------------------------------------------------------------

        .code

; ---------------------------------------------------------------------------
; uci_ident  ->  A = the raw identification register
; ---------------------------------------------------------------------------
uci_ident:
_uci_ident_register:
        lda UCI_REG_IDENT
        ldx #$00
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
        lda #$01
        ldx #$00
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
        lda uci_timeout
        ldx #$00
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
        lda #UCI_CTRL_ABORT
        sta UCI_REG_CONTROL
        jsr uci_poll_idle
        bcs @timeout
        and #UCI_STAT_ERROR
        beq @done
        lda #UCI_CTRL_CLR_ERR
        sta UCI_REG_CONTROL
@done:  lda #ULTIMATE_OK
        ldx #$00
        rts
@timeout:
        lda #ULTIMATE_ERR_TIMEOUT
        ldx #$00
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
        cmp #$00                ; test A explicitly: uci_present returns with
        bne @probe              ; Z set from its trailing ldx, not from A
        lda #ULTIMATE_ERR_NO_DEVICE
        ldx #$00
        rts

@probe: jsr uci_abort
        cmp #ULTIMATE_OK
        beq @ok
        ldx #$00
        rts                     ; the abort already returned a timeout

@ok:    lda #UCI_CTRL_CLR_ERR
        sta UCI_REG_CONTROL
        lda #$01
        sta uci_ready
        lda #ULTIMATE_OK
        ldx #$00
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
uci_exec:
_uci_exec:
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
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        ldx #$00
        rts

@ready_check:
        lda uci_ready
        bne @wait_idle
        jsr uci_init
        cmp #ULTIMATE_OK
        beq @wait_idle
        ldx #$00
        rts

        ; --- wait for idle, then submit ---
@wait_idle:
        jsr uci_poll_idle
        bcc @idle
        lda #ULTIMATE_ERR_TIMEOUT
        ldx #$00
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
        lda (uci_rq),y
        sta uci_ptr
        iny
        lda (uci_rq),y
        sta uci_ptr + 1
        ldy #UCI_REQ_ARGLEN
        jsr uci_get_word
        lda uci_tmp
        sta uci_cnt
        lda uci_tmp + 1
        sta uci_cnt + 1
        jsr uci_write_span

        ldy #UCI_REQ_PAYLOAD
        lda (uci_rq),y
        sta uci_ptr
        iny
        lda (uci_rq),y
        sta uci_ptr + 1
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
        lda #ULTIMATE_ERR_PROTOCOL
        ldx #$00
        rts

@sent:  ; --- fire and forget ---
        ldy #UCI_REQ_TARGET
        lda (uci_rq),y
        and #UCI_TARGET_NO_REPLY
        beq @collect
        jsr uci_poll_idle
        bcc @ok_noreply
        lda #ULTIMATE_ERR_TIMEOUT
        ldx #$00
        rts
@ok_noreply:
        lda #ULTIMATE_OK
        ldx #$00
        rts

        ; --- collect the reply, one block at a time ---
@collect:
        jsr uci_poll_reply
        bcc @have_state
        jsr uci_abort
        lda #ULTIMATE_ERR_TIMEOUT
        ldx #$00
        rts

@have_state:
        and #UCI_STAT_STATE
        bne @block
        jmp @translate          ; back to idle with no data phase at all

@block: pha                     ; remember whether more blocks follow
        jsr uci_read_block
        lda #UCI_CTRL_DATA_ACC
        sta UCI_REG_CONTROL
        pla
        cmp #UCI_STATE_DATA_LAST
        beq @translate
        jmp @collect

@translate:
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
        rts
@out_ok:
        lda #ULTIMATE_OK
        ldx #$00
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
        ; uci_ptr = data buffer, advanced past whatever is already stored
        ldy #UCI_REQ_DATA
        lda (uci_rq),y
        sta uci_ptr
        iny
        lda (uci_rq),y
        sta uci_ptr + 1
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
        bcs @store_loop         ; datalen > datamax cannot happen, but be safe
        lda #$00
        sta uci_cnt
        sta uci_cnt + 1

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
@no_hi: ldy #UCI_REQ_DATALEN    ; datalen += 1
        lda (uci_rq),y
        clc
        adc #$01
        sta (uci_rq),y
        iny
        lda (uci_rq),y
        adc #$00
        sta (uci_rq),y
        lda uci_cnt
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
        ldx uci_statlen         ; keep the first four bytes for the decoder
        cpx #$04
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
        lda (uci_rq),y
        sta uci_ptr             ; free by now: the data phase has finished
        iny
        lda (uci_rq),y
        sta uci_ptr + 1
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
        lda #UCI_STATUS_FMT_DECIMAL2
        ldx #$00
        rts
@binary:
        lda #UCI_STATUS_FMT_BINARY
        ldx #$00
        rts
@dec3:  lda #UCI_STATUS_FMT_DECIMAL3
        ldx #$00
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
; The three encodings are mutually exclusive on sight:
;   three leading ASCII digits         -> "NNN TEXT"
;   two digits, third not a digit      -> "NN,TEXT"
;   a leading byte that is not a digit -> a single binary byte
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
        lda #ULTIMATE_OK        ; silence is success
        ldx #$00
        rts

@have:  ; is byte 0 a digit?
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

        ; Below 400 is success. This channel carries both firmware errors and
        ; the response code a remote server sent, and nothing distinguishes
        ; them, so a 404 from a web server is a device error with the code kept
        ; rather than an SDK misuse.
        lda uci_tmp + 1
        cmp #>400
        bcc @ok
        bne @d3_err
        lda uci_tmp
        cmp #<400
        bcc @ok
@d3_err:
        lda #ULTIMATE_ERR_DEVICE
        ldx #$00
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

; --- a single binary byte ---
@binary_form:
        lda uci_dec_target
        jsr uci_status_fmt
        cmp #UCI_STATUS_FMT_BINARY
        beq @binary_ok
        jmp @malformed
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
        lda #ULTIMATE_ERR_PROTOCOL
        ldx #$00
        rts

@ok:    lda #ULTIMATE_OK
        ldx #$00
        rts

; ---------------------------------------------------------------------------
; Digit weights. Three multiplies by a constant, done as lookups: smaller and
; faster than shift-and-add, and there are only ten possible digits.
; ---------------------------------------------------------------------------
        .rodata
uci_tens:
        .byte 0, 10, 20, 30, 40, 50, 60, 70, 80, 90
uci_hundreds_lo:
        .byte <0, <100, <200, <300, <400, <500, <600, <700, <800, <900
uci_hundreds_hi:
        .byte >0, >100, >200, >300, >400, >500, >600, >700, >800, >900
        .code

; ---------------------------------------------------------------------------
; Internal: carry set when A holds an ASCII digit.
;
; The bounds are numeric on purpose. An assembler charmap, or a compiler's idea
; of what character set the target uses, must not reach bytes that came off the
; wire - the status channel carries ASCII whatever the screen wants.
; ---------------------------------------------------------------------------
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
        lda #ULTIMATE_ERR_DEVICE
        ldx #$00
        rts
@ok:    lda #ULTIMATE_OK
        ldx #$00
        rts
@unsup: lda #ULTIMATE_ERR_NOT_SUPPORTED
        ldx #$00
        rts
@badarg:
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        ldx #$00
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
        lda #ULTIMATE_ERR_DEVICE
        ldx #$00
        rts
@ok:    lda #ULTIMATE_OK
        ldx #$00
        rts
@unsup: lda #ULTIMATE_ERR_NOT_SUPPORTED
        ldx #$00
        rts
@badarg:
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        ldx #$00
        rts
@io:    lda #ULTIMATE_ERR_IO
        ldx #$00
        rts
