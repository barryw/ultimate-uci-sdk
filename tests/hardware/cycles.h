/*
 * cycles.h - a 32-bit cycle counter, and the length of a frame in its units.
 *
 * Shared by ucitime.c, which measures how long a UCI round trip takes, and
 * ucitest.c, which has to prove that turbo really made the machine faster.
 * Both need the same two things and neither should own a second copy.
 *
 * CIA #2 is the free one: the KERNAL drives its timers only for RS232, and
 * nothing here touches $DD00, so the VIC bank and the serial bus are unharmed.
 * Timer A counts phi2 and timer B counts timer A's underflows, which chains
 * them into one 32-bit counter.
 *
 * **Always divide by cycles_frame(), never by a constant.** Measuring the
 * raster on the same counter is what makes every result a ratio of two figures
 * off one clock, and that is what survives PAL versus NTSC, whatever the CIA is
 * really clocked at on an Ultimate 64, and the CPU sitting in turbo. A machine
 * running eight times faster either counts eight times fewer cycles for the
 * same work or counts eight times more per frame, depending on what the turbo
 * implementation does to the CIA - and the ratio is right either way, without
 * anyone having to know which.
 *
 * SPDX-License-Identifier: MIT
 */

#ifndef ULTIMATE_TEST_CYCLES_H
#define ULTIMATE_TEST_CYCLES_H

#include <stdint.h>
#include <peekpoke.h>

#define CIA2_TA_LO 0xDD04
#define CIA2_TA_HI 0xDD05
#define CIA2_TB_LO 0xDD06
#define CIA2_TB_HI 0xDD07
#define CIA2_ICR   0xDD0D
#define CIA2_CRA   0xDD0E
#define CIA2_CRB   0xDD0F

#define CRA_RUN    0x11            /* force load, count phi2, start */
#define CRB_RUN    0x51            /* force load, count timer A underflows, start */

#define VIC_RASTER 0xD012

/* Raster line 250 exists once per frame on PAL and on NTSC alike: $D012 is the
 * low eight bits of a line number that never reaches 506. */
#define SYNC_LINE  250

/* The timer's own start-and-stop cost, in its own units. Set by
 * cycles_calibrate() and subtracted from every measurement below. */
static uint32_t cycles_overhead;

static void timer_start(void)
{
    POKE(CIA2_CRA, 0x00);
    POKE(CIA2_CRB, 0x00);
    POKE(CIA2_ICR, 0x7F);          /* no NMI from either timer, whatever ran before */
    (void)PEEK(CIA2_ICR);          /* reading clears the latched flags */
    POKE(CIA2_TA_LO, 0xFF);
    POKE(CIA2_TA_HI, 0xFF);
    POKE(CIA2_TB_LO, 0xFF);
    POKE(CIA2_TB_HI, 0xFF);
    POKE(CIA2_CRB, CRB_RUN);       /* B first: it must already be counting when A wraps */
    POKE(CIA2_CRA, CRA_RUN);
}

/*
 * Both timers count down from $FFFF and reload on underflow, so a timer A
 * period is $FFFF + 1 cycles. Stop before reading: a rollover between the two
 * reads would otherwise be worth 65536 cycles of nonsense.
 */
static uint32_t timer_stop(void)
{
    uint16_t a, b;

    POKE(CIA2_CRA, 0x00);
    POKE(CIA2_CRB, 0x00);
    a = PEEK(CIA2_TA_LO) | ((uint16_t)PEEK(CIA2_TA_HI) << 8);
    b = PEEK(CIA2_TB_LO) | ((uint16_t)PEEK(CIA2_TB_HI) << 8);
    return ((uint32_t)(0xFFFFu - b) << 16) | (uint32_t)(uint16_t)(0xFFFFu - a);
}

/* Subtract the fixed cost, without going negative on a very short interval. */
static uint32_t cycles_net(uint32_t total)
{
    return total > cycles_overhead ? total - cycles_overhead : 0;
}

static void cycles_calibrate(void)
{
    cycles_overhead = 0;
    __asm__("sei");
    timer_start();
    cycles_overhead = timer_stop();
    __asm__("cli");
}

/*
 * One raster frame, in the counter's units.
 *
 * Sync before starting the timer, not after: starting it first puts a partial
 * frame in front of the ten, which reads as 9.5 frames divided by 10 and looks
 * like a plausible number rather than an obviously broken one. That is exactly
 * how the first version of this got it 5% wrong.
 */
static uint32_t cycles_frame(void)
{
    uint8_t i;
    uint32_t total;

    __asm__("sei");
    while (PEEK(VIC_RASTER) != SYNC_LINE)
        ;
    while (PEEK(VIC_RASTER) == SYNC_LINE)
        ;
    timer_start();
    for (i = 0; i < 10; ++i) {
        while (PEEK(VIC_RASTER) != SYNC_LINE)
            ;
        while (PEEK(VIC_RASTER) == SYNC_LINE)
            ;
    }
    total = timer_stop();
    __asm__("cli");

    return cycles_net(total) / 10;
}

#endif /* ULTIMATE_TEST_CYCLES_H */
