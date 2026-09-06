/* Show exactly where a live Ultimate palette write reaches the raster. */

#include <stdint.h>
#include <string.h>
#include <ultimate.h>

#define SCREEN       ((uint8_t *)0x0400)
#define COLOR_RAM    ((uint8_t *)0xd800)
#define VIC_RASTER   (*(volatile uint8_t *)0xd012)
#define VIC_CONTROL1 (*(volatile uint8_t *)0xd011)
#define VIC_CONTROL2 (*(volatile uint8_t *)0xd016)
#define VIC_MEMORY   (*(volatile uint8_t *)0xd018)
#define VIC_BORDER   (*(volatile uint8_t *)0xd020)
#define VIC_BG       (*(volatile uint8_t *)0xd021)
#define VIC_SPRITES  (*(volatile uint8_t *)0xd015)
#define UCI_CONTROL  (*(volatile uint8_t *)0xdf1c)
#define UCI_COMMAND  (*(volatile uint8_t *)0xdf1d)
#define STATUS       ((volatile uint8_t *)0x033c)

#define START_LINE 80
#define MARKER_BLACK 14
#define MARKER_WHITE 15

static uint8_t saved[ULTIMATE_PALETTE_BYTES];
static uint8_t warm[ULTIMATE_PALETTE_BYTES];
static uint8_t cool[ULTIMATE_PALETTE_BYTES];
static uint8_t readback[ULTIMATE_PALETTE_BYTES];

static void raw_palette_set(const uint8_t *palette)
{
    uint8_t i;

    while (UCI_CONTROL & 0x30) {}
    UCI_COMMAND = 0x84;         /* control target, no reply */
    UCI_COMMAND = 0x52;         /* SET_PALETTE */
    for (i = 0; i < ULTIMATE_PALETTE_BYTES; ++i)
        UCI_COMMAND = palette[i];
    UCI_CONTROL = 0x01;         /* push command */
    while (UCI_CONTROL & 0x30) {}
}

static void make_palettes(void)
{
    uint8_t i;

    for (i = 0; i < 14; ++i) {
        warm[3 * i] = 255;
        warm[3 * i + 1] = i * 18;
        warm[3 * i + 2] = 0;
        cool[3 * i] = 0;
        cool[3 * i + 1] = i * 18;
        cool[3 * i + 2] = 255;
    }

    /* Stable colors make the border an independent call-duration marker. */
    warm[42] = cool[42] = 0;
    warm[43] = cool[43] = 0;
    warm[44] = cool[44] = 0;
    warm[45] = cool[45] = 255;
    warm[46] = cool[46] = 255;
    warm[47] = cool[47] = 255;
}

static void draw_bars(void)
{
    uint16_t at;
    uint8_t x;
    uint8_t y;

    VIC_CONTROL1 = 0x1b;
    VIC_CONTROL2 = 0x08;
    VIC_MEMORY = 0x14;
    VIC_SPRITES = 0;
    VIC_BG = MARKER_BLACK;
    VIC_BORDER = MARKER_BLACK;

    for (y = 0; y < 25; ++y) {
        for (x = 0; x < 40; ++x) {
            at = (uint16_t)y * 40 + x;
            SCREEN[at] = 0xa0;       /* reversed space: a solid color cell */
            COLOR_RAM[at] = (uint8_t)(((uint16_t)x * 14) / 40);
        }
    }
}

static void wait_for_start_line(void)
{
    while (VIC_RASTER >= START_LINE) {}
    while (VIC_RASTER < START_LINE) {}
}

int main(void)
{
    const uint8_t *next;
    uint8_t err;
    uint8_t phase = 0;
    uint16_t frames = 0;

    STATUS[0] = 0x50;             /* "PLTM", not subject to cc65's charmap */
    STATUS[1] = 0x4c;
    STATUS[2] = 0x54;
    STATUS[3] = 0x4d;
    memset((void *)(STATUS + 4), 0, 12);

    err = ultimate_init();
    if (err == ULTIMATE_OK)
        err = ultimate_palette_get(saved);
    if (err != ULTIMATE_OK) {
        STATUS[5] = 0xff;
        STATUS[6] = err;
        return 1;
    }

    make_palettes();
    draw_bars();
    raw_palette_set(warm);
    err = ultimate_palette_get(readback);
    if (err != ULTIMATE_OK) {
        STATUS[5] = 0xff;
        STATUS[6] = err;
        return 1;
    }
    for (phase = 0; phase < ULTIMATE_PALETTE_BYTES; ++phase) {
        if (readback[phase] != warm[phase]) {
            STATUS[5] = 0xfe;
            STATUS[12] = phase + 1;
            STATUS[13] = warm[phase];
            STATUS[14] = readback[phase];
            ultimate_palette_set(saved);
            return 1;
        }
    }
    phase = 0;

    /* Hold the warm palette for direct HDMI verification. The host writes
     * STATUS[4] once to begin the alternating raster test, then again to stop. */
    STATUS[5] = 3;
    while (!STATUS[4]) {}
    STATUS[4] = 0;

    __asm__("sei");
    STATUS[5] = 1;
    for (;;) {
        wait_for_start_line();
        next = phase ? warm : cool;
        VIC_BORDER = MARKER_WHITE;
        STATUS[7] = VIC_RASTER;
        err = ultimate_palette_set(next);
        STATUS[8] = VIC_RASTER;
        VIC_BORDER = MARKER_BLACK;
        if (err != ULTIMATE_OK || STATUS[4])
            break;
        phase ^= 1;
        ++frames;
        STATUS[9] = phase;
        STATUS[10] = (uint8_t)frames;
        STATUS[11] = (uint8_t)(frames >> 8);
    }

    STATUS[6] = err;
    ultimate_palette_set(saved);
    VIC_BORDER = 0;
    VIC_BG = 0;
    STATUS[5] = 2;
    __asm__("cli");
    return err == ULTIMATE_OK ? 0 : 1;
}
