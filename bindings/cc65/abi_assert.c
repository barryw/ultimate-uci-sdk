/*
 * abi_assert.c - keep the assembly view of uci_request honest.
 *
 * bindings/asm/ultimate.inc hard-codes the byte offsets of every field in
 * uci_request. If the struct ever changes shape - a field reordered, a type
 * widened, a compiler that pads differently - assembly callers would start
 * writing into the wrong fields and the failure would show up as mysterious
 * protocol errors on real hardware.
 *
 * So the offsets are asserted here instead, at build time, in C, where the
 * compiler is the authority on the layout. A mismatch is a compile error
 * naming the field that moved.
 *
 * This file emits no code.
 *
 * Part of the Ultimate SDK. SPDX-License-Identifier: MIT
 */

#include <stddef.h>
#include "ultimate.h"

/*
 * A negative array size is a hard error in every C compiler worth using.
 *
 * **Written as arithmetic rather than as a comparison on purpose.** The obvious
 * form is `[(expr == want) ? 1 : -1]`, and cc65 2.18 - which is what Ubuntu
 * ships, and therefore what CI uses - rejects it: comparing two constants earns
 * "Result of comparison is constant", `-W error` promotes that to an error, and
 * the array size never gets evaluated. Subtracting instead says the same thing
 * with no comparison operator in it, and both 2.18 and 2.19 accept it.
 *
 * `1 - 2 * !!(difference)` is 1 when the two agree and -1 when they do not.
 */
#define UCI_STATIC_ASSERT(name, expr, want) \
    typedef char uci_abi_check_##name[1 - 2 * !!((expr) - (want))]

UCI_STATIC_ASSERT(target,     offsetof(uci_request, target), 0);
UCI_STATIC_ASSERT(command, offsetof(uci_request, command), 1);
UCI_STATIC_ASSERT(args, offsetof(uci_request, args), 2);
UCI_STATIC_ASSERT(arglen, offsetof(uci_request, arglen), 4);
UCI_STATIC_ASSERT(payload, offsetof(uci_request, payload), 6);
UCI_STATIC_ASSERT(payloadlen, offsetof(uci_request, payloadlen), 8);
UCI_STATIC_ASSERT(data, offsetof(uci_request, data), 10);
UCI_STATIC_ASSERT(datamax, offsetof(uci_request, datamax), 12);
UCI_STATIC_ASSERT(datalen, offsetof(uci_request, datalen), 14);
UCI_STATIC_ASSERT(status, offsetof(uci_request, status), 16);
UCI_STATIC_ASSERT(statusmax, offsetof(uci_request, statusmax), 18);
UCI_STATIC_ASSERT(statuslen, offsetof(uci_request, statuslen), 20);
UCI_STATIC_ASSERT(size, sizeof(uci_request), 22);

/* Pointers are 16 bits on the 6502; the assembly shim assumes it. */
UCI_STATIC_ASSERT(pointer, sizeof(uint8_t *), 2);

/* The capability block the assembly service layer fills in. */
UCI_STATIC_ASSERT(caps_present, offsetof(ultimate_capabilities, present), 0);
UCI_STATIC_ASSERT(caps_ident, offsetof(ultimate_capabilities, ident), 1);
UCI_STATIC_ASSERT(caps_targets, offsetof(ultimate_capabilities, targets), 2);
UCI_STATIC_ASSERT(caps_size, sizeof(ultimate_capabilities), 4);

/* The SID reply is received directly into this count-prefixed structure. */
UCI_STATIC_ASSERT(sid_primary, offsetof(ultimate_sid, primary_address), 0);
UCI_STATIC_ASSERT(sid_secondary, offsetof(ultimate_sid, secondary_address), 2);
UCI_STATIC_ASSERT(sid_type, offsetof(ultimate_sid, type), 4);
UCI_STATIC_ASSERT(sid_record_size, sizeof(ultimate_sid), 5);
UCI_STATIC_ASSERT(sid_count, offsetof(ultimate_sid_info, count), 0);
UCI_STATIC_ASSERT(sid_records, offsetof(ultimate_sid_info, sid), 1);
UCI_STATIC_ASSERT(sid_info_size, sizeof(ultimate_sid_info), 21);
