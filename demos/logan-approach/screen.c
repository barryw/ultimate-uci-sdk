/* Logan Approach operating-screen prototype. */

#include <conio.h>
#include <stdint.h>
#include <ultimate.h>

#define SCREEN ((volatile uint8_t *)0x0400)
#define DISPLAY_SCREEN ((volatile uint8_t *)0x8400)
#define COLOR  ((volatile uint8_t *)0xD800)
#define CHARSET ((volatile uint8_t *)0xB800)
#define CPU_PORT (*(volatile uint8_t *)0x0001)
#define VIC_BANK (*(volatile uint8_t *)0xDD00)
#define VIC_MEMORY (*(volatile uint8_t *)0xD018)
#define VIC_RASTER (*(volatile uint8_t *)0xD012)
#define VIC_CONTROL (*(volatile uint8_t *)0xD011)
#define VIC_IRQ_STATUS (*(volatile uint8_t *)0xD019)
#define VIC_IRQ_ENABLE (*(volatile uint8_t *)0xD01A)
#define VIC_SPRITE_XY ((volatile uint8_t *)0xD000)
#define VIC_SPRITE_X_MSB (*(volatile uint8_t *)0xD010)
#define VIC_SPRITE_ENABLE (*(volatile uint8_t *)0xD015)
#define VIC_SPRITE_Y_EXPAND (*(volatile uint8_t *)0xD017)
#define VIC_SPRITE_PRIORITY (*(volatile uint8_t *)0xD01B)
#define VIC_SPRITE_MULTICOLOR (*(volatile uint8_t *)0xD01C)
#define VIC_SPRITE_X_EXPAND (*(volatile uint8_t *)0xD01D)
#define VIC_SPRITE_COLORS ((volatile uint8_t *)0xD027)
#define SPRITE_POINTERS ((volatile uint8_t *)0x87F8)
#define PLANE_SPRITES ((volatile uint8_t *)0xA000)
#define TAG_SPRITES ((volatile uint8_t *)0xB000)
#define PLANE_PATTERN_BASE 0x80
#define TAG_PATTERN_BASE 0xC0
#define JOYSTICK2 (*(volatile uint8_t *)0xDC00)
#define IRQ_VECTOR (*(volatile uint16_t *)0x0314)
#define DEMO_STATUS ((volatile uint8_t *)0x033C)

#define AIRCRAFT_LARGE_JET 0
#define AIRCRAFT_SMALL_JET 1
#define AIRCRAFT_TURBOPROP 2
#define AIRCRAFT_GA 3
#define AIRCRAFT_COUNT 4
#define VIRTUAL_SPRITE_COUNT 12
#define MUX_EVENT_COUNT 4

#define C_BLACK 0
#define C_WHITE 1
#define C_RED 2
#define C_CYAN 3
#define C_GRID 4
#define C_GREEN 5
#define C_BLUE 6
#define C_YELLOW 7
#define C_DARK_GREY 11
#define C_GREY 12
#define C_LIGHT_GREEN 13
#define C_LIGHT_BLUE 14
#define C_LIGHT_GREY 15

#define G_SEPARATOR 0x60
#define G_COAST 0x61
#define G_TERMINAL 0x62
#define G_PLANE 0x63
#define G_PLANE_SELECTED 0x64
#define G_GATE_N 0x65
#define G_GATE_E 0x66
#define G_GATE_S 0x67
#define G_GATE_W 0x68
#define G_GRID 0x69
#define G_LABEL_32 0x6A
#define AIRPORT_CHAR_BASE 0x80
#define AIRPORT_X 13
#define AIRPORT_Y 6
#define AIRPORT_COLS 14
#define AIRPORT_ROWS 8

static uint8_t old_vic_memory;
static uint8_t old_vic_bank;
static uint16_t old_irq_vector;
static uint8_t saved_palette[ULTIMATE_PALETTE_BYTES];
static uint8_t have_palette;

typedef struct {
    int16_t x, y;
    uint8_t heading, type, altitude, speed, phase, active, tag_above;
    uint8_t base_color, detail_color;
    const char *callsign;
} Aircraft;

typedef struct {
    uint16_t x;
    uint8_t y, pointer, color, front;
} VirtualSprite;

static Aircraft planes[AIRCRAFT_COUNT] = {
    {32, 68, 2, AIRCRAFT_LARGE_JET, 50, 18, 0, 1, 0, C_GREEN, C_WHITE, "J17"},
    {280, 68, 5, AIRCRAFT_SMALL_JET, 70, 24, 8, 1, 0, C_RED, C_WHITE, "A81"},
    {32, 172, 1, AIRCRAFT_TURBOPROP, 30, 16, 16, 1, 1, C_GREEN, C_WHITE, "D24"},
    {296, 172, 7, AIRCRAFT_GA, 80, 21, 24, 1, 1, C_GREEN, C_CYAN, "LOG44"},
};
VirtualSprite virtual_sprites[VIRTUAL_SPRITE_COUNT];
uint8_t virtual_count;
static uint8_t selected_aircraft = 3;
static uint8_t old_joystick;

volatile uint8_t mux_event_count;
volatile uint8_t mux_event_index;
volatile uint8_t mux_ready_raster;
volatile uint8_t virtual_overflow;
uint8_t mux_event_line[MUX_EVENT_COUNT];
uint8_t mux_event_slot[MUX_EVENT_COUNT];
uint8_t mux_event_x[MUX_EVENT_COUNT];
uint8_t mux_event_y[MUX_EVENT_COUNT];
uint8_t mux_event_xmsb[MUX_EVENT_COUNT];
uint8_t mux_event_pointer[MUX_EVENT_COUNT];
uint8_t mux_event_color[MUX_EVENT_COUNT];

void mux_irq(void);
void prepare_multiplexer(void);
void sort_virtual_sprites(void);

static const uint8_t scope_palette[ULTIMATE_PALETTE_BYTES] = {
      3,   8,  12,  210, 224, 218,  255,  68,  54,   69, 216, 202,
     34,  62,  70,   55, 220, 110,   25,  70, 100,  255, 190,  40,
    230, 108,  35,   73,  52,  41,  255, 124, 103,   39,  55,  61,
    104, 125, 128,  126, 255, 157,   75, 135, 170,  175, 194, 193,
};

static const uint8_t glyphs[][8] = {
    {0x00, 0x00, 0xFF, 0x81, 0xFF, 0x00, 0x00, 0x00},
    {0x00, 0x40, 0x08, 0x01, 0x20, 0x04, 0x80, 0x00},
    {0x7E, 0x42, 0x5A, 0x42, 0x5A, 0x42, 0x7E, 0x00},
    {0x18, 0x18, 0x5A, 0xFF, 0x18, 0x3C, 0x24, 0x00},
    {0x18, 0x18, 0x5A, 0xFF, 0x18, 0x7E, 0x42, 0x00},
    {0x18, 0x3C, 0x7E, 0xDB, 0x18, 0x18, 0x18, 0x00},
    {0x10, 0x18, 0xFC, 0xFE, 0xFC, 0x18, 0x10, 0x00},
    {0x18, 0x18, 0x18, 0xDB, 0x7E, 0x3C, 0x18, 0x00},
    {0x08, 0x18, 0x3F, 0x7F, 0x3F, 0x18, 0x08, 0x00},
    {0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00},
    {0x00, 0xE7, 0x21, 0xE7, 0x24, 0xE7, 0x00, 0x00},
};

static const uint8_t tiny_font[][5] = {
    {7, 5, 5, 5, 7}, {2, 6, 2, 2, 7}, {7, 1, 7, 4, 7},
    {7, 1, 7, 1, 7}, {5, 5, 7, 1, 1}, {7, 4, 7, 1, 7},
    {7, 4, 7, 5, 7}, {7, 1, 1, 1, 1}, {7, 5, 7, 5, 7},
    {7, 5, 7, 1, 7}, {4, 4, 4, 4, 7}, {6, 5, 6, 5, 5},
};

static const uint8_t tag_font[][5] = {
    {7, 5, 5, 5, 7}, {2, 6, 2, 2, 7}, {7, 1, 7, 4, 7},
    {7, 1, 7, 1, 7}, {5, 5, 7, 1, 1}, {7, 4, 7, 1, 7},
    {7, 4, 7, 5, 7}, {7, 1, 1, 1, 1}, {7, 5, 7, 5, 7},
    {7, 5, 7, 1, 7},
    {2, 5, 7, 5, 5}, {6, 5, 6, 5, 6}, {7, 4, 4, 4, 7},
    {6, 5, 5, 5, 6}, {7, 4, 6, 4, 7}, {7, 4, 6, 4, 4},
    {7, 4, 5, 5, 7}, {5, 5, 7, 5, 5}, {7, 2, 2, 2, 7},
    {1, 1, 1, 5, 7}, {5, 5, 6, 5, 5}, {4, 4, 4, 4, 7},
    {5, 7, 7, 5, 5}, {5, 7, 7, 7, 5}, {7, 5, 5, 5, 7},
    {6, 5, 6, 4, 4}, {7, 5, 5, 7, 1}, {6, 5, 6, 5, 5},
    {7, 4, 7, 1, 7}, {7, 2, 2, 2, 2}, {5, 5, 5, 5, 7},
    {5, 5, 5, 5, 2}, {5, 5, 7, 7, 5}, {5, 5, 2, 5, 5},
    {5, 5, 2, 2, 2}, {7, 1, 2, 4, 7},
};

static void wait_frame(void)
{
    while (VIC_RASTER < 250) {}
    while (VIC_RASTER >= 250) {}
}

static void cell(uint8_t x, uint8_t y, uint8_t ch, uint8_t color)
{
    uint16_t offset;
    if (x >= 40 || y >= 25) return;
    offset = (uint16_t)y * 40 + x;
    SCREEN[offset] = ch;
    COLOR[offset] = color;
}

static void label(uint8_t x, uint8_t y, const char *text, uint8_t color)
{
    textcolor(color);
    cputsxy(x, y, text);
}

static void sprite_pixel(uint8_t type, uint8_t heading, uint8_t layer, int x, int y)
{
    uint16_t offset;
    if (x < 0 || x >= 24 || y < 0 || y >= 21) return;
    offset = (((uint16_t)type * 8 + heading) * 2 + layer) * 64 +
        (uint16_t)y * 3 + (x >> 3);
    PLANE_SPRITES[offset] |= (uint8_t)(0x80 >> (x & 7));
}

static void build_plane_sprites(void)
{
    static const int8_t forward_x[8] = {0, 1, 1, 1, 0, -1, -1, -1};
    static const int8_t forward_y[8] = {-1, -1, 0, 1, 1, 1, 0, -1};
    uint16_t i;
    uint8_t heading, type;
    int x, y, px, py, dx, dy, ax, width, right_x, right_y;
    uint8_t body, detail;

    for (i = 0; i < 4096; ++i) PLANE_SPRITES[i] = 0;
    for (type = 0; type < AIRCRAFT_COUNT; ++type) {
        for (heading = 0; heading < 8; ++heading) {
            right_x = -forward_y[heading];
            right_y = forward_x[heading];
            for (py = 0; py < 21; ++py) {
                for (px = 0; px < 24; ++px) {
                    dx = px - 12;
                    dy = py - 10;
                    x = dx * right_x + dy * right_y;
                    y = -(dx * forward_x[heading] + dy * forward_y[heading]);
                    if (heading & 1) { x = x * 2 / 3; y = y * 2 / 3; }
                    ax = x < 0 ? -x : x;
                    width = 0;
                    if (type == AIRCRAFT_LARGE_JET) {
                        if (y >= -8 && y <= -3) width = 1;
                        else if (y == -2) width = 3;
                        else if (y == -1) width = 6;
                        else if (y == 0) width = 9;
                        else if (y == 1) width = 6;
                        else if (y >= 2 && y <= 5) width = 1;
                        else if (y == 6) width = 4;
                        else if (y == 7) width = 3;
                        else if (y == 8) width = 1;
                        body = y >= -9 && y <= 8 && ax <= width;
                        detail = (x == 0 && y >= -7 && y <= 7) ||
                            (y == 0 && ax <= 7) || (y == 6 && ax <= 3);
                    } else if (type == AIRCRAFT_SMALL_JET) {
                        if (y >= -6 && y <= -3) width = 1;
                        else if (y == -2) width = 2;
                        else if (y == -1) width = 4;
                        else if (y == 0) width = 6;
                        else if (y == 1) width = 4;
                        else if (y >= 2 && y <= 4) width = 1;
                        else if (y == 5) width = 3;
                        else if (y == 6) width = 2;
                        body = y >= -7 && y <= 7 && ax <= width;
                        detail = (x == 0 && y >= -5 && y <= 5) ||
                            (y == 0 && ax <= 5) || (y == 5 && ax <= 2);
                    } else if (type == AIRCRAFT_TURBOPROP) {
                        if (y >= -7 && y <= -3) width = 1;
                        else if (y == -2 || y == 1) width = 2;
                        else if (y == -1 || y == 0) width = 7;
                        else if (y >= 2 && y <= 4) width = 1;
                        else if (y == 5) width = 3;
                        else if (y == 6) width = 2;
                        body = y >= -8 && y <= 7 && ax <= width;
                        detail = (x == 0 && y >= -6 && y <= 6) ||
                            (y == -1 && (ax == 3 || ax == 4)) ||
                            (y == 0 && (ax == 5 || ax == 6)) ||
                            (y == 5 && ax <= 2);
                    } else {
                        if (y >= -5 && y <= -2) width = 1;
                        else if (y == -1 || y == 0) width = 5;
                        else if (y >= 1 && y <= 3) width = 1;
                        else if (y == 4) width = 2;
                        else if (y == 5) width = 1;
                        body = y >= -6 && y <= 6 && ax <= width;
                        detail = (x == 0 && y >= -4 && y <= 4) ||
                            (y == -1 && ax <= 4) || (y == 4 && ax <= 1);
                    }
                    if (!body) continue;
                    sprite_pixel(type, heading, 0, px, py);
                    if (detail) sprite_pixel(type, heading, 1, px, py);
                }
            }
        }
    }
}

static void tag_pixel(uint8_t aircraft, uint8_t x, uint8_t y)
{
    uint16_t offset;
    if (x >= 24 || y >= 21) return;
    offset = (uint16_t)aircraft * 64 + (uint16_t)y * 3 + (x >> 3);
    TAG_SPRITES[offset] |= (uint8_t)(0x80 >> (x & 7));
}

static uint8_t tag_index(char ch)
{
    if (ch >= '0' && ch <= '9') return (uint8_t)(ch - '0');
    if (ch >= 'A' && ch <= 'Z') return (uint8_t)(ch - 'A' + 10);
    if (ch >= 'a' && ch <= 'z') return (uint8_t)(ch - 'a' + 10);
    return 0xFF;
}

static void tag_text(uint8_t aircraft, uint8_t y, const char *text)
{
    uint8_t x = 0;
    uint8_t row, col, bits, glyph;
    while (*text && x < 24) {
        glyph = tag_index(*text++);
        if (glyph != 0xFF) {
            for (row = 0; row < 5; ++row) {
                bits = tag_font[glyph][row];
                for (col = 0; col < 3; ++col)
                    if (bits & (4 >> col)) tag_pixel(aircraft, x + col, y + row);
            }
        }
        x += 4;
    }
}

static void build_tag_sprite(uint8_t aircraft)
{
    char data[7];
    uint8_t i;
    Aircraft *plane = &planes[aircraft];
    for (i = 0; i < 64; ++i) TAG_SPRITES[(uint16_t)aircraft * 64 + i] = 0;
    tag_text(aircraft, 0, plane->callsign);
    data[0] = (char)('0' + plane->altitude / 100);
    data[1] = (char)('0' + plane->altitude / 10 % 10);
    data[2] = (char)('0' + plane->altitude % 10);
    data[3] = ' ';
    data[4] = (char)('0' + plane->speed / 10);
    data[5] = (char)('0' + plane->speed % 10);
    data[6] = 0;
    tag_text(aircraft, 6, data);
}

static void setup_aircraft(void)
{
    uint8_t i;
    build_plane_sprites();
    for (i = 0; i < AIRCRAFT_COUNT; ++i) build_tag_sprite(i);
    VIC_SPRITE_ENABLE = 0;
    VIC_SPRITE_X_MSB = 0;
    VIC_SPRITE_MULTICOLOR = 0;
    VIC_SPRITE_X_EXPAND = 0;
    VIC_SPRITE_Y_EXPAND = 0;
    VIC_SPRITE_PRIORITY = 0;
}

static void coastline(int x0, int y0, int x1, int y1)
{
    int dx = x1 > x0 ? x1 - x0 : x0 - x1;
    int sx = x0 < x1 ? 1 : -1;
    int dy = y1 > y0 ? y0 - y1 : y1 - y0;
    int sy = y0 < y1 ? 1 : -1;
    int error = dx + dy;
    int twice;

    for (;;) {
        cell((uint8_t)x0, (uint8_t)y0, G_COAST, C_BLUE);
        if (x0 == x1 && y0 == y1) break;
        twice = error * 2;
        if (twice >= dy) { error += dy; x0 += sx; }
        if (twice <= dx) { error += dx; y0 += sy; }
    }
}

static void airport_pixel(int x, int y)
{
    uint16_t tile;
    if (x < 0 || x >= AIRPORT_COLS * 8 || y < 0 || y >= AIRPORT_ROWS * 8) return;
    tile = (uint16_t)(y >> 3) * AIRPORT_COLS + (x >> 3);
    CHARSET[((uint16_t)AIRPORT_CHAR_BASE + tile) * 8 + (y & 7)] |=
        (uint8_t)(0x80 >> (x & 7));
}

static void airport_line(int x0, int y0, int x1, int y1)
{
    int dx = x1 > x0 ? x1 - x0 : x0 - x1;
    int sx = x0 < x1 ? 1 : -1;
    int dy = y1 > y0 ? y0 - y1 : y1 - y0;
    int sy = y0 < y1 ? 1 : -1;
    int error = dx + dy;
    int twice;

    for (;;) {
        airport_pixel(x0, y0);
        if (x0 == x1 && y0 == y1) break;
        twice = error * 2;
        if (twice >= dy) { error += dy; x0 += sx; }
        if (twice <= dx) { error += dx; y0 += sy; }
    }
}

static void airport_runway(int x0, int y0, int x1, int y1)
{
    airport_line(x0, y0, x1, y1);
    airport_line(x0, y0 + 1, x1, y1 + 1);
}

static uint8_t tiny_index(char ch)
{
    if (ch >= '0' && ch <= '9') return (uint8_t)(ch - '0');
    return ch == 'l' ? 10 : 11;
}

static void airport_tiny_text(int x, int y, const char *text)
{
    uint8_t row, col, bits;
    while (*text) {
        for (row = 0; row < 5; ++row) {
            bits = tiny_font[tiny_index(*text)][row];
            for (col = 0; col < 3; ++col)
                if (bits & (4 >> col)) airport_pixel(x + col, y + row);
        }
        x += 4;
        ++text;
    }
}

static void build_airport_chars(void)
{
    uint16_t i;
    for (i = 0; i < AIRPORT_COLS * AIRPORT_ROWS * 8; ++i)
        CHARSET[(uint16_t)AIRPORT_CHAR_BASE * 8 + i] = 0;
    airport_runway(15, 55, 77, 8);   /* 04L / 22R */
    airport_runway(25, 61, 88, 14);  /* 04R / 22L */
    airport_runway(26, 4, 76, 59);   /* 15R / 33L */
    airport_runway(40, 3, 90, 57);   /* 15L / 33R */
    airport_runway(8, 43, 104, 43);  /* 09 / 27 */
    airport_runway(66, 4, 105, 51);  /* 14 / 32 */
    airport_tiny_text(4, 55, "4l");
    airport_tiny_text(17, 57, "4r");
    airport_tiny_text(80, 2, "22r");
    airport_tiny_text(91, 10, "22l");
    airport_tiny_text(14, 0, "15r");
    airport_tiny_text(42, 0, "15l");
    airport_tiny_text(78, 57, "33l");
    airport_tiny_text(90, 58, "33r");
    airport_tiny_text(2, 37, "9");
    airport_tiny_text(103, 37, "27");
    airport_tiny_text(57, 0, "14");
}

static void install_charset(void)
{
    uint16_t i;
    uint8_t old_port = CPU_PORT;

    __asm__("sei");
    CPU_PORT = old_port & 0xFB;
    for (i = 0; i < 2048; ++i) CHARSET[i] = ((volatile uint8_t *)0xD000)[i];
    CPU_PORT = old_port;
    __asm__("cli");
    for (i = 0; i < sizeof(glyphs); ++i)
        CHARSET[(uint16_t)G_SEPARATOR * 8 + i] = ((const uint8_t *)glyphs)[i];
    build_airport_chars();
    old_vic_memory = VIC_MEMORY;
    old_vic_bank = VIC_BANK;
    VIC_BANK = (old_vic_bank & 0xFC) | 0x01;
    VIC_MEMORY = 0x1E;
}

static void draw_harbor(void)
{
    coastline(12, 5, 26, 4);
    coastline(26, 4, 30, 8);
    coastline(30, 8, 29, 14);
    coastline(29, 14, 24, 16);
    coastline(24, 16, 13, 15);
    coastline(13, 15, 10, 11);
    coastline(10, 11, 12, 5);
}

static void draw_airport(void)
{
    uint8_t x, y;
    uint8_t code = AIRPORT_CHAR_BASE;
    for (y = 0; y < AIRPORT_ROWS; ++y)
        for (x = 0; x < AIRPORT_COLS; ++x)
            cell(AIRPORT_X + x, AIRPORT_Y + y, code++, C_LIGHT_GREY);
    cell(19, 9, G_TERMINAL, C_CYAN);
    cell(27, 13, G_LABEL_32, C_LIGHT_GREY);
}

static void draw_gates(void)
{
    label(17, 1, "mon", C_LIGHT_BLUE);
    cell(20, 1, G_GATE_N, C_LIGHT_BLUE);
    cell(0, 7, G_GATE_W, C_LIGHT_BLUE);
    label(1, 7, "chi", C_LIGHT_BLUE);
    cell(0, 14, G_GATE_W, C_LIGHT_BLUE);
    label(1, 14, "lax", C_LIGHT_BLUE);
    label(36, 8, "lon", C_LIGHT_BLUE);
    cell(39, 8, G_GATE_E, C_LIGHT_BLUE);
    label(9, 18, "dal", C_LIGHT_BLUE);
    cell(12, 18, G_GATE_S, C_LIGHT_BLUE);
    label(25, 18, "mia", C_LIGHT_BLUE);
    cell(28, 18, G_GATE_S, C_LIGHT_BLUE);
}

static void draw_grid(void)
{
    uint8_t x, y;
    for (y = 1; y < 19; ++y)
        for (x = 0; x < 40; ++x)
            cell(x, y, G_GRID, C_GRID);
}

static void draw_panel(void)
{
    uint8_t x;
    for (x = 0; x < 40; ++x) cell(x, 19, G_SEPARATOR, C_DARK_GREY);
    label(0, 20, "departures", C_CYAN);
    label(18, 20, "selected: log744h", C_YELLOW);
    label(0, 21, "a swa492 22r ord", C_LIGHT_GREEN);
    label(20, 21, "alt 040 > 070", C_WHITE);
    label(0, 22, "b jbu117 22l jfk", C_LIGHT_GREEN);
    label(20, 22, "hdg 225 > 315", C_WHITE);
    label(0, 23, "c n172sp 09  pwm", C_LIGHT_GREEN);
    label(20, 23, "spd 210  wake h", C_WHITE);
    label(1, 24, "1-4 sel joy turn/alt fire on/off", C_GREY);
}

static void draw_screen(void)
{
    uint16_t i;
    clrscr();
    bgcolor(C_BLACK);
    bordercolor(C_DARK_GREY);
    label(0, 0, "logan approach", C_CYAN);
    label(16, 0, "12:49", C_WHITE);
    label(23, 0, "arr 06 dep 03", C_LIGHT_GREEN);
    draw_grid();
    draw_harbor();
    draw_airport();
    draw_gates();
    draw_panel();
    for (i = 0; i < 1000; ++i) DISPLAY_SCREEN[i] = SCREEN[i];
}

static void add_virtual(uint16_t x, uint8_t y, uint8_t pointer, uint8_t color,
                        uint8_t front)
{
    VirtualSprite *sprite;
    if (virtual_count >= VIRTUAL_SPRITE_COUNT) {
        virtual_overflow = 1;
        return;
    }
    sprite = &virtual_sprites[virtual_count++];
    sprite->x = x;
    sprite->y = y;
    sprite->pointer = pointer;
    sprite->color = color;
    sprite->front = front;
}

static void build_virtual_sprites(void)
{
    uint8_t i, j, shape, body_color, overlaps;
    int16_t tag_x, tag_y;
    Aircraft *plane;

    virtual_count = 0;
    virtual_overflow = 0;
    for (i = 0; i < AIRCRAFT_COUNT; ++i) {
        plane = &planes[i];
        if (!plane->active) continue;
        shape = PLANE_PATTERN_BASE + ((plane->type * 8 + plane->heading) * 2);
        body_color = i == selected_aircraft ? C_YELLOW : plane->base_color;
        add_virtual((uint16_t)plane->x, (uint8_t)plane->y,
                    shape, body_color, 0);
        tag_x = plane->x > 288 ? plane->x - 18 : plane->x + 14;
        tag_y = plane->tag_above ? plane->y - 30 : plane->y + 30;
        add_virtual((uint16_t)tag_x, (uint8_t)tag_y,
                    TAG_PATTERN_BASE + i, body_color, 0);
    }
    for (i = 0; i < AIRCRAFT_COUNT; ++i) {
        plane = &planes[i];
        if (!plane->active) continue;
        overlaps = 0;
        for (j = 0; j < virtual_count; ++j)
            if ((uint16_t)virtual_sprites[j].y < (uint16_t)plane->y + 29 &&
                (uint16_t)plane->y < (uint16_t)virtual_sprites[j].y + 29)
                ++overlaps;
        if (overlaps >= 8) continue;
        shape = PLANE_PATTERN_BASE + ((plane->type * 8 + plane->heading) * 2);
        add_virtual((uint16_t)plane->x, (uint8_t)plane->y,
                    shape + 1, plane->detail_color, 1);
    }
}

static void move_aircraft(void)
{
    static const int8_t dx[8] = {0, 1, 1, 1, 0, -1, -1, -1};
    static const int8_t dy[8] = {-1, -1, 0, 1, 1, 1, 0, -1};
    uint8_t i, low_y, high_y;
    Aircraft *plane;

    for (i = 0; i < AIRCRAFT_COUNT; ++i) {
        plane = &planes[i];
        if (!plane->active) continue;
        plane->phase += plane->speed;
        if (plane->phase < 32) continue;
        plane->phase -= 32;
        plane->x += dx[plane->heading];
        plane->y += dy[plane->heading];
        if (plane->x < 16) plane->x = 328;
        else if (plane->x > 328) plane->x = 16;
        low_y = plane->tag_above ? 90 : 58;
        high_y = plane->tag_above ? 188 : 158;
        if (plane->y < low_y) plane->y = high_y;
        else if (plane->y > high_y) plane->y = low_y;
    }
}

static uint8_t handle_input(void)
{
    uint8_t key, joystick, pressed;
    Aircraft *plane;

    if (kbhit()) {
        key = cgetc();
        if (key == CH_STOP) return 0;
        if (key >= '1' && key <= '4') selected_aircraft = key - '1';
    }
    joystick = (uint8_t)(~JOYSTICK2) & 0x1F;
    pressed = joystick & (uint8_t)~old_joystick;
    old_joystick = joystick;
    plane = &planes[selected_aircraft];
    if (pressed & 0x04) plane->heading = (plane->heading + 7) & 7;
    if (pressed & 0x08) plane->heading = (plane->heading + 1) & 7;
    if ((pressed & 0x01) && plane->altitude <= 245) {
        plane->altitude += 10;
        build_tag_sprite(selected_aircraft);
    }
    if ((pressed & 0x02) && plane->altitude >= 10) {
        plane->altitude -= 10;
        build_tag_sprite(selected_aircraft);
    }
    if (pressed & 0x10) plane->active ^= 1;
    return 1;
}

static void install_multiplexer(void)
{
    __asm__("sei");
    old_irq_vector = IRQ_VECTOR;
    VIC_IRQ_ENABLE &= 0xFE;
    VIC_IRQ_STATUS = 1;
    IRQ_VECTOR = (uint16_t)mux_irq;
    __asm__("cli");
}

static void remove_multiplexer(void)
{
    __asm__("sei");
    VIC_IRQ_ENABLE &= 0xFE;
    VIC_IRQ_STATUS = 1;
    IRQ_VECTOR = old_irq_vector;
    __asm__("cli");
}

int main(void)
{
    DEMO_STATUS[0] = 'L';
    DEMO_STATUS[1] = 'M';
    DEMO_STATUS[2] = 'U';
    DEMO_STATUS[3] = 'X';
    if (ultimate_init() == ULTIMATE_OK &&
        ultimate_palette_get(saved_palette) == ULTIMATE_OK &&
        ultimate_palette_set(scope_palette) == ULTIMATE_OK)
        have_palette = 1;
    install_charset();
    draw_screen();
    setup_aircraft();
    install_multiplexer();
    build_virtual_sprites();
    sort_virtual_sprites();
    for (;;) {
        wait_frame();
        prepare_multiplexer();
        DEMO_STATUS[4] = virtual_count;
        DEMO_STATUS[5] = mux_event_count;
        DEMO_STATUS[6] = mux_ready_raster;
        DEMO_STATUS[7] = virtual_overflow;
        DEMO_STATUS[8] = VIC_RASTER;
        if (!handle_input()) break;
        move_aircraft();
        build_virtual_sprites();
        sort_virtual_sprites();
    }
    remove_multiplexer();
    VIC_SPRITE_ENABLE = 0;
    VIC_MEMORY = old_vic_memory;
    VIC_BANK = old_vic_bank;
    if (have_palette) ultimate_palette_set(saved_palette);
    clrscr();
    return 0;
}
