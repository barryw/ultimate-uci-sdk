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
        .import uci_req_clear, uci_decode, uci_status_fmt
        .import ultimate_palette_get, ultimate_palette_set
        .import ultimate_palette_set_color, ultimate_palette_reset
        .import ultimate_turbo_available, ultimate_turbo_get
        .import ultimate_turbo_set, ultimate_turbo_badlines
        .import ultimate_chdir, ultimate_getpath
        .import ultimate_opendir, ultimate_readdir
        .import ultimate_open, ultimate_close, ultimate_read
        .import ultimate_write, ultimate_seek, ultimate_delete
        .import ultimate_load, ultimate_bload, ultimate_save
        .import ultimate_reu_available
        .import ultimate_reu_stash, ultimate_reu_fetch
        .import ultimate_reu_load, ultimate_reu_save
        .import ult_buf, ult_buflen, ult_outlen, ult_attrib, ult_num
        .import ult_addr, ult_max, ult_end, ult_reu, ult_reulen

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
