/* Can one 10 KB video frame plus one palette update fit in one raster frame? */

#include <stdint.h>
#include <string.h>
#include <ultimate.h>
#include <uci.h>
#include "../../tests/hardware/cycles.h"

#define STATUS      ((volatile uint8_t *)0x033c)
#define SCREEN_RAM   0x4000
#define BITMAP_RAM   0x6000
#define COLOR_RAM    0xd800
#define WORK_REU     0x00100000UL
#define BITMAP_BYTES 8000
#define CELL_BYTES   1000
#define COLOR_BACKUP (WORK_REU + BITMAP_BYTES + 2 * CELL_BYTES)
#define START_LINE  80
#define TEST_FRAMES 600

static uint8_t palette[UCI_PALETTE_BYTES];
static uci_request request;

static void put32(uint8_t offset, uint32_t value)
{
    STATUS[offset] = (uint8_t)value;
    STATUS[offset + 1] = (uint8_t)(value >> 8);
    STATUS[offset + 2] = (uint8_t)(value >> 16);
    STATUS[offset + 3] = (uint8_t)(value >> 24);
}

static void wait_frame(void)
{
    while (PEEK(VIC_RASTER) >= START_LINE) {}
    while (PEEK(VIC_RASTER) < START_LINE) {}
}

int main(void)
{
    uint8_t err;
    uint16_t i;
    uint16_t frames = 0;
    uint32_t elapsed;
    uint32_t maximum = 0;

    memset((void *)STATUS, 0, 32);
    STATUS[0] = 0x46; STATUS[1] = 0x4d; STATUS[2] = 0x56; STATUS[3] = 0x42;

    err = ultimate_init();
    if (err == ULTIMATE_OK)
        err = ultimate_palette_get(palette);
    if (err == ULTIMATE_OK && !ultimate_reu_available())
        err = ULTIMATE_ERR_NOT_SUPPORTED;
    if (err == ULTIMATE_OK)
        err = ultimate_reu_stash(BITMAP_RAM, WORK_REU, BITMAP_BYTES);
    if (err == ULTIMATE_OK)
        err = ultimate_reu_stash(SCREEN_RAM, WORK_REU + BITMAP_BYTES,
                                 CELL_BYTES);
    if (err == ULTIMATE_OK)
        err = ultimate_reu_stash(COLOR_RAM, COLOR_BACKUP, CELL_BYTES);
    if (err == ULTIMATE_OK) {
        for (i = 0; i < CELL_BYTES; ++i)
            POKE(COLOR_RAM + i, (uint8_t)i & 15);
        err = ultimate_reu_stash(COLOR_RAM,
                                 WORK_REU + BITMAP_BYTES + CELL_BYTES,
                                 CELL_BYTES);
    }
    if (err == ULTIMATE_OK) {
        for (i = 0; i < CELL_BYTES; ++i)
            POKE(COLOR_RAM + i, 0);
        err = ultimate_reu_fetch(COLOR_RAM,
                                 WORK_REU + BITMAP_BYTES + CELL_BYTES,
                                 CELL_BYTES);
    }
    if (err == ULTIMATE_OK) {
        STATUS[11] = 1;
        for (i = 0; i < CELL_BYTES; ++i) {
            if ((PEEK(COLOR_RAM + i) & 15) != ((uint8_t)i & 15)) {
                STATUS[11] = 0;
                err = ULTIMATE_ERR_IO;
                break;
            }
        }
    }
    if (err != ULTIMATE_OK) {
        ultimate_reu_fetch(COLOR_RAM, COLOR_BACKUP, CELL_BYTES);
        STATUS[4] = 0xff;
        STATUS[6] = err;
        return 1;
    }

    memset(&request, 0, sizeof(request));
    request.target = UCI_TARGET_CONTROL | UCI_TARGET_NO_REPLY;
    request.command = CTRL_CMD_SET_PALETTE;
    request.args = palette;
    request.arglen = sizeof(palette);

    cycles_calibrate();
    put32(12, cycles_frame());
    STATUS[4] = 1;

    while (!STATUS[5] && frames < TEST_FRAMES) {
        wait_frame();
        STATUS[7] = PEEK(VIC_RASTER);
        timer_start();
        err = ultimate_reu_fetch(BITMAP_RAM, WORK_REU, BITMAP_BYTES);
        if (err == ULTIMATE_OK)
            err = ultimate_reu_fetch(SCREEN_RAM, WORK_REU + BITMAP_BYTES,
                                     CELL_BYTES);
        if (err == ULTIMATE_OK)
            err = ultimate_reu_fetch(COLOR_RAM,
                                     WORK_REU + BITMAP_BYTES + CELL_BYTES,
                                     CELL_BYTES);
        if (err == ULTIMATE_OK)
            err = uci_exec(&request);
        elapsed = cycles_net(timer_stop());
        STATUS[8] = PEEK(VIC_RASTER);
        put32(16, elapsed);
        if (elapsed > maximum) {
            maximum = elapsed;
            put32(20, maximum);
        }
        ++frames;
        STATUS[9] = (uint8_t)frames;
        STATUS[10] = (uint8_t)(frames >> 8);
        STATUS[6] = err;
        if (err != ULTIMATE_OK)
            break;
    }

    ultimate_reu_fetch(COLOR_RAM, COLOR_BACKUP, CELL_BYTES);
    ultimate_palette_set(palette);
    STATUS[4] = 2;
    return err == ULTIMATE_OK ? 0 : 1;
}
