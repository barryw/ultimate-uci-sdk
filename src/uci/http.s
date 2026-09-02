; http.s - Layer 2: fetching things over HTTP, on the HTTP target.
;
; Six entry points out of twenty-three commands. src/uci/httpbody.s has ten
; more, for the JSON and form bodies; the ones neither file wraps are listed at
; the end of this comment.
;
; **The status channel is why this file exists.** Measured on firmware 3.15,
; not read out of the protocol document:
;
;   an ordinary command   `000 OK`, or `400 BAD COMMAND` when it is refused
;   an exchange           `HTTP/1.0 200 OK` followed by the whole header block
;
; The second is not a status code at all - it is the response line the remote
; server sent, verbatim. Before uci_decode learned that shape, it read the 'H'
; as the binary encoding and every successful request came back as
; ULTIMATE_ERR_DEVICE. That is fixed in the core rather than here, because the
; generic form has the same problem and a fix in this file would not reach it;
; see uci_core.s and docs/uci.md, "Status encodings".
;
; What survives into this file is the consequence: **a result of ULTIMATE_OK
; means the exchange happened and the server answered below 400.** The number
; it answered with is in uci_last_device_code(), and the header block - the
; Content-Type, the Location, anything else worth having - is in the caller's
; status buffer, because the SDK reads only the digits out of it.
;
; **A reply is truncated to the buffer and there is no continuation.** A 2000
; byte page fetched into 700 bytes gives 700 bytes and no way to ask for the
; rest: nothing in the command set offers a range or a second block, and the
; transport reported no further blocks either. uci_exec answers
; ULTIMATE_ERR_TRUNCATED, which is the honest result and not a failure of the
; request.
;
; **An exchange is not bounded by the SDK's timeout budget.** Measured at 47 ms
; to 256 ms against a server on the same subnet, which is comfortable - but an
; exchange contains a DNS lookup and a TCP connect, and net.s measured a connect
; to a dead address at 30.8 seconds. The budget is a byte of 256-poll units and
; tops out near a second, so the exchange runs on UCI_TIMEOUT_FOREVER and puts
; the caller's budget back afterwards, exactly as ultimate_net_connect does and
; for exactly the same reason.
;
; **URLs are bytes, and cc65 will rewrite a literal.** The charmap turns source
; 'a'-'z' into $41-$5A, so a lowercase C string arrives as uppercase ASCII - and
; an HTTP path is case sensitive. Build the URL as bytes, or fold it back at
; runtime. docs/uci.md has the whole of that rule.
;
; What is not wrapped, and why:
;
;   HTTP_CMD_DO_EXCHANGE_OBJ       it parses the *response* as JSON, not the
;                                  request, and answers "400 NO VALID JSON" for
;                                  anything else. That is a decoder this file
;                                  would have to surface typed values from, and
;                                  it is a service of its own if it is ever
;                                  wanted.
;   HTTP_CMD_BODY_QUERY            reading typed values back out of a body the
;   HTTP_CMD_BODY_MOVE             program just built, for the same reason.
;   HTTP_CMD_BODY_REMOVE
;   HEADER_QUERY / HEADER_LIST     reading back headers that were just set.
;
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"
        .include "uci_seg.inc"
        .include "uci_zp.inc"

        .import uci_exec, uci_devcode
        .import uci_get_timeout_a, uci_set_timeout_a
        .import ult_req, ult_req_clear, ult_invalid, ult_have_buf
        .import ult_buf, ult_buflen
        .import ult_url, ult_http, ult_body, ult_httplen

        .export ultimate_http_open
        .export ultimate_http_header
        .export ultimate_http_exchange
        .export ultimate_http_close, _ultimate_http_close
        .export ultimate_http_free_all, _ultimate_http_free_all
        .export ultimate_http_get

; An exchange sends <header> <body> as two consecutive bytes, straight out of
; the variables. Both layouts put them in that order and this is what says so if
; either ever changes.
.assert ult_body = ult_http + 1, lderror, "ult_body must follow ult_http"

        uci_code

; ---------------------------------------------------------------------------
; ultimate_http_open   A = HTTP_VERB_*, ult_url = URL
;                   -> A = ULTIMATE_* result, ult_http = header handle
;
; The verb goes out of ult_http and the handle comes back into it, which is not
; a trick so much as the same byte meaning the same thing in both directions:
; the small HTTP number this call is about. A failed open leaves $FF there,
; which is not a handle, so a caller that forgets to check the result frees
; nothing rather than freeing somebody else's request.
; ---------------------------------------------------------------------------
ultimate_http_open:
        sta ult_http                    ; the verb, on its way out

        lda ult_url
        ora ult_url + 1
        beq @invalid

        jsr ult_req_clear
        jsr http_target
        lda #HTTP_CMD_HEADER_CREATE
        sta ult_req + UCI_REQ_COMMAND

        lda #<ult_http                  ; <verb>
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_http
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$01
        sta ult_req + UCI_REQ_ARGLEN

        jsr http_url_payload            ; <url>, and nothing copied
        beq @invalid                    ; an empty URL is not a URL

        lda #<ult_http                  ; ...and the handle comes back here
        sta ult_req + UCI_REQ_DATA
        lda #>ult_http
        sta ult_req + UCI_REQ_DATA + 1
        lda #$01
        sta ult_req + UCI_REQ_DATAMAX

        jsr http_exec
        cmp #ULTIMATE_OK
        bne @failed

        lda ult_req + UCI_REQ_DATALEN
        cmp #$01
        bne @noreply
        lda ult_req + UCI_REQ_DATALEN + 1
        bne @noreply
        ldx #$00
        lda #ULTIMATE_OK
        rts

@failed:
        pha
        lda #$FF
        sta ult_http
        ldx #$00
        pla
        rts

@noreply:
        lda #$FF
        sta ult_http
        ldx #$00
        lda #ULTIMATE_ERR_PROTOCOL
        rts

@invalid:
        lda #$FF
        sta ult_http
        jmp ult_invalid

; ---------------------------------------------------------------------------
; ultimate_http_header   ult_http, ult_url = "key: value"
;                     -> A = ULTIMATE_* result
;
; One line, colon and all, exactly as it goes on the wire. The firmware splits
; it; the SDK does not, because a caller that wants a colon in a value should
; get one.
; ---------------------------------------------------------------------------
ultimate_http_header:
        lda ult_url
        ora ult_url + 1
        beq @invalid

        jsr ult_req_clear
        jsr http_target
        lda #HTTP_CMD_HEADER_ADD
        sta ult_req + UCI_REQ_COMMAND
        jsr http_handle_arg
        jsr http_url_payload
        beq @invalid                    ; an empty header line says nothing

        jsr http_exec
        rts

@invalid:
        jmp ult_invalid

; ---------------------------------------------------------------------------
; ultimate_http_exchange   ult_http, ult_body, ult_buf, ult_buflen
;                       -> A = result, ult_httplen = reply bytes stored
;
; ult_body is HTTP_BODY_NONE for a request that sends nothing, or the handle of
; a body built through the generic form.
;
; The reply body lands in the caller's buffer. The response headers land in the
; caller's *status* buffer if it gave the request one - this fills in the
; request block's own status fields, so a caller wanting the headers should
; point ult_req's status at a buffer before calling. Most do not, and pass
; nothing, and the digits are still decoded because the core keeps its own copy
; of the prefix.
;
; ULTIMATE_ERR_TRUNCATED means the exchange worked and the buffer was too small;
; ult_httplen is what was kept, and the rest cannot be asked for again.
; ---------------------------------------------------------------------------
ultimate_http_exchange:
        lda #$00
        sta ult_httplen
        sta ult_httplen + 1

        jsr ult_have_buf
        bcc @invalid

        jsr ult_req_clear
        jsr http_target
        lda #HTTP_CMD_DO_EXCHANGE_RAW
        sta ult_req + UCI_REQ_COMMAND

        lda #<ult_http                  ; <header> <body>, adjacent on purpose
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_http
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$02
        sta ult_req + UCI_REQ_ARGLEN

        lda ult_buf
        sta ult_req + UCI_REQ_DATA
        lda ult_buf + 1
        sta ult_req + UCI_REQ_DATA + 1
        lda ult_buflen
        sta ult_req + UCI_REQ_DATAMAX
        lda ult_buflen + 1
        sta ult_req + UCI_REQ_DATAMAX + 1

        ; A request contains a name lookup and a connection, and neither fits
        ; the timeout byte. See the file header.
        jsr uci_get_timeout_a
        pha
        lda #UCI_TIMEOUT_FOREVER
        jsr uci_set_timeout_a
        jsr http_exec
        tax
        pla
        jsr uci_set_timeout_a
        txa

        ; Whatever the result, what did arrive is worth reporting: a truncated
        ; reply still filled the buffer, and a device error can still carry the
        ; server's error page.
        pha
        lda ult_req + UCI_REQ_DATALEN
        sta ult_httplen
        lda ult_req + UCI_REQ_DATALEN + 1
        sta ult_httplen + 1
        ldx #$00
        pla
        rts

@invalid:
        jmp ult_invalid

; ---------------------------------------------------------------------------
; ultimate_http_close   ult_http  ->  A = ULTIMATE_* result
;
; Frees one request. ultimate_http_free_all is the bigger hammer, and is worth
; calling on the way out of a program that has been careless.
; ---------------------------------------------------------------------------
_ultimate_http_close:
        sta ult_http
ultimate_http_close:
        jsr ult_req_clear
        jsr http_target
        lda #HTTP_CMD_HEADER_FREE
        sta ult_req + UCI_REQ_COMMAND
        jsr http_handle_arg
        jsr http_exec
        rts

; ---------------------------------------------------------------------------
; ultimate_http_free_all  ->  A = ULTIMATE_* result
;
; Every header and every body the firmware is holding for this machine, gone.
; The Ultimate has a finite number of slots and a crashed program returns none
; of them, so this is the equivalent of uci_abort for the HTTP target.
; ---------------------------------------------------------------------------
ultimate_http_free_all:
_ultimate_http_free_all:
        jsr ult_req_clear
        jsr http_target
        lda #HTTP_CMD_FREE_ALL
        sta ult_req + UCI_REQ_COMMAND
        jsr http_exec
        rts

; ---------------------------------------------------------------------------
; ultimate_http_get   ult_url, ult_buf, ult_buflen
;                  -> A = result, ult_httplen = reply bytes stored
;
; The whole of the common case in one call: create the request, run it, and
; give the slot back. **The slot is returned whether the exchange worked or
; not**, which is the reason to prefer this over the three calls it replaces -
; a program that fetches in a loop and forgets one free eventually runs the
; firmware out of headers, and nothing tells it that is what happened.
; ---------------------------------------------------------------------------
ultimate_http_get:
        lda #$00
        sta ult_httplen
        sta ult_httplen + 1

        lda #HTTP_VERB_GET
        jsr ultimate_http_open
        cmp #ULTIMATE_OK
        bne @out                        ; nothing was opened, nothing to free

        lda #HTTP_BODY_NONE
        sta ult_body
        jsr ultimate_http_exchange

        ; **The free is another command, and it answers "000 OK".** Left alone
        ; it overwrites the number the caller came for: a 200 read back as 0,
        ; and a 404 the same. So the exchange's result and its device code both
        ; ride the stack across the tidy-up and are put back afterwards.
        pha                             ; the result
        lda uci_devcode + 1
        pha
        lda uci_devcode
        pha
        jsr ultimate_http_close         ; whatever the exchange said
        pla
        sta uci_devcode
        pla
        sta uci_devcode + 1
        pla                             ; ...and the result it came with
@out:   ldx #$00
        ora #$00                ; N and Z from A, not the ldx
        rts

; ---------------------------------------------------------------------------
; Internals
; ---------------------------------------------------------------------------

http_target:
        lda #UCI_TARGET_HTTP
        sta ult_req + UCI_REQ_TARGET
        rts

http_exec:
        lda #<ult_req
        ldx #>ult_req
        jmp uci_exec

; The header handle as the command's single argument.
http_handle_arg:
        lda #<ult_http
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_http
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$01
        sta ult_req + UCI_REQ_ARGLEN
        rts

; ult_url as the request's payload, measured in place. Returns with Z set when
; the string is empty, which no command here has any use for.
;
; The payload span exists so a fixed header and a long body need not be copied
; into one buffer, and this is exactly that case: the verb or the handle is the
; argument, and the caller's string goes out untouched behind it.
http_url_payload:
        lda ult_url
        sta uci_ptr
        sta ult_req + UCI_REQ_PAYLOAD
        lda ult_url + 1
        sta uci_ptr + 1
        sta ult_req + UCI_REQ_PAYLOAD + 1

        ldy #$00
@len:   lda (uci_ptr),y
        beq @done
        iny
        bne @len
@done:  sty ult_req + UCI_REQ_PAYLOADLEN
        lda #$00
        sta ult_req + UCI_REQ_PAYLOADLEN + 1
        cpy #$00
        rts
