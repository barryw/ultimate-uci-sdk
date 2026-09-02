/*
 * ucitest.c - the Ultimate SDK, on real hardware.
 *
 * Host tests prove the protocol logic. Emulator tests prove the compiled code
 * drives the registers correctly. This proves it against the machine the SDK
 * exists for, on whatever firmware that machine happens to be running.
 *
 * Output is TAP (Test Anything Protocol): a human can read it off the screen,
 * and a harness can parse it without guessing. The header lines carry the
 * hardware and firmware information a failure report needs.
 *
 *     # ultimate-sdk hardware tests
 *     # model=ULTIMATE 64 ident=$c9 targets=$001e
 *     ok 1 - signature-present
 *     not ok 3 - identify-dos1 (expected 0, got 2)
 *     ok 9 - get-model # skip no control target on this firmware
 *     1..10
 *     # 9 passed, 1 failed, 1 skipped
 *
 * Build:  make
 * Run:    load and run it on an Ultimate with the command interface enabled.
 *
 * SPDX-License-Identifier: MIT
 */

#include <stdio.h>
#include <string.h>
#include <ultimate.h>

#include "cycles.h"

static uint8_t test_no;
static uint8_t passed;
static uint8_t failed;
static uint8_t skipped;

static void ok(const char *name)
{
    ++test_no;
    ++passed;
    printf("ok %u - %s\n", test_no, name);
}

static void not_ok(const char *name, int expected, int actual)
{
    ++test_no;
    ++failed;
    printf("not ok %u - %s (expected %d, got %d)\n", test_no, name, expected, actual);
}

static void skip(const char *name, const char *why)
{
    ++test_no;
    ++skipped;
    /*
     * "skip", not "SKIP". The TAP directive is case-insensitive, and cc65
     * charmaps uppercase source letters to PETSCII $C1-$DA, which CHROUT draws
     * as graphics symbols. Nothing parses this text anyway - hwtest.py reads
     * the result block at $033C by DMA - but a human reads it off the screen.
     */
    printf("ok %u - %s # skip %s\n", test_no, name, why);
}

static void check(const char *name, int expected, int actual)
{
    if (expected == actual)
        ok(name);
    else
        not_ok(name, expected, actual);
}

/* ------------------------------------------------------------------------ */

static char scratch[64];
static ultimate_capabilities caps;

/* ---------------------------------------------------------------------------
 * The network fixtures.
 *
 * **The socket round trip needs a peer, and this file will not invent one.**
 * An earlier version connected to the Ultimate's own web server, on the theory
 * that a machine can always reach itself. It hung: the run never returned from
 * the connect, and the firmware was still busy long enough afterwards to fail
 * the three scenarios that followed. Whether a self-connect is refused,
 * dropped, or merely slower than the harness waits was never established - the
 * bench machine went off the network before the probe that would have settled
 * it could run.
 *
 * So the peer is supplied from outside, or the socket checks skip:
 *
 *     make -C tests/hardware NET_PEER=192.168.1.242:6464
 *
 * with something at the far end that accepts a connection and sends a byte.
 * **A dotted quad, not a name**: cc65 charmaps source characters into PETSCII,
 * and digits and '.' survive that unchanged where letters do not.
 *
 * Everything that needs no peer - the interface count, the addresses, and the
 * argument checks that never reach the wire - always runs, and is what the
 * harness asserts on.
 * ------------------------------------------------------------------------ */
static uint8_t net_buf[288];
static uint8_t net_ip[UCI_NET_IPCONFIG_BYTES];
static uint8_t net_mac[UCI_NET_MACADDR_BYTES];

#ifdef HTTP_PEER_HOST
/* A request header the caller adds. Lowercase source is ASCII uppercase on the
   wire, which is a perfectly good header name and value. */
static const char http_hdr[] = "x-from: c64";

/* Built at runtime rather than written as a literal: the URL has to be real
   lowercase ASCII and cc65 charmaps a literal into the uppercase range. The
   peer has to answer 200 with a non-empty body at /hello and 404 at /nope. */
static char http_url[64];

static void build_url(const char *path)
{
    static const char host[] = HTTP_PEER_HOST;
    uint16_t port = HTTP_PEER_PORT;
    char *w = http_url;
    const char *r;
    uint8_t started = 0;
    uint16_t div;

    for (r = "http://"; *r; ++r) *w++ = *r;
    for (r = host; *r; ++r)      *w++ = *r;
    *w++ = 0x3A;                                    /* ':' */
    for (div = 10000; div; div /= 10) {
        uint8_t d = (uint8_t)((port / div) % 10);
        if (d || started || div == 1) { *w++ = (char)(0x30 + d); started = 1; }
    }
    for (r = path; *r; ++r) *w++ = *r;
    *w = 0;
    /* Source lowercase became ASCII uppercase on the way in; put it back. */
    for (w = http_url; *w; ++w)
        if ((uint8_t)*w >= 0x41 && (uint8_t)*w <= 0x5A)
            *w = (char)(*w + 0x20);
}
#endif

#ifdef NET_PEER_HOST
static const char net_peer[] = NET_PEER_HOST;

/* Something to say to a peer that waits to be spoken to. Bytes rather than a
   literal, because the charmap would rewrite it. */
static const uint8_t net_hello[] = { 0x68, 0x69, 0x0D, 0x0A };  /* "hi" CRLF */
#endif

/*
 * A fixed amount of CPU work, measured in 256ths of a raster frame.
 *
 * This is how "did turbo actually do anything?" gets answered. Setting $D031
 * and reading it back proves only that a register remembers what was written
 * to it - the machine has to be seen doing more work between two raster lines.
 *
 * The loop touches RAM and nothing else on purpose. The Ultimate 64 keeps I/O
 * at the stock rate under turbo so that timing-sensitive code keeps working, so
 * a loop that poked the VIC or a CIA would measure the part that deliberately
 * did not speed up.
 *
 * Both halves come off the same counter - see cycles.h - so this is a ratio,
 * and it does not matter whether turbo speeds the CPU up relative to the CIA or
 * slows the CIA down relative to the CPU.
 */
#define WORK_ITERATIONS 2000
#define WORK_UNITS      256

static volatile uint8_t sink;

static uint16_t work_per_frame(void)
{
    uint16_t i;
    uint32_t work, frame;

    __asm__("sei");
    timer_start();
    for (i = 0; i < WORK_ITERATIONS; ++i)
        sink = (uint8_t)i;
    work = cycles_net(timer_stop());
    __asm__("cli");

    frame = cycles_frame();
    if (frame == 0)
        return 0;
    return (uint16_t)((work * WORK_UNITS) / frame);
}
/*
 * Somewhere to load into that is neither the program nor its data. $C000 is the
 * 4K block a cc65 .prg never touches, and this test never runs the bytes it
 * puts there - it only looks at them.
 */
#define LOAD_TEST_ADDR 0xC000

/*
 * "/Usb1/data/hello.txt", as bytes.
 *
 * A filename goes on the wire, so it is protocol and not display text: cc65
 * would charmap a literal, and 'd' would leave here as $44 - ASCII 'D'. FAT
 * lookup is case-insensitive, so a charmapped name happens to work, which is
 * exactly the sort of accident that stops being true on the first filesystem
 * that cares. See docs/handover.md section 2.
 */
static const char hello_path[] = {
    0x2F, 0x55, 0x73, 0x62, 0x31, 0x2F,         /* /Usb1/ - absolute, because
                                                   the DOS target's current
                                                   directory is whatever the
                                                   last thing to touch it left
                                                   behind */
    0x64, 0x61, 0x74, 0x61, 0x2F,               /* data/  */
    0x68, 0x65, 0x6C, 0x6C, 0x6F,               /* hello  */
    0x2E, 0x74, 0x78, 0x74, 0x00                /* .txt   */
};

/*
 * The scratch file the write tests make, use and take away again. Numeric for
 * the same reason hello_path is: what goes on the wire is bytes, and cc65 would
 * charmap a string literal into PETSCII on its way there.
 *
 * **It goes on /Temp, not on the USB stick.** /Temp is a FAT filesystem the
 * firmware formats in RAM at boot - software/filesystem/ramdisk.cc - so a test
 * writing there cannot fill somebody's medium, cannot wear flash, and cannot
 * survive a power cycle even if this program dies halfway through. The bench
 * machine's stick is full of firmware images, which is its owner's business;
 * this needs somewhere to write, not somewhere in particular.
 */
static const char scratch_path[] = {
    0x2F, 0x54, 0x65, 0x6D, 0x70, 0x2F,         /* /Temp/ */
    0x77, 0x72, 0x2E, 0x74, 0x6D, 0x70, 0x00    /* wr.tmp */
};


/*
 * The files and the directory the DOS tests below make, use, and take away
 * again. All on /Temp, for the reason scratch_path is, and all written out as
 * bytes because cc65 charmaps a string literal into PETSCII on its way to the
 * wire.
 */
static const char stat_src[] = {
    0x2F, 0x54, 0x65, 0x6D, 0x70, 0x2F,         /* /Temp/ */
    0x73, 0x74, 0x31, 0x2E, 0x74, 0x6D, 0x70, 0x00      /* st1.tmp */
};
static const char stat_dst[] = {
    0x2F, 0x54, 0x65, 0x6D, 0x70, 0x2F,
    0x73, 0x74, 0x32, 0x2E, 0x74, 0x6D, 0x70, 0x00      /* st2.tmp */
};
static const char stat_ren[] = {
    0x2F, 0x54, 0x65, 0x6D, 0x70, 0x2F,
    0x73, 0x74, 0x33, 0x2E, 0x74, 0x6D, 0x70, 0x00      /* st3.tmp */
};
static const char temp_subdir[] = {
    0x2F, 0x54, 0x65, 0x6D, 0x70, 0x2F,
    0x73, 0x75, 0x62, 0x2E, 0x74, 0x6D, 0x70, 0x00      /* sub.tmp */
};

static ultimate_fileinfo finfo;
static ultimate_drives drives;
static uint8_t ramdisks[CTRL_RAMDISK_BYTES];
static char timebuf[ULTIMATE_TIME_BUFFER];
static char timebuf2[ULTIMATE_TIME_BUFFER];

/*
 * An IEC device number no drive answers as. The disk image commands are
 * checked against it on purpose: the firmware looks the drive up, finds
 * nothing, and answers "88,DRIVE NOT PRESENT", which proves the command and
 * its argument reached the target without mounting, unmounting or swapping
 * anything on the machine running the test.
 */
#define NO_SUCH_DRIVE 3

/* Two digits at a fixed offset, as a number, or -1 when they are not digits. */
static int two_digits(const char *at)
{
    if (at[0] < 0x30 || at[0] > 0x39 || at[1] < 0x30 || at[1] > 0x39)
        return -1;
    return (at[0] - 0x30) * 10 + (at[1] - 0x30);
}

/* What was in the expansion before the REU tests, and what they put there. */
static uint8_t reu_before[32];
static uint8_t reu_work[32];

static uint8_t saved[UCI_PALETTE_BYTES];
static uint8_t readback[UCI_PALETTE_BYTES];
static ultimate_sid_info sid_info;

/*
 * Machine-readable result block, for a host driver that reads memory over the
 * Ultimate's REST API instead of squinting at the screen.
 *
 * It lives in the cassette buffer: 192 free bytes that neither BASIC nor cc65
 * touches, and that the KERNAL's reset routine clears - so a stale block from a
 * previous run can never be mistaken for this one.
 *
 *   +0  magic "UCIT"        +6  passed        +10 targets low
 *   +4  format version      +7  failed        +11 targets high
 *   +5  tests run           +8  skipped       +12 $A5 once main() is done
 *                           +9  ident         +13 1 when the turbo checks ran
 *
 * The done marker is written last, after every other field, so a driver that
 * polls for it and then reads the rest can never catch a half-written block.
 */
#define RESULT_BLOCK  ((uint8_t *)0x033C)
#define RESULT_FORMAT 5
#define RESULT_DONE   0xA5

static uint8_t turbo_ran;
static uint8_t net_ran;
static uint8_t net_sock_ran;
static uint8_t http_ran;
static uint16_t reu_banks;
static uint8_t reu_probe_clean;
static uint8_t sid_physical_count;
static uint16_t sid_physical_address[2];
static uint8_t audio_ran;
static uint8_t audio_version;

static void publish(void)
{
    RESULT_BLOCK[0]  = 0x55;            /* 'U' - written as bytes, not a */
    RESULT_BLOCK[1]  = 0x43;            /* 'C'   literal, so no charmap  */
    RESULT_BLOCK[2]  = 0x49;            /* 'I'   can rewrite it          */
    RESULT_BLOCK[3]  = 0x54;            /* 'T' */
    RESULT_BLOCK[4]  = RESULT_FORMAT;
    RESULT_BLOCK[5]  = test_no;
    RESULT_BLOCK[6]  = passed;
    RESULT_BLOCK[7]  = failed;
    RESULT_BLOCK[8]  = skipped;
    RESULT_BLOCK[9]  = caps.ident;
    RESULT_BLOCK[10] = (uint8_t)caps.targets;
    RESULT_BLOCK[11] = (uint8_t)(caps.targets >> 8);
    RESULT_BLOCK[13] = turbo_ran;
    /* Format 3 and later: whether the network checks ran rather than skipped,
       and separately whether a socket really carried bytes - which needs a peer
       this file is handed rather than one it assumes exists. */
    RESULT_BLOCK[14] = net_ran;
    RESULT_BLOCK[15] = net_sock_ran;
    RESULT_BLOCK[16] = http_ran;
    /* The expansion's measured size, so the harness can check it against the
       size it configured rather than against a number this file invents. */
    RESULT_BLOCK[17] = (uint8_t)reu_banks;
    RESULT_BLOCK[18] = (uint8_t)(reu_banks >> 8);
    RESULT_BLOCK[19] = reu_probe_clean;
    /* Format 4: the physical socket records, for comparison with the settings
       REST endpoint by the host harness. */
    RESULT_BLOCK[20] = sid_info.count;
    RESULT_BLOCK[21] = sid_physical_count;
    RESULT_BLOCK[22] = (uint8_t)sid_physical_address[0];
    RESULT_BLOCK[23] = (uint8_t)(sid_physical_address[0] >> 8);
    RESULT_BLOCK[24] = (uint8_t)sid_physical_address[1];
    RESULT_BLOCK[25] = (uint8_t)(sid_physical_address[1] >> 8);
    /* Format 5: whether the mapped PCM engine completed a real sample. */
    RESULT_BLOCK[26] = audio_ran;
    RESULT_BLOCK[27] = audio_version;
    RESULT_BLOCK[12] = RESULT_DONE;     /* last, always */
}

/*
 * The Ultimate speaks ASCII. Target identification strings are uppercase and
 * print as-is, but the model name from CTRL_CMD_GET_HWINFO is mixed case
 * ("Ultimate 64 Elite"), and the C64's default character set renders lowercase
 * ASCII as graphics glyphs. Fold it before printing.
 *
 * The bounds are written as numbers on purpose: cc65 translates character
 * constants into the target character set, so 'a' here would compile to $41,
 * not $61. See docs/api-design.md.
 */
#define ASCII_LOWER_A 0x61
#define ASCII_LOWER_Z 0x7A

static void ascii_upper(char *s)
{
    while (*s != '\0') {
        if ((uint8_t)*s >= ASCII_LOWER_A && (uint8_t)*s <= ASCII_LOWER_Z)
            *s = (char)(*s - 0x20);
        ++s;
    }
}

int main(void)
{
    uci_request  req;
    uint8_t      data[16];
    uint8_t      err;
    uint16_t     len;
    static const uint8_t echo_args[] = { 0xDE, 0xAD, 0xBE, 0xEF };

    printf("# ultimate-sdk hardware tests\n");

    /* 1: is anything there at all? */
    if (uci_signature_present()) {
        ok("signature-present");
    } else {
        not_ok("signature-present", 1, 0);
        printf("1..1\n# no command interface found.\n");
        printf("# enable it in the ultimate settings menu.\n");
        publish();
        return 1;
    }

    /* 2: bring-up, including recovery from whatever ran before us. */
    err = ultimate_init();
    check("init", ULTIMATE_OK, err);
    if (err != ULTIMATE_OK) {
        printf("1..2\n# transport unusable, stopping.\n");
        publish();
        return 1;
    }

    /*
     * The very first command after init has to get its own reply. uci_init
     * recovers the interface with an abort, and the firmware services that
     * abort with a reset that rewinds the command queue; before uci_abort
     * waited for the abort flag to clear, a command pushed in that window was
     * wiped and answered with an empty block, ULTIMATE_ERR_PROTOCOL to the
     * caller. So the first thing sent is a command with a known, non-OK
     * answer, and it must come back as exactly that.
     */
    memset(&req, 0, sizeof(req));
    req.target  = UCI_TARGET_DOS1;
    req.command = 0x7E;                  /* no DOS firmware implements this */
    err = uci_exec(&req);
    check("first-command-after-init", ULTIMATE_ERR_NOT_SUPPORTED, err);

    ultimate_detect(&caps);
    printf("# ident=$%02x targets=$%04x\n", caps.ident, caps.targets);

    if (ultimate_get_model(scratch, sizeof(scratch), NULL) == ULTIMATE_OK) {
        ascii_upper(scratch);
        printf("# model=%s\n", scratch);
    }

    /* 3: the DOS target exists on every firmware that has a UCI at all. */
    err = ultimate_identify(UCI_TARGET_DOS1, scratch, sizeof(scratch), &len);
    if (err == ULTIMATE_OK && len > 0) {
        printf("# dos=%s\n", scratch);
        ok("identify-dos1");
    } else {
        not_ok("identify-dos1", ULTIMATE_OK, err);
    }

    /* 4: capability probing must recognise a target that is not there. */
    err = ultimate_identify(0x07, scratch, sizeof(scratch), &len);
    check("identify-absent-target", ULTIMATE_ERR_NOT_SUPPORTED, err);

    /* 5: and it must leave the caller's buffer empty rather than "NO TARGET". */
    check("absent-target-buffer-empty", 0, (int)len);

    /* 6: detection agrees with itself. */
    check("detect-present", 1, caps.present);
    check("detect-has-dos", 1, ultimate_has_dos(&caps));

    /* The count and every record are received in one call. The host harness
       independently reads the two configured socket addresses over REST and
       compares them with the physical records published above. */
    if (!ultimate_has_control(&caps)) {
        skip("legacy-sid-info", "no control target on this firmware");
    } else {
        uint8_t i;
        err = ultimate_legacy_get_sid_info(&sid_info);
        check("legacy-sid-info", ULTIMATE_OK, err);
        if (err == ULTIMATE_OK) {
            for (i = 0; i < sid_info.count; ++i) {
                uint8_t kind = (uint8_t)(sid_info.sid[i].type & 0x7F);
                printf("# sid %u primary=$%04x secondary=$%04x type=$%02x\n",
                       (uint8_t)(i + 1), sid_info.sid[i].primary_address,
                       sid_info.sid[i].secondary_address, sid_info.sid[i].type);
                if ((kind == 4 || kind == 5) && sid_physical_count < 2) {
                    sid_physical_address[sid_physical_count] =
                        sid_info.sid[i].primary_address;
                    ++sid_physical_count;
                }
            }
        }
    }

    /*
     * Command framing, end to end. ECHO hands back the exact bytes the
     * Ultimate received, so a mismatch here means the command never made it
     * onto the wire the way we wrote it.
     */
    memset(&req, 0, sizeof(req));
    req.target  = UCI_TARGET_DOS1;
    req.command = DOS_CMD_ECHO;
    req.args    = echo_args;
    req.arglen  = sizeof(echo_args);
    req.data    = data;
    req.datamax = sizeof(data);
    err = uci_exec(&req);
    if (err == ULTIMATE_OK && req.datalen >= 6 &&
        data[0] == UCI_TARGET_DOS1 && data[1] == DOS_CMD_ECHO &&
        data[2] == 0xDE && data[3] == 0xAD && data[4] == 0xBE && data[5] == 0xEF) {
        ok("echo-round-trip");
    } else {
        not_ok("echo-round-trip", ULTIMATE_OK, err);
    }

    /* 9: an unknown command is reported as unsupported, not as success. */
    memset(&req, 0, sizeof(req));
    req.target  = UCI_TARGET_DOS1;
    req.command = 0x7E;                  /* no DOS firmware implements this */
    err = uci_exec(&req);
    check("unknown-command", ULTIMATE_ERR_NOT_SUPPORTED, err);

    /* 10: a reply that does not fit is reported, and the transport survives. */
    memset(&req, 0, sizeof(req));
    req.target  = UCI_TARGET_DOS1;
    req.command = DOS_CMD_ECHO;
    req.args    = echo_args;
    req.arglen  = sizeof(echo_args);
    req.data    = data;
    req.datamax = 3;
    err = uci_exec(&req);
    check("truncation-reported", ULTIMATE_ERR_TRUNCATED, err);

    /* 11: ...and the next command still works, which is the real point. */
    err = ultimate_identify(UCI_TARGET_DOS1, scratch, sizeof(scratch), NULL);
    check("recovers-after-truncation", ULTIMATE_OK, err);

    /* 12: argument checking happens before anything reaches the hardware. */
    memset(&req, 0, sizeof(req));
    req.target  = 0x00;
    req.command = UCI_CMD_IDENTIFY;
    check("rejects-target-zero", ULTIMATE_ERR_INVALID_ARGUMENT, uci_exec(&req));

    /* 13: the control target is firmware-dependent, so its absence is not a failure. */
    if (ultimate_has_control(&caps)) {
        err = ultimate_identify(UCI_TARGET_CONTROL, scratch, sizeof(scratch), &len);
        check("identify-control", ULTIMATE_OK, err);
    } else {
        skip("identify-control", "no control target on this firmware");
    }

    /*
     * 14-19: the palette. The simulator does not implement these four commands
     * at all - they are newer than firmware 3.15 - so this is the only place
     * they run.
     *
     * Not destructive, by construction. The live palette is read first and
     * written back last, so the machine ends exactly as it started; the only
     * window where it differs is the few milliseconds between the probe write
     * and the restore. Nothing goes near flash or a VPL file: these commands
     * change the running palette only, and a power cycle would undo them even
     * if this program died halfway through.
     *
     * The probe write is the point. Reading the palette and writing back the
     * same bytes proves nothing - it passes whether or not the write works - so
     * one colour is changed to a value it demonstrably did not have, read back,
     * and only then restored.
     */
    if (!ultimate_has_control(&caps)) {
        skip("palette-get", "no control target on this firmware");
    } else {
        err = ultimate_palette_get(saved);
        if (err == ULTIMATE_ERR_NOT_SUPPORTED) {
            skip("palette-get", "palette commands need firmware after 3.15");
        } else {
            uint8_t probe;

            check("palette-get", ULTIMATE_OK, err);

            /* colour 15's red component, inverted: certainly not what it was */
            probe = (uint8_t)(saved[45] ^ 0xFF);
            check("palette-set-color", ULTIMATE_OK,
                  ultimate_palette_set_color(15, probe, saved[46], saved[47]));

            check("palette-get-after-set", ULTIMATE_OK,
                  ultimate_palette_get(readback));
            check("palette-color-took-effect", (int)probe, (int)readback[45]);

            check("palette-reset", ULTIMATE_OK, ultimate_palette_reset());

            /* and put the machine's own palette back, which is also the test */
            check("palette-set", ULTIMATE_OK, ultimate_palette_set(saved));
            ultimate_palette_get(readback);
            check("palette-restored", 0,
                  memcmp(saved, readback, UCI_PALETTE_BYTES));
        }
    }

    /* 20: an index past the sixteenth colour never reaches the wire. */
    check("palette-rejects-bad-index", ULTIMATE_ERR_INVALID_ARGUMENT,
          ultimate_palette_set_color(16, 0, 0, 0));

    /*
     * 21-27: turbo. Not a UCI command - there is none - so this is the SDK's
     * only hardware-register service, and the only one whose whole point is a
     * thing a register readback cannot show.
     *
     * It runs only when the machine's owner has set "Turbo Control" to
     * "U64 Turbo Registers". A program cannot set that for itself, which is the
     * whole reason ultimate_turbo_available() exists, so skipping here is a
     * normal outcome and not a gap. hwtest.py has a scenario that switches the
     * setting on, runs this, and puts it back.
     */
    if (!ultimate_turbo_available()) {
        skip("turbo-speed-changes", "turbo control is off in the ultimate settings");
    } else {
        uint8_t  entry = ultimate_turbo_get();
        uint16_t slow, fast, nobad;

        turbo_ran = 1;
        cycles_calibrate();     /* before the first work_per_frame(), or the
                                   timer's own cost is never subtracted */
        check("turbo-set-1mhz", ULTIMATE_OK, ultimate_turbo_set(U64_SPEED_1MHZ));
        check("turbo-get-1mhz", U64_SPEED_1MHZ, ultimate_turbo_get());
        slow = work_per_frame();

        check("turbo-set-4mhz", ULTIMATE_OK, ultimate_turbo_set(U64_SPEED_4MHZ));
        check("turbo-get-4mhz", U64_SPEED_4MHZ, ultimate_turbo_get());
        fast = work_per_frame();

        printf("# work/frame: %u at 1mhz, %u at 4mhz\n", slow, fast);
        /* four times the clock; two times the work is the honest floor. */
        check("turbo-speed-changes", 1,
              (fast != 0 && (slow / fast) >= 2) ? 1 : 0);

        /*
         * Badlines off is the other half of the register, and the half that is
         * worth having at 1MHz too: the VIC steals around 43 cycles on each of
         * 25 character rows, which is about 6% of a frame. The threshold is 3%,
         * comfortably above the 2% this measurement moves by between runs.
         */
        ultimate_turbo_set(U64_SPEED_1MHZ);
        check("badlines-off", ULTIMATE_OK, ultimate_turbo_badlines(0));
        nobad = work_per_frame();
        check("badlines-on", ULTIMATE_OK, ultimate_turbo_badlines(1));

        printf("# work/frame: %u with badlines, %u without\n", slow, nobad);
        check("badlines-off-is-faster", 1,
              (nobad != 0 && nobad <= slow - (slow / 32)) ? 1 : 0);

        /*
         * And the same race at full speed, where a push follows the abort
         * within microseconds: re-init at the top speed index and send the
         * rejected command first again.
         */
        ultimate_turbo_set(U64_SPEED_MAX);
        check("init-at-max-turbo", ULTIMATE_OK, ultimate_init());
        memset(&req, 0, sizeof(req));
        req.target  = UCI_TARGET_DOS1;
        req.command = 0x7E;
        check("first-command-after-init-at-max-turbo",
              ULTIMATE_ERR_NOT_SUPPORTED, uci_exec(&req));

        /* Put the machine back at the speed it was found at. */
        ultimate_turbo_set(entry);
    }

    /*
     * 28-31: the fast load path, which only exists on real hardware. u64sim has
     * no SoftwareIEC target at all, so the emulator suite always exercises the
     * DOS fallback - the two halves of ultimate_load() are tested in different
     * places by necessity, and each is the only place its half runs.
     *
     * The fixture is pushed over FTP by the test data policy in
     * docs/handover.md section 6; if it is not there the load fails cleanly and
     * says so, which is itself the behaviour a program shipping to other people
     * depends on.
     */
    if (!ultimate_has_softiec(&caps)) {
        skip("load-fast-path", "no softwareiec target on this firmware");
    } else {
        uint8_t *at = (uint8_t *)LOAD_TEST_ADDR;

        at[0] = 0x00;
        err = ultimate_load(hello_path, LOAD_TEST_ADDR);
        if (err != ULTIMATE_OK) {
            skip("load-fast-path", "the fixture is not on the device");
        } else {
            check("load-fast-path", ULTIMATE_OK, err);
            /*
             * hello.txt is 28 bytes of "HELLO FROM THE U...". Two of them are
             * eaten as the PRG header whichever tier ran, so 26 land, and the
             * first stored byte is the third character.
             */
            check("load-end-address", LOAD_TEST_ADDR + 26,
                  (int)ultimate_last_end());
            check("load-wrote-the-file", 0x4C, (int)at[0]);  /* 'L' of HELLO */
        }

        /* Raw, with a limit: no header eaten, and not a byte past the cap. */
        at[0] = 0x00;
        err = ultimate_bload(hello_path, LOAD_TEST_ADDR, 8);
        if (err == ULTIMATE_OK) {
            check("bload-honours-its-limit", LOAD_TEST_ADDR + 8,
                  (int)ultimate_last_end());
            check("bload-strips-nothing", 0x48, (int)at[0]);  /* 'H' */
        } else {
            skip("bload-honours-its-limit", "the fixture is not on the device");
        }
    }

    /*
     * 32-40: the write half, against a real filesystem.
     *
     * Every byte this touches is a byte it made: the file is created here,
     * written, read back, and deleted, which is the test data policy in
     * docs/handover.md section 6. Nothing pre-existing on the device is opened
     * for writing at any point.
     *
     * The emulator suite runs the same sequence against u64sim's filesystem.
     * This is the one that runs it against FAT on a real USB stick, where a
     * create can fail for reasons a simulator has never heard of - no medium,
     * write protection, a full volume - and where failing cleanly is the
     * behaviour that matters.
     */
    err = ultimate_open(scratch_path,
                        DOS_FA_CREATE_ALWAYS | DOS_FA_WRITE | DOS_FA_READ);
    if (err != ULTIMATE_OK) {
        skip("write-creates-a-file", "no writable /usb1/data on this machine");
    } else {
        static const uint8_t written[] = { 0xDE, 0xAD, 0xBE, 0xEF };
        uint8_t back[4];

        ok("write-creates-a-file");

        /*
         * A write can still fail for a reason no test can fix - a full medium
         * answers "DISK IS FULL", which the SDK reports as
         * ULTIMATE_ERR_DEVICE - so that case skips and says so rather than
         * failing. On the RAM disk it does not happen, and anything else is a
         * real failure reported as one.
         */
        err = ultimate_write(written, sizeof(written));
        if (err == ULTIMATE_ERR_DEVICE) {
            skip("write-data", "the device refused the write: full, or read-only");
            ultimate_close();
            ultimate_delete(scratch_path);
            goto after_write;
        }
        check("write-data", ULTIMATE_OK, err);
        check("write-close", ULTIMATE_OK, ultimate_close());

        /* Reopen for reading, seek past the first two bytes, and read the rest.
           A read that ignored the seek would answer four bytes from $DE. */
        check("reopen-for-read", ULTIMATE_OK,
              ultimate_open(scratch_path, DOS_FA_READ));
        check("seek", ULTIMATE_OK, ultimate_seek(2));

        len = 0;
        back[0] = 0x00;
        check("read-after-seek", ULTIMATE_OK,
              ultimate_read(back, sizeof(back), &len));
        check("read-stops-at-the-end", 2, (int)len);
        check("seek-landed", 0xBE, (int)back[0]);
        ultimate_close();

        check("delete", ULTIMATE_OK, ultimate_delete(scratch_path));

        /*
         * And it is really gone - which is what makes the cleanup a test.
         * ULTIMATE_ERR_DEVICE exactly: the firmware answers a missing file with
         * "FILE DOESN'T EXIST", bare text with no code, and reading that as a
         * device error rather than a protocol one is the whole point.
         */
        err = ultimate_open(scratch_path, DOS_FA_READ);
        check("delete-removed-it", ULTIMATE_ERR_DEVICE, err);
        if (err == ULTIMATE_OK)
            ultimate_close();
    }
after_write:

    /*
     * Abandoning a directory walk, which is the ordinary way to reach the one
     * failure mode abort could not clear: the firmware holds a reply block
     * until it is released, does not service an abort while it holds one, and
     * leaves every later command timing out. The simulator reproduces it and
     * so does the real machine, which is why this runs in both places.
     */
    if (ultimate_opendir() != ULTIMATE_OK) {
        skip("abort-recovers-an-abandoned-walk", "no directory to walk here");
    } else {
        ultimate_readdir(scratch, sizeof(scratch), NULL);   /* one entry, then stop */
        check("abort-after-an-abandoned-walk", ULTIMATE_OK, uci_abort());
        check("abort-recovers-an-abandoned-walk", ULTIMATE_OK,
              ultimate_identify(UCI_TARGET_DOS1, scratch, sizeof(scratch), NULL));
    }

    /*
     * The RAM expansion, both halves of it: the DMA registers, which are the
     * only way to move bytes between C64 RAM and the expansion, and
     * DOS_CMD_LOAD_REU, which moves a file into it without the C64 seeing any
     * of them.
     *
     * Whether there is an expansion at all is the machine owner's setting, the
     * same as turbo, so skipping is a normal outcome. hwtest.py has a scenario
     * that switches it on.
     *
     * Not destructive: the 32 bytes at REU $000000 are read first and written
     * back last, so the expansion ends holding exactly what it held. The same
     * shape as the palette tests above, for the same reason.
     */
    if (!ultimate_reu_available()) {
        skip("reu-round-trip", "no ram expansion in the ultimate settings");
    } else {
        uint8_t i;

        check("reu-save-what-was-there", ULTIMATE_OK,
              ultimate_reu_fetch((uint16_t)reu_before, 0, sizeof(reu_before)));

        for (i = 0; i < 8; ++i)
            reu_work[i] = (uint8_t)(0xA0 + i);
        check("reu-stash", ULTIMATE_OK,
              ultimate_reu_stash((uint16_t)reu_work, 0, 8));

        /* Wipe it first, or a fetch that did nothing would still pass. */
        memset(reu_work, 0, sizeof(reu_work));
        check("reu-fetch", ULTIMATE_OK,
              ultimate_reu_fetch((uint16_t)reu_work, 0, 8));
        check("reu-round-trip", 0xA0, (int)reu_work[0]);
        check("reu-round-trip-end", 0xA7, (int)reu_work[7]);

        /*
         * And the file half. hello.txt is 28 bytes; LOAD_REU puts them in the
         * expansion with none of them passing through here, so reading them
         * back out is the only way to see that it worked.
         */
        if (ultimate_open(hello_path, DOS_FA_READ) != ULTIMATE_OK) {
            skip("reu-load-from-a-file", "the fixture is not on the device");
        } else {
            check("reu-load-from-a-file", ULTIMATE_OK,
                  ultimate_reu_load(0, 14));
            check("reu-load-continues-from-current-position", ULTIMATE_OK,
                  ultimate_reu_load(14, 14));
            ultimate_close();

            memset(reu_work, 0, sizeof(reu_work));
            ultimate_reu_fetch((uint16_t)reu_work, 0, 28);
            check("reu-load-really-moved-it", 0x48, (int)reu_work[0]);  /* 'H' */
        }

        /*
         * And out of the expansion into a file, which is the pair of the one
         * above. It writes to the RAM disk like every other mutating test
         * here, and reads it back to prove the bytes really left the
         * expansion - a status of OK on its own would pass for a save that
         * wrote nothing at all.
         */
        err = ultimate_open(scratch_path, DOS_FA_CREATE_ALWAYS | DOS_FA_WRITE);
        if (err != ULTIMATE_OK) {
            skip("reu-save-to-a-file", "no ram disk to write to on this firmware");
        } else {
            err = ultimate_reu_save(0, 8);
            ultimate_close();
            if (err == ULTIMATE_ERR_DEVICE) {
                skip("reu-save-to-a-file", "the device refused the write");
                ultimate_delete(scratch_path);
            } else {
                check("reu-save-to-a-file", ULTIMATE_OK, err);

                /*
                 * Read it back. A status of OK proves the command was accepted
                 * and nothing else: a save that wrote no bytes at all would
                 * pass on the status alone. The expansion holds hello.txt at
                 * this point, put there by LOAD_REU above, so the first eight
                 * bytes of the file are the first eight of "HELLO FROM...".
                 */
                memset(reu_work, 0, sizeof(reu_work));
                check("reu-save-reads-back", ULTIMATE_OK,
                      ultimate_bload(scratch_path, (uint16_t)reu_work, 8));
                check("reu-save-wrote-the-bytes", 0x48, (int)reu_work[0]);
                check("reu-save-wrote-all-of-them", 8,
                      (int)(ultimate_last_end() - (uint16_t)reu_work));

                check("reu-save-cleanup", ULTIMATE_OK,
                      ultimate_delete(scratch_path));
            }
        }

        /*
         * How big is it? Nothing in the protocol answers that, so the SDK
         * measures it - and the harness knows what it configured, so the two
         * are checked against each other rather than against a constant here.
         *
         * The probe writes twelve bytes and puts them back, so the bytes it
         * touched have to be unchanged afterwards. That is asserted rather
         * than assumed: a size probe that quietly corrupts offset zero would
         * pass every size check and still be wrong.
         */
        {
            uint8_t snap[16];
            uint8_t j;

            ultimate_reu_fetch((uint16_t)snap, 0, sizeof(snap));
            reu_banks = ultimate_reu_size();
            check("reu-size-is-not-zero", 1, reu_banks != 0 ? 1 : 0);
            /* Every legal size is a power of two from 2 banks to 256. */
            check("reu-size-is-a-power-of-two", 0,
                  (int)(reu_banks & (reu_banks - 1)));
            check("reu-size-is-in-range", 1,
                  (reu_banks >= 2 && reu_banks <= 256) ? 1 : 0);
            printf("# reu=%u banks (%uk)\n", reu_banks, reu_banks * 64);

            ultimate_reu_fetch((uint16_t)reu_work, 0, sizeof(snap));
            reu_probe_clean = 1;
            for (j = 0; j < sizeof(snap); ++j)
                if (snap[j] != reu_work[j])
                    reu_probe_clean = 0;
            check("reu-size-left-nothing-changed", 1, (int)reu_probe_clean);
        }

        /*
         * Ultimate Audio reads PCM from this same memory without CPU feeding.
         * Volume zero keeps the hardware test silent; the end flag proves the
         * sampler actually consumed all 32 bytes. When the owner has not
         * mapped the module, configure must fail cleanly and touch nothing.
         */
        {
            ultimate_audio_voice voice;
            uint16_t polls;
            uint8_t start_err;
            uint8_t clear_err;
            uint8_t stop_err;
            uint8_t ended;
            uint8_t cleared;

            memset(&voice, 0, sizeof(voice));
            voice.channel = 6;
            voice.flags = UA_CTRL_IRQ;
            voice.volume = 0;
            voice.pan = UA_PAN_CENTER;
            voice.reu_address = 0;
            voice.length = sizeof(reu_work);
            voice.rate = 2000;             /* 3.125 kHz, about 10 ms total */

            err = ultimate_audio_init();
            if (err != ULTIMATE_OK) {
                check("audio-disabled-init", ULTIMATE_ERR_NOT_SUPPORTED, err);
                check("audio-disabled-available", 0,
                      ultimate_audio_available());
                check("audio-disabled-fails-cleanly", ULTIMATE_ERR_NOT_SUPPORTED,
                      ultimate_audio_configure(&voice));
            } else {
                audio_ran = 1;
                audio_version = ultimate_audio_version();
                check("audio-init", ULTIMATE_OK, err);
                check("audio-available", 1, ultimate_audio_available());
                memset(reu_work, 0, sizeof(reu_work));
                check("audio-silent-sample-stashed", ULTIMATE_OK,
                      ultimate_reu_stash((uint16_t)reu_work, 0,
                                         sizeof(reu_work)));
                check("audio-configure", ULTIMATE_OK,
                      ultimate_audio_configure(&voice));
                __asm__("sei");
                start_err = ultimate_audio_start(voice.channel, voice.flags);
                for (polls = 0; polls != 0xFFFF; ++polls)
                    if (ultimate_audio_irq_status() & (1u << voice.channel))
                        break;
                ended = polls != 0xFFFF ? 1 : 0;
                clear_err = ultimate_audio_irq_clear(voice.channel);
                cleared = ultimate_audio_irq_status() & (1u << voice.channel);
                stop_err = ultimate_audio_stop(voice.channel);
                __asm__("cli");
                check("audio-start", ULTIMATE_OK, start_err);
                check("audio-reached-end", 1, ended);
                check("audio-clear", ULTIMATE_OK, clear_err);
                check("audio-end-cleared", 0, cleared);
                check("audio-stop", ULTIMATE_OK, stop_err);
            }
        }

        /* Put the expansion back exactly as it was found. */
        check("reu-restored", ULTIMATE_OK,
              ultimate_reu_stash((uint16_t)reu_before, 0, sizeof(reu_before)));
    }

    /* ------------------------------------------------------------------
     * The network target.
     *
     * u64sim implements none of these commands, so this file is the only place
     * they run at all. It is in two halves deliberately: the addresses and the
     * argument checks need nothing on the network and always run, and the
     * socket round trip needs a peer and skips without one. The fixtures at the
     * top of this file say why that split exists - it was not free.
     * ------------------------------------------------------------------ */

    /* ------------------------------------------------------------------
     * What a file is, and moving files about.
     *
     * The same rule as the write tests above: everything here is created on
     * /Temp, used, and deleted. big.bin-style fixtures are not needed - the
     * file this stats is one it wrote a moment earlier, so the size it checks
     * is a size it knows.
     * ------------------------------------------------------------------ */
    err = ultimate_open(stat_src,
                        DOS_FA_CREATE_ALWAYS | DOS_FA_WRITE | DOS_FA_READ);
    if (err != ULTIMATE_OK) {
        skip("stat", "no writable scratch area on this machine");
    } else {
        static const uint8_t four[] = { 0x01, 0x02, 0x03, 0x04 };

        ultimate_write(four, sizeof(four));
        ultimate_close();

        finfo.size = 0xFFFFFFFFUL;
        err = ultimate_stat(stat_src, &finfo);
        check("stat", ULTIMATE_OK, err);
        check("stat-reports-the-size", 4, (int)finfo.size);
        check("stat-is-not-a-directory", 0, finfo.attrib & DOS_ATTR_DIR);
        check("stat-terminated-the-name", 0x73, (int)finfo.name[0]);   /* 's' */

        check("fstat-opens", ULTIMATE_OK, ultimate_open(stat_src, DOS_FA_READ));
        finfo.size = 0xFFFFFFFFUL;
        check("fstat", ULTIMATE_OK, ultimate_fstat(&finfo));
        check("fstat-reports-the-size", 4, (int)finfo.size);
        ultimate_close();

        /*
         * The copy and the rename are what prove the <name> $00 <name> shape
         * survives the trip: the first name goes out with its own terminator
         * counted in the argument length, and a length one byte short makes
         * the firmware read the two names as one.
         */
        check("copy", ULTIMATE_OK, ultimate_copy(stat_src, stat_dst));
        finfo.size = 0xFFFFFFFFUL;
        check("copy-made-a-copy", ULTIMATE_OK, ultimate_stat(stat_dst, &finfo));
        check("copy-copied-the-bytes", 4, (int)finfo.size);

        check("rename", ULTIMATE_OK, ultimate_rename(stat_dst, stat_ren));
        check("rename-moved-it", ULTIMATE_OK, ultimate_stat(stat_ren, &finfo));
        check("rename-left-nothing-behind", ULTIMATE_ERR_DEVICE,
              ultimate_stat(stat_dst, &finfo));

        check("delete-the-copy", ULTIMATE_OK, ultimate_delete(stat_ren));
        check("delete-the-source", ULTIMATE_OK, ultimate_delete(stat_src));

        err = ultimate_mkdir(temp_subdir);
        check("mkdir", ULTIMATE_OK, err);
        if (err != ULTIMATE_OK) {
            skip("mkdir-made-a-directory", "the directory was not created");
            skip("mkdir-cleanup", "the directory was not created");
        } else {
            check("mkdir-made-a-directory", DOS_ATTR_DIR,
                  ultimate_stat(temp_subdir, &finfo) == ULTIMATE_OK
                      ? (finfo.attrib & DOS_ATTR_DIR) : 0);
            check("mkdir-cleanup", ULTIMATE_OK, ultimate_delete(temp_subdir));
        }
    }

    /*
     * The home directory is optional: firmware without one answers
     * "99,FUNCTION NOT IMPLEMENTED". Both results are correct, so the check is
     * that one of the two came back.
     */
    err = ultimate_home();
    if (err == ULTIMATE_OK || err == ULTIMATE_ERR_NOT_SUPPORTED)
        ok("home");
    else
        not_ok("home", ULTIMATE_OK, err);

    /* ------------------------------------------------------------------
     * Disk images.
     *
     * Against a device number no drive answers as, so the firmware answers
     * "88,DRIVE NOT PRESENT" and nothing on the machine is mounted, unmounted
     * or swapped. What is being checked is the command and its argument
     * reaching the target; what a successful mount does is not something a
     * test should do to somebody's running machine.
     * ------------------------------------------------------------------ */
    err = ultimate_mount(NO_SUCH_DRIVE, stat_src);
    if (err == ULTIMATE_ERR_NOT_SUPPORTED) {
        skip("mount-refuses-a-drive-that-is-not-there",
             "no disk image commands on this firmware");
        skip("unmount-refuses-a-drive-that-is-not-there",
             "no disk image commands on this firmware");
        skip("swap-refuses-a-drive-that-is-not-there",
             "no disk image commands on this firmware");
    } else {
        check("mount-refuses-a-drive-that-is-not-there",
              ULTIMATE_ERR_DEVICE, err);
        check("unmount-refuses-a-drive-that-is-not-there",
              ULTIMATE_ERR_DEVICE, ultimate_unmount(NO_SUCH_DRIVE));
        check("swap-refuses-a-drive-that-is-not-there",
              ULTIMATE_ERR_DEVICE, ultimate_swap(NO_SUCH_DRIVE));
    }

    /* ------------------------------------------------------------------
     * The clock.
     *
     * Read it, write back what was read, and read it again. The clock is the
     * machine owner's, so this puts back the time it found rather than a time
     * of its own; at most it loses the seconds that passed in between, and the
     * date is what the second read is checked against.
     * ------------------------------------------------------------------ */
    err = ultimate_get_time(ULTIMATE_TIME_PLAIN, timebuf, sizeof(timebuf), &len);
    if (err == ULTIMATE_ERR_NOT_SUPPORTED) {
        skip("get-time", "no clock commands on this firmware");
        skip("get-time-has-the-shape-of-a-date", "no clock commands");
        skip("set-time", "no clock commands");
        skip("set-time-kept-the-date", "no clock commands");
    } else {
        int year, month, day, hour, minute, second;

        check("get-time", ULTIMATE_OK, err);
        printf("# time=%s\n", timebuf);

        /* "YYYY/MM/DD HH:MM:SS" - nineteen bytes, and the separators are what
           say the fields are where the parse below expects them. */
        year   = two_digits(timebuf + 2);
        month  = two_digits(timebuf + 5);
        day    = two_digits(timebuf + 8);
        hour   = two_digits(timebuf + 11);
        minute = two_digits(timebuf + 14);
        second = two_digits(timebuf + 17);
        check("get-time-has-the-shape-of-a-date", 1,
              (len == 19 && timebuf[4] == 0x2F && timebuf[7] == 0x2F &&
               timebuf[10] == 0x20 && timebuf[13] == 0x3A &&
               timebuf[16] == 0x3A && year >= 0 && month >= 1 && month <= 12 &&
               day >= 1 && day <= 31 && hour >= 0 && minute >= 0 &&
               second >= 0) ? 1 : 0);

        if (year < 0 || month < 0 || day < 0 ||
            hour < 0 || minute < 0 || second < 0) {
            skip("set-time", "the clock did not read back as a date");
            skip("set-time-kept-the-date", "the clock did not read back as a date");
        } else {
            /* The year byte is the year less 1900, and timebuf holds the last
               two digits of a year the firmware prints as 19xx or 20xx. */
            uint8_t y1900 = (uint8_t)(timebuf[2] == 0x31 ? year : year + 100);

            check("set-time", ULTIMATE_OK,
                  ultimate_set_time(y1900, (uint8_t)month, (uint8_t)day,
                                    (uint8_t)hour, (uint8_t)minute,
                                    (uint8_t)second));
            check("set-time-kept-the-date", ULTIMATE_OK,
                  ultimate_get_time(ULTIMATE_TIME_PLAIN, timebuf2,
                                    sizeof(timebuf2), NULL));
            check("set-time-kept-the-day", 0,
                  memcmp(timebuf, timebuf2, 10));
        }
    }

    /* ------------------------------------------------------------------
     * The emulated drives.
     *
     * Reading is free. The one write is ultimate_drive_enable() setting a
     * drive to the power state ultimate_drive_power() just reported, so the
     * command goes on the wire and the machine is left as it was found.
     *
     * ultimate_reboot() and ultimate_freeze() are never called here: the first
     * resets the machine part way through the run and the second stops it
     * until somebody leaves the Ultimate's menu. Both are exercised against
     * the simulated Ultimate in tests/emulator/sdk.suite instead.
     * ------------------------------------------------------------------ */
    skip("reboot", "it would reset the machine this test is running on");
    skip("freeze", "it would stop the machine until a person resumed it");

    drives.count = 0xFF;
    err = ultimate_drive_info(&drives);
    if (err == ULTIMATE_ERR_NOT_SUPPORTED) {
        skip("drive-info", "no drive commands on this firmware");
        skip("drive-info-counts-the-drives", "no drive commands");
        skip("drive-power", "no drive commands");
        skip("drive-enable", "no drive commands");
        skip("ramdisk-info", "no drive commands");
    } else {
        uint8_t on = 0xFF;

        uint8_t rec;

        check("drive-info", ULTIMATE_OK, err);

        /* The count includes the occupied IEC bus slots, not only drives A
         * and B, so this is up to ULTIMATE_DRIVES_MAX and not 2. Every record
         * is printed, because a machine running SoftwareIEC or an IEC printer
         * is where the count and the reply length disagree, and the run log is
         * where that shows. */
        check("drive-info-counts-the-drives", 1,
              drives.count <= ULTIMATE_DRIVES_MAX ? 1 : 0);
        for (rec = 0; rec < drives.count; rec++)
            printf("# record %u: drive=%u type=$%02x power=%u\n",
                   rec, drives.drive[rec].device, drives.drive[rec].type,
                   drives.drive[rec].power);

        check("drive-power", ULTIMATE_OK,
              ultimate_drive_power(ULTIMATE_DRIVE_A, &on));
        check("drive-power-is-a-flag", 1, on <= 1 ? 1 : 0);

        /* Back to the state it was already in, so nothing changes. */
        check("drive-enable", ULTIMATE_OK,
              ultimate_drive_enable(ULTIMATE_DRIVE_A, on));

        check("ramdisk-info", ULTIMATE_OK, ultimate_ramdisk_info(ramdisks));
    }

    check("drive-enable-rejects-a-third-drive", ULTIMATE_ERR_INVALID_ARGUMENT,
          ultimate_drive_enable(2, 1));

    if (!ultimate_has_network(&caps)) {
        skip("net-interfaces", "no network target on this firmware");
    } else {
        uint8_t  ifcount = 0;
        uint8_t  iface;
        uint8_t  live = 0xFF;
        uint16_t got;

        err = ultimate_net_ifcount(&ifcount);
        check("net-interfaces", ULTIMATE_OK, err);

        /*
         * Which interface is up is not a given: this machine reports two, and
         * on the bench one of them has a MAC and an all-zero address. A count
         * is not a list of usable interfaces, so find one with an address.
         */
        for (iface = 0; iface < ifcount && live == 0xFF; ++iface) {
            memset(net_ip, 0, sizeof(net_ip));
            if (ultimate_net_ipconfig(iface, net_ip) == ULTIMATE_OK &&
                (net_ip[0] | net_ip[1] | net_ip[2] | net_ip[3]) != 0)
                live = iface;
        }

        if (live == 0xFF) {
            skip("net-has-an-address", "no interface has an address");
        } else {
            net_ran = 1;
            ok("net-has-an-address");
            printf("# ip=%u.%u.%u.%u iface=%u of %u\n",
                   net_ip[0], net_ip[1], net_ip[2], net_ip[3], live, ifcount);

            check("net-macaddr", ULTIMATE_OK,
                  ultimate_net_macaddr(live, net_mac));
            /* All zeros is not a MAC, and would pass on the status alone. */
            check("net-macaddr-is-not-empty", 1,
                  (net_mac[0] | net_mac[1] | net_mac[2] |
                   net_mac[3] | net_mac[4] | net_mac[5]) != 0 ? 1 : 0);

            /* An interface the machine does not have is the firmware's own
               "82,PARAMETER(S) OUT OF RANGE", not something invented here. */
            check("net-bad-interface-is-refused", ULTIMATE_ERR_DEVICE,
                  ultimate_net_ipconfig(ifcount + 5, net_ip));

            /*
             * ultimate_net_setip() is checked on its argument and no further.
             * Writing an address to a live interface can take the machine off
             * the network - see docs/uci.md, "The network stack is fragile" -
             * and this test runs on somebody's machine over that network. The
             * command itself is covered against the simulated Ultimate in
             * tests/emulator/sdk.suite.
             */
            check("net-setip-rejects-a-null-block",
                  ULTIMATE_ERR_INVALID_ARGUMENT,
                  ultimate_net_setip(live, NULL));
            skip("net-setip", "it would reconfigure the interface this run uses");
        }

        /* Neither of these reaches the wire, so they run whatever the machine
           is plugged into. */
        check("net-read-refuses-a-null-buffer",
              ULTIMATE_ERR_INVALID_ARGUMENT,
              ultimate_net_read(0, (uint8_t *)0, sizeof(net_buf), &got));
        check("net-read-refuses-a-buffer-with-no-room",
              ULTIMATE_ERR_INVALID_ARGUMENT,
              ultimate_net_read(0, net_buf, UCI_NET_READ_PREFIX, &got));

#ifdef NET_PEER_HOST
        {
            uint8_t  handle = 0xFF;
            uint16_t sent = 0;
            uint16_t total;
            uint8_t  tries;

            printf("# peer=%s:%u\n", net_peer, (unsigned)NET_PEER_PORT);

            err = ultimate_net_connect(net_peer, NET_PEER_PORT, &handle);
            check("net-connect", ULTIMATE_OK, err);

            if (err != ULTIMATE_OK) {
                skip("net-write", "nothing connected");
            } else {
                net_sock_ran = 1;

                check("net-write", ULTIMATE_OK,
                      ultimate_net_write(handle, net_hello, sizeof(net_hello),
                                         &sent));
                check("net-write-took-all-of-it", (int)sizeof(net_hello),
                      (int)sent);

                /*
                 * **A read does not wait for the wire**, so this polls - and
                 * the polling is the behaviour being pinned rather than an
                 * accident of the test. The bound is small on purpose: an idle
                 * read costs about 42 ms and the harness gives the whole
                 * program about 26 seconds, so a generous-looking loop here is
                 * what times the run out.
                 */
                got = 0;
                for (tries = 0; tries < 40; ++tries) {
                    err = ultimate_net_read(handle, net_buf, sizeof(net_buf),
                                            &got);
                    if (err != ULTIMATE_OK || got != 0)
                        break;
                }
                check("net-read-gets-something-back", ULTIMATE_OK, err);
                check("net-read-returned-bytes", 1, got != 0 ? 1 : 0);

                /* Drain what is already buffered, bounded for the same reason. */
                total = got;
                for (tries = 0; tries < 40; ++tries) {
                    got = 0;
                    err = ultimate_net_read(handle, net_buf, sizeof(net_buf),
                                            &got);
                    if (err != ULTIMATE_OK)
                        break;
                    total += got;
                }
                printf("# read %u bytes, ended %u\n", total, err);

                /*
                 * ULTIMATE_END means the peer hung up and the handle is already
                 * gone, so closing it then is an error about a socket that no
                 * longer exists. Which ending happens depends on the peer, so
                 * the close is checked against the ending that actually
                 * occurred rather than against an assumed one.
                 */
                if (err == ULTIMATE_END)
                    check("net-close-after-end-is-refused",
                          ULTIMATE_ERR_DEVICE, ultimate_net_close(handle));
                else
                    check("net-close-an-open-socket", ULTIMATE_OK,
                          ultimate_net_close(handle));

                /*
                 * UDP has no handshake, so the socket opens whether or not
                 * anything is listening. That is the whole of what this proves
                 * - the command reaches the firmware and hands back a handle
                 * that closes cleanly - and it is deliberately not a claim that
                 * a datagram went anywhere.
                 */
                handle = 0xFF;
                err = ultimate_net_udp(net_peer, NET_PEER_PORT, &handle);
                check("net-udp-opens-a-socket", ULTIMATE_OK, err);
                if (err == ULTIMATE_OK) {
                    check("net-udp-gives-back-a-handle", 1,
                          handle != 0xFF ? 1 : 0);
                    check("net-udp-closes", ULTIMATE_OK,
                          ultimate_net_close(handle));
                } else {
                    skip("net-udp-gives-back-a-handle", "the socket did not open");
                    skip("net-udp-closes", "the socket did not open");
                }
            }
        }
#else
        skip("net-connect", "no peer: build with net_peer=<dotted-quad>:<port>");
#endif
    }

    /* ------------------------------------------------------------------
     * HTTP.
     *
     * Same bargain as the sockets: this needs a server, so it takes one or
     * skips. Build with HTTP_PEER=<dotted-quad>:<port> pointed at something
     * that answers 200 with a body at /hello and 404 at /nope.
     * ------------------------------------------------------------------ */
    if (!ultimate_has_http(&caps)) {
        skip("http-get", "no http target on this firmware");
    } else {
#ifdef HTTP_PEER_HOST
        uint16_t got = 0;
        uint8_t  handle = 0xFF;

        build_url("/hello");
        printf("# url=%s\n", http_url);

        err = ultimate_http_get(http_url, net_buf, sizeof(net_buf), &got);
        check("http-get", ULTIMATE_OK, err);
        check("http-get-returned-a-body", 1, got != 0 ? 1 : 0);
        /*
         * The number matters as much as the result: ULTIMATE_OK here means the
         * server answered below 400, and this is what says the response line
         * was really parsed rather than the status being ignored.
         */
        check("http-get-kept-the-status-number", 200,
              (int)ultimate_device_code());
        http_ran = 1;

        /* A 404 is the server's answer, not a failure of ours - so it is a
           device error with the number kept, and the error page still arrives. */
        build_url("/nope");
        got = 0;
        err = ultimate_http_get(http_url, net_buf, sizeof(net_buf), &got);
        check("http-404-is-a-device-error", ULTIMATE_ERR_DEVICE, err);
        check("http-404-kept-the-number", 404, (int)ultimate_device_code());

        /* A reply bigger than the buffer is truncated and cannot be resumed.
           Two bytes is small enough that any real page overflows it. */
        build_url("/hello");
        got = 0;
        err = ultimate_http_get(http_url, net_buf, 2, &got);
        check("http-truncates-into-a-small-buffer",
              ULTIMATE_ERR_TRUNCATED, err);
        check("http-truncated-still-filled-the-buffer", 2, (int)got);

        /* The long form, which is what a caller needs when it has a header to
           add. The header itself is proved by the request succeeding with it
           attached; what the server did with it is the server's business. */
        build_url("/hello");
        err = ultimate_http_open(HTTP_VERB_GET, http_url, &handle);
        check("http-open", ULTIMATE_OK, err);
        if (err != ULTIMATE_OK) {
            skip("http-header", "nothing opened");
            skip("http-exchange", "nothing opened");
            skip("http-close", "nothing opened");
        } else {
            check("http-open-gave-a-handle", 1, handle != 0xFF ? 1 : 0);
            check("http-header", ULTIMATE_OK,
                  ultimate_http_header(handle, http_hdr));
            got = 0;
            check("http-exchange", ULTIMATE_OK,
                  ultimate_http_exchange(handle, HTTP_BODY_NONE, net_buf,
                                         sizeof(net_buf), &got));
            check("http-exchange-returned-a-body", 1, got != 0 ? 1 : 0);
            check("http-close", ULTIMATE_OK, ultimate_http_close(handle));
        }

        check("http-free-all", ULTIMATE_OK, ultimate_http_free_all());
#else
        skip("http-get", "no peer: build with http_peer=<dotted-quad>:<port>");
#endif

        /*
         * Request bodies need no server: the body is built inside the
         * Ultimate, and only the exchange that sends it would reach the
         * network. So these run whenever the HTTP target is present.
         *
         * Keys and values are written as ordinary literals. cc65 charmaps
         * lowercase source into the uppercase ASCII range, which makes them
         * uppercase on the wire and leaves them perfectly good JSON.
         */
        {
            uint8_t body = HTTP_BODY_NONE;
            static const uint8_t blob[] = { 0x01, 0x02, 0x03 };
            static char longkey[ULTIMATE_HTTP_KEY_MAX + 2];

            err = ultimate_http_body(HTTP_BODY_JSON_OBJECT, &body);
            check("http-body-create", ULTIMATE_OK, err);
            if (err != ULTIMATE_OK) {
                skip("http-body-string", "no body was created");
                skip("http-body-int", "no body was created");
                skip("http-body-bool", "no body was created");
                skip("http-body-object", "no body was created");
                skip("http-body-up", "no body was created");
                skip("http-body-array", "no body was created");
                skip("http-body-clear", "no body was created");
                skip("http-body-free", "no body was created");
            } else {
                check("http-body-gave-a-handle", 1,
                      body != HTTP_BODY_NONE ? 1 : 0);
                check("http-body-string", ULTIMATE_OK,
                      ultimate_http_body_string(body, "name", "c64"));
                check("http-body-int", ULTIMATE_OK,
                      ultimate_http_body_int(body, "count", 42));
                check("http-body-bool", ULTIMATE_OK,
                      ultimate_http_body_bool(body, "ready", 1));

                /* Into an object, then back out of it, then an array beside
                   it - which is what proves the current container moves. */
                check("http-body-object", ULTIMATE_OK,
                      ultimate_http_body_object(body, "inner"));
                check("http-body-int-inside-the-object", ULTIMATE_OK,
                      ultimate_http_body_int(body, "deep", 1));
                check("http-body-up", ULTIMATE_OK,
                      ultimate_http_body_up(body));
                check("http-body-array", ULTIMATE_OK,
                      ultimate_http_body_array(body, "list"));

                check("http-body-clear", ULTIMATE_OK,
                      ultimate_http_body_clear(body));
                check("http-body-free", ULTIMATE_OK,
                      ultimate_http_body_free(body));
            }

            /* A binary body takes bytes and no keys. */
            body = HTTP_BODY_NONE;
            err = ultimate_http_body(HTTP_BODY_BINARY, &body);
            check("http-body-binary-create", ULTIMATE_OK, err);
            if (err != ULTIMATE_OK) {
                skip("http-body-binary", "no body was created");
                skip("http-body-binary-free", "no body was created");
            } else {
                check("http-body-binary", ULTIMATE_OK,
                      ultimate_http_body_binary(body, blob, sizeof(blob)));
                check("http-body-binary-free", ULTIMATE_OK,
                      ultimate_http_body_free(body));
            }

            /* The two argument checks, which never reach the wire. */
            body = 0x00;
            check("http-body-rejects-a-bad-format",
                  ULTIMATE_ERR_INVALID_ARGUMENT,
                  ultimate_http_body(0, &body));
            check("http-body-bad-format-invents-no-handle", HTTP_BODY_NONE,
                  (int)body);

            memset(longkey, 0x41, sizeof(longkey) - 1);
            longkey[sizeof(longkey) - 1] = 0x00;
            check("http-body-rejects-a-key-that-does-not-fit",
                  ULTIMATE_ERR_INVALID_ARGUMENT,
                  ultimate_http_body_int(0, longkey, 1));

            check("http-free-all-after-the-bodies", ULTIMATE_OK,
                  ultimate_http_free_all());
        }
    }

    printf("1..%u\n", test_no);
    printf("# %u passed, %u failed, %u skipped\n", passed, failed, skipped);

    publish();
    return failed == 0 ? 0 : 1;
}
