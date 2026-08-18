; uci_seg.inc - where the SDK's code goes.
;
; Every SDK module opens with `uci_code` instead of `.code`, so that one build
; flag can put the whole library somewhere other than the CODE segment without
; touching a line of the modules themselves.
;
; The BASIC wedge is the caller that needs it. Phase 3 took the wedge and the
; SDK together past the 4K at $C000, so the wedge keeps the block and the SDK
; moves to $A000 under BASIC ROM, reached through the stubs in
; src/basic/bank.s. That is a link-time choice, made here:
;
;     ca65 -D UCI_BANKED ...        code goes to the UCICODE segment
;     ca65 ...                      code goes to CODE, as it always did
;
; Only the code moves. RODATA and BSS stay where they were, because $C000 is RAM
; whatever the 6510's port says and data is read rather than executed.
;
; SPDX-License-Identifier: MIT

.macro  uci_code
.ifdef  UCI_BANKED
        .segment "UCICODE"
.else
        .code
.endif
.endmacro
