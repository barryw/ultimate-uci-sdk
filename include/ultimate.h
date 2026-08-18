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

/*
 * The VIC-II palette: what each of the sixteen colour indices actually looks
 * like. Requires the control target and firmware newer than 3.15; older
 * firmware answers ULTIMATE_ERR_NOT_SUPPORTED, and there is no version number
 * to test beforehand that can be trusted - the REST API reports a post-3.15
 * development build as "3.15". Call one and look at the result.
 *
 * These change the **live palette only**. Nothing is written to flash or to a
 * VPL file, so a program that dies mid-cycle cannot leave the machine looking
 * wrong permanently, and ultimate_palette_reset() always puts it back.
 *
 * A whole-palette write costs about a quarter of a frame on a 1MHz C64 and a
 * single colour about an eighth, so cycling the palette per frame is
 * comfortable. `make time-run` measures it on your machine.
 */
#define ULTIMATE_PALETTE_COLORS UCI_PALETTE_COLORS   /* 16 */
#define ULTIMATE_PALETTE_BYTES  UCI_PALETTE_BYTES    /* 48: 16 * RGB */

/*
 * Read all sixteen colours into palette[48], as R, G, B per colour.
 *
 * Returns ULTIMATE_ERR_PROTOCOL if the firmware answers with anything other
 * than exactly 48 bytes: a half-written palette looks like a working one.
 */
uint8_t ultimate_palette_get(uint8_t *palette);

/* Write all sixteen colours from palette[48]. One command, one round trip. */
uint8_t ultimate_palette_set(const uint8_t *palette);

/*
 * Write one colour. index is 0..15; anything else is
 * ULTIMATE_ERR_INVALID_ARGUMENT and never reaches the wire.
 */
uint8_t ultimate_palette_set_color(uint8_t index, uint8_t r, uint8_t g, uint8_t b);

/* Back to the machine's built-in palette. */
uint8_t ultimate_palette_reset(void);

/* A short, stable, English description of an ULTIMATE_* code. Never NULL. */
const char *ultimate_strerror(uint8_t err);

/* Raw status number from the last command; see uci_last_device_code(). */
#define ultimate_device_code() uci_last_device_code()

#ifdef __cplusplus
}
#endif

#endif /* ULTIMATE_H */
