; control.s - Layer 2: the machine itself, on the control target.
;
; Reset, freeze, the emulated drives, and the GEOS RAM disk layout. Its own
; module for the reason palette.s is: cc65 links whole object files, and a
; program that never reboots the machine should not carry the code that would.
;
; **Two of these do not come back.** ultimate_reboot resets the C64, so the
; program that called it stops existing part way through the call; it is sent
; with UCI_TARGET_NO_REPLY so that the machine coming up finds the interface
; idle rather than holding a reply nobody will ever read. ultimate_freeze stops
; the C64 until whoever is at the keyboard leaves the Ultimate's menu, and then
; carries on from the instruction after it - which can be a long time later, and
; is the one place in this SDK where a timeout would be measuring the user.
;
; **The drive power commands answer in words.** "on " or "off", three ASCII
; bytes, not a flag - control_target.cc builds them with sprintf. They are
; compared numerically here, never against a string literal, because a compiler
; charmap must not reach a byte that came off the wire.
;
; What is deliberately not wrapped, and why:
;
;   CTRL_CMD_EASYFLASH        erases a flash sector. A wrapper would make it
;                             look like an ordinary call; it is not one.
;   CTRL_CMD_DECODE_TRACK     GCR track decoding into the REU, for a disk
;   CTRL_CMD_ENCODE_TRACK     copier. A service of its own if it is ever wanted,
;                             and INFERRED in the encode direction.
;   CTRL_CMD_LOAD_REU         the control target's REU pair never returns on
;   CTRL_CMD_SAVE_REU         firmware 3.14d and wedges the interface. The DOS
;                             pair does the same job and is what reu.s uses.
;                             See GideonZ/1541ultimate#740.
;   CTRL_CMD_U64_SAVEMEM      writes the whole of C64 memory to a file, U64
;                             family only.
;   CTRL_CMD_READ_RTC         INFERRED, and src/uci/clock.s reads the clock
;                             through a documented command instead.
;   CTRL_CMD_LOAD_CONFIG      INFERRED, and it reloads the machine's own
;                             settings from a file.
;   CTRL_CMD_FINISH_CAPTURE   ends a tape capture nothing else here starts.
;
; All of them are reachable through uci_exec, which is the whole reason the
; generic form exists.
;
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"
        .include "uci_seg.inc"
        .include "uci_zp.inc"

        .import uci_exec
        .import ult_req, ult_buf, ult_stage
        .import ult_req_clear, ult_invalid

        .export ultimate_reboot,       _ultimate_reboot
        .export ultimate_freeze,       _ultimate_freeze
        .export ultimate_drive_enable
        .export ultimate_drive_power
        .export ultimate_drive_info,   _ultimate_drive_info
        .export ctrl_drvinfo_reply
        .export ultimate_ramdisk_info, _ultimate_ramdisk_info

; The second byte of the drive power reply: 'n' of "on ", 'f' of "off".
ULT_POWER_ON_BYTE  = $6E
ULT_POWER_OFF_BYTE = $66

        uci_code

; ---------------------------------------------------------------------------
; ultimate_reboot  ->  A = ULTIMATE_* result, if the caller still exists
;
; Resets the C64. On a machine that reboots quickly this never returns; on one
; that does not, it returns ULTIMATE_ERR_TIMEOUT, because the reset happens
; before the interface goes idle. Neither is a failure and neither is worth
; branching on: the useful thing to know is that nothing after this line runs.
; ---------------------------------------------------------------------------
ultimate_reboot:
_ultimate_reboot:
        jsr ult_req_clear
        lda #UCI_TARGET_CONTROL | UCI_TARGET_NO_REPLY
        sta ult_req + UCI_REQ_TARGET
        lda #CTRL_CMD_REBOOT
        sta ult_req + UCI_REQ_COMMAND
        jmp ctrl_exec

; ---------------------------------------------------------------------------
; ultimate_freeze  ->  A = ULTIMATE_* result
;
; The same thing as pressing the Ultimate's freeze button. The C64 stops, the
; menu appears, and this call returns when the machine is let go again - so it
; is bounded by a person, not by the timeout budget. Callers that mind should
; not offer it.
; ---------------------------------------------------------------------------
ultimate_freeze:
_ultimate_freeze:
        jsr ult_req_clear
        jsr ctrl_target
        lda #CTRL_CMD_FREEZE
        sta ult_req + UCI_REQ_COMMAND
        jmp ctrl_exec

; ---------------------------------------------------------------------------
; ultimate_drive_enable   A = drive (0 = A, 1 = B), X = 0 to switch it off
;                      -> A = ULTIMATE_* result
;
; Drive power, which is what the Ultimate's menu calls it: an enabled drive
; answers on the IEC bus and can be mounted into, a disabled one is not there at
; all. A machine with no second drive configured accepts the command for it and
; does nothing, which is the firmware's own behaviour and not worth hiding.
;
; **This is drive A or B, not an IEC device number** - unlike src/uci/disk.s,
; which names the drive by the number it answers as. The commands are separate
; per drive, so there is nothing to look the number up with.
; ---------------------------------------------------------------------------
ultimate_drive_enable:
        cmp #CTRL_DRIVE_SLOTS
        bcs @invalid
        asl a                           ; A: $30 enable, $31 disable
        clc                             ; B: $32 enable, $33 disable
        adc #CTRL_CMD_ENABLE_DRIVE_A
        cpx #$00
        bne @store
        clc
        adc #$01                        ; the disable of the same pair
@store: pha
        jsr ult_req_clear
        jsr ctrl_target
        pla
        sta ult_req + UCI_REQ_COMMAND
        jmp ctrl_exec

@invalid:
        jmp ult_invalid

; ---------------------------------------------------------------------------
; ultimate_drive_power   A = drive (0 = A, 1 = B)
;                     -> A = ULTIMATE_* result, ult_stage = 1 when it is on
;
; The reply is three ASCII bytes rather than a flag, so it is read here and
; turned into one. A reply that is neither "on " nor "off" is
; ULTIMATE_ERR_PROTOCOL: a power state guessed from an unrecognised word would
; be a plausible-looking wrong answer.
; ---------------------------------------------------------------------------
ultimate_drive_power:
        cmp #CTRL_DRIVE_SLOTS
        bcs @invalid
        clc
        adc #CTRL_CMD_GET_DRIVE_A_POWER
        pha
        lda #$00
        sta ult_stage                   ; off unless the firmware says otherwise
        jsr ult_req_clear
        jsr ctrl_target
        pla
        sta ult_req + UCI_REQ_COMMAND

        lda #<(ult_stage + 1)           ; the three bytes, behind the answer
        sta ult_req + UCI_REQ_DATA
        lda #>(ult_stage + 1)
        sta ult_req + UCI_REQ_DATA + 1
        lda #CTRL_POWER_BYTES
        sta ult_req + UCI_REQ_DATAMAX

        jsr ctrl_exec
        cmp #ULTIMATE_OK
        bne @out

        lda ult_req + UCI_REQ_DATALEN + 1
        bne @protocol
        lda ult_req + UCI_REQ_DATALEN
        cmp #CTRL_POWER_BYTES
        bne @protocol

        lda ult_stage + 2               ; 'n' of "on ", 'f' of "off"
        cmp #ULT_POWER_ON_BYTE
        beq @on
        cmp #ULT_POWER_OFF_BYTE
        bne @protocol
        lda #$00
        beq @answer                     ; always
@on:    lda #$01
@answer:
        sta ult_stage
        lda #ULTIMATE_OK
@out:   ldx #$00
        rts

@protocol:
        lda #ULTIMATE_ERR_PROTOCOL
        ldx #$00
        rts

@invalid:
        jmp ult_invalid

; ---------------------------------------------------------------------------
; ultimate_drive_info   ult_buf = a CTRL_DRVINFO_BYTES block
;                    -> A = ULTIMATE_* result
;
; A count, then one three-byte record per drive: type, IEC device number, and
; whether it is running. The type is a CTRL_DRVTYPE_* code; the device number is
; the one src/uci/disk.s takes, so this is how a program finds out what to mount
; into without asking its user.
;
; **The records are not only drives A and B.** The firmware adds one per
; occupied IEC bus slot as well, so the block has to be CTRL_DRVINFO_BYTES - the
; count and six records - and not the seven bytes two drives need. The type of a
; slot record is CTRL_DRVTYPE_SOFTIEC or CTRL_DRVTYPE_PRINTER, neither of which
; is a disk drive, so a caller looking for something to mount into has to read
; the type rather than assume every record is one.
;
; The effective device number is asked for rather than the configured one: a
; drive whose address the running software changed answers on the effective one,
; which is the number that matters to anything trying to reach it.
;
; ctrl_drvinfo_reply below checks the reply, and says what the firmware gets
; wrong about the count.
; ---------------------------------------------------------------------------
ultimate_drive_info:
_ultimate_drive_info:
        sta ult_buf
        stx ult_buf + 1
        ora ult_buf + 1
        beq @invalid

        jsr ctrl_no_drives              ; a failed call reports no drives

        jsr ult_req_clear
        jsr ctrl_target
        lda #CTRL_CMD_GET_DRVINFO
        sta ult_req + UCI_REQ_COMMAND
        lda #$01                        ; effective IEC addresses, not configured
        sta ult_stage
        lda #<ult_stage
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_stage
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$01
        sta ult_req + UCI_REQ_ARGLEN

        lda ult_buf
        sta ult_req + UCI_REQ_DATA
        lda ult_buf + 1
        sta ult_req + UCI_REQ_DATA + 1
        lda #CTRL_DRVINFO_BYTES
        sta ult_req + UCI_REQ_DATAMAX

        jsr ctrl_exec
        cmp #ULTIMATE_OK
        bne @failed

        jsr ctrl_drvinfo_reply
        cmp #ULTIMATE_OK
        bne @failed
        ldx #$00
        rts

@failed:
        pha
        jsr ctrl_no_drives              ; whatever went wrong, report none
        pla
        ldx #$00
        rts

@invalid:
        jmp ult_invalid

; ---------------------------------------------------------------------------
; ctrl_drvinfo_reply   ult_buf = the caller's block, holding the reply
;                      ult_req + UCI_REQ_DATALEN = how many bytes of it arrived
;                   -> A = ULTIMATE_OK or ULTIMATE_ERR_PROTOCOL
;
; **The count the reply declares can be larger than the number of records the
; reply carries.** control_target.cc emits a record for drive A and one for
; drive B and adds three to the reply length for each. IecInterface::info then
; increments the same count byte once per occupied IEC bus slot - a SoftwareIEC
; drive, an IEC printer - but never grows the reply length, so those records are
; written into the firmware's buffer and never sent. A machine with SoftwareIEC
; enabled therefore answers, for example, a count of 3 in a reply seven bytes
; long.
;
; So the count is clamped to the records that actually arrived rather than the
; reply being rejected: rejecting it would fail ultimate_drive_info() on every
; machine with an IEC slot in use, and trusting it would walk the caller past
; the data. A firmware that grows the length to match sends more records and
; this clamps nothing.
;
; What is still refused: a count above CTRL_DRVINFO_MAX, which no machine has
; slots for, and a length that is not the count byte plus a whole number of
; records, which means the layout is not the one read here.
;
; Split out of ultimate_drive_info and exported so that
; tests/emulator/sdk.suite can call it with the reply a machine running
; SoftwareIEC sends. u64sim does not implement GET_DRVINFO, so there is no other
; way to run this against that reply, and a test that rebuilt the check instead
; would pass while the shipping one was wrong. Nothing else calls it.
; ---------------------------------------------------------------------------
ctrl_drvinfo_reply:
        lda ult_req + UCI_REQ_DATALEN + 1
        bne @protocol                   ; no reply this long is this reply
        lda ult_buf
        sta uci_ptr
        lda ult_buf + 1
        sta uci_ptr + 1

        ldy #$00                        ; the count is the first byte
        lda (uci_ptr),y
        cmp #CTRL_DRVINFO_MAX + 1
        bcs @protocol                   ; a count no machine has slots for

        ldy #$00                        ; Y = records the reply actually carries
        lda #CTRL_DRVINFO_FIRST         ; A = bytes the count and those records fill
@span:  cmp ult_req + UCI_REQ_DATALEN
        beq @carried                    ; the reply ends on a record boundary
        bcs @protocol                   ; it ends inside one
        cpy #CTRL_DRVINFO_MAX
        bcs @protocol                   ; longer than the longest reply there is
        clc
        adc #CTRL_DRVINFO_RECORD
        iny
        bne @span                       ; always: the cpy above bounds Y at 6

@carried:
        tya
        ldy #$00
        cmp (uci_ptr),y
        bcs @ok                         ; every record the count declares arrived
        sta (uci_ptr),y                 ; otherwise report only the ones that did
@ok:    lda #ULTIMATE_OK
        rts

@protocol:
        lda #ULTIMATE_ERR_PROTOCOL
        rts

; Zero the count at the front of the caller's block.
ctrl_no_drives:
        lda ult_buf
        sta uci_ptr
        lda ult_buf + 1
        sta uci_ptr + 1
        lda #$00
        ldy #$00
        sta (uci_ptr),y
        rts

; ---------------------------------------------------------------------------
; ultimate_ramdisk_info   ult_buf = a CTRL_RAMDISK_BYTES block
;                      -> A = ULTIMATE_* result
;
; Four two-byte records describing the GEOS MegaPatch RAM disks the machine is
; carrying: a drive type code and a size in 64K units. A type of zero is a slot
; with nothing in it.
; ---------------------------------------------------------------------------
ultimate_ramdisk_info:
_ultimate_ramdisk_info:
        sta ult_buf
        stx ult_buf + 1
        ora ult_buf + 1
        beq @invalid

        jsr ult_req_clear
        jsr ctrl_target
        lda #CTRL_CMD_GET_RAMDISKINFO
        sta ult_req + UCI_REQ_COMMAND
        lda ult_buf
        sta ult_req + UCI_REQ_DATA
        lda ult_buf + 1
        sta ult_req + UCI_REQ_DATA + 1
        lda #CTRL_RAMDISK_BYTES
        sta ult_req + UCI_REQ_DATAMAX

        jsr ctrl_exec
        cmp #ULTIMATE_OK
        bne @out

        lda ult_req + UCI_REQ_DATALEN + 1
        bne @protocol
        lda ult_req + UCI_REQ_DATALEN
        cmp #CTRL_RAMDISK_BYTES
        bne @protocol
        lda #ULTIMATE_OK
@out:   ldx #$00
        rts

@protocol:
        lda #ULTIMATE_ERR_PROTOCOL
        ldx #$00
        rts

@invalid:
        jmp ult_invalid

; ---------------------------------------------------------------------------
; Internals
; ---------------------------------------------------------------------------

ctrl_target:
        lda #UCI_TARGET_CONTROL
        sta ult_req + UCI_REQ_TARGET
        rts

ctrl_exec:
        lda #<ult_req
        ldx #>ult_req
        jmp uci_exec
