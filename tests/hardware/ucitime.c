/*
 * ucitime.c - how long is one UCI round trip, in frames?
 *
 * docs/handover-next.md asks for one number, because it decides the shape of
 * anything that wants to talk to the Ultimate while a demo is running. Colour
 * cycling wants a palette write every frame or two; nobody had measured whether
 * a round trip fits in a frame at all.
 *
 * Every UCI command is a handshake: write the bytes, push, poll until BUSY
 * clears, read the status. That poll is the cost, and it is the Ultimate's
 * turnaround, not the C64's - so it can only be measured on real hardware.
 *
 * **The frame length is measured, not assumed.** CIA #2's two timers are
 * chained into a 32-bit cycle counter, and the same counter times ten raster
 * frames. Every result is then a ratio of two numbers off one clock, which is
 * what makes it immune to PAL versus NTSC, to whatever the CIA is really
 * clocked at on an Ultimate 64, and to the machine sitting in turbo. The turbo
 * register is published alongside so the report can say which it was.
 *
 * Build:  make ucitime.prg
 * Run:    make time-run U64_HOST=<ip>, which reads the results back by DMA.
 *
 * SPDX-License-Identifier: MIT
 */

#include <stdio.h>
#include <string.h>
#include <ultimate.h>

#include "cycles.h"

/* ------------------------------------------------------------------------ */

#define MAX_SLOTS 8
#define ITERS     8                /* per measurement, to average out badline jitter */

static uint32_t cycles[MAX_SLOTS];
static uint8_t  errors[MAX_SLOTS];
static uint8_t  slots;

static uint32_t frame_cycles;      /* one raster frame, on the same clock */

/* The KERNAL's PAL/NTSC flag. Informational: every ratio below comes from
 * frame_cycles, which is measured rather than looked up. */
#define PAL_FLAG 0x02A6

/*
 * Interrupts off for the whole burst. The KERNAL's own IRQ is not part of a
 * round trip, and leaving it in would measure the jiffy clock as well. The
 * screen stays on: a demo's screen is on, so the VIC's stolen cycles belong in
 * the number.
 */
static uint32_t time_exec(uci_request *req, uint8_t slot)
{
    uint8_t i;
    uint32_t total;

    __asm__("sei");
    timer_start();
    for (i = 0; i < ITERS; ++i)
        errors[slot] = uci_exec(req);
    total = timer_stop();
    __asm__("cli");

    return cycles_net(total);
}

/* ------------------------------------------------------------------------ */

/*
 * Machine-readable results, in the cassette buffer, exactly as ucitest.c does
 * it: 192 bytes neither BASIC nor cc65 touches, cleared by the KERNAL's reset
 * so a stale block cannot be read as a fresh one.
 *
 *   +0  magic "UCIM"      +8  $D031             +18 8 x 4 cycle totals
 *   +4  format version    +9  reserved          +50 8 x 1 error code
 *   +5  measurements      +10 frame cycles      +58 $A5 once main() is done
 *   +6  $02A6, 1 = PAL    +14 timer overhead
 *   +7  iterations
 */
#define RESULT_BLOCK  ((uint8_t *)0x033C)
#define RESULT_FORMAT 1
#define RESULT_DONE   0xA5

static void put32(uint8_t *at, uint32_t v)
{
    at[0] = (uint8_t)v;
    at[1] = (uint8_t)(v >> 8);
    at[2] = (uint8_t)(v >> 16);
    at[3] = (uint8_t)(v >> 24);
}

static void publish(void)
{
    uint8_t i;

    RESULT_BLOCK[0] = 0x55;             /* 'U' - written as bytes, not a  */
    RESULT_BLOCK[1] = 0x43;             /* 'C'   literal, so no charmap   */
    RESULT_BLOCK[2] = 0x49;             /* 'I'   can rewrite it           */
    RESULT_BLOCK[3] = 0x4D;             /* 'M' */
    RESULT_BLOCK[4] = RESULT_FORMAT;
    RESULT_BLOCK[5] = slots;
    RESULT_BLOCK[6] = PEEK(PAL_FLAG);
    RESULT_BLOCK[7] = ITERS;
    RESULT_BLOCK[8] = PEEK(U64_REG_TURBO);
    RESULT_BLOCK[9] = 0;
    put32(RESULT_BLOCK + 10, frame_cycles);
    put32(RESULT_BLOCK + 14, cycles_overhead);
    for (i = 0; i < MAX_SLOTS; ++i) {
        put32(RESULT_BLOCK + 18 + 4 * i, cycles[i]);
        RESULT_BLOCK[50 + i] = errors[i];
    }
    RESULT_BLOCK[58] = RESULT_DONE;
}

/* ------------------------------------------------------------------------ */

static uci_request req;
static uint8_t     scratch[64];
static uint8_t     palette[UCI_PALETTE_BYTES];
static uint8_t     echo_args[4] = { 0xDE, 0xAD, 0xBE, 0xEF };
static uint8_t     color_args[4];

/* Every measurement is the same three steps, so they are one function. */
static void record(const char *name, uint8_t slot)
{
    cycles[slot] = time_exec(&req, slot);
    if (slot >= slots)
        slots = slot + 1;
    printf("%-14s %6lu %s\n", name, cycles[slot] / ITERS,
           errors[slot] == ULTIMATE_OK ? "" : "err");
}

static void skip(const char *name, uint8_t slot, uint8_t err)
{
    errors[slot] = err;
    cycles[slot] = 0;
    if (slot >= slots)
        slots = slot + 1;
    printf("%-14s      - skipped\n", name);
}

int main(void)
{
    uint8_t err;
    uint8_t have_palette;

    printf("uci round trip, in cycles\n\n");

    if (ultimate_init() != ULTIMATE_OK) {
        printf("no ultimate. enable the command\n");
        printf("interface in its settings menu.\n");
        publish();
        return 1;
    }

    /* The zero baseline: what the timer costs to start and stop. */
    cycles_calibrate();

    frame_cycles = cycles_frame();
    printf("frame          %6lu cycles\n", frame_cycles);
    printf("timer overhead %6lu\n\n", cycles_overhead);

    /* 0: identify. A short reply, and the command every program starts with. */
    memset(&req, 0, sizeof(req));
    req.target  = UCI_TARGET_DOS1;
    req.command = UCI_CMD_IDENTIFY;
    req.data    = scratch;
    req.datamax = sizeof(scratch);
    record("identify", 0);

    /* 1: echo, four bytes out and six back - about as small as a command gets. */
    memset(&req, 0, sizeof(req));
    req.target  = UCI_TARGET_DOS1;
    req.command = DOS_CMD_ECHO;
    req.args    = echo_args;
    req.arglen  = sizeof(echo_args);
    req.data    = scratch;
    req.datamax = sizeof(scratch);
    record("echo", 1);

    /* 2: the same command with the reply thrown away, which is the fire-and-
     * forget path a demo would actually use. */
    memset(&req, 0, sizeof(req));
    req.target  = UCI_TARGET_DOS1 | UCI_TARGET_NO_REPLY;
    req.command = DOS_CMD_ECHO;
    req.args    = echo_args;
    req.arglen  = sizeof(echo_args);
    record("echo-noreply", 2);

    /*
     * The palette commands are firmware 3.15-and-newer. Probing with the read
     * first does double duty: it says whether to measure them at all, and it
     * hands back the colour to write, so the write below sets colour 0 to the
     * value it already has. Nothing on the screen changes, which is what keeps
     * this out of the destructive bucket.
     */
    memset(&req, 0, sizeof(req));
    req.target  = UCI_TARGET_CONTROL;
    req.command = CTRL_CMD_GET_PALETTE;
    req.data    = palette;
    req.datamax = sizeof(palette);
    err = uci_exec(&req);
    have_palette = (err == ULTIMATE_OK && req.datalen == UCI_PALETTE_BYTES);

    if (have_palette) {
        /* 3: read the whole palette - 48 bytes back. */
        record("get-palette", 3);

        color_args[0] = 0;                  /* colour 0 */
        color_args[1] = palette[0];
        color_args[2] = palette[1];
        color_args[3] = palette[2];

        /* 4: one colour, six bytes on the wire. The cheapest command there is. */
        memset(&req, 0, sizeof(req));
        req.target  = UCI_TARGET_CONTROL;
        req.command = CTRL_CMD_SET_PALETTE_COLOR;
        req.args    = color_args;
        req.arglen  = sizeof(color_args);
        record("set-color", 4);

        /* 5: and the same, fire and forget. */
        memset(&req, 0, sizeof(req));
        req.target  = UCI_TARGET_CONTROL | UCI_TARGET_NO_REPLY;
        req.command = CTRL_CMD_SET_PALETTE_COLOR;
        req.args    = color_args;
        req.arglen  = sizeof(color_args);
        record("set-color-nr", 5);

        /*
         * 6 and 7: all sixteen colours in one command. This is the one a colour
         * cycling demo actually wants - a rotation is every colour moving at
         * once - and sixteen separate SET_PALETTE_COLORs is the alternative it
         * is being compared against. Writing back exactly what was read leaves
         * the screen alone.
         */
        memset(&req, 0, sizeof(req));
        req.target  = UCI_TARGET_CONTROL;
        req.command = CTRL_CMD_SET_PALETTE;
        req.args    = palette;
        req.arglen  = sizeof(palette);
        record("set-palette", 6);

        memset(&req, 0, sizeof(req));
        req.target  = UCI_TARGET_CONTROL | UCI_TARGET_NO_REPLY;
        req.command = CTRL_CMD_SET_PALETTE;
        req.args    = palette;
        req.arglen  = sizeof(palette);
        record("set-palette-nr", 7);
    } else {
        skip("get-palette", 3, err);
        skip("set-color", 4, err);
        skip("set-color-nr", 5, err);
        skip("set-palette", 6, err);
        skip("set-palette-nr", 7, err);
    }

    printf("\nper call, %u calls each\n", ITERS);
    publish();
    return 0;
}
