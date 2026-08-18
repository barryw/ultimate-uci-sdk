; net.s - Layer 2: TCP and UDP sockets, on the network target.
;
; Nine commands of the fifteen. Built entirely out of uci_exec, like every
; service except turbo.s and reu.s; nothing here touches a hardware register.
;
; **Everything in this file was measured against firmware 3.15 on real
; hardware, not read out of the protocol document.** The document gives the
; argument shapes and stops there, and the parts it stops before are the parts
; a caller trips over. What the probes found, and why the API is shaped this
; way:
;
; **A read does not wait for the wire.** A READ_SOCKET issued straight after a
; connect answers "nothing yet" even when the peer sent its greeting on accept.
; Callers poll. This is not a bug to work around - it is the only behaviour
; that lets a C64 stay responsive while a socket is idle.
;
; **The firmware puts its own 16-bit count in front of the data**, so a reply
; is <count:16 LE> <bytes> and a count of $FFFF means nothing was available.
; ultimate_net_read strips it, which costs one pass over the data and is the
; price of a caller-facing buffer that starts at byte zero.
;
; **The device code is the whole state machine, and uci_exec hides it.** A
; read answers 0 with data, 1 when the peer has hung up, 2 when there is
; nothing pending - and 00/01/02 are all success in the CBM DOS numbering that
; uci_decode_status follows, so all three arrive as ULTIMATE_OK. Reading the
; code back is what turns the middle one into ULTIMATE_END. Nothing here parses
; the status text; the code alone separates the three.
;
; **A connect can take thirty seconds.** Measured: 48-75 ms to a host that is
; up, and 30.8 seconds to an address on the same subnet with nothing at it,
; before the firmware gave up and answered "11,ERROR ON CONNECTION". The SDK's
; timeout budget is a byte of 256-poll units - about 0.65 s at the default and
; about 1 s at its maximum - so **the budget cannot express a connect**. The
; open entry points therefore run on UCI_TIMEOUT_FOREVER and rely on the
; firmware's own limit, which always fired, and put the caller's budget back
; afterwards. Every other command here finished in 75 ms or less and runs on
; whatever the caller set.
;
; **Read lengths between 769 and 1023 are dangerous.** The firmware range-checks
; at 1024 and answers "82,PARAMETER(S) OUT OF RANGE" above it, but its own
; response queue is UCI_MAX_RESPONSE = $380 = 896 bytes, and a probe stepping
; through that gap took the machine off the network entirely and needed a power
; cycle. UCI_NET_READ_MAX is 512, which is verified with real data behind it,
; and this file will not ask for more. See docs/uci.md.
;
; **The four LISTEN commands are not here.** tools/gen_protocol.py marks them
; INFERRED: their command numbers are not in the published specification. The
; generic form reaches them, so issuing one stays a deliberate act rather than
; something the SDK appears to endorse.
;
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"
        .include "uci_seg.inc"
        .include "uci_zp.inc"

        .import uci_exec, uci_last_code
        .import uci_get_timeout_a, uci_set_timeout_a
        .import ult_req, ult_req_clear, ult_invalid, ult_have_buf
        .import ult_buf, ult_buflen
        .import ult_sock, ult_socklen, ult_iface, ult_port

        .export ultimate_net_ifcount
        .export ultimate_net_macaddr
        .export ultimate_net_ipconfig
        .export ultimate_net_connect
        .export ultimate_net_udp
        .export ultimate_net_close, _ultimate_net_close
        .export ultimate_net_read
        .export ultimate_net_write

; READ_SOCKET wants <handle> <len:16> as three consecutive bytes, and they go
; on the wire straight out of the variable block. Both layouts put them in that
; order - the BSS one by declaration and the placed one by its equates - and
; this is what says so if either ever changes.
.assert ult_socklen = ult_sock + 1, lderror, "ult_socklen must follow ult_sock"

        uci_code

; ---------------------------------------------------------------------------
; ultimate_net_ifcount  ->  A = ULTIMATE_* result, ult_iface = interfaces
;
; Two on an Ultimate 64 Elite, indexed from zero. Which of them is up is a
; different question: on the bench machine interface 0 has a MAC and an all-zero
; IP configuration, and interface 1 is the live Ethernet. Ask ipconfig.
;
; The count lands in ult_iface because that is where the other two entry points
; take it from, so discovering the range and walking it need no copying. It is
; zeroed first: a failed call reports no interfaces rather than whatever was
; there before.
; ---------------------------------------------------------------------------
ultimate_net_ifcount:
        lda #$00
        sta ult_iface

        jsr ult_req_clear
        jsr net_target
        lda #NET_CMD_GET_INTERFACE_COUNT
        sta ult_req + UCI_REQ_COMMAND

        lda #<ult_iface
        sta ult_req + UCI_REQ_DATA
        lda #>ult_iface
        sta ult_req + UCI_REQ_DATA + 1
        lda #$01
        sta ult_req + UCI_REQ_DATAMAX

        jsr net_exec
        ldx #$00
        rts

; ---------------------------------------------------------------------------
; ultimate_net_macaddr    ult_iface, ult_buf = UCI_NET_MACADDR_BYTES bytes
; ultimate_net_ipconfig   ult_iface, ult_buf = UCI_NET_IPCONFIG_BYTES bytes
;                      -> A = ULTIMATE_* result
;
; The ipconfig triple is address, netmask, gateway, four bytes each, in the
; order they are written down.
;
; An interface index the machine does not have is "82,PARAMETER(S) OUT OF
; RANGE" from the firmware, which arrives as ULTIMATE_ERR_DEVICE. It is not
; checked here: the count that would bound it costs a second command, and the
; firmware's own answer is both cheaper and correct on a machine with more
; interfaces than this one was tested against.
; ---------------------------------------------------------------------------
ultimate_net_macaddr:
        lda #NET_CMD_GET_NETADDR
        ldx #UCI_NET_MACADDR_BYTES
        bne net_getaddr                 ; always: the size is not zero

ultimate_net_ipconfig:
        lda #NET_CMD_GET_IPADDR
        ldx #UCI_NET_IPCONFIG_BYTES

; A = command, X = exactly how many bytes the reply must be.
net_getaddr:
        pha
        txa
        pha
        lda ult_buf
        ora ult_buf + 1
        bne @have
        pla                             ; the branch has to leave the stack as
        pla                             ; it found it
        jmp ult_invalid

@have:  jsr ult_req_clear
        jsr net_target
        pla
        sta ult_req + UCI_REQ_DATAMAX   ; the expected size is also the cap
        pla
        sta ult_req + UCI_REQ_COMMAND

        lda #<ult_iface
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_iface
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$01
        sta ult_req + UCI_REQ_ARGLEN

        lda ult_buf
        sta ult_req + UCI_REQ_DATA
        lda ult_buf + 1
        sta ult_req + UCI_REQ_DATA + 1

        jsr net_exec
        cmp #ULTIMATE_OK
        bne @out

        ; A short reply is a protocol error rather than a half-filled buffer:
        ; four bytes of an address read as six is a plausible-looking wrong
        ; answer, which is the same argument palette_get makes.
        lda ult_req + UCI_REQ_DATALEN + 1
        bne @short
        lda ult_req + UCI_REQ_DATALEN
        cmp ult_req + UCI_REQ_DATAMAX
        bne @short
        lda #ULTIMATE_OK
@out:   ldx #$00
        rts
@short: lda #ULTIMATE_ERR_PROTOCOL
        ldx #$00
        rts

; ---------------------------------------------------------------------------
; ultimate_net_connect   ult_port, ult_buf = host  ->  A = result
; ultimate_net_udp       the same, for a UDP socket
;
; On success ult_sock holds the handle every other socket call takes; on any
; failure it holds $FF, so a caller that forgets to check the result closes
; nothing rather than closing somebody else's socket.
;
; The host is a NUL-terminated name or dotted-quad, sent as its own bytes with
; no terminator - the request's payload span, so nothing is copied. The port is
; little-endian like every other number in the protocol; that was measured
; rather than assumed, by connecting successfully with it that way round.
;
; **This is the one entry point in the SDK that is not bounded by the SDK.**
; See the header: a connect to an address with nothing at it took 30.8 seconds
; to fail, and no value of the timeout byte reaches that. It runs on
; UCI_TIMEOUT_FOREVER and puts the caller's budget back afterwards. A caller
; that cannot afford to wait should not call this; the generic form is still
; there, with the caller's own budget and its own recovery.
; ---------------------------------------------------------------------------
ultimate_net_connect:
        lda #NET_CMD_OPEN_TCP
        bne net_open                    ; always

ultimate_net_udp:
        lda #NET_CMD_OPEN_UDP

net_open:
        pha
        jsr ult_req_clear
        pla
        sta ult_req + UCI_REQ_COMMAND
        jsr net_target

        lda #$FF
        sta ult_sock                    ; nothing is open until it is

        lda ult_buf
        ora ult_buf + 1
        beq @invalid

        lda #<ult_port
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_port
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$02
        sta ult_req + UCI_REQ_ARGLEN

        lda ult_buf
        sta uci_ptr
        sta ult_req + UCI_REQ_PAYLOAD
        lda ult_buf + 1
        sta uci_ptr + 1
        sta ult_req + UCI_REQ_PAYLOAD + 1

        ldy #$00                        ; how long the host name is
@len:   lda (uci_ptr),y
        beq @got
        iny
        bne @len
@got:   cpy #$00
        beq @invalid                    ; an empty host is not a host, and a
                                        ; name with no terminator in 256 bytes
                                        ; arrives here as one
        sty ult_req + UCI_REQ_PAYLOADLEN

        lda #<ult_sock                  ; the handle comes back as one byte
        sta ult_req + UCI_REQ_DATA
        lda #>ult_sock
        sta ult_req + UCI_REQ_DATA + 1
        lda #$01
        sta ult_req + UCI_REQ_DATAMAX

        jsr uci_get_timeout_a
        pha
        lda #UCI_TIMEOUT_FOREVER
        jsr uci_set_timeout_a
        jsr net_exec
        tax                             ; the result, across the restore
        pla
        jsr uci_set_timeout_a
        txa

        cmp #ULTIMATE_OK
        beq @check
        lda #$FF                        ; a failed open leaves no handle
        sta ult_sock
        txa                             ; the result, which the store clobbered
        ldx #$00
        rts

@check: lda ult_req + UCI_REQ_DATALEN
        cmp #$01
        bne @noreply
        lda ult_req + UCI_REQ_DATALEN + 1
        bne @noreply
        lda #ULTIMATE_OK
        ldx #$00
        rts

@noreply:
        lda #$FF
        sta ult_sock
        lda #ULTIMATE_ERR_PROTOCOL
        ldx #$00
        rts

@invalid:
        jmp ult_invalid

; ---------------------------------------------------------------------------
; ultimate_net_close   ult_sock  ->  A = ULTIMATE_* result
;
; **Do not call this after ultimate_net_read has answered ULTIMATE_END.** Once
; the peer has hung up the firmware has already let the handle go, and closing
; it answers "12,ERROR ON CLOSE" - which is a true statement about a socket
; that no longer exists rather than a failure to act on. Measured, not assumed.
; ---------------------------------------------------------------------------
_ultimate_net_close:
        sta ult_sock
ultimate_net_close:
        jsr ult_req_clear
        jsr net_target
        lda #NET_CMD_CLOSE_SOCKET
        sta ult_req + UCI_REQ_COMMAND

        lda #<ult_sock
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_sock
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$01
        sta ult_req + UCI_REQ_ARGLEN

        jsr net_exec
        ldx #$00
        rts

; ---------------------------------------------------------------------------
; ultimate_net_read   ult_sock, ult_buf, ult_socklen = buffer size
;                  -> A = result, ult_socklen = bytes stored
;
; Three answers, and a caller wants to tell them apart:
;
;   ULTIMATE_OK  with ult_socklen > 0   bytes arrived
;   ULTIMATE_OK  with ult_socklen = 0   nothing pending; ask again
;   ULTIMATE_END                        the peer hung up, and this is said once
;
; ULTIMATE_END is the same code ultimate_readdir uses at the end of a
; directory, and for the same reason: running out is not failing.
;
; **ult_socklen is the size of the buffer, not the number of bytes wanted**,
; and at most two fewer than that are stored. The firmware puts a 16-bit count
; in front of the data, so a reply for n bytes occupies n+2, and asking for
; what fits is the only way the buffer cannot overflow. The count is then
; shifted off the front, which is one pass over the data - about 7 ms for a
; full 512 bytes at 1 MHz, against the 4-21 ms the read itself costs.
;
; The request is capped at UCI_NET_READ_MAX whatever the buffer size, because
; larger reads have taken the machine off the network - see the file header.
; ---------------------------------------------------------------------------
ultimate_net_read:
        lda ult_buf
        ora ult_buf + 1
        beq @bad

        ; A buffer with no room for the count and a byte can carry nothing.
        lda ult_socklen + 1
        bne @wide
        lda ult_socklen
        cmp #UCI_NET_READ_PREFIX + 1
        bcs @wide
@bad:   jmp @invalid            ; trampoline: the real target is out of range

@wide:  ; want = buffer size - the count the firmware prefixes
        sec
        lda ult_socklen
        sbc #UCI_NET_READ_PREFIX
        sta ult_socklen
        lda ult_socklen + 1
        sbc #$00
        sta ult_socklen + 1

        ; ...and never more than has been proved safe
        lda ult_socklen + 1
        cmp #>UCI_NET_READ_MAX
        bcc @fits
        bne @cap
        lda ult_socklen
        cmp #<UCI_NET_READ_MAX
        bcc @fits
        beq @fits
@cap:   lda #<UCI_NET_READ_MAX
        sta ult_socklen
        lda #>UCI_NET_READ_MAX
        sta ult_socklen + 1

@fits:  jsr ult_req_clear
        jsr net_target
        lda #NET_CMD_READ_SOCKET
        sta ult_req + UCI_REQ_COMMAND

        lda #<ult_sock                  ; <handle> <len:16>, three bytes, sent
        sta ult_req + UCI_REQ_ARGS      ; out of the variables themselves
        lda #>ult_sock
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$03
        sta ult_req + UCI_REQ_ARGLEN

        lda ult_buf
        sta ult_req + UCI_REQ_DATA
        lda ult_buf + 1
        sta ult_req + UCI_REQ_DATA + 1

        clc                             ; room for the data and the count
        lda ult_socklen
        adc #UCI_NET_READ_PREFIX
        sta ult_req + UCI_REQ_DATAMAX
        lda ult_socklen + 1
        adc #$00
        sta ult_req + UCI_REQ_DATAMAX + 1

        jsr net_exec
        cmp #ULTIMATE_OK
        bne @failed

        ; Data, end of stream, or nothing yet - and only the device code knows,
        ; because all three are success to uci_decode_status.
        jsr uci_last_code
        cmp #UCI_NET_DEV_CLOSED
        beq @closed
        cmp #UCI_NET_DEV_NO_DATA
        beq @empty

        ; The count in front of the data is redundant with the transport's own
        ; reply length, and the reply length is the one that says how much
        ; really arrived - so that is what the payload is measured by.
        lda ult_req + UCI_REQ_DATALEN + 1
        bne @have
        lda ult_req + UCI_REQ_DATALEN
        cmp #UCI_NET_READ_PREFIX
        bcc @short

@have:  sec
        lda ult_req + UCI_REQ_DATALEN
        sbc #UCI_NET_READ_PREFIX
        sta ult_socklen
        lda ult_req + UCI_REQ_DATALEN + 1
        sbc #$00
        sta ult_socklen + 1
        jsr net_unprefix
        lda #ULTIMATE_OK
        ldx #$00
        rts

@empty: jsr net_nothing
        lda #ULTIMATE_OK
        ldx #$00
        rts

@closed:
        jsr net_nothing
        lda #ULTIMATE_END
        ldx #$00
        rts

@short: jsr net_nothing
        lda #ULTIMATE_ERR_PROTOCOL
        ldx #$00
        rts

@failed:
        pha
        jsr net_nothing
        pla
        ldx #$00
        rts

@invalid:
        jsr net_nothing
        jmp ult_invalid

; ---------------------------------------------------------------------------
; ultimate_net_write   ult_sock, ult_buf, ult_buflen
;                   -> A = result, ult_socklen = bytes the firmware accepted
;
; **A short write is not an error.** The count that comes back is how many
; bytes went, and a caller with more to send carries on from there. It has
; matched the length asked for in every measurement so far, which is exactly
; why it is worth reporting rather than assuming.
;
; The bytes go in the request's payload span, so nothing is copied. The whole
; command has to fit the interface's command queue, so the most that can go in
; one call is UCI_MAX_COMMAND_USABLE less the target, the command and the
; handle; past that uci_exec answers ULTIMATE_ERR_INVALID_ARGUMENT before
; anything reaches the wire, which is the check already there rather than a
; second one here.
; ---------------------------------------------------------------------------
ultimate_net_write:
        jsr net_nothing
        jsr ult_have_buf
        bcc @invalid

        jsr ult_req_clear
        jsr net_target
        lda #NET_CMD_WRITE_SOCKET
        sta ult_req + UCI_REQ_COMMAND

        lda #<ult_sock
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_sock
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

        ; The reply is the accepted count, and it lands straight in the
        ; variable that reports it.
        lda #<ult_socklen
        sta ult_req + UCI_REQ_DATA
        lda #>ult_socklen
        sta ult_req + UCI_REQ_DATA + 1
        lda #$02
        sta ult_req + UCI_REQ_DATAMAX

        jsr net_exec
        cmp #ULTIMATE_OK
        bne @failed

        lda ult_req + UCI_REQ_DATALEN + 1
        bne @noreply
        lda ult_req + UCI_REQ_DATALEN
        cmp #$02
        bne @noreply
        lda #ULTIMATE_OK
        ldx #$00
        rts

@noreply:
        jsr net_nothing
        lda #ULTIMATE_ERR_PROTOCOL
        ldx #$00
        rts

@failed:
        pha
        jsr net_nothing
        pla
        ldx #$00
        rts

@invalid:
        jmp ult_invalid

; ---------------------------------------------------------------------------
; Internals
; ---------------------------------------------------------------------------

net_target:
        lda #UCI_TARGET_NETWORK
        sta ult_req + UCI_REQ_TARGET
        rts

net_exec:
        lda #<ult_req
        ldx #>ult_req
        jmp uci_exec

; No bytes moved. Every path that does not store data goes through here, so
; "how many" is never left holding what the last call put there.
net_nothing:
        lda #$00
        sta ult_socklen
        sta ult_socklen + 1
        rts

; Shift ult_socklen bytes down over the count the firmware sent in front of
; them, so the caller's buffer starts at its own first byte.
;
; Two zero page pointers, and the second is uci_rq. That is safe and not a
; coincidence: uci_rq holds the request block only for the duration of one
; uci_exec, and this runs after that call has returned and before the next one
; sets it again. uci_ptr is borrowed on the same terms, which uci_zp.inc says
; the service layer may do.
net_unprefix:
        lda ult_buf
        sta uci_ptr                     ; where the data has to end up
        clc
        adc #UCI_NET_READ_PREFIX
        sta uci_rq                      ; and where it is now
        lda ult_buf + 1
        sta uci_ptr + 1
        adc #$00
        sta uci_rq + 1

        ldy #$00
        ldx ult_socklen + 1             ; whole pages first
        beq @tail
@page:  lda (uci_rq),y
        sta (uci_ptr),y
        iny
        bne @page
        inc uci_rq + 1
        inc uci_ptr + 1
        dex
        bne @page

@tail:  ldy #$00
@byte:  cpy ult_socklen
        beq @done
        lda (uci_rq),y
        sta (uci_ptr),y
        iny
        bne @byte
@done:  rts
