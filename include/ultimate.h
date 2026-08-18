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

/*
 * The Ultimate 64's CPU speed.
 *
 * Not a UCI command - there is none for speed - but memory-mapped I/O at
 * $D031, which is why these four are the SDK's only entry points that touch a
 * hardware register directly. See src/uci/turbo.s.
 *
 * **Turbo may simply not be there**, and a program cannot switch it on for
 * itself: it depends on the machine's "Turbo Control" setting, which its owner
 * chooses. ultimate_turbo_available() is the test, and it is honest on a plain
 * C64 too, where the same register reads $FF because unimplemented VIC
 * registers do. Treat turbo as an optimisation, never as a requirement.
 *
 * **The index above U64_SPEED_4MHZ does not mean the same thing on every
 * machine.** The U64's table is 1,2,3,4,5,6,8..48 and the U64-II's is
 * 1,2,3,4,6,8..64, so index 4 is 5MHz on one and 6MHz on the other. Only
 * U64_SPEED_1MHZ..U64_SPEED_4MHZ are portable; U64_SPEED_MAX is "as fast as
 * this machine goes", whatever that is.
 */

/* 1 when the turbo registers answer, 0 when turbo is off in the machine's
 * configuration - or when this is not an Ultimate 64 at all. */
uint8_t ultimate_turbo_available(void);

/* The current speed index, or U64_TURBO_UNAVAILABLE ($FF), which is not a
 * speed: the index is four bits, so the two can never be confused. */
uint8_t ultimate_turbo_get(void);

/*
 * Set the speed index. Leaves the badline setting alone.
 *
 * Returns ULTIMATE_ERR_INVALID_ARGUMENT for an index above U64_SPEED_MAX -
 * refused rather than masked - and ULTIMATE_ERR_NOT_SUPPORTED when turbo is
 * unavailable.
 */
uint8_t ultimate_turbo_set(uint8_t index);

/*
 * Badlines on (non-zero) or off (zero). Leaves the speed alone.
 *
 * Off means the VIC stops stealing the CPU's cycles on a character row, which
 * is a measurable win at 1MHz as well as under turbo. What it does to the
 * display is the machine's business and is not documented here: look at a real
 * screen before shipping it, because a badline is how the VIC fetches the
 * characters it is about to draw.
 */
uint8_t ultimate_turbo_badlines(uint8_t on);

/*
 * Files and directories, on the Ultimate's own filesystem.
 *
 * Target $01 throughout. Buffers belong to the caller, as everywhere else in
 * this header: nothing is allocated and nothing is retained after the call.
 *
 * Names go on the wire exactly as given. The Ultimate speaks ASCII and a C64
 * program usually holds PETSCII, and converting here would be the SDK guessing
 * which one it had been handed.
 */

/* Change directory. Absolute or relative, as the firmware understands it. */
uint8_t ultimate_chdir(const char *path);

/*
 * The current directory, NUL-terminated. At most buflen-1 bytes are stored;
 * a path too long for the buffer is clipped and still ULTIMATE_OK, because a
 * clipped path is still the answer to "where am I". outlen may be NULL.
 */
uint8_t ultimate_getpath(char *buf, uint16_t buflen, uint16_t *outlen);

/* Open the current directory for reading. */
uint8_t ultimate_opendir(void);

/*
 * One directory entry per call, NUL-terminated in name, with the DOS_ATTR_*
 * bits in *attrib. attrib may be NULL.
 *
 * Returns ULTIMATE_END when the directory is finished. That is a result, not a
 * failure, and it is a code of its own so that a caller never has to tell "no
 * more entries" apart from "something broke".
 *
 * **Issue no other command between calls.** A directory walk is one live
 * exchange with the Ultimate - the firmware sends an entry per reply block -
 * and any other command in the middle of it ends the walk.
 *
 * **To stop before the end, call uci_abort().** The firmware holds a block
 * until it is released, so a half-read walk leaves the interface unable to
 * take another command; uci_abort() releases it and returns the interface to
 * idle. Reading to ULTIMATE_END needs no abort.
 *
 *     if (ultimate_opendir() == ULTIMATE_OK)
 *         while (ultimate_readdir(name, sizeof(name), &attrib) == ULTIMATE_OK)
 *             puts(name);
 */
uint8_t ultimate_readdir(char *name, uint16_t namelen, uint8_t *attrib);

/* Open a file. attrib is a DOS_FA_* mask: DOS_FA_READ, DOS_FA_WRITE, ... */
uint8_t ultimate_open(const char *name, uint8_t attrib);

/* Close whatever is open. Harmless when nothing is. */
uint8_t ultimate_close(void);

/*
 * Read up to len bytes. Fewer than asked for is the end of the file rather
 * than an error, so *outlen is the answer and the result stays ULTIMATE_OK.
 * outlen may be NULL. The firmware answers in 512-byte blocks; the SDK walks
 * the chain, so a caller asks for what it wants and gets it whole.
 */
uint8_t ultimate_read(uint8_t *buf, uint16_t len, uint16_t *outlen);

/* Write len bytes to the open file. */
uint8_t ultimate_write(const uint8_t *buf, uint16_t len);

/* Seek to an absolute byte position in the open file. */
uint8_t ultimate_seek(uint32_t pos);

/* Delete a file, by name in the current directory or by path. */
uint8_t ultimate_delete(const char *name);

/*
 * Loading and saving, which is what most programs actually want from a
 * filesystem.
 *
 * ultimate_load() has two tiers and picks between them by trying the fast one:
 *
 *   SoftwareIEC usable?  -> LOAD_SU + LOAD_EX, and the firmware writes straight
 *                           into C64 RAM
 *   otherwise            -> DOS open/read/close, every byte through the
 *                           response queue
 *
 * Trying rather than asking is deliberate. Target $05 reports present even when
 * the IEC drive is switched off, and detection could not tell you a particular
 * *file* is loadable in any case, so the only honest test is the command
 * itself. Nothing about this is visible to the caller except the speed.
 */

/*
 * Load a PRG. addr == 0 takes the address from the file's own first two bytes,
 * exactly as LOAD"X",8,1 does; any other value loads there instead. The two
 * header bytes are consumed either way and never stored.
 *
 * ultimate_last_end() then gives the address after the last byte written.
 */
uint8_t ultimate_load(const char *name, uint16_t addr);

/*
 * Load raw bytes: no header consumed, no address taken from the file. max is a
 * hard limit and must be given, because the destination is RAM the caller
 * named and nothing else is going to stop the write.
 */
uint8_t ultimate_bload(const char *name, uint16_t addr, uint16_t max);

/* Write len bytes of memory from start to a file, replacing any existing one. */
uint8_t ultimate_save(const char *name, uint16_t start, uint16_t len);

/* The address after the last byte the previous load wrote. */
uint16_t ultimate_last_end(void);

/*
 * The RAM expansion.
 *
 * Two pairs, and they are not the same operation twice. ultimate_reu_stash()
 * and ultimate_reu_fetch() move bytes between C64 RAM and the expansion over
 * the REU's own DMA registers, because no UCI command does it. The transfer
 * runs with the CPU halted, so it is finished when the call returns and
 * nothing here can block.
 *
 * ultimate_reu_load() and ultimate_reu_save() move bytes between the expansion
 * and the *currently open file* - open it with ultimate_open() first - without
 * any of them passing through the C64 at all.
 *
 * Lengths are bytes. A DMA length of 0 means 65536, which is the REU's own
 * convention rather than an SDK invention.
 *
 * Whether there is an expansion at all is the machine owner's decision, exactly
 * as turbo is: ultimate_reu_available() answers it, and the DMA pair returns
 * ULTIMATE_ERR_NOT_SUPPORTED rather than pretending.
 */
uint8_t ultimate_reu_available(void);
uint8_t ultimate_reu_stash(uint16_t addr, uint32_t reuaddr, uint16_t len);
uint8_t ultimate_reu_fetch(uint16_t addr, uint32_t reuaddr, uint16_t len);
uint8_t ultimate_reu_load(uint32_t reuaddr, uint32_t len);
uint8_t ultimate_reu_save(uint32_t reuaddr, uint32_t len);

/* ---------------------------------------------------------------------------
 * Network: TCP and UDP sockets.
 *
 * Everything below was measured against firmware 3.15 on real hardware. Three
 * of those measurements decide how this is used, and none of them is in the
 * protocol document:
 *
 * **Reads do not wait.** A read issued straight after a connect answers "not
 * yet" even when the peer greeted you on accept. Poll:
 *
 *     for (;;) {
 *         err = ultimate_net_read(h, buf, sizeof buf, &got);
 *         if (err == ULTIMATE_END)  break;          // the peer hung up
 *         if (err != ULTIMATE_OK)   return err;
 *         if (got == 0)             continue;       // nothing yet
 *         ...use buf[0..got-1]...
 *     }
 *
 * **ULTIMATE_END is end of stream**, the same code ultimate_readdir() uses at
 * the end of a directory. It is reported exactly once, and after it the handle
 * is already gone - do not call ultimate_net_close() on it.
 *
 * **A connect can take thirty seconds.** 48-75 ms to a host that is up, and
 * 30.8 s to an address with nothing at it before the firmware gives up. No
 * value of the uci_set_timeout() budget reaches that, so ultimate_net_connect()
 * and ultimate_net_udp() wait without a limit of their own and restore your
 * budget afterwards. They are the only entry points in the SDK that do.
 *
 * bufsize in ultimate_net_read() is the size of the buffer, and at most
 * UCI_NET_READ_PREFIX fewer bytes than that are stored: the firmware sends its
 * own 16-bit count in front of the data, which this strips. The request is also
 * capped at UCI_NET_READ_MAX; larger reads have taken the machine off the
 * network, so this SDK will not issue one. See docs/uci.md.
 *
 * A write reports how many bytes the firmware took. It has matched the length
 * asked for every time it has been measured, which is why it is worth checking
 * rather than assuming.
 *
 * The four LISTEN commands are deliberately absent - their command numbers are
 * not in the published specification. uci_exec() still reaches them.
 * ------------------------------------------------------------------------- */
uint8_t ultimate_net_ifcount(uint8_t *count);
uint8_t ultimate_net_macaddr(uint8_t iface, uint8_t *mac);
uint8_t ultimate_net_ipconfig(uint8_t iface, uint8_t *ipconfig);
uint8_t ultimate_net_connect(const char *host, uint16_t port, uint8_t *handle);
uint8_t ultimate_net_udp(const char *host, uint16_t port, uint8_t *handle);
uint8_t ultimate_net_close(uint8_t handle);
uint8_t ultimate_net_read(uint8_t handle, uint8_t *buf, uint16_t bufsize,
                          uint16_t *got);
uint8_t ultimate_net_write(uint8_t handle, const uint8_t *buf, uint16_t len,
                           uint16_t *sent);

/* A short, stable, English description of an ULTIMATE_* code. Never NULL. */
const char *ultimate_strerror(uint8_t err);

/* Raw status number from the last command; see uci_last_device_code(). */
#define ultimate_device_code() uci_last_device_code()

#ifdef __cplusplus
}
#endif

#endif /* ULTIMATE_H */
