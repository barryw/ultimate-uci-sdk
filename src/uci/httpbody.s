; httpbody.s - Layer 2: request bodies for the HTTP target.
;
; Ten of the thirteen BODY_* commands. Separate from http.s because cc65 links
; whole object files, and a program that only fetches a URL should not carry a
; JSON builder it never calls.
;
; A body is built in the Ultimate, not in the C64: the program creates a slot,
; adds keys and values to it one command at a time, and then hands the slot's
; handle to ultimate_http_exchange. Nothing larger than one key and one value is
; ever in C64 memory at once, which is what makes a 38K machine able to post a
; JSON object of a size it could not hold.
;
;     ultimate_http_body(HTTP_BODY_JSON_OBJECT, &body);
;     ultimate_http_body_string(body, key, value);
;     ultimate_http_body_int(body, count, 3);
;     ultimate_http_open(HTTP_VERB_POST, url, &req);
;     ultimate_http_exchange(req, body, buf, sizeof buf, &got);
;     ultimate_http_body_free(body);
;     ultimate_http_close(req);
;
; **Four of these commands interleave lengths with strings more times than the
; request block can express.** BODY_ADD_STRING is
; <handle> <keylen> <key> <vallen> <value>, which is five runs of bytes against
; the block's two spans, so the key is copied into the shared staging buffer
; with the two lengths around it and only the value goes out uncopied. That is
; where ULT_HTTP_KEY_MAX comes from: a key longer than the staging buffer holds
; is ULTIMATE_ERR_INVALID_ARGUMENT and never reaches the wire. Values are not
; bounded by it - only by the command queue, which uci_exec already checks.
;
; **Adding an object or an array enters it.** BODY_ADD_OBJECT and BODY_ADD_ARRAY
; make the new container the one subsequent keys go into, and
; ultimate_http_body_up() steps back out to its parent.
;
; **A binary body takes no keys.** HTTP_BODY_BINARY accepts only
; ultimate_http_body_binary(), and the firmware answers "400 BAD FORMAT" for
; anything else; the JSON and form formats are the other way round. Neither is
; checked here, because the format is the caller's own choice one call earlier
; and the firmware's answer names the mistake.
;
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"
        .include "uci_seg.inc"
        .include "uci_zp.inc"
        .include "uci_vars.inc"

        .import uci_exec
        .import ult_req, ult_req_clear, ult_invalid
        .import ult_buf, ult_buflen, ult_url, ult_body
        .import ult_stage, ult_stagelen, ult_val

        .export ultimate_http_body
        .export ultimate_http_body_free,  _ultimate_http_body_free
        .export ultimate_http_body_clear, _ultimate_http_body_clear
        .export ultimate_http_body_up,    _ultimate_http_body_up
        .export ultimate_http_body_int
        .export ultimate_http_body_bool
        .export ultimate_http_body_string
        .export ultimate_http_body_object
        .export ultimate_http_body_array
        .export ultimate_http_body_binary

; The staging buffer holds <handle> <keylen> <key> and then either four bytes of
; integer or one length byte, so the longest key it can carry is six bytes short
; of the buffer.
ULT_HTTP_KEY_MAX = ULT_STAGE_SIZE - 6

; Offsets inside the staging buffer.
ULT_HB_HANDLE = 0
ULT_HB_KEYLEN = 1
ULT_HB_KEY    = 2

.assert ULT_HB_KEY + ULT_HTTP_KEY_MAX + 4 <= ULT_STAGE_SIZE, error, "a staged integer would run off the end of the buffer"

        uci_code

; ---------------------------------------------------------------------------
; ultimate_http_body   A = HTTP_BODY_* format
;                   -> A = ULTIMATE_* result, ult_body = the handle
;
; The firmware has sixteen body slots for the whole machine and a crashed
; program returns none of them, so free what you create - or call
; ultimate_http_free_all(), which takes back headers and bodies together.
;
; A failed create leaves HTTP_BODY_NONE in ult_body rather than a handle, so a
; caller that forgets to check the result frees nothing rather than freeing
; somebody else's body. That value is also what ultimate_http_exchange reads as
; "send no body", so an unchecked failure sends the request without one instead
; of with a wrong one.
; ---------------------------------------------------------------------------
ultimate_http_body:
        sta ult_stage                   ; <format>

        lda #HTTP_BODY_NONE
        sta ult_body                    ; nothing is open until it is

        lda ult_stage
        beq @invalid                    ; the firmware takes 1 to 4 only, and
        cmp #HTTP_BODY_URL_ENCODED + 1  ; refusing here keeps HTTP_BODY_NONE
        bcs @invalid                    ; from being read as a format

        jsr ult_req_clear
        jsr hb_target
        lda #HTTP_CMD_BODY_CREATE
        sta ult_req + UCI_REQ_COMMAND
        lda #<ult_stage
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_stage
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$01
        sta ult_req + UCI_REQ_ARGLEN

        lda #<ult_body                  ; the handle comes back as one byte
        sta ult_req + UCI_REQ_DATA
        lda #>ult_body
        sta ult_req + UCI_REQ_DATA + 1
        lda #$01
        sta ult_req + UCI_REQ_DATAMAX

        jsr hb_exec
        cmp #ULTIMATE_OK
        bne @failed

        lda ult_req + UCI_REQ_DATALEN + 1
        bne @noreply
        lda ult_req + UCI_REQ_DATALEN
        cmp #$01
        bne @noreply
        ldx #$00
        lda #ULTIMATE_OK
        rts

@noreply:
        lda #ULTIMATE_ERR_PROTOCOL
@failed:
        pha
        lda #HTTP_BODY_NONE
        sta ult_body
        ldx #$00
        pla
        rts

@invalid:
        jmp ult_invalid

; ---------------------------------------------------------------------------
; ultimate_http_body_free    ult_body  ->  A = ULTIMATE_* result
; ultimate_http_body_clear   empty it but keep the slot and its format
; ultimate_http_body_up      leave the object or array being filled in
; ---------------------------------------------------------------------------
_ultimate_http_body_free:
        sta ult_body
ultimate_http_body_free:
        lda #HTTP_CMD_BODY_FREE
        bne hb_handle_cmd               ; always

_ultimate_http_body_clear:
        sta ult_body
ultimate_http_body_clear:
        lda #HTTP_CMD_BODY_CLEAR
        bne hb_handle_cmd               ; always

_ultimate_http_body_up:
        sta ult_body
ultimate_http_body_up:
        lda #HTTP_CMD_BODY_UP

; A = command byte; the body handle is its only argument.
hb_handle_cmd:
        pha
        jsr ult_req_clear
        jsr hb_target
        pla
        sta ult_req + UCI_REQ_COMMAND
        lda #<ult_body
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_body
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$01
        sta ult_req + UCI_REQ_ARGLEN
        jmp hb_exec

; ---------------------------------------------------------------------------
; ultimate_http_body_int      ult_body, ult_url = key, ult_val = 32-bit value
; ultimate_http_body_bool     ult_body, ult_url = key, ult_val = 0 or non-zero
; ultimate_http_body_object   ult_body, ult_url = key
; ultimate_http_body_array    ult_body, ult_url = key
;                          -> A = ULTIMATE_* result
;
; The value of an integer is the four bytes of ult_val, little-endian and
; signed, and all four are always sent: the firmware sign-extends from whichever
; byte it received last, so sending three would make 200 negative.
;
; A boolean is one byte and anything non-zero is true.
;
; Inside an array the firmware ignores the key, because a list has positions
; rather than names. An empty key is passed through rather than refused for that
; reason; in an object it produces an entry whose name is the empty string.
; ---------------------------------------------------------------------------
ultimate_http_body_int:
        lda #HTTP_CMD_BODY_ADD_INT
        bne hb_keyed                    ; always

ultimate_http_body_bool:
        lda #HTTP_CMD_BODY_ADD_BOOL
        bne hb_keyed

ultimate_http_body_object:
        lda #HTTP_CMD_BODY_ADD_OBJECT
        bne hb_keyed

ultimate_http_body_array:
        lda #HTTP_CMD_BODY_ADD_ARRAY

; A = command byte. Stages <handle> <keylen> <key> and appends whatever the
; command needs after it.
hb_keyed:
        pha
        jsr hb_stage_key
        bcc @toolong
        pla
        pha
        cmp #HTTP_CMD_BODY_ADD_INT
        beq @int
        cmp #HTTP_CMD_BODY_ADD_BOOL
        beq @bool
        jmp @send                       ; an object or an array is key and no more

@int:   ldy #$00                        ; four bytes, little-endian, as sent
@copy:  lda ult_val,y
        jsr hb_append                   ; indexed with X, so Y survives it
        iny
        cpy #$04
        bne @copy
        jmp @send

@bool:  lda ult_val
        jsr hb_append

@send:  pla
        jsr hb_stage_cmd
        jmp hb_exec

@toolong:
        pla
        jmp ult_invalid

; ---------------------------------------------------------------------------
; ultimate_http_body_string   ult_body, ult_url = key, ult_buf = value
;                          -> A = ULTIMATE_* result
;
; The value is a NUL-terminated string of at most 255 bytes; its length goes on
; the wire in front of it as a single byte, which is the firmware's own shape
; and the reason for the limit.
; ---------------------------------------------------------------------------
ultimate_http_body_string:
        jsr hb_stage_key
        bcc @invalid

        lda ult_buf                     ; the value, measured where it is
        sta uci_ptr
        lda ult_buf + 1
        sta uci_ptr + 1
        ora ult_buf
        beq @invalid

        ldy #$00
@len:   lda (uci_ptr),y
        beq @got
        iny
        bne @len
        beq @invalid                    ; 256 bytes and no terminator
@got:   tya
        jsr hb_append                   ; <vallen>, ahead of the value itself

        lda #HTTP_CMD_BODY_ADD_STRING
        jsr hb_stage_cmd

        lda ult_buf                     ; <value>, and nothing copied
        sta ult_req + UCI_REQ_PAYLOAD
        lda ult_buf + 1
        sta ult_req + UCI_REQ_PAYLOAD + 1
        sty ult_req + UCI_REQ_PAYLOADLEN
        jmp hb_exec

@invalid:
        jmp ult_invalid

; ---------------------------------------------------------------------------
; ultimate_http_body_binary   ult_body, ult_buf = bytes, ult_buflen = how many
;                          -> A = ULTIMATE_* result
;
; Appends to a HTTP_BODY_BINARY body. There is no key: a binary body is one run
; of bytes, and successive calls add to the end of it. The bytes go out
; uncopied, so the only limit is the command queue, which uci_exec checks.
; ---------------------------------------------------------------------------
ultimate_http_body_binary:
        lda ult_buf
        ora ult_buf + 1
        beq @invalid
        lda ult_buflen
        ora ult_buflen + 1
        beq @invalid

        jsr ult_req_clear
        jsr hb_target
        lda #HTTP_CMD_BODY_ADD_BINARY
        sta ult_req + UCI_REQ_COMMAND
        lda #<ult_body
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_body
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$01
        sta ult_req + UCI_REQ_ARGLEN

        lda ult_buf
        sta ult_req + UCI_REQ_PAYLOAD
        lda ult_buf + 1
        sta ult_req + UCI_REQ_PAYLOAD + 1
        lda ult_buflen
        sta ult_req + UCI_REQ_PAYLOADLEN
        lda ult_buflen + 1
        sta ult_req + UCI_REQ_PAYLOADLEN + 1
        jmp hb_exec

@invalid:
        jmp ult_invalid

; ---------------------------------------------------------------------------
; Internals
; ---------------------------------------------------------------------------

hb_target:
        lda #UCI_TARGET_HTTP
        sta ult_req + UCI_REQ_TARGET
        rts

hb_exec:
        lda #<ult_req
        ldx #>ult_req
        jmp uci_exec

; Put <handle> <keylen> <key> in the staging buffer.
;
; Carry set when it fitted. A key longer than ULT_HTTP_KEY_MAX is refused rather
; than clipped, because a JSON object whose key has been shortened is accepted
; by the server and means something else.
hb_stage_key:
        lda ult_body
        sta ult_stage + ULT_HB_HANDLE

        lda ult_url
        sta uci_ptr
        lda ult_url + 1
        sta uci_ptr + 1
        ora ult_url
        beq @toolong                    ; no key at all is a caller bug

        ldy #$00
@len:   lda (uci_ptr),y
        beq @got
        iny
        cpy #ULT_HTTP_KEY_MAX + 1
        bcc @len
        bcs @toolong                    ; always
@got:   sty ult_stage + ULT_HB_KEYLEN

        ldy #$00
@copy:  cpy ult_stage + ULT_HB_KEYLEN
        beq @done
        lda (uci_ptr),y
        sta ult_stage + ULT_HB_KEY,y
        iny
        bne @copy

@done:  tya                             ; used = handle + keylen + the key
        clc
        adc #ULT_HB_KEY
        sta ult_stagelen
        sec
        rts

@toolong:
        clc
        rts

; Append A to the staging buffer. Indexed with X, because the two callers are
; walking a caller buffer with Y while they do it.
hb_append:
        ldx ult_stagelen
        sta ult_stage,x
        inc ult_stagelen
        rts

; A = command byte. Point the request at the staged bytes.
hb_stage_cmd:
        pha
        jsr ult_req_clear
        jsr hb_target
        pla
        sta ult_req + UCI_REQ_COMMAND
        lda #<ult_stage
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_stage
        sta ult_req + UCI_REQ_ARGS + 1
        lda ult_stagelen
        sta ult_req + UCI_REQ_ARGLEN
        rts
