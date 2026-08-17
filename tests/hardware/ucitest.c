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
 *     ok 9 - get-model # SKIP no control target on this firmware
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
    printf("ok %u - %s # SKIP %s\n", test_no, name, why);
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
 *                           +9  ident
 */
#define RESULT_BLOCK  ((uint8_t *)0x033C)
#define RESULT_FORMAT 1
#define RESULT_DONE   0xA5

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
    RESULT_BLOCK[12] = RESULT_DONE;
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

    printf("1..%u\n", test_no);
    printf("# %u passed, %u failed, %u skipped\n", passed, failed, skipped);

    publish();
    return failed == 0 ? 0 : 1;
}
