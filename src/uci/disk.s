; disk.s - Layer 2: disk images in the emulated drives.
;
; Mounting a D64 is the thing an Ultimate is bought for, and it was the largest
; gap in this SDK: three commands, all of them on the Ultimate DOS target.
;
; **The drive is named by its IEC device number, not by a slot.** Pass 8 for the
; drive answering as device 8, 9 for the one answering as 9, and
; ULTIMATE_DRIVE_LAST ($00) for the drive that was mounted last - falling back
; to drive A when nothing has been. That is `Dos::getDriveByID` in
; software/filemanager/dos.cc, and it means a program does not have to know
; which physical drive its user configured.
;
; **A drive that is switched off does not exist.** getDriveByID only matches a
; drive whose power is on, so mounting into a disabled drive answers
; "88,DRIVE NOT PRESENT" rather than switching it on. src/uci/control.s has
; ultimate_drive_enable for that.
;
; **The firmware decides the image type from the extension**: .D64, .D71, .D81,
; .G64 and .G71. Anything else is "89,NOT A DISK IMAGE", and a 1571 or 1581
; image on an FPGA core without mechanical-drive support is
; "90,INCOMPATIBLE IMAGE". Neither is worth pre-empting here: the firmware's own
; answer is both cheaper and right on hardware this was never tested against.
;
; SPDX-License-Identifier: MIT

        .include "uci_protocol.inc"
        .include "uci_seg.inc"
        .include "uci_zp.inc"

        .import ult_req, ult_buf, ult_buflen, ult_stage
        .import ult_req_clear, ult_invalid
        .import ult_dos_target, ult_dos_exec, ult_strlen

        .export ultimate_mount
        .export ultimate_unmount, _ultimate_unmount
        .export ultimate_swap,    _ultimate_swap

        uci_code

; ---------------------------------------------------------------------------
; ultimate_mount   A = IEC device number, ult_buf = image file name
;               -> A = ULTIMATE_* result
;
; The name is relative to the current directory unless it carries a path.
; ---------------------------------------------------------------------------
ultimate_mount:
        sta ult_stage                   ; <id>, sent out of the staging buffer

        jsr ult_strlen
        bcc @invalid
        lda ult_buflen
        ora ult_buflen + 1
        beq @invalid

        jsr ult_req_clear
        jsr ult_dos_target
        lda #DOS_CMD_MOUNT_DISK
        sta ult_req + UCI_REQ_COMMAND
        jsr disk_id_arg

        lda ult_buf                     ; <filename>, and nothing copied
        sta ult_req + UCI_REQ_PAYLOAD
        lda ult_buf + 1
        sta ult_req + UCI_REQ_PAYLOAD + 1
        lda ult_buflen
        sta ult_req + UCI_REQ_PAYLOADLEN
        lda ult_buflen + 1
        sta ult_req + UCI_REQ_PAYLOADLEN + 1
        jmp ult_dos_exec

@invalid:
        jmp ult_invalid

; ---------------------------------------------------------------------------
; ultimate_unmount   A = IEC device number  ->  A = ULTIMATE_* result
;
; The drive keeps running with no disk in it, exactly as removing one by hand
; would leave it.
; ---------------------------------------------------------------------------
ultimate_unmount:
_ultimate_unmount:
        sta ult_stage
        lda #DOS_CMD_UMOUNT_DISK
        bne disk_id_cmd                 ; always

; ---------------------------------------------------------------------------
; ultimate_swap   A = IEC device number  ->  A = ULTIMATE_* result
;
; The next image in the same set, which is what a multi-disk game asks for when
; it says INSERT SIDE B. The set is the one the Ultimate's own menu would step
; through; a drive with nothing mounted has nothing to swap to.
; ---------------------------------------------------------------------------
ultimate_swap:
_ultimate_swap:
        sta ult_stage
        lda #DOS_CMD_SWAP_DISK

; A = command byte, ult_stage = the device number already stored.
disk_id_cmd:
        pha
        jsr ult_req_clear
        jsr ult_dos_target
        pla
        sta ult_req + UCI_REQ_COMMAND
        jsr disk_id_arg
        jmp ult_dos_exec

; The device number as the command's single argument byte.
disk_id_arg:
        lda #<ult_stage
        sta ult_req + UCI_REQ_ARGS
        lda #>ult_stage
        sta ult_req + UCI_REQ_ARGS + 1
        lda #$01
        sta ult_req + UCI_REQ_ARGLEN
        rts
