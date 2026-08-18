/*
 * uci.h - Layer 1: Ultimate Command Interface transport.
 *
 * This is the low-level protocol layer. Application code should normally use
 * <ultimate.h> instead; this header exists for services, for people writing
 * new bindings, and for programs that need to issue a raw UCI command.
 *
 * Rules this layer obeys:
 *   - no heap, no stdlib, no hidden buffers: every byte lands in a buffer the
 *     caller owns
 *   - no interrupts required, no zero page beyond what the compiler uses
 *   - every entry point is bounded in time: it either completes or returns
 *     ULTIMATE_ERR_TIMEOUT
 *
 * Part of the Ultimate SDK. SPDX-License-Identifier: MIT
 */

#ifndef ULTIMATE_UCI_H
#define ULTIMATE_UCI_H

#include <stddef.h>
#include <stdint.h>
#include "uci_protocol.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * One UCI command/response exchange.
 *
 * Fill in the request fields, call uci_exec(), read the reply fields.
 * All buffers belong to the caller and are never retained after the call.
 *
 * The command placed on the wire is:
 *     <target> <command> <args[0..arglen-1]> <payload[0..payloadlen-1]>
 *
 * args and payload are two separate spans purely so that a caller can send a
 * fixed header plus a large body without copying them into one buffer first.
 * Either may be NULL with a length of 0.
 */
typedef struct {
    /* --- request --- */
    uint8_t         target;      /* UCI_TARGET_*, optionally | UCI_TARGET_NO_REPLY */
    uint8_t         command;     /* target-specific command byte */
    const uint8_t  *args;        /* may be NULL when arglen == 0 */
    uint16_t        arglen;
    const uint8_t  *payload;     /* may be NULL when payloadlen == 0 */
    uint16_t        payloadlen;

    /* --- reply --- */
    /*
     * data == NULL means "I do not want the reply data": it is read and
     * discarded, and that is not reported as truncation. A non-NULL buffer that
     * fills up before the reply ends does yield ULTIMATE_ERR_TRUNCATED.
     *
     * status == NULL is always safe: the numeric device code is decoded either
     * way, so a command that fails still returns a failure.
     */
    uint8_t        *data;        /* response bytes land here; may be NULL */
    uint16_t        datamax;     /* capacity of data */
    uint16_t        datalen;     /* out: bytes actually stored */
    uint8_t        *status;      /* status bytes land here; may be NULL */
    uint16_t        statusmax;   /* capacity of status */
    uint16_t        statuslen;   /* out: bytes actually stored */
} uci_request;

/*
 * Probe for the command interface.
 *
 * Reads the identification register and compares it against the documented
 * signature. This is a pure register read: it costs a handful of cycles and
 * never blocks, but it also cannot tell a wedged Ultimate from a healthy one.
 * uci_init() does the stronger, functional check.
 *
 * Returns 1 when the signature is present, 0 otherwise.
 */
uint8_t uci_signature_present(void);

/* Raw value of the identification register. For diagnostics. */
uint8_t uci_ident_register(void);

/*
 * Bring the transport up.
 *
 * Verifies the signature, clears any latent state error and returns the
 * interface to idle, aborting a half-finished exchange left behind by a
 * previous program if necessary.
 *
 * Returns ULTIMATE_OK, ULTIMATE_ERR_NO_DEVICE or ULTIMATE_ERR_TIMEOUT.
 */
uint8_t uci_init(void);

/*
 * Run one command to completion.
 *
 * Returns an ULTIMATE_* code. ULTIMATE_ERR_TRUNCATED means the exchange itself
 * succeeded but the reply did not fit in req->data; req->datalen then holds the
 * number of bytes that were kept and the rest was discarded.
 *
 * When req->target has UCI_TARGET_NO_REPLY set, the call returns as soon as the
 * interface is idle again and no data or status is collected.
 */
uint8_t uci_exec(uci_request *req);

/*
 * The same exchange, stopped at each reply-block boundary.
 *
 * uci_exec() drains every block of a reply into one buffer, which is what
 * almost every command wants. These two exist for the commands where the
 * boundaries carry meaning - and DOS_CMD_READ_DIR is why: the firmware sends
 * one directory entry per block, each of them <attrib> <name> with no
 * terminator and no length, so stitching them together destroys the only thing
 * separating one entry from the next.
 *
 * req->datalen is reset per call, so it is this block's length and nothing
 * else. Call uci_more_blocks() afterwards to find out whether another follows;
 * the call that returns with it clear is the one that decodes the device
 * status, so a loop reads the result of that last call.
 *
 *     err = uci_exec_first(&req);
 *     while (err == ULTIMATE_OK) {
 *         ...use req.data, req.datalen...
 *         if (!uci_more_blocks())
 *             break;
 *         err = uci_exec_next(&req);
 *     }
 *
 * Issue no other command in the middle: the walk is one live exchange.
 */
uint8_t uci_exec_first(uci_request *req);
uint8_t uci_exec_next(uci_request *req);

/* 1 while another reply block follows the one just collected. */
uint8_t uci_more_blocks(void);

/*
 * Ask the Ultimate to abandon the exchange in progress and force the transport
 * back to idle. Safe to call at any time; bounded like everything else.
 */
uint8_t uci_abort(void);

/*
 * Timeout budget, in units of 256 status polls. 0 means "wait forever".
 *
 * The wall-clock meaning of a unit depends on the CPU speed, which on Ultimate
 * hardware ranges from 1 MHz to 48 MHz - see docs/compatibility.md. Services
 * that wait on the network or on a disk raise this themselves; restore it with
 * uci_set_timeout(UCI_TIMEOUT_DEFAULT) afterwards.
 *
 * uci_init() installs UCI_TIMEOUT_DEFAULT, so a program that never calls
 * uci_set_timeout() still gets the bounded-time guarantee. UCI_TIMEOUT_DEFAULT
 * and UCI_TIMEOUT_FOREVER come from uci_protocol.h.
 */
void    uci_set_timeout(uint8_t units);
uint8_t uci_get_timeout(void);

/*
 * Raw device status from the most recent uci_exec().
 *
 * uci_last_device_code() returns the numeric status the target reported, in the
 * target's own numbering: 0-99 for the DOS/network/control family, 0-999 for
 * HTTP, 0-255 for SoftwareIEC. UCI_DEVICE_CODE_NONE means the target said
 * nothing. Keep this out of program logic where you can - it is firmware
 * detail, useful for diagnostics and for services that need the exact code.
 */
#define UCI_DEVICE_CODE_NONE 0xFFFFu

uint16_t uci_last_device_code(void);

/*
 * Which status encoding a target is *expected* to use, as a UCI_STATUS_FMT_*
 * value. This is documentation, not a decoding rule: at least one target does
 * not keep to its own convention, so uci_decode_status() reads the bytes rather
 * than trusting this. See docs/uci.md, "Status encodings".
 */
uint8_t uci_status_format(uint8_t target);

/*
 * Translate a raw status buffer into an ULTIMATE_* code and, as a side effect,
 * record the numeric device code. Exposed because it is worth unit-testing on
 * its own and because services occasionally re-decode a stashed status.
 *
 * The encoding is determined from the bytes: three leading ASCII digits is the
 * HTTP form, two is the "NN,TEXT" form, and a leading non-digit is a single
 * binary byte. The three cannot be confused for one another. Pass the first
 * four bytes of the status at minimum - a shorter prefix can look like a
 * different encoding.
 *
 * An empty status buffer is success: several commands stay quiet when all is
 * well.
 */
uint8_t uci_decode_status(uint8_t target, const uint8_t *status, uint16_t statuslen);

#ifdef __cplusplus
}
#endif

#endif /* ULTIMATE_UCI_H */
