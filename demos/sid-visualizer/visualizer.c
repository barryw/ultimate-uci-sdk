/* Six SID voices, six 24-bit Ultimate palette colours. */

#include <c64.h>
#include <conio.h>
#include <stdint.h>
#include <string.h>

#include <ultimate.h>

#ifndef TUNE
#define TUNE 0
#endif
#ifndef SID1_ADDRESS
#define SID1_ADDRESS 0
#endif
#ifndef SID2_ADDRESS
#define SID2_ADDRESS 0
#endif
#ifndef SDK_VERSION
#define SDK_VERSION "dev"
#endif

#if TUNE < 0 || TUNE > 6
#error TUNE must be from 0 through 6
#endif
#if (SID1_ADDRESS && !SID2_ADDRESS) || (!SID1_ADDRESS && SID2_ADDRESS)
#error specify both SID1_ADDRESS and SID2_ADDRESS, or neither
#endif
#if SID1_ADDRESS && SID1_ADDRESS == SID2_ADDRESS
#error SID addresses must be distinct
#endif

#define SCREEN       ((uint8_t *)0x0400)
#define VIZ_COLOR_RAM ((uint8_t *)0xD800)
#define CIA1_PRA     (*(volatile uint8_t *)0xDC00)
#define CIA1_PRB     (*(volatile uint8_t *)0xDC01)
#define CIA1_DDRA    (*(volatile uint8_t *)0xDC02)
#define CIA1_DDRB    (*(volatile uint8_t *)0xDC03)
#define CIA1_TALO    (*(volatile uint8_t *)0xDC04)
#define CIA1_TAHI    (*(volatile uint8_t *)0xDC05)
#define CIA1_ICR     (*(volatile uint8_t *)0xDC0D)
#define CIA1_CRA     (*(volatile uint8_t *)0xDC0E)
#define VIC_RASTER   (*(volatile uint8_t *)0xD012)
#define VIC_BORDER   (*(volatile uint8_t *)0xD020)
#define VIC_BG       (*(volatile uint8_t *)0xD021)
#define PAL_FLAG     (*(uint8_t *)0x02A6)
#define BLOCK        0xA0
#define BAR_TOP      3
#define BAR_BOTTOM   20
#define BAR_ROWS     (BAR_BOTTOM - BAR_TOP + 1)
#define DEMO_STATUS  ((volatile uint8_t *)0x033C)

void __fastcall__ music_init(uint8_t tune);
void music_irq(void);
void music_meter_reset(void);
void music_render_bars(void);
void machine_reset(void);

static uint8_t saved_palette[ULTIMATE_PALETTE_BYTES];
static uint8_t palette[ULTIMATE_PALETTE_BYTES];
static uint8_t voice_target[6];
static uint8_t current_tune = TUNE;
extern uint8_t visualizer_level[6];
extern uint8_t music_brightness[6];
extern uint8_t music_energy_peak[6];
#if !SID1_ADDRESS
static ultimate_sid_info sid_info;
#endif

static const char *song_title[7] = {
    "DIVISION BY ZERO", "DEVICE NOT PRESENT", "FORMULA TOO COMPLEX",
    "OVERFLOW", "CAN'T CONTINUE", "REDO FROM START",
    "RETURN WITHOUT GOSUB"
};

static void fail(const char *message, uint8_t err)
{
    DEMO_STATUS[4] = 0x80;
    DEMO_STATUS[5] = err;
    clrscr();
    bordercolor(COLOR_BLACK);
    bgcolor(COLOR_BLACK);
    textcolor(COLOR_WHITE);
    cputsxy(2, 4, message);
    if (err) cprintf("\r\n\r\n  SDK ERROR: %u", err);
    cputs("\r\n\r\n  RESET AFTER CORRECTING THE PROBLEM.");
}

static uint8_t valid_sid(uint16_t address)
{
    return address >= 0xD400 && address <= 0xDFE0 &&
           (address & 0x001F) == 0;
}

static uint8_t find_sid_pair(uint16_t *first, uint16_t *second)
{
#if SID1_ADDRESS && SID2_ADDRESS
    if (!valid_sid(SID1_ADDRESS) || !valid_sid(SID2_ADDRESS))
        return ULTIMATE_ERR_INVALID_ARGUMENT;
    *first = SID1_ADDRESS;
    *second = SID2_ADDRESS;
    return ULTIMATE_OK;
#else
    uint8_t i;
    uint8_t found = 0;
    uint8_t err = ultimate_legacy_get_sid_info(&sid_info);
    if (err != ULTIMATE_OK) return err;
    for (i = 0; i < sid_info.count; ++i) {
        uint8_t kind = (uint8_t)(sid_info.sid[i].type & 0x7F);
        uint16_t address = sid_info.sid[i].primary_address;
        /* HWINFO returns UltiSIDs first. Types 4 and 5 are the two physical
         * U64 sockets; use their configured primaries, never mirror aliases. */
        if ((kind == 4 || kind == 5) && valid_sid(address)) {
            if (!found) {
                *first = address;
                found = 1;
            } else if (address != *first) {
                *second = address;
                if (*second == 0xD400) {
                    address = *first;
                    *first = *second;
                    *second = address;
                }
                return ULTIMATE_OK;
            }
        }
    }
    return ULTIMATE_ERR_NOT_SUPPORTED;
#endif
}

static void draw_song(void)
{
    const char *title = song_title[current_tune];
    uint8_t x = (uint8_t)((40 - strlen(title)) / 2);
    uint8_t c;
    memset(SCREEN + 40, ' ', 40);
    memset(VIZ_COLOR_RAM + 40, 15, 40);
    while ((c = (uint8_t)*title++) != 0)
        SCREEN[40 + x++] = c >= 'A' && c <= 'Z' ? (uint8_t)(c & 0x3F) : c;
    SCREEN[(uint16_t)23 * 40 + 29] = (uint8_t)('1' + current_tune);
    DEMO_STATUS[14] = current_tune;
}

static void draw_screen(uint16_t first, uint16_t second)
{
    uint8_t voice, x, y;
    clrscr();
    VIC_BORDER = COLOR_BLACK;
    VIC_BG = COLOR_BLACK;
    textcolor(15);                 /* keep labels off the six animated colours */
    cputsxy(3, 0, "MACHINE YEARNING // SIX VOICES");
    cputsxy(14, 22, "SDK " SDK_VERSION);
    gotoxy(5, 23);
    cprintf("SID $%04X + $%04X  TUNE %u", first, second, current_tune + 1);
    cputsxy(2, 24, "A/D OR CURSORS: SONG  RUN/STOP: EXIT");
    for (voice = 0; voice < 6; ++voice) {
        x = (uint8_t)(2 + voice * 6);
        for (y = BAR_TOP; y <= BAR_BOTTOM; ++y) {
            memset(SCREEN + (uint16_t)y * 40 + x, BLOCK, 5);
            memset(VIZ_COLOR_RAM + (uint16_t)y * 40 + x, COLOR_BLACK, 5);
        }
    }
    draw_song();
}

static uint8_t update_palette(void)
{
    uint8_t i, delta;
    for (i = 0; i < 6; ++i) {
        if (visualizer_level[i] < voice_target[i]) {
            delta = voice_target[i] - visualizer_level[i];
            visualizer_level[i] += delta > 64 ? 64 : delta;
        } else if (visualizer_level[i] > voice_target[i]) {
            delta = visualizer_level[i] - voice_target[i];
            visualizer_level[i] -= delta > 12 ? 12 : delta;
        }
    }
    for (i = 0; i < 6; ++i) DEMO_STATUS[7 + i] = visualizer_level[i];
    palette[0] = palette[1] = palette[2] = 0;
    palette[3] = visualizer_level[0]; palette[4] = palette[5] = 0;
    palette[6] = 0; palette[7] = visualizer_level[1]; palette[8] = 0;
    palette[9] = palette[10] = 0; palette[11] = visualizer_level[2];
    palette[12] = visualizer_level[3];
    palette[13] = (visualizer_level[3] >> 1) + (visualizer_level[3] >> 3);
    palette[14] = 0;
    palette[15] = palette[16] = visualizer_level[4]; palette[17] = 0;
    palette[18] = (visualizer_level[5] >> 1) + (visualizer_level[5] >> 2);
    palette[19] = 0; palette[20] = visualizer_level[5];
    palette[45] = palette[46] = palette[47] = 255;
    return ultimate_palette_set(palette);
}

static uint8_t stop_pressed(void)
{
    uint8_t port = CIA1_PRA;
    uint8_t direction = CIA1_DDRA;
    uint8_t pressed;
    CIA1_DDRA = 0xFF;
    CIA1_PRA = 0x7F;
    pressed = (CIA1_PRB & 0x80) == 0;
    CIA1_PRA = port;
    CIA1_DDRA = direction;
    return pressed;
}

static uint8_t key_row(uint8_t row)
{
    uint8_t port = CIA1_PRA;
    uint8_t dira = CIA1_DDRA;
    uint8_t dirb = CIA1_DDRB;
    uint8_t keys;
    CIA1_DDRA = 0xFF;
    CIA1_DDRB = 0x00;
    CIA1_PRA = (uint8_t)~(1u << row);
    keys = (uint8_t)~CIA1_PRB;
    CIA1_PRA = port;
    CIA1_DDRA = dira;
    CIA1_DDRB = dirb;
    return keys;
}

#define SONG_PREV 0x01
#define SONG_NEXT 0x02

static uint8_t song_keys(void)
{
    uint8_t row0 = key_row(0);
    uint8_t row1 = key_row(1);
    uint8_t row2 = key_row(2);
    uint8_t keys = 0;
    if (row1 & 0x04) keys |= SONG_PREV; /* A */
    if (row2 & 0x04) keys |= SONG_NEXT; /* D */
    if (row0 & 0x04) {                  /* horizontal cursor key */
        if ((row1 & 0x80) || (key_row(6) & 0x10)) keys |= SONG_PREV;
        else keys |= SONG_NEXT;
    }
    return keys;
}

static void silence(uint16_t base)
{
    volatile uint8_t *sid = (volatile uint8_t *)base;
    uint8_t i;
    for (i = 0; i < 25; ++i) sid[i] = 0;
}

static void start_music_timer(void)
{
    uint16_t latch = PAL_FLAG ? 9851 : 10226;
    CIA1_CRA = 0;
    CIA1_ICR = 0x7F;
    (void)CIA1_ICR;
    *(uint16_t *)0x0314 = (uint16_t)music_irq;
    CIA1_TALO = (uint8_t)latch;
    CIA1_TAHI = (uint8_t)(latch >> 8);
    CIA1_ICR = 0x81;
    CIA1_CRA = 0x11;
}

int main(void)
{
    uint16_t sid1, sid2;
    uint8_t err;
    uint8_t saved_speed;
    uint8_t palette_line = PAL_FLAG ? 251 : 203;
    uint8_t keys = 0;
    uint8_t pressed;
    uint8_t previous_keys = 0;

    DEMO_STATUS[0] = 0x53;
    DEMO_STATUS[1] = 0x56;
    DEMO_STATUS[2] = 0x49;
    DEMO_STATUS[3] = 0x5A;
    DEMO_STATUS[4] = 1;
    DEMO_STATUS[5] = 0;
    DEMO_STATUS[6] = 0;
    DEMO_STATUS[13] = 0;
    DEMO_STATUS[14] = current_tune;
    DEMO_STATUS[21] = 0;
    clrscr();
    bordercolor(COLOR_BLACK);
    bgcolor(COLOR_BLACK);
    textcolor(COLOR_WHITE);
    cputsxy(5, 5, "CHECKING ULTIMATE FEATURES...");
    err = ultimate_init();
    if (err != ULTIMATE_OK) {
        fail("ULTIMATE COMMAND INTERFACE NOT FOUND.", err);
        return err;
    }
    err = ultimate_palette_get(saved_palette);
    if (err != ULTIMATE_OK) {
        fail("PALETTE UCI NEEDS FIRMWARE AFTER 3.15.", err);
        return err;
    }
    err = find_sid_pair(&sid1, &sid2);
    if (err != ULTIMATE_OK) {
        fail("MAP TWO SIDS TO DISTINCT ADDRESSES.", err);
        cputs("\r\n  TRY $D400 AND $D500.");
        return err;
    }
    saved_speed = ultimate_turbo_get();
    if (saved_speed == U64_TURBO_UNAVAILABLE) {
        fail("ENABLE U64 TURBO REGISTERS.", ULTIMATE_ERR_NOT_SUPPORTED);
        return ULTIMATE_ERR_NOT_SUPPORTED;
    }
    err = ultimate_turbo_set(U64_SPEED_4MHZ);
    if (err != ULTIMATE_OK) {
        fail("COULD NOT ENABLE 4 MHZ TURBO.", err);
        return err;
    }

    memcpy(palette, saved_palette, sizeof(palette));
    *(uint16_t *)0x100F = sid1;
    *(uint16_t *)0x1016 = sid2;
    draw_screen(sid1, sid2);
    DEMO_STATUS[4] = 2;
    __asm__("sei");
    CIA1_CRA = 0;
    CIA1_ICR = 0x7F;
    (void)CIA1_ICR;
    music_meter_reset();
    music_init(current_tune);
    DEMO_STATUS[4] = 3;
    start_music_timer();
    DEMO_STATUS[4] = 4;
    __asm__("cli");

    for (;;) {
        while (VIC_RASTER < palette_line) {}
        /* Sending 48 RGB bytes takes about 47 raster lines before firmware
         * applies them. Start early so the visible change lands near line 300
         * on PAL or line 250 on NTSC: inside vertical blank on both systems. */
        ++DEMO_STATUS[21];
        __asm__("sei");
        for (err = 0; err < 6; ++err) {
            voice_target[err] = music_energy_peak[err]
                ? (music_brightness[err] >> 1) + (music_energy_peak[err] >> 1)
                : 0;
        }
        err = update_palette();
        __asm__("cli");
        if (err != ULTIMATE_OK) break;
        keys = 0;
        if ((DEMO_STATUS[21] & 7) == 2) {
            pressed = song_keys();
            keys = pressed & (uint8_t)~previous_keys;
            previous_keys = pressed;
            if (keys == SONG_PREV)
                current_tune = current_tune ? (uint8_t)(current_tune - 1) : 6;
            else if (keys == SONG_NEXT)
                current_tune = current_tune == 6 ? 0 : (uint8_t)(current_tune + 1);
            else keys = 0;
        }
        if (keys) {
            __asm__("sei");
            CIA1_CRA = 0;
            CIA1_ICR = 0x7F;
            (void)CIA1_ICR;
            silence(sid1);
            silence(sid2);
            memset(voice_target, 0, sizeof(voice_target));
            memset(visualizer_level, 0, sizeof(visualizer_level));
            music_meter_reset();
            for (err = 0; err < 6; ++err)
                for (keys = BAR_TOP; keys <= BAR_BOTTOM; ++keys)
                    memset(VIZ_COLOR_RAM + (uint16_t)keys * 40 +
                           2 + err * 6, COLOR_BLACK, 5);
            music_init(current_tune);
            start_music_timer();
            draw_song();
            __asm__("cli");
        }
        __asm__("sei");
        music_render_bars();
        __asm__("cli");
        if (DEMO_STATUS[13] || stop_pressed()) {
            if (!DEMO_STATUS[13]) while (stop_pressed()) {}
            break;
        }
        while (VIC_RASTER >= palette_line) {}
    }

    __asm__("sei");
    CIA1_CRA = 0;
    CIA1_ICR = 0x7F;
    silence(sid1);
    silence(sid2);
    ultimate_palette_set(saved_palette);
    ultimate_turbo_set(saved_speed);
    machine_reset();
    return 0;
}
