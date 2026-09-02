/* Browse and play a packed Logan Approach PCM bank from Ultimate REU. */

#include <cbm.h>
#include <conio.h>
#include <stdint.h>
#include <string.h>

#include <ultimate.h>
#include "generated/logan-auditions.h"

#ifndef BANK_PATH
#define BANK_PATH "/usb1/logan-auditions.reu"
#endif
#ifndef START_INDEX
#define START_INDEX 0
#endif

#define AUDIO_RATE 567
#define PAGE_SIZE 18
#define VIC_RASTER (*(volatile uint8_t *)0xD012)
#define PAL_FLAG   (*(uint8_t *)0x02A6)

static void wait_frame(void)
{
    uint8_t line = PAL_FLAG ? 250 : 200;
    while (VIC_RASTER < line) {}
    while (VIC_RASTER >= line) {}
}

static void wait_clip(void)
{
    while (!(ultimate_audio_irq_status() & 1u))
        wait_frame();
}

static uint8_t play_clip(uint8_t index)
{
    const logan_clip *clip = &logan_clips[index];
    ultimate_audio_voice voice;
    uint8_t err;

    memset(&voice, 0, sizeof(voice));
    voice.channel = 0;
    voice.flags = UA_CTRL_IRQ;
    voice.volume = UA_VOLUME_MAX;
    voice.pan = UA_PAN_CENTER;
    voice.reu_address = clip->offset;
    voice.length = clip->length;
    voice.rate = AUDIO_RATE;
    err = ultimate_audio_configure(&voice);
    if (err != ULTIMATE_OK) return err;
    err = ultimate_audio_irq_clear(0);
    if (err != ULTIMATE_OK) return err;
    __asm__("sei");
    err = ultimate_audio_start(0, UA_CTRL_IRQ);
    if (err == ULTIMATE_OK) {
        wait_clip();
        ultimate_audio_irq_clear(0);
    }
    ultimate_audio_stop(0);
    __asm__("cli");
    return err;
}

static void draw(uint8_t selected)
{
    uint8_t top = selected / PAGE_SIZE * PAGE_SIZE;
    uint8_t row;
    uint8_t index;

    clrscr();
    bordercolor(COLOR_BLUE);
    bgcolor(COLOR_BLACK);
    textcolor(COLOR_WHITE);
    cputsxy(7, 0, "logan approach comms");
    cputsxy(2, 23, "cursor: select  return/fire: play");
    cputsxy(9, 24, "run/stop: exit");
    for (row = 0; row < PAGE_SIZE; ++row) {
        index = top + row;
        if (index >= LOGAN_CLIP_COUNT) break;
        gotoxy(2, row + 3);
        revers(index == selected);
        cprintf("%2u  %-31s", index + 1, logan_clips[index].label);
    }
    revers(0);
}

static void fail(const char *stage, uint8_t err)
{
    clrscr();
    bordercolor(COLOR_RED);
    textcolor(COLOR_WHITE);
    cputsxy(2, 8, "logan comms failed");
    cputsxy(2, 10, stage);
    cprintf(" error $%02x", err);
    cputsxy(2, 13, "press any key");
    cgetc();
}

int main(void)
{
    uint8_t selected = START_INDEX;
    uint8_t key;
    uint8_t err;

    clrscr();
    cputsxy(5, 10, "loading comms into reu...");
    err = ultimate_init();
    if (err != ULTIMATE_OK) { fail("ultimate init", err); return err; }
    err = ultimate_audio_init();
    if (err != ULTIMATE_OK) { fail("audio init", err); return err; }
    if ((uint32_t)ultimate_reu_size() * 65536UL < LOGAN_BANK_SIZE) {
        fail("reu too small", ULTIMATE_ERR_NOT_SUPPORTED);
        return ULTIMATE_ERR_NOT_SUPPORTED;
    }
    err = ultimate_open(BANK_PATH, DOS_FA_READ);
    if (err != ULTIMATE_OK) { fail("open bank", err); return err; }
    err = ultimate_reu_load(0, LOGAN_BANK_SIZE);
    ultimate_close();
    if (err != ULTIMATE_OK) { fail("load bank", err); return err; }

    draw(selected);
    for (;;) {
        key = cgetc();
        if (key == CH_STOP) break;
        if (key == CH_CURS_UP) {
            selected = selected ? selected - 1 : LOGAN_CLIP_COUNT - 1;
            draw(selected);
        } else if (key == CH_CURS_DOWN) {
            selected = selected + 1 == LOGAN_CLIP_COUNT ? 0 : selected + 1;
            draw(selected);
        } else if (key == CH_ENTER || key == ' ') {
            gotoxy(2, 22);
            cprintf("playing %-31s", logan_clips[selected].label);
            err = play_clip(selected);
            if (err != ULTIMATE_OK) { fail("play clip", err); return err; }
            draw(selected);
        }
    }
    clrscr();
    return ULTIMATE_OK;
}
