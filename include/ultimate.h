/*
 * ultimate.h - the Ultimate SDK public API.
 *
 * One include, one link, and your C64 program can talk to an Ultimate. This
 * header is the layer application code should use. Drop to <uci.h> only when
 * you need to issue a command the SDK does not wrap yet.
 *
 *     #include <ultimate.h>
 *
 *     int main(void)
 *     {
 *         ultimate_capabilities caps;
 *
 *         if (ultimate_init() != ULTIMATE_OK)
 *             return 1;
 *
 *         ultimate_detect(&caps);
 *         if (ultimate_has_http(&caps)) {
 *             ...
 *         }
 *         return 0;
 *     }
 *
 * Part of the Ultimate SDK. SPDX-License-Identifier: MIT
 */

#ifndef ULTIMATE_H
#define ULTIMATE_H

#include <stdint.h>
#include "uci.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * What this machine can do.
 *
 * Filled in by ultimate_detect() by asking each target to identify itself.
 * Prefer testing these flags over testing for a particular model: an
 * Ultimate-II+ on new firmware has more of them set than an Ultimate 64 on old
 * firmware.
 */
typedef struct {
    uint8_t  present;   /* 1 when a working command interface answered */
    uint8_t  ident;     /* raw value of the identification register */
    uint16_t targets;   /* bit N is set when target N is implemented */
} ultimate_capabilities;

#define ultimate_has_target(caps, target) \
    ((uint8_t)(((caps)->targets >> ((target) & UCI_TARGET_MASK)) & 1u))

#define ultimate_has_dos(caps)      ultimate_has_target(caps, UCI_TARGET_DOS1)
#define ultimate_has_dos2(caps)     ultimate_has_target(caps, UCI_TARGET_DOS2)
#define ultimate_has_network(caps)  ultimate_has_target(caps, UCI_TARGET_NETWORK)
#define ultimate_has_control(caps)  ultimate_has_target(caps, UCI_TARGET_CONTROL)
#define ultimate_has_softiec(caps)  ultimate_has_target(caps, UCI_TARGET_SOFTIEC)
#define ultimate_has_http(caps)     ultimate_has_target(caps, UCI_TARGET_HTTP)

/*
 * Bring the SDK up. Call once, before anything else.
 *
 * Returns ULTIMATE_OK when a command interface is present and responding,
 * ULTIMATE_ERR_NO_DEVICE when there is nothing there (no Ultimate, or the
 * command interface is switched off in its configuration menu), or
 * ULTIMATE_ERR_TIMEOUT when the interface is present but wedged.
 */
uint8_t ultimate_init(void);

/* 1 when ultimate_init() has succeeded, 0 otherwise. Never touches hardware. */
uint8_t ultimate_available(void);

/*
 * Ask every known target whether it exists, and record the answers in caps.
 *
 * Costs one UCI round trip per target, so call it once at startup and keep the
 * result. Returns ULTIMATE_OK even when some targets are missing - that is the
 * normal case on older firmware. Returns ULTIMATE_ERR_NO_DEVICE if there is no
 * interface at all.
 */
uint8_t ultimate_detect(ultimate_capabilities *caps);

/*
 * Read a target's identification string, e.g. "ULTIMATE-II DOS V1.0".
 *
 * buf receives a NUL-terminated string; the protocol does not terminate its
 * strings, so at most buflen-1 bytes are stored. outlen may be NULL; when
 * given it receives the string length, excluding the terminator.
 *
 * Returns ULTIMATE_ERR_NOT_SUPPORTED when the firmware has no such target.
 */
uint8_t ultimate_identify(uint8_t target, char *buf, uint16_t buflen, uint16_t *outlen);

/*
 * Read the hardware model name, e.g. "ULTIMATE 64".
 *
 * Requires the control target. Returns ULTIMATE_ERR_NOT_SUPPORTED on firmware
 * that predates it. Same NUL-termination rules as ultimate_identify().
 */
uint8_t ultimate_get_model(char *buf, uint16_t buflen, uint16_t *outlen);

/* A short, stable, English description of an ULTIMATE_* code. Never NULL. */
const char *ultimate_strerror(uint8_t err);

/* Raw status number from the last command; see uci_last_device_code(). */
#define ultimate_device_code() uci_last_device_code()

#ifdef __cplusplus
}
#endif

#endif /* ULTIMATE_H */
