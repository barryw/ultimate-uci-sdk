/* Stream a 22.05 kHz stereo WAV from Ultimate storage into Ultimate Audio. */

#include <c64.h>
#include <conio.h>
#include <stdint.h>
#include <string.h>

#include <ultimate.h>

#ifndef SDK_VERSION
#define SDK_VERSION "dev"
#endif

#define VIZ_SCREEN     ((uint8_t *)0x0400)
#define VIZ_COLOR_RAM  ((uint8_t *)0xD800)
#define VIC_RASTER     (*(volatile uint8_t *)0xD012)
#define VIC_BORDER     (*(volatile uint8_t *)0xD020)
#define VIC_BG         (*(volatile uint8_t *)0xD021)
#define CIA1_PRA       (*(volatile uint8_t *)0xDC00)
#define CIA1_PRB       (*(volatile uint8_t *)0xDC01)
#define CIA1_DDRA      (*(volatile uint8_t *)0xDC02)
#define PAL_FLAG       (*(uint8_t *)0x02A6)
#define STATUS         ((volatile uint8_t *)0x033C)
#ifndef WAV_PATH
#define WAV_PATH       "/usb1/hall22.wav"
#endif
#define BUFFER_SIZE    0x100000UL
#define PAIR_COUNT     2
#ifndef REFILL_SIZE
#define REFILL_SIZE    0x4000UL
#endif
#define AUDIO_RATE     283
#define AUDIO_FLAGS    (UA_CTRL_16BIT | UA_CTRL_INTERLEAVE)
#define BAR_TOP        3
#define BAR_BOTTOM     20
#define BAR_ROWS       (BAR_BOTTOM - BAR_TOP + 1)
#define BLOCK          0xA0
#define METER_FRAMES   128
#define METER_BYTES    (METER_FRAMES * 4)

static uint8_t saved_palette[ULTIMATE_PALETTE_BYTES];
static uint8_t palette[ULTIMATE_PALETTE_BYTES];
static uint8_t target[6];
static uint8_t level[6];
static uint8_t pair_ready[PAIR_COUNT];
static uint32_t pair_length[PAIR_COUNT];
static uint32_t remaining;
static uint32_t refill_offset;
static uint32_t refill_length;
static uint32_t refill_remaining;
static uint32_t meter_offset;
static uint8_t refill_buffer[REFILL_SIZE];
#ifndef PCM_AUDIO_ONLY
static int16_t meter[METER_FRAMES * 2];
static uint16_t meter_peak[6];
#endif
static uint8_t active_pair;
static uint8_t refill_pair;
static uint8_t file_open;
static uint8_t finished;
static uint8_t stash_border_frames;

static uint32_t pair_base(uint8_t pair)
{
    return (uint32_t)pair << 20;
}

static uint16_t le16(const uint8_t *p)
{
    return (uint16_t)p[0] | (uint16_t)p[1] << 8;
}

static uint32_t le32(const uint8_t *p)
{
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 |
           (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static uint8_t read_exact(uint8_t *buffer, uint16_t length)
{
    uint16_t got = 0;
    uint8_t err = ultimate_read(buffer, length, &got);
    if (err != ULTIMATE_OK) return err;
    return got == length ? ULTIMATE_OK : ULTIMATE_ERR_PROTOCOL;
}

static uint8_t parse_wav(uint32_t *data_offset, uint32_t *data_length)
{
    uint8_t header[16];
    uint8_t have_format = 0;
    uint32_t position = 12;
    uint32_t size;
    uint32_t next;
    uint8_t err;

    err = ultimate_seek(0);
    if (err != ULTIMATE_OK) return err;
    err = read_exact(header, 12);
    if (err != ULTIMATE_OK) return err;
    if (memcmp(header, "riff", 4) || memcmp(header + 8, "wave", 4))
        return ULTIMATE_ERR_PROTOCOL;

    for (;;) {
        err = ultimate_seek(position);
        if (err != ULTIMATE_OK) return err;
        err = read_exact(header, 8);
        if (err != ULTIMATE_OK) return err;
        size = le32(header + 4);
        next = position + 8 + size + (size & 1);
        if (next <= position) return ULTIMATE_ERR_PROTOCOL;
        if (!memcmp(header, "\x66\x6d\x74\x20", 4)) { /* "fmt " */
            if (size < 16) return ULTIMATE_ERR_PROTOCOL;
            err = read_exact(header, 16);
            if (err != ULTIMATE_OK) return err;
            if (le16(header) != 1 || le16(header + 2) != 2 ||
                le32(header + 4) != 22050UL || le16(header + 12) != 4 ||
                le16(header + 14) != 16)
                return ULTIMATE_ERR_NOT_SUPPORTED;
            have_format = 1;
        } else if (!memcmp(header, "\x64\x61\x74\x61", 4)) { /* "data" */
            if (!have_format || size < 4) return ULTIMATE_ERR_PROTOCOL;
            *data_offset = position + 8;
            *data_length = size & ~3UL;
            return ULTIMATE_OK;
        }
        position = next;
    }
}

static uint8_t configure_pair(uint8_t pair, uint32_t length)
{
    ultimate_audio_voice voice;
    uint8_t err;
    uint8_t left = pair << 1;
    uint32_t base = pair_base(pair);

    memset(&voice, 0, sizeof(voice));
    voice.channel = left;
    voice.flags = AUDIO_FLAGS | UA_CTRL_IRQ;
    voice.volume = UA_VOLUME_MAX;
#ifdef PCM_SINGLE_VOICE
    voice.pan = UA_PAN_CENTER;
#else
    voice.pan = UA_PAN_LEFT;
#endif
    voice.reu_address = base;
    voice.length = length;
    voice.rate = AUDIO_RATE;
    err = ultimate_audio_configure(&voice);
    if (err != ULTIMATE_OK) return err;

#ifndef PCM_SINGLE_VOICE
    voice.channel = left + 1;
    voice.flags = AUDIO_FLAGS;
    voice.pan = UA_PAN_RIGHT;
    voice.reu_address = base + 2;
    voice.length = length - 2;
    err = ultimate_audio_configure(&voice);
    if (err != ULTIMATE_OK) return err;
#endif
    ultimate_audio_irq_clear(left);
#ifndef PCM_SINGLE_VOICE
    ultimate_audio_irq_clear(left + 1);
#endif
    pair_length[pair] = length;
    pair_ready[pair] = 1;
    return ULTIMATE_OK;
}

static uint8_t fill_pair(uint8_t pair)
{
    uint32_t length = remaining > BUFFER_SIZE ? BUFFER_SIZE : remaining;
    uint8_t err;
    if (length < 4) return ULTIMATE_END;
    length &= ~3UL;
    err = ultimate_reu_load(pair_base(pair), length);
    if (err != ULTIMATE_OK) return err;
    remaining -= length;
    return configure_pair(pair, length);
}

static void begin_refill(uint8_t pair)
{
    refill_pair = pair;
    refill_offset = pair_base(pair);
    refill_length = remaining > BUFFER_SIZE ? BUFFER_SIZE : remaining;
    refill_length &= ~3UL;
    refill_remaining = refill_length;
    STATUS[16] = 0;
}

static uint8_t start_pair(uint8_t pair)
{
    uint8_t left = pair << 1;
    uint8_t err;
#ifndef PCM_SINGLE_VOICE
    /* Start the IRQ-bearing left voice last, so its end marks both complete. */
    err = ultimate_audio_start(left + 1, AUDIO_FLAGS);
    if (err != ULTIMATE_OK) return err;
#endif
    err = ultimate_audio_start(left, AUDIO_FLAGS | UA_CTRL_IRQ);
#ifndef PCM_SINGLE_VOICE
    if (err != ULTIMATE_OK) ultimate_audio_stop(left + 1);
#endif
    return err;
}

static void stop_pair(uint8_t pair)
{
    uint8_t left = pair << 1;
    ultimate_audio_stop(left);
#ifndef PCM_SINGLE_VOICE
    ultimate_audio_stop(left + 1);
#endif
    ultimate_audio_irq_clear(left);
#ifndef PCM_SINGLE_VOICE
    ultimate_audio_irq_clear(left + 1);
#endif
}

static uint8_t close_audio_file(void)
{
    uint8_t err;
    if (!file_open) return ULTIMATE_OK;
    file_open = 0;
    err = ultimate_close();
    return err;
}

static uint8_t service_refill(void)
{
    uint32_t length;
    uint16_t got;
    uint8_t err;

    if (!refill_remaining) return ULTIMATE_OK;
    length = refill_remaining > REFILL_SIZE ? REFILL_SIZE : refill_remaining;
    STATUS[15] = 1;
    err = ultimate_read(refill_buffer, (uint16_t)length, &got);
    if (err != ULTIMATE_OK) return err;
    if (got != (uint16_t)length) return ULTIMATE_ERR_PROTOCOL;
    STATUS[15] = 3;
    VIC_BORDER = COLOR_RED;
    err = ultimate_reu_stash((uint16_t)refill_buffer, refill_offset, got);
    if (err != ULTIMATE_OK) return err;
    VIC_BORDER = COLOR_WHITE;
    stash_border_frames = PAL_FLAG ? 50 : 60;
    STATUS[15] = 0;
    ++STATUS[16];
    refill_offset += length;
    refill_remaining -= length;
    remaining -= length;
    if (refill_remaining) return ULTIMATE_OK;
    err = configure_pair(refill_pair, refill_length);
    if (err != ULTIMATE_OK) return err;
    return remaining ? ULTIMATE_OK : close_audio_file();
}

static uint8_t service_audio(void)
{
    uint8_t old_pair;
    uint8_t next_pair;
    uint8_t err;
    uint8_t left = active_pair << 1;

    if (!(ultimate_audio_irq_status() & (1u << left))) return ULTIMATE_OK;
    old_pair = active_pair;
    next_pair = old_pair ^ 1;
    stop_pair(old_pair);
    pair_ready[old_pair] = 0;
    ++STATUS[7];
    if (!pair_ready[next_pair]) {
        if (refill_remaining || remaining >= 4) ++STATUS[14];
        finished = 1;
        return ULTIMATE_OK;
    }
    err = start_pair(next_pair);
    if (err != ULTIMATE_OK) return err;
    active_pair = next_pair;
    STATUS[6] = active_pair;
    meter_offset = 0;
    if (remaining >= 4) begin_refill(old_pair);
    return ULTIMATE_OK;
}

#ifndef PCM_AUDIO_ONLY
static uint16_t magnitude(int32_t value)
{
    return value < 0 ? (uint16_t)-value : (uint16_t)value;
}
#endif

static uint8_t analyze_pcm(void)
{
#ifdef PCM_AUDIO_ONLY
    return ULTIMATE_OK;
#else
    uint32_t sum[6] = { 0, 0, 0, 0, 0, 0 };
    int16_t slow[2];
    int16_t fast[2];
    uint32_t address;
    uint16_t energy;
    uint16_t frames;
    uint16_t i;
    uint8_t channel;
    uint8_t band;
    uint8_t err;

    frames = pair_length[active_pair] < METER_BYTES
        ? (uint16_t)(pair_length[active_pair] >> 2) : METER_FRAMES;
    if (meter_offset + (uint32_t)frames * 4 > pair_length[active_pair])
        meter_offset = pair_length[active_pair] - (uint32_t)frames * 4;
    address = pair_base(active_pair) + meter_offset;
    err = ultimate_reu_fetch((uint16_t)meter, address, frames * 4);
    if (err != ULTIMATE_OK) return err;
    slow[0] = fast[0] = meter[0];
    slow[1] = fast[1] = meter[1];
    for (i = 0; i < frames; ++i) {
        for (channel = 0; channel < 2; ++channel) {
            int16_t sample = meter[(i << 1) + channel];
            slow[channel] += ((int32_t)sample - slow[channel]) / 16;
            fast[channel] += ((int32_t)sample - fast[channel]) / 4;
            band = channel * 3;
            sum[band] += magnitude(slow[channel]);
            sum[band + 1] += magnitude(fast[channel] - slow[channel]);
            sum[band + 2] += magnitude(sample - fast[channel]);
        }
    }
    for (band = 0; band < 6; ++band) {
        energy = (uint16_t)(sum[band] / frames);
        if (energy > meter_peak[band]) meter_peak[band] = energy;
        else if (meter_peak[band] > 64) meter_peak[band] -= meter_peak[band] >> 5;
        target[band] = meter_peak[band]
            ? (uint8_t)((uint32_t)energy * 15 / meter_peak[band]) : 0;
    }
    meter_offset += PAL_FLAG ? 1764UL : 1470UL;
    return ULTIMATE_OK;
#endif
}

static uint8_t update_visual(void)
{
    uint8_t i;
    uint8_t y;
    uint8_t x;
    uint8_t height;
    uint8_t intensity;
    uint8_t err = analyze_pcm();

    if (err != ULTIMATE_OK) return err;
    for (i = 0; i < 6; ++i) {
        if (level[i] < target[i]) {
            level[i] += target[i] - level[i] > 3 ? 3 : target[i] - level[i];
        } else if (level[i] > target[i]) {
            --level[i];
        }
        STATUS[8 + i] = level[i];
        height = (uint8_t)(((uint16_t)level[i] * BAR_ROWS + 7) / 15);
        x = (uint8_t)(2 + i * 6);
        for (y = BAR_TOP; y <= BAR_BOTTOM; ++y)
            memset(VIZ_COLOR_RAM + (uint16_t)y * 40 + x,
                   y > BAR_BOTTOM - height ? i + 1 : COLOR_BLACK, 5);
        intensity = level[i] ? (uint8_t)(32 + level[i] * 14) : 0;
        if (i == 0) {
            palette[3] = intensity; palette[4] = palette[5] = 0;
        } else if (i == 1) {
            palette[6] = 0; palette[7] = intensity; palette[8] = 0;
        } else if (i == 2) {
            palette[9] = palette[10] = 0; palette[11] = intensity;
        } else if (i == 3) {
            palette[12] = intensity; palette[13] = intensity * 5u / 8u;
            palette[14] = 0;
        } else if (i == 4) {
            palette[15] = palette[16] = intensity; palette[17] = 0;
        } else {
            palette[18] = intensity * 3u / 4u; palette[19] = 0;
            palette[20] = intensity;
        }
    }
    palette[45] = palette[46] = palette[47] = 255;
    return ULTIMATE_OK;
}

static void draw_screen(void)
{
    uint8_t voice;
    uint8_t y;
    uint8_t x;
    clrscr();
    VIC_BORDER = COLOR_BLACK;
    VIC_BG = COLOR_BLACK;
    textcolor(15);
    cputsxy(2, 0, "hall of the mountain king // pcm");
    cputsxy(4, 1, "l: low mid high  r: low mid high");
    cputsxy(14, 22, "sdk " SDK_VERSION);
    cputsxy(4, 24, "disk stream // run/stop: exit");
    for (voice = 0; voice < 6; ++voice) {
        x = (uint8_t)(2 + voice * 6);
        for (y = BAR_TOP; y <= BAR_BOTTOM; ++y) {
            memset(VIZ_SCREEN + (uint16_t)y * 40 + x, BLOCK, 5);
            memset(VIZ_COLOR_RAM + (uint16_t)y * 40 + x, COLOR_BLACK, 5);
        }
    }
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

static void puthex(uint8_t value)
{
    static const char digits[] = "0123456789abcdef";
    cputc(digits[value >> 4]);
    cputc(digits[value & 15]);
}

static void fail(const char *message, uint8_t err)
{
    STATUS[4] = 0x80;
    STATUS[5] = err;
    __asm__("cli");
    clrscr();
    bordercolor(COLOR_RED);
    bgcolor(COLOR_BLACK);
    textcolor(COLOR_WHITE);
    cputsxy(2, 5, message);
    cputs("\r\n\r\n  sdk error: $");
    puthex(err);
    cputs("\r\n  stage: $");
    puthex(STATUS[15]);
    cputs("  slice: $");
    puthex(STATUS[16]);
    cputs("\r\n\r\n  run/stop: exit");
    while (!stop_pressed()) {}
    while (stop_pressed()) {}
}

int main(void)
{
    uint32_t data_offset;
    uint8_t err = ULTIMATE_OK;
    uint8_t close_err;
    uint8_t saved_speed = U64_TURBO_UNAVAILABLE;
    uint8_t have_palette = 0;
    uint8_t have_speed = 0;
    uint8_t pair;
    uint8_t raster_line = PAL_FLAG ? 251 : 203;

    /* cc65 maps source lowercase to wire-format ASCII uppercase. */
    memcpy((void *)STATUS, "pviz", 4);
    memset((void *)(STATUS + 4), 0, 18);
    STATUS[4] = 1;
#ifdef STARTUP_PROBE
    while (STATUS[4]) {}
#endif
    clrscr();
    cputsxy(4, 5, "checking ultimate audio...");
    err = ultimate_init();
    if (err != ULTIMATE_OK) goto failed;
    err = ultimate_audio_init();
    if (err != ULTIMATE_OK) goto failed;
    if (ultimate_reu_size() < PAIR_COUNT * 16) {
        err = ULTIMATE_ERR_NOT_SUPPORTED;
        goto failed;
    }
    err = ultimate_palette_get(saved_palette);
    if (err != ULTIMATE_OK) goto failed;
    have_palette = 1;
    memcpy(palette, saved_palette, sizeof(palette));
    saved_speed = ultimate_turbo_get();
    if (saved_speed == U64_TURBO_UNAVAILABLE) {
        err = ULTIMATE_ERR_NOT_SUPPORTED;
        goto failed;
    }
    have_speed = 1;
    err = ultimate_turbo_set(U64_SPEED_MAX);
    if (err != ULTIMATE_OK) goto failed;

    err = ultimate_open(WAV_PATH, DOS_FA_READ);
    if (err != ULTIMATE_OK) goto failed;
    file_open = 1;
    err = parse_wav(&data_offset, &remaining);
    if (err != ULTIMATE_OK) goto failed;
    err = ultimate_seek(data_offset);
    if (err != ULTIMATE_OK) goto failed;
    for (pair = 0; pair < PAIR_COUNT && remaining >= 4; ++pair) {
        err = fill_pair(pair);
        if (err != ULTIMATE_OK) goto failed;
    }
    if (!remaining) {
        err = close_audio_file();
        if (err != ULTIMATE_OK) goto failed;
    }

    draw_screen();
    __asm__("sei");
    active_pair = 0;
    err = start_pair(0);
    if (err != ULTIMATE_OK) goto failed_sei;
    STATUS[4] = 2;
    for (;;) {
        while (VIC_RASTER < raster_line) {
            err = service_audio();
            if (err != ULTIMATE_OK || finished) goto stopped;
        }
        err = update_visual();
        if (err != ULTIMATE_OK) goto stopped;
#ifndef PCM_AUDIO_ONLY
        STATUS[15] = 2;
        err = ultimate_palette_set(palette);
        if (err != ULTIMATE_OK) goto stopped;
        STATUS[15] = 0;
#endif
        err = service_refill();
        if (err != ULTIMATE_OK) goto stopped;
        if (stash_border_frames && !--stash_border_frames)
            VIC_BORDER = COLOR_BLACK;
        if (stop_pressed()) {
            while (stop_pressed()) {}
            goto stopped;
        }
        while (VIC_RASTER >= raster_line) {
            err = service_audio();
            if (err != ULTIMATE_OK || finished) goto stopped;
        }
    }

stopped:
    for (pair = 0; pair < PAIR_COUNT; ++pair) stop_pair(pair);
    STATUS[4] = err == ULTIMATE_OK ? 3 : 0x80;
failed_sei:
    __asm__("cli");
    close_err = close_audio_file();
    if (err == ULTIMATE_OK) err = close_err;
    if (have_palette) ultimate_palette_set(saved_palette);
    if (have_speed) ultimate_turbo_set(saved_speed);
    if (err != ULTIMATE_OK) fail("pcm stream failed.", err);
    else clrscr();
    return err;

failed:
    close_audio_file();
    if (have_palette) ultimate_palette_set(saved_palette);
    if (have_speed) ultimate_turbo_set(saved_speed);
    fail("ultimate pcm needs uci, reu, audio,", err);
    cputs("\r\n  turbo, palette, and /usb1/hall22.wav.");
    return err;
}
