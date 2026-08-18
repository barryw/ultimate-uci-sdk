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

/* What was in the expansion before the REU tests, and what they put there. */
static uint8_t reu_before[32];
static uint8_t reu_work[32];

static uint8_t saved[UCI_PALETTE_BYTES];
static uint8_t readback[UCI_PALETTE_BYTES];

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
#define RESULT_FORMAT 2
#define RESULT_DONE   0xA5

static uint8_t turbo_ran;

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

    /*
     * 8: command framing, end to end. ECHO hands back the exact bytes the
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
                  ultimate_reu_load(0, 28));
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

        /* Put the expansion back exactly as it was found. */
        check("reu-restored", ULTIMATE_OK,
              ultimate_reu_stash((uint16_t)reu_before, 0, sizeof(reu_before)));
    }

    printf("1..%u\n", test_no);
    printf("# %u passed, %u failed, %u skipped\n", passed, failed, skipped);

    publish();
    return failed == 0 ? 0 : 1;
}
