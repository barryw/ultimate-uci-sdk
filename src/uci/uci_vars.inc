; uci_vars.inc - sizes of the shared variable block's buffers.
;
; The block itself is laid out in src/uci/uci_core.s, twice: once as BSS and
; once as equates from UCI_VARS. The sizes are here rather than there because
; the modules that use the buffers need them too, and two spellings of the same
; number is how a placed build stops matching a linked one.
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
