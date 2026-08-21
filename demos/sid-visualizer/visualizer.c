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
#define CIA1_TALO    (*(volatile uint8_t *)0xDC04)
#define CIA1_TAHI    (*(volatile uint8_t *)0xDC05)
#define CIA1_ICR     (*(volatile uint8_t *)0xDC0D)
#define CIA1_CRA     (*(volatile uint8_t *)0xDC0E)
#define VIC_BORDER   (*(volatile uint8_t *)0xD020)
#define VIC_BG       (*(volatile uint8_t *)0xD021)
#define BLOCK        0xA0
#define PLAYER_ZP(a) (*(volatile uint8_t *)(a))
#define DEMO_STATUS  ((volatile uint8_t *)0x033C)

void __fastcall__ music_init(uint8_t tune);
void music_play(void);
void machine_reset(void);

static uint8_t saved_palette[ULTIMATE_PALETTE_BYTES];
static uint8_t palette[ULTIMATE_PALETTE_BYTES];
extern uint8_t visualizer_level[6];
#if !SID1_ADDRESS
static ultimate_sid_info sid_info;
#endif

static const uint8_t shadow[6] = {0x58, 0x5F, 0x66, 0x89, 0x90, 0x97};
static const uint8_t mask[6]   = {0x08, 0x0F, 0x16, 0x39, 0x40, 0x47};
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
    uint8_t i, j, a, b;
    uint8_t err = ultimate_legacy_get_sid_info(&sid_info);
    if (err != ULTIMATE_OK) return err;
    for (i = 0; i < sid_info.count; ++i) {
        uint16_t left[2];
        left[0] = sid_info.sid[i].primary_address;
        left[1] = sid_info.sid[i].secondary_address;
        for (j = (uint8_t)(i + 1); j < sid_info.count; ++j) {
            uint16_t right[2];
            right[0] = sid_info.sid[j].primary_address;
            right[1] = sid_info.sid[j].secondary_address;
            for (a = 0; a < 2; ++a)
                for (b = 0; b < 2; ++b)
                    if (valid_sid(left[a]) && valid_sid(right[b]) &&
                        left[a] != right[b]) {
                        if (right[b] == 0xD400) {
                            *first = right[b];
                            *second = left[a];
                        } else {
                            *first = left[a];
                            *second = right[b];
                        }
                        return ULTIMATE_OK;
                    }
        }
    }
    return ULTIMATE_ERR_NOT_SUPPORTED;
#endif
}

static void draw_screen(uint16_t first, uint16_t second)
{
    uint8_t voice, x, y;
    clrscr();
    VIC_BORDER = COLOR_BLACK;
    VIC_BG = COLOR_BLACK;
    textcolor(15);                 /* keep labels off the six animated colours */
    cputsxy(3, 0, "MACHINE YEARNING // SIX VOICES");
    cputsxy((uint8_t)((40 - strlen(song_title[TUNE])) / 2), 1,
            song_title[TUNE]);
    cputsxy(14, 22, "SDK " SDK_VERSION);
    gotoxy(5, 23);
    cprintf("SID $%04X + $%04X  TUNE %u", first, second, TUNE + 1);
    cputsxy(9, 24, "RUN/STOP TO EXIT");
    for (voice = 0; voice < 6; ++voice) {
        x = (uint8_t)(2 + voice * 6);
        for (y = 3; y < 21; ++y) {
            memset(SCREEN + (uint16_t)y * 40 + x, BLOCK, 5);
            memset(VIZ_COLOR_RAM + (uint16_t)y * 40 + x, voice + 1, 5);
        }
    }
}

static uint8_t voice_level(uint8_t voice)
{
    uint8_t s = shadow[voice];
    uint8_t m = mask[voice];
    uint8_t hi = PLAYER_ZP(s + 1) & PLAYER_ZP(m + 1);
    uint8_t control = PLAYER_ZP(s + 4) & PLAYER_ZP(m + 4);
    uint16_t bright;

    if ((control & 0xF1) == 0x01 || !(control & 0x01)) {
        return visualizer_level[voice] > 8 ?
               (uint8_t)(visualizer_level[voice] - 8) : 0;
    }
    bright = (uint16_t)32 + hi - (hi >> 3);
    return bright > 255 ? 255 : (uint8_t)bright;
}

static void rgb(uint8_t index, uint8_t r, uint8_t g, uint8_t b)
{
    uint8_t *p = palette + (uint8_t)(index * 3);
    p[0] = r;
    p[1] = g;
    p[2] = b;
}

static uint8_t update_palette(void)
{
    uint8_t i;
    for (i = 0; i < 6; ++i) visualizer_level[i] = voice_level(i);
    for (i = 0; i < 6; ++i) DEMO_STATUS[7 + i] = visualizer_level[i];
    rgb(0, 0, 0, 0);
    rgb(1, visualizer_level[0], 0, 0);
    rgb(2, 0, visualizer_level[1], 0);
    rgb(3, 0, 0, visualizer_level[2]);
    rgb(4, visualizer_level[3], visualizer_level[3] >> 2, 0);
    rgb(5, visualizer_level[4], visualizer_level[4], 0);
    rgb(6, visualizer_level[5] >> 1, 0, visualizer_level[5]);
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

static void silence(uint16_t base)
{
    volatile uint8_t *sid = (volatile uint8_t *)base;
    uint8_t i;
    for (i = 0; i < 25; ++i) sid[i] = 0;
}

int main(void)
{
    uint16_t sid1, sid2;
    uint8_t err;
    uint8_t half = 0;

    DEMO_STATUS[0] = 0x53;
    DEMO_STATUS[1] = 0x56;
    DEMO_STATUS[2] = 0x49;
    DEMO_STATUS[3] = 0x5A;
    DEMO_STATUS[4] = 1;
    DEMO_STATUS[5] = 0;
    DEMO_STATUS[6] = 0;
    DEMO_STATUS[13] = 0;
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

    memcpy(palette, saved_palette, sizeof(palette));
    *(uint16_t *)0x100F = sid1;
    *(uint16_t *)0x1016 = sid2;
    draw_screen(sid1, sid2);
    DEMO_STATUS[4] = 2;
    music_init(TUNE);
    DEMO_STATUS[4] = 3;

    __asm__("sei");
    CIA1_CRA = 0;
    CIA1_ICR = 0x7F;
    (void)CIA1_ICR;
    CIA1_TALO = 0x63;
    CIA1_TAHI = 0x26;
    CIA1_CRA = 0x11;

    for (;;) {
        while (!(CIA1_ICR & 0x01)) {}
        music_play();
        ++DEMO_STATUS[6];
        DEMO_STATUS[4] = 4;
        half ^= 1;
        if (!half) {
            err = update_palette();
            if (err != ULTIMATE_OK) break;
            if (DEMO_STATUS[13] || stop_pressed()) {
                if (!DEMO_STATUS[13]) while (stop_pressed()) {}
                break;
            }
        }
    }

    CIA1_CRA = 0;
    silence(sid1);
    silence(sid2);
    ultimate_palette_set(saved_palette);
    machine_reset();
    return 0;
}
