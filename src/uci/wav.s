; wav.s - a WAV file into the REU, and a voice ready to play it.
;
; ultimate_audio_load_wav opens the file, walks the RIFF header, loads the data
; chunk straight into the REU with ultimate_reu_load, closes the file, and
; fills the voice's address, length, rate divider and format flags. The engine
; plays signed PCM at any rate the divider can express, so the only thing a
; WAV ever needs converting is the 8-bit sign: WAV stores 8-bit samples
; unsigned. Those get one more pass, in place inside the REU, WAV_SLICE bytes
; at a time through the staging area. 16-bit data is played as it is.
;
; audio.s is the register layer and knows nothing about files; this is the
; composition every demo used to write for itself.
;
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"
        .include "uci_seg.inc"
        .include "uci_zp.inc"

        .import ultimate_open, ultimate_close, ultimate_read, ultimate_seek
        .import ultimate_reu_load, ultimate_reu_fetch, ultimate_reu_stash
        .import ult_buf, ult_buflen, ult_outlen, ult_num
        .import ult_addr, ult_reu, ult_reulen
        .import ult_scratch, ult_stage, ult_arg2

        .export ultimate_audio_load_wav

; State: ult_scratch (16 bytes) and the tail of ult_stage (40 bytes, of which
; the first WAV_SLICE are the read buffer and the sign pass's slice).
WAV_POS    = ult_scratch + 0    ; 4  file offset of the chunk header in hand;
                                ;    then the REU address the sign pass started at
WAV_SIZE   = ult_scratch + 4    ; 4  that chunk's size
WAV_LEN    = ult_scratch + 8    ; 4  the division's dividend, then the data byte
                                ;    count, which the sign pass counts down
WAV_RATE   = ult_scratch + 12   ; 2  sample rate in Hz, then the divider
WAV_BITS   = ult_scratch + 14   ; 1  8 or 16
WAV_CHANS  = ult_scratch + 15   ; 1  1 or 2
WAV_GOT    = ult_stage + 32     ; 2  how many bytes the last read returned
WAV_REM    = ult_stage + 34     ; 3  the division's remainder; a read's expected count
WAV_FMT    = ult_stage + 37     ; 1  1 once the fmt chunk has been seen
WAV_SLICE  = 32                 ; bytes per sign-pass DMA

RATE_MIN   = 96                 ; below this the divider does not fit 16 bits

        uci_code

; ---------------------------------------------------------------------------
; ultimate_audio_load_wav   ult_buf = name, ult_reu = REU address,
;                           A/X = ultimate_audio_voice  ->  A = result
;
; On success reu_address, length, rate and flags describe the loaded sample and
; channel, volume, pan and the repeat points are as the caller left them. On
; failure the voice may be partly written and means nothing. The file is
; closed on every path after a successful open.
; ---------------------------------------------------------------------------
ultimate_audio_load_wav:
        sta ult_arg2
        stx ult_arg2 + 1
        ora ult_arg2 + 1
        beq @invalid

        lda #DOS_FA_READ
        jsr ultimate_open
        cmp #ULTIMATE_OK
        beq :+
        rts                     ; the DOS result; nothing is open
:
        jsr wav_parse
        bcs @fail
        jsr wav_fill
        jsr wav_load
        bcs @fail
        jmp ultimate_close      ; its result is the result

@fail:  pha
        jsr ultimate_close
        ldx #$00
        pla
        rts

@invalid:
        ldx #$00
        lda #ULTIMATE_ERR_INVALID_ARGUMENT
        rts

; ---------------------------------------------------------------------------
; The header. Leaves the file positioned at the first data byte and WAV_LEN,
; WAV_RATE (as a divider), WAV_BITS and WAV_CHANS filled. Carry set and A = the
; result on failure.
; ---------------------------------------------------------------------------
wav_parse:
        lda #$00
        sta WAV_FMT

        lda #8                  ; "RIFF" and the file size
        jsr wav_read_stage
        bcs @out
        lda #<riff_tag
        ldx #>riff_tag
        jsr wav_tag_is
        bne @protocol
        lda #4                  ; "WAVE"
        jsr wav_read_stage
        bcs @out
        lda #<wave_tag
        ldx #>wave_tag
        jsr wav_tag_is
        bne @protocol

        lda #12                 ; the first chunk header
        sta WAV_POS
        lda #$00
        sta WAV_POS + 1
        sta WAV_POS + 2
        sta WAV_POS + 3

@chunk: jsr wav_seek_pos
        bcs @out
        lda #8                  ; tag and size
        jsr wav_read_stage
        bcs @out
        ldx #$03
@size:  lda ult_stage + 4,x
        sta WAV_SIZE,x
        dex
        bpl @size

        lda #<fmt_tag
        ldx #>fmt_tag
        jsr wav_tag_is
        bne @notfmt
        jsr wav_fmt_chunk
        bcs @out
        jmp @advance
@notfmt:
        lda #<data_tag
        ldx #>data_tag
        jsr wav_tag_is
        bne @advance
        jmp wav_data_chunk      ; the end of the walk, carry says how it went
@advance:
        jsr wav_next
        bcs @out
        jmp @chunk

@protocol:
        lda #ULTIMATE_ERR_PROTOCOL
        sec
@out:   rts

; A/X = a four-byte tag. Z set when ult_stage starts with it.
wav_tag_is:
        sta uci_ptr
        stx uci_ptr + 1
        ldy #$03
@cmp:   lda (uci_ptr),y
        cmp ult_stage,y
        bne @no
        dey
        bpl @cmp
        lda #$00
@no:    rts

; A = how many bytes to read into ult_stage. Fewer is a truncated file, which
; is a broken header rather than an I/O failure. Carry set on failure.
wav_read_stage:
        sta ult_buflen
        sta WAV_REM
        lda #$00
        sta ult_buflen + 1
        lda #<ult_stage
        sta ult_buf
        lda #>ult_stage
        sta ult_buf + 1
        lda #<WAV_GOT
        sta ult_outlen
        lda #>WAV_GOT
        sta ult_outlen + 1
        jsr ultimate_read
        cmp #ULTIMATE_OK
        bne @err
        lda WAV_GOT + 1
        bne @short
        lda WAV_GOT
        cmp WAV_REM
        bne @short
        clc
        rts
@short: lda #ULTIMATE_ERR_PROTOCOL
@err:   sec
        rts

; Seek to WAV_POS. Carry set on failure.
wav_seek_pos:
        ldx #$03
@copy:  lda WAV_POS,x
        sta ult_num,x
        dex
        bpl @copy
        jsr ultimate_seek
        ; falls into wav_check

; A = a result. Carry set when it is not ULTIMATE_OK; A is kept either way.
wav_check:
        cmp #ULTIMATE_OK
        beq @ok
        sec
        rts
@ok:    clc
        rts

; WAV_POS = WAV_POS + 8 + WAV_SIZE, rounded up to even, as RIFF pads an odd
; chunk. A sum that wraps past 32 bits is a corrupt header.
wav_next:
        lda WAV_SIZE
        and #$01
        clc
        adc #8
        adc WAV_SIZE
        sta WAV_REM
        lda WAV_SIZE + 1
        adc #$00
        sta WAV_REM + 1
        lda WAV_SIZE + 2
        adc #$00
        sta WAV_REM + 2
        lda WAV_SIZE + 3
        adc #$00
        bcs @wrap
        pha
        clc
        lda WAV_POS
        adc WAV_REM
        sta WAV_POS
        lda WAV_POS + 1
        adc WAV_REM + 1
        sta WAV_POS + 1
        lda WAV_POS + 2
        adc WAV_REM + 2
        sta WAV_POS + 2
        pla
        adc WAV_POS + 3
        sta WAV_POS + 3
        bcs @wrap
        clc
        rts
@wrap:  lda #ULTIMATE_ERR_PROTOCOL
        sec
        rts

; The fmt chunk: PCM, 1 or 2 channels, 8 or 16 bits, a rate that fits sixteen
; bits and is at least RATE_MIN. The file is positioned just past the chunk
; header, so the body is the next read.
wav_fmt_chunk:
        lda WAV_SIZE + 1
        ora WAV_SIZE + 2
        ora WAV_SIZE + 3
        bne @big
        lda WAV_SIZE
        cmp #16
        bcc @protocol
@big:   lda #16
        jsr wav_read_stage
        bcs @out

        lda ult_stage + 0       ; format 1 = PCM
        cmp #$01
        bne @unsupported
        lda ult_stage + 1
        bne @unsupported

        lda ult_stage + 3       ; channels 1 or 2
        bne @unsupported
        lda ult_stage + 2
        beq @unsupported
        cmp #$03
        bcs @unsupported
        sta WAV_CHANS

        lda ult_stage + 6       ; rate: 16 bits, at least RATE_MIN
        ora ult_stage + 7
        bne @unsupported
        lda ult_stage + 5
        bne @rate_ok
        lda ult_stage + 4
        cmp #RATE_MIN
        bcc @unsupported
@rate_ok:
        lda ult_stage + 4
        sta WAV_RATE
        lda ult_stage + 5
        sta WAV_RATE + 1

        lda ult_stage + 15      ; bits 8 or 16
        bne @unsupported
        lda ult_stage + 14
        cmp #8
        beq @bits_ok
        cmp #16
        bne @unsupported
@bits_ok:
        sta WAV_BITS
        jsr wav_divider
        lda #$01
        sta WAV_FMT
        clc
        rts

@protocol:
        lda #ULTIMATE_ERR_PROTOCOL
        sec
        rts
@unsupported:
        lda #ULTIMATE_ERR_NOT_SUPPORTED
        sec
@out:   rts

; WAV_RATE = UA_RATE_CLOCK / WAV_RATE, truncated. A 24-bit dividend over a
; 16-bit divisor by restoring division; the quotient fits sixteen bits because
; the rate is at least RATE_MIN. The dividend sits in WAV_LEN, free until the
; data chunk; the remainder in WAV_REM.
wav_divider:
        lda #<UA_RATE_CLOCK
        sta WAV_LEN
        lda #>UA_RATE_CLOCK
        sta WAV_LEN + 1
        lda #^UA_RATE_CLOCK
        sta WAV_LEN + 2
        lda #$00
        sta WAV_REM
        sta WAV_REM + 1
        sta WAV_REM + 2
        ldx #24
@bit:   asl WAV_LEN
        rol WAV_LEN + 1
        rol WAV_LEN + 2
        rol WAV_REM
        rol WAV_REM + 1
        rol WAV_REM + 2
        lda WAV_REM + 2
        bne @sub
        lda WAV_REM + 1
        cmp WAV_RATE + 1
        bcc @next
        bne @sub
        lda WAV_REM
        cmp WAV_RATE
        bcc @next
@sub:   lda WAV_REM
        sec
        sbc WAV_RATE
        sta WAV_REM
        lda WAV_REM + 1
        sbc WAV_RATE + 1
        sta WAV_REM + 1
        lda WAV_REM + 2
        sbc #$00
        sta WAV_REM + 2
        inc WAV_LEN             ; the quotient bit; asl left bit 0 clear
@next:  dex
        bne @bit
        lda WAV_LEN
        sta WAV_RATE
        lda WAV_LEN + 1
        sta WAV_RATE + 1
        rts

; The data chunk: needs a fmt before it; its size, rounded down to even for
; 16-bit or stereo data, is the length; and the engine addresses 16 MB.
; Carry set with A = the result on failure, clear when the walk is done.
wav_data_chunk:
        lda WAV_FMT
        beq @protocol
        ldx #$03
@copy:  lda WAV_SIZE,x
        sta WAV_LEN,x
        dex
        bpl @copy
        lda WAV_LEN + 3
        bne @unsupported
        lda WAV_BITS
        cmp #16
        beq @even
        lda WAV_CHANS
        cmp #2
        bne @sized
@even:  lda WAV_LEN
        and #$FE
        sta WAV_LEN
@sized: lda WAV_LEN
        ora WAV_LEN + 1
        ora WAV_LEN + 2
        beq @protocol
        clc
        rts
@protocol:
        lda #ULTIMATE_ERR_PROTOCOL
        sec
        rts
@unsupported:
        lda #ULTIMATE_ERR_NOT_SUPPORTED
        sec
        rts

; ---------------------------------------------------------------------------
; The voice: reu_address from ult_reu, length, rate, and the format flags.
; ---------------------------------------------------------------------------
wav_fill:
        lda ult_arg2
        sta uci_ptr
        lda ult_arg2 + 1
        sta uci_ptr + 1
        ldx #$00
@dword: txa
        clc
        adc #UA_VOICE_REU
        tay
        lda ult_reu,x
        sta (uci_ptr),y
        txa
        clc
        adc #UA_VOICE_LENGTH
        tay
        lda WAV_LEN,x
        sta (uci_ptr),y
        inx
        cpx #$04
        bne @dword
        ldy #UA_VOICE_RATE
        lda WAV_RATE
        sta (uci_ptr),y
        iny
        lda WAV_RATE + 1
        sta (uci_ptr),y
        lda #$00
        ldx WAV_BITS
        cpx #16
        bne :+
        ora #UA_CTRL_16BIT
:       ldx WAV_CHANS
        cpx #2
        bne :+
        ora #UA_CTRL_INTERLEAVE
:       ldy #UA_VOICE_FLAGS
        sta (uci_ptr),y
        rts

; ---------------------------------------------------------------------------
; The data chunk into the REU, then the sign pass for 8-bit data. The file is
; positioned at the first data byte, which is where reu_load reads from.
; Carry set with A = the result on failure.
; ---------------------------------------------------------------------------
wav_load:
        ldx #$03
@copy:  lda WAV_LEN,x
        sta ult_reulen,x
        dex
        bpl @copy
        jsr ultimate_reu_load
        jsr wav_check
        bcs @out
        lda WAV_BITS
        cmp #8
        beq wav_sign_pass
        clc
@out:   rts

; 8-bit WAV samples are unsigned and the engine plays signed: flip bit 7 of
; every byte in place, WAV_SLICE bytes at a time, through ult_stage. Leaves
; ult_reu where it started.
wav_sign_pass:
        ldx #$03
@save:  lda ult_reu,x
        sta WAV_POS,x
        dex
        bpl @save
        lda #<ult_stage
        sta ult_addr
        lda #>ult_stage
        sta ult_addr + 1
        lda #$00
        sta ult_reulen + 1
        sta ult_reulen + 2
        sta ult_reulen + 3

@slice: lda WAV_LEN + 1
        ora WAV_LEN + 2
        bne @full
        lda WAV_LEN
        beq @done
        cmp #WAV_SLICE
        bcc @part
@full:  lda #WAV_SLICE
@part:  sta ult_reulen
        jsr ultimate_reu_fetch
        jsr wav_check
        bcs @out
        ldx ult_reulen
@flip:  lda ult_stage - 1,x
        eor #$80
        sta ult_stage - 1,x
        dex
        bne @flip
        jsr ultimate_reu_stash
        jsr wav_check
        bcs @out

        lda ult_reu             ; next slice
        clc
        adc ult_reulen
        sta ult_reu
        bcc :+
        inc ult_reu + 1
        bne :+
        inc ult_reu + 2
:       lda WAV_LEN             ; and that much less to do
        sec
        sbc ult_reulen
        sta WAV_LEN
        bcs @slice
        dec WAV_LEN + 1
        lda WAV_LEN + 1
        cmp #$FF
        bne @slice
        dec WAV_LEN + 2
        jmp @slice

@done:  ldx #$03
@rest:  lda WAV_POS,x
        sta ult_reu,x
        dex
        bpl @rest
        clc
@out:   rts

        .rodata
riff_tag: .byte $52, $49, $46, $46      ; "RIFF"
wave_tag: .byte $57, $41, $56, $45      ; "WAVE"
fmt_tag:  .byte $66, $6D, $74, $20      ; "fmt "
data_tag: .byte $64, $61, $74, $61      ; "data"

        uci_code
