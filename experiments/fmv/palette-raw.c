/* Raw UCI palette smoke test: no SDK transport code is linked. */

#include <stdint.h>
#include <conio.h>

#define SCREEN      ((volatile uint8_t *)0x0400)
#define CELL_COLORS ((volatile uint8_t *)0xd800)
#define VIC_BORDER  (*(volatile uint8_t *)0xd020)
#define VIC_BG      (*(volatile uint8_t *)0xd021)
#define UCI_CONTROL (*(volatile uint8_t *)0xdf1c)
#define UCI_COMMAND (*(volatile uint8_t *)0xdf1d)
#define STATUS      ((volatile uint8_t *)0x033c)

static void wait_idle(void)
{
    while (UCI_CONTROL & 0x30) {}
}

static void set_color(uint8_t index, uint8_t r, uint8_t g, uint8_t b)
{
    wait_idle();
    UCI_COMMAND = 0x84;          /* control target, no reply */
    UCI_COMMAND = 0x53;          /* SET_PALETTE_COLOR */
    UCI_COMMAND = index;
    UCI_COMMAND = r;
    UCI_COMMAND = g;
    UCI_COMMAND = b;
    UCI_CONTROL = 0x01;          /* push command */
    wait_idle();
}

static void reset_palette(void)
{
    wait_idle();
    UCI_COMMAND = 0x84;          /* control target, no reply */
    UCI_COMMAND = 0x54;          /* RESET_PALETTE */
    UCI_CONTROL = 0x01;
    wait_idle();
}

int main(void)
{
    uint16_t i;

    STATUS[0] = 'R';
    STATUS[1] = 'A';
    STATUS[2] = 'W';
    STATUS[3] = 0;

    for (i = 0; i < 1000; ++i) {
        SCREEN[i] = 0xa0;
        CELL_COLORS[i] = 15;
    }
    VIC_BORDER = 15;
    VIC_BG = 15;

    set_color(15, 255, 0, 0);
    STATUS[3] = UCI_CONTROL;
    cgetc();
    reset_palette();
    VIC_BORDER = 0;
    VIC_BG = 0;
    return 0;
}
