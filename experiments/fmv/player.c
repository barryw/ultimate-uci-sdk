/* First 24 fps FMV player: the 288-frame Dragon's Lair conversion, looping. */
#include <conio.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <peekpoke.h>
#include <ultimate.h>
#include <uci.h>
#include "../../tests/hardware/cycles.h"

#define ST ((volatile uint8_t *)0x033c)
#define FRAME_SIZE 10049UL
#define FRAME_COUNT 288
#define AUDIO_BASE 0x300000UL
#define AUDIO_SIZE 192000UL
#define COLORS_REU (AUDIO_BASE + AUDIO_SIZE)

static uint8_t saved_palette[48], metadata[49];
static uint8_t active_palette[48], palette_valid, palette_changed;
/* UCI paths are ASCII; ordinary cc65 literals are PETSCII-mapped. */
static const char video_path[] = {0x2f, 0x54, 0x65, 0x6d, 0x70, 0x2f, 0x66, 0x6d, 0x76, 0x2d, 0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2e, 0x66, 0x72, 0x61, 0x6d, 0x65, 0x73, 0};
static const char audio_path[] = {0x2f, 0x54, 0x65, 0x6d, 0x70, 0x2f, 0x66, 0x6d, 0x76, 0x2d, 0x61, 0x75, 0x64, 0x69, 0x6f, 0x2e, 0x73, 0x38, 0};
static uci_request request;
static ultimate_audio_voice voice;
static uint8_t saved_bank, saved_d011, saved_d016, saved_d018;
static uint8_t saved_border, saved_bg, have_audio, have_palette, have_colors;
static uint16_t frame, late;
static uint32_t period, deadline;

static uint32_t now(void)
{
    uint16_t high, low;
    do {
        high = PEEKW(CIA2_TB_LO);
        low = PEEKW(CIA2_TA_LO);
    } while (high != PEEKW(CIA2_TB_LO));
    return ~(((uint32_t)high << 16) | low);
}

static uint8_t stop_requested(void)
{
    uint8_t key;
    if (ST[6]) return 1;
    /* IRQs are off; scan RUN/STOP directly, preserving keyboard port setup. */
    key = PEEK(0xdc00);
    POKE(0xdc00, 0x7f);
    ST[15] = PEEK(0xdc01);
    POKE(0xdc00, key);
    return !(ST[15] & 0x80);
}

static uint8_t load(const char *path, uint32_t address, uint32_t length)
{
    uint8_t err = ultimate_open(path, DOS_FA_READ);
    if (err) return err;
    err = ultimate_reu_load(address, length);
    ultimate_close();
    return err;
}

static uint8_t prepare(uint8_t back)
{
    uint32_t at = (uint32_t)frame * FRAME_SIZE;
    uint8_t err;
    err = ultimate_reu_fetch(back ? 0xa000 : 0x6000, at, 8000);
    if (!err) err = ultimate_reu_fetch(back ? 0x8400 : 0x4400, at + 8000, 1000);
    if (!err) err = ultimate_reu_fetch((uint16_t)metadata, at + 10000, 49);
    if (!err) palette_changed = !palette_valid || memcmp(active_palette, metadata + 1, 48);
    return err;
}

static uint8_t present(uint8_t back)
{
    uint8_t err;
    /* End of the 200-line picture. Color RAM and palette are shared between
     * buffers; HDMI inspection must establish whether this fits blanking. */
    while (PEEK(VIC_RASTER) == 250) {}
    while (PEEK(VIC_RASTER) != 250) {}
    err = ultimate_reu_fetch(0xd800, (uint32_t)frame * FRAME_SIZE + 9000, 1000);
    if (err) return err;
    POKE(0xdd00, (saved_bank & 0xfc) | (back ? 1 : 2));
    POKE(0xd021, metadata[0]);
    if (palette_changed) {
        err = uci_exec(&request);
        if (!err) {
            memcpy(active_palette, metadata + 1, 48);
            palette_valid = 1;
            ++ST[12];
        }
    }
    return err;
}

int main(void)
{
    uint8_t err = 0, back = 0;
    uint32_t ticks;
    memset((void *)ST, 0, 16);
    ST[0] = 0x46; ST[1] = 0x4d; ST[2] = 0x56; ST[3] = 0x50;
    ST[4] = 1;
    saved_bank = PEEK(0xdd00); saved_d011 = PEEK(0xd011);
    saved_d016 = PEEK(0xd016); saved_d018 = PEEK(0xd018);
    saved_border = PEEK(0xd020); saved_bg = PEEK(0xd021);
    clrscr(); cputs("loading dragon's lair into reu...");
    ST[13] = 1;
    err = ultimate_init();
    if (err) goto done;
    err = ultimate_palette_get(saved_palette);
    if (err) goto done;
    have_palette = 1;
    if (ultimate_reu_size() < 64) { err = ULTIMATE_ERR_NOT_SUPPORTED; goto done; }
    err = ultimate_reu_stash(0xd800, COLORS_REU, 1000);
    if (err) goto done;
    have_colors = 1;
    ST[13] = 2;
    err = load(video_path, 0, FRAME_COUNT * FRAME_SIZE);
    if (err) goto done;
    ST[13] = 3;
    err = load(audio_path, AUDIO_BASE, AUDIO_SIZE);
    if (err) goto done;
    ST[13] = 4;
    err = ultimate_audio_init();
    if (err) goto done;
    have_audio = 1;
    memset(&voice, 0, sizeof(voice));
    voice.volume = UA_VOLUME_MAX;
    voice.pan = UA_PAN_CENTER;
    voice.reu_address = AUDIO_BASE;
    voice.length = AUDIO_SIZE;
    voice.rate = 391;
    memset(&request, 0, sizeof(request));
    request.target = UCI_TARGET_CONTROL | UCI_TARGET_NO_REPLY;
    request.command = CTRL_CMD_SET_PALETTE;
    request.args = metadata + 1;
    request.arglen = 48;
    period = PEEK(0x02a6) ? 985248UL / 24 : 1022727UL / 24;
    __asm__("sei");
    POKE(0xd015, 0);
    POKE(0xd020, 0);
    POKE(0xd011, 0x3b); POKE(0xd016, 0x18); POKE(0xd018, 0x18);
    ST[13] = 5;
    ST[4] = 2;
    while (!stop_requested()) {
        err = ultimate_audio_configure(&voice);
        if (err) break;
        for (frame = 0; frame < FRAME_COUNT && !stop_requested(); ++frame) {
            err = prepare(back);
            if (err) goto done;
            if (frame) {
                ticks = now();
                if (ticks > deadline + period) ++late;
                while (now() < deadline && !stop_requested()) {}
            }
            if (stop_requested()) break;
            err = present(back);
            if (err) goto done;
            if (!frame) {
                err = ultimate_audio_start(0, 0);
                if (err) goto done;
                timer_start();
                deadline = 0;
            }
            deadline += period;
            ST[8] = (uint8_t)frame; ST[9] = (uint8_t)(frame >> 8);
            ST[10] = (uint8_t)late; ST[11] = (uint8_t)(late >> 8);
            back ^= 1;
        }
        while (now() < deadline && !stop_requested()) {}
        ultimate_audio_stop(0);
        ++ST[7];
    }
done:
    if (have_audio) ultimate_audio_stop(0);
    if (have_palette) ultimate_palette_set(saved_palette);
    if (have_colors) ultimate_reu_fetch(0xd800, COLORS_REU, 1000);
    POKE(CIA2_CRA, 0); POKE(CIA2_CRB, 0);
    POKE(0xdd00, saved_bank); POKE(0xd011, saved_d011);
    POKE(0xd016, saved_d016); POKE(0xd018, saved_d018);
    POKE(0xd020, saved_border); POKE(0xd021, saved_bg);
    __asm__("cli");
    ST[5] = err; ST[4] = err ? 0x80 : 3;
    clrscr(); cprintf("fmv stopped. error %u\r\n", err);
    return err;
}
