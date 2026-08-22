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
 *
 * Probing borrows the shared buffer variables the assembly interface uses -
 * ult_buf, ult_buflen and ult_outlen - so an assembly caller has to set them
 * again after this returns. A C caller passes its buffers per call and never
 * sees them.
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
 * The firmware documentation marks the underlying CTRL_CMD_GET_HWINFO command
 * deprecated. This wrapper remains for compatibility with existing programs.
 *
 * Requires the control target. Returns ULTIMATE_ERR_NOT_SUPPORTED on firmware
 * that predates it. Same NUL-termination rules as ultimate_identify().
 */
uint8_t ultimate_get_model(char *buf, uint16_t buflen, uint16_t *outlen);

/*
 * The SID address map reported by the deprecated CTRL_CMD_GET_HWINFO command.
 *
 * Firmware returns up to four records: two emulated SIDs followed by the
 * enabled physical sockets on an Ultimate 64. Both addresses are little-endian
 * on the wire, so this structure is the reply layout on a 6502. A zero
 * secondary address means that the record has no second mapping.
 *
 * `type` is deliberately raw. Current firmware uses it to describe the SID
 * implementation and address-mask mode; it does not identify 6581 versus
 * 8580. Preserve unknown values for forward compatibility.
 */
#define ULTIMATE_SID_MAX 4

typedef struct {
    uint16_t primary_address;
    uint16_t secondary_address;
    uint8_t  type;
} ultimate_sid;

typedef struct {
    uint8_t      count;
    ultimate_sid sid[ULTIMATE_SID_MAX];
} ultimate_sid_info;

/*
 * Fetch the configured SID addresses through deprecated CTRL_CMD_GET_HWINFO.
 *
 * The legacy name is intentional: firmware still implements this command, but
 * its documentation marks it deprecated and publishes no C64-side UCI
 * replacement. New code must handle ULTIMATE_ERR_NOT_SUPPORTED in case the
 * command is removed.
 *
 * Returns ULTIMATE_ERR_NOT_SUPPORTED when the control target or selector is
 * unavailable, ULTIMATE_ERR_PROTOCOL for a malformed reply, and
 * ULTIMATE_ERR_TRUNCATED if future firmware returns more than four records.
 * info->count is zero on every failure.
 */
uint8_t ultimate_legacy_get_sid_info(ultimate_sid_info *info);

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
 * What a file is: its size, when it was last written, and its attributes.
 *
 * The reply has exactly this layout on the wire, so it is received straight
 * into the structure; `name` is NUL-terminated afterwards by the SDK. `date`
 * and `time` are FAT's own packed forms - date is year-1980 in bits 15-9, month
 * in 8-5 and day in 4-0; time is hour in 15-11, minute in 10-5 and two-second
 * units in 4-0 - and are passed through unconverted, because a C64 program that
 * wants them formatted has a different idea of formatted than the next one.
 * `extension` is three bytes, space padded, with no terminator.
 *
 * A reply shorter than the header is ULTIMATE_ERR_PROTOCOL: a size read out of
 * half of its four bytes looks like a real answer.
 */
#define ULTIMATE_NAME_MAX DOS_INFO_NAME_MAX   /* 63, the longest name reported */

typedef struct {
    uint32_t size;
    uint16_t date;
    uint16_t time;
    char     extension[3];
    uint8_t  attrib;                      /* DOS_ATTR_* bits */
    char     name[ULTIMATE_NAME_MAX + 1];
} ultimate_fileinfo;

/* By name, in the current directory or by path. */
uint8_t ultimate_stat(const char *name, ultimate_fileinfo *info);

/* The same, for the file ultimate_open() left open. */
uint8_t ultimate_fstat(ultimate_fileinfo *info);

/*
 * Rename or copy, both names in the current directory unless they carry a path.
 * The Ultimate does the copying, so no bytes pass through the C64.
 */
uint8_t ultimate_rename(const char *from, const char *to);
uint8_t ultimate_copy(const char *from, const char *to);

/* Make one directory, in the current one. */
uint8_t ultimate_mkdir(const char *name);

/*
 * Change to the Ultimate's configured home directory. Firmware without one
 * answers ULTIMATE_ERR_NOT_SUPPORTED.
 */
uint8_t ultimate_home(void);

/*
 * Disk images, in the emulated drives.
 *
 * **The drive is named by the IEC device number it answers as** - 8, 9, and so
 * on - not by a slot. ULTIMATE_DRIVE_LAST asks for the drive that was mounted
 * into last, or drive A when nothing has been, which is what lets a program
 * work without knowing how its user configured the machine.
 * ultimate_drive_info() reports the numbers in use.
 *
 * A drive that is switched off is not there as far as these are concerned:
 * mounting into one answers ULTIMATE_ERR_DEVICE, and
 * ultimate_drive_enable() is what switches it on.
 *
 * The image type comes from the extension - .D64, .D71, .D81, .G64, .G71 - and
 * anything else is refused by the firmware.
 */
#define ULTIMATE_DRIVE_LAST 0

uint8_t ultimate_mount(uint8_t device, const char *image);
uint8_t ultimate_unmount(uint8_t device);

/* The next image of a multi-image set, the way the Ultimate's menu steps. */
uint8_t ultimate_swap(uint8_t device);

/*
 * The Ultimate's battery-backed clock.
 *
 * The time comes back as text, because that is what the firmware formats:
 * "2026/08/22 14:30:00", or the same with the weekday in front of it.
 * ULTIMATE_TIME_BUFFER is a buffer size that always fits. Nothing here parses
 * it back into numbers.
 *
 * Setting it takes numbers, and **the year is the year less 1900** - 2026 is
 * 126. That is the firmware's own encoding and the one field that is not what
 * it looks like.
 */
#define ULTIMATE_TIME_PLAIN   0
#define ULTIMATE_TIME_WEEKDAY 1
#define ULTIMATE_TIME_BUFFER  24

uint8_t ultimate_get_time(uint8_t format, char *buf, uint16_t buflen,
                          uint16_t *outlen);
uint8_t ultimate_set_time(uint8_t year_1900, uint8_t month, uint8_t day,
                          uint8_t hour, uint8_t minute, uint8_t second);

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

/*
 * The expansion's size in 64K banks, or 0 when there is none.
 *
 *     128 KB = 2    1 MB = 16     8 MB = 128
 *     256 KB = 4    2 MB = 32    16 MB = 256
 *     512 KB = 8    4 MB = 64
 *
 * **Banks, not bytes, and a word rather than a byte.** 16 MB is 256 banks,
 * which will not fit a byte, and 65536 pages of 256, which will not fit a word
 * either - both compact units are one short at exactly the largest machine.
 * A bank count in a word reaches 4 GB with no boundary to trip over.
 *
 * Nothing in the protocol answers this, so it is measured: the expansion
 * aliases, and the first power-of-two boundary whose write comes back round to
 * offset zero is the size. Twelve bytes are saved and restored, so calling it
 * changes nothing. It costs one small DMA burst per boundary, eight at most,
 * each with the CPU halted - cheap enough at start-up and not worth caching.
 *
 * 16 MB is the ceiling whatever the machine has, because the REU address
 * registers are 24 bits. A machine with more RAM than that cannot reach the
 * rest through this interface.
 */
uint16_t ultimate_reu_size(void);
uint8_t ultimate_reu_stash(uint16_t addr, uint32_t reuaddr, uint16_t len);
uint8_t ultimate_reu_fetch(uint16_t addr, uint32_t reuaddr, uint16_t len);
uint8_t ultimate_reu_load(uint32_t reuaddr, uint32_t len);
uint8_t ultimate_reu_save(uint32_t reuaddr, uint32_t len);

/* ---------------------------------------------------------------------------
 * The machine itself: reset, freeze, and the emulated drives.
 *
 * **ultimate_reboot() does not return.** It resets the C64, so the program that
 * called it stops existing part way through the call. Nothing after that line
 * runs.
 *
 * **ultimate_freeze() returns when a person lets it.** It is the freeze button:
 * the C64 stops, the Ultimate's menu appears, and the call returns after
 * whoever is at the keyboard leaves it. That can be minutes.
 *
 * The drive functions take ULTIMATE_DRIVE_A or ULTIMATE_DRIVE_B, which is a
 * physical drive - unlike ultimate_mount(), which takes the IEC device number
 * the drive answers as. The two are connected by ultimate_drive_info(), whose
 * records carry both.
 * ------------------------------------------------------------------------- */
#define ULTIMATE_DRIVE_A 0
#define ULTIMATE_DRIVE_B 1
#define ULTIMATE_DRIVES_MAX CTRL_DRVINFO_MAX      /* 2 */

typedef struct {
    uint8_t type;      /* CTRL_DRVTYPE_*: 1541, 1571, 1581, SoftwareIEC... */
    uint8_t device;    /* the IEC device number it answers as */
    uint8_t power;     /* 1 while the drive is running */
} ultimate_drive;

typedef struct {
    uint8_t        count;
    ultimate_drive drive[ULTIMATE_DRIVES_MAX];
} ultimate_drives;

uint8_t ultimate_reboot(void);
uint8_t ultimate_freeze(void);

/* Switch a drive on (non-zero) or off (zero). */
uint8_t ultimate_drive_enable(uint8_t drive, uint8_t on);

/* 1 in *on when that drive is running. on may not be NULL. */
uint8_t ultimate_drive_power(uint8_t drive, uint8_t *on);

/* Every drive the machine has, with the device number to mount into. */
uint8_t ultimate_drive_info(ultimate_drives *drives);

/*
 * The GEOS MegaPatch RAM disks: CTRL_RAMDISK_DRIVES records of a drive type
 * code and a size in 64K units, so info must have room for CTRL_RAMDISK_BYTES.
 * A type of zero is a slot with nothing in it.
 */
uint8_t ultimate_ramdisk_info(uint8_t *info);

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

/*
 * Write an interface's address, netmask and gateway: the same
 * UCI_NET_IPCONFIG_BYTES block ultimate_net_ipconfig() hands back.
 *
 * This changes the running configuration only - nothing is written to the
 * Ultimate's stored settings, and the machine is already on the network by the
 * time a C64 program runs. Neither the firmware nor the SDK checks the address
 * against anything else on the segment.
 */
uint8_t ultimate_net_setip(uint8_t iface, const uint8_t *ipconfig);
uint8_t ultimate_net_connect(const char *host, uint16_t port, uint8_t *handle);
uint8_t ultimate_net_udp(const char *host, uint16_t port, uint8_t *handle);
uint8_t ultimate_net_close(uint8_t handle);
uint8_t ultimate_net_read(uint8_t handle, uint8_t *buf, uint16_t bufsize,
                          uint16_t *got);
uint8_t ultimate_net_write(uint8_t handle, const uint8_t *buf, uint16_t len,
                           uint16_t *sent);

/* ---------------------------------------------------------------------------
 * HTTP.
 *
 * ultimate_http_get() is the whole of the common case: it creates the request,
 * runs it, and gives the firmware's slot back whether the exchange worked or
 * not. The firmware has a finite number of slots and a program that leaks them
 * in a loop is not told what went wrong, so prefer it to the three calls it
 * replaces.
 *
 *     uint16_t got;
 *     err = ultimate_http_get(url, buf, sizeof buf, &got);
 *     if (err == ULTIMATE_ERR_TRUNCATED)  // the page was bigger than buf
 *         ...got is what was kept, and the rest cannot be asked for...
 *     else if (err != ULTIMATE_OK)
 *         ...uci_last_device_code() is the server's status, or the firmware's...
 *
 * **ULTIMATE_OK means the server answered below 400.** A 404 or a 500 is
 * ULTIMATE_ERR_DEVICE with the number in uci_last_device_code() - the request
 * itself succeeded, and the body of the error page is in your buffer. This
 * needed a fix in the core to work at all: firmware 3.15 answers an exchange
 * with the response line ("HTTP/1.0 200 OK...") rather than with a status code,
 * and before uci_decode_status() knew that shape every successful request came
 * back as a device error. See docs/uci.md.
 *
 * **There is no continuation.** A reply larger than the buffer is truncated and
 * the rest is gone; nothing in the protocol offers a range or a second block.
 *
 * **An exchange is not bounded by the uci_set_timeout() budget**, for the same
 * reason ultimate_net_connect() is not: it contains a name lookup and a TCP
 * connect, and those can take tens of seconds. It waits, and restores the
 * caller's budget afterwards.
 *
 * **URLs are case sensitive and cc65 charmaps string literals**, turning source
 * 'a'-'z' into the bytes ASCII uses for 'A'-'Z'. A URL written as a plain C
 * literal arrives uppercased. Build it as bytes, or fold it back at runtime.
 *
 * The JSON body builder is not wrapped - thirteen commands for a machine with
 * 38K of BASIC - but a body built through uci_exec() can still be sent, by
 * passing its handle to ultimate_http_exchange(). Pass HTTP_BODY_NONE to send
 * no body at all.
 * ------------------------------------------------------------------------- */
uint8_t ultimate_http_get(const char *url, uint8_t *buf, uint16_t bufsize,
                          uint16_t *got);
uint8_t ultimate_http_open(uint8_t verb, const char *url, uint8_t *handle);
uint8_t ultimate_http_header(uint8_t handle, const char *line);
uint8_t ultimate_http_exchange(uint8_t handle, uint8_t body, uint8_t *buf,
                               uint16_t bufsize, uint16_t *got);
uint8_t ultimate_http_close(uint8_t handle);
uint8_t ultimate_http_free_all(void);

/* ---------------------------------------------------------------------------
 * HTTP request bodies: JSON, form encoding, or raw bytes.
 *
 * The body is built inside the Ultimate rather than in C64 memory. Create a
 * slot, add to it one call at a time, and hand its handle to
 * ultimate_http_exchange(); only one key and one value are ever in C64 memory
 * at once, which is what makes a 38K machine able to post an object bigger than
 * it could hold.
 *
 *     uint8_t body, req;
 *     uint16_t got;
 *
 *     ultimate_http_body(HTTP_BODY_JSON_OBJECT, &body);
 *     ultimate_http_body_string(body, key, value);
 *     ultimate_http_body_int(body, count, 3);
 *     ultimate_http_open(HTTP_VERB_POST, url, &req);
 *     ultimate_http_exchange(req, body, buf, sizeof buf, &got);
 *     ultimate_http_body_free(body);
 *     ultimate_http_close(req);
 *
 * **The firmware has sixteen slots for the whole machine** and a crashed
 * program returns none of them. Free what you create, or call
 * ultimate_http_free_all(), which takes back headers and bodies together.
 *
 * **Adding an object or an array enters it**: keys added afterwards go inside,
 * until ultimate_http_body_up() steps back out to the parent.
 *
 * **A key is copied through a staging buffer** and is limited to
 * ULTIMATE_HTTP_KEY_MAX bytes; a longer one is ULTIMATE_ERR_INVALID_ARGUMENT
 * and never reaches the wire. Values are not limited by it, only by the command
 * queue. A string value is at most 255 bytes, which is the firmware's own
 * length byte.
 *
 * **A HTTP_BODY_BINARY body takes ultimate_http_body_binary() and nothing
 * else**, and the JSON and form formats take everything else. The firmware
 * answers the wrong combination with ULTIMATE_ERR_DEVICE.
 *
 * **cc65 charmaps string literals**, so a key or value written as a plain C
 * literal arrives with its case swapped, exactly as a URL does. Build them as
 * bytes, or fold them at runtime.
 * ------------------------------------------------------------------------- */
#define ULTIMATE_HTTP_KEY_MAX 34

uint8_t ultimate_http_body(uint8_t format, uint8_t *handle);
uint8_t ultimate_http_body_free(uint8_t handle);

/* Empty it, keeping the slot and its format. */
uint8_t ultimate_http_body_clear(uint8_t handle);

/* Leave the object or array being filled in, back to its parent. */
uint8_t ultimate_http_body_up(uint8_t handle);

uint8_t ultimate_http_body_int(uint8_t handle, const char *key, int32_t value);
uint8_t ultimate_http_body_bool(uint8_t handle, const char *key, uint8_t value);
uint8_t ultimate_http_body_string(uint8_t handle, const char *key,
                                  const char *value);

/* Add a container, and enter it. Inside an array the key is ignored. */
uint8_t ultimate_http_body_object(uint8_t handle, const char *key);
uint8_t ultimate_http_body_array(uint8_t handle, const char *key);

/* Append to a HTTP_BODY_BINARY body. Successive calls add to the end. */
uint8_t ultimate_http_body_binary(uint8_t handle, const uint8_t *data,
                                  uint16_t len);

/* A short, stable, English description of an ULTIMATE_* code. Never NULL. */
const char *ultimate_strerror(uint8_t err);

/* Raw status number from the last command; see uci_last_device_code(). */
#define ultimate_device_code() uci_last_device_code()

#ifdef __cplusplus
}
#endif

#endif /* ULTIMATE_H */
