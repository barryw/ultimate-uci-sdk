; uci_zp.inc - the SDK's zero page block, defined once.
;
; Four bytes, and the caller chooses where. $FB-$FE is the default because it is
; free on a stock C64 (the KERNAL uses it only for tape) and cc65's runtime does
; not allocate it. Override it at assembly time:
;
;       ca65 -D UCI_ZP=$A3 ...
;
; SPDX-License-Identifier: MIT

.ifndef UCI_ZP_INC
UCI_ZP_INC = 1

.ifndef UCI_ZP
UCI_ZP  = $FB
.endif

uci_rq  = UCI_ZP + 0            ; pointer to the request block being run
uci_ptr = UCI_ZP + 2            ; working pointer into a caller buffer
                                ; The service layer borrows uci_ptr between core
                                ; calls, which is safe because the core only
                                ; holds it for the duration of one uci_exec.
.endif
