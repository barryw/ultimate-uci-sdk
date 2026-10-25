; uci_vars.inc - sizes of the shared variable block's buffers.
;
; One field list in src/uci/uci_core.s produces BSS or equates from UCI_VARS.
; Buffer sizes live here because other modules use them too.
;
; SPDX-License-Identifier: MIT

.ifndef UCI_VARS_INC
UCI_VARS_INC = 1

; The staging buffer, for commands that have to hand the firmware a short run of
; bytes it cannot be pointed at. Two services need it: src/uci/clock.s, whose
; six numbers arrive as six separate arguments, and src/uci/httpbody.s, whose
; commands interleave lengths with strings more times than the request block's
; two spans can express.
;
; Forty bytes is what the longest of those commands needs: a body handle, a key
; length, a key of up to ULT_HTTP_KEY_MAX bytes, and four bytes of integer
; behind it.
ULT_STAGE_SIZE = 40

.endif
