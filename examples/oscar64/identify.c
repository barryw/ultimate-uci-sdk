/*
 * identify.c - the Ultimate SDK vertical slice, from Oscar64.
 *
 * Same program as examples/cc65/identify.c, compiled by a different toolchain
 * against the same SDK source. Nothing about the protocol is repeated here.
 *
 * Build:  make OSCAR64=/path/to/oscar64
 *
 * SPDX-License-Identifier: MIT
 */

#include <stdio.h>
#include <ultimate.h>


/*
 * The Ultimate speaks ASCII. Target identification strings are uppercase and
 * print as-is, but the model name from CTRL_CMD_GET_HWINFO is mixed case
 * ("Ultimate 64 Elite"), and the C64's default character set renders lowercase
 * ASCII as graphics glyphs. Fold it before printing.
 *
 * The bounds are written as numbers on purpose: cc65 translates character
 * constants into the target character set, so 'a' here would compile to $41,
 * not $61. See docs/api-design.md.
 */
#define ASCII_LOWER_A 0x61
#define ASCII_LOWER_Z 0x7A

static void ascii_upper(char *s)
{
    while (*s != '\0') {
        if ((uint8_t)*s >= ASCII_LOWER_A && (uint8_t)*s <= ASCII_LOWER_Z)
            *s = (char)(*s - 0x20);
        ++s;
    }
}

static void show(const char *label, uint8_t target)
{
    char name[48];

    printf("%s", label);
    if (ultimate_identify(target, name, sizeof(name), NULL) == ULTIMATE_OK)
        printf("%s\n", name);
    else
        printf("-\n");
}

int main(void)
{
    ultimate_capabilities caps;
    char    model[32];
    uint8_t err;

    printf("ultimate sdk - identify\n\n");

    err = ultimate_init();
    if (err != ULTIMATE_OK) {
        printf("no ultimate: %s\n", ultimate_strerror(err));
        return 1;
    }

    ultimate_detect(&caps);

    if (ultimate_get_model(model, sizeof(model), NULL) == ULTIMATE_OK) {
        ascii_upper(model);
        printf("model   : %s\n\n", model);
    } else
        printf("model   : unknown\n\n");

    show("dos 1   : ", UCI_TARGET_DOS1);
    show("dos 2   : ", UCI_TARGET_DOS2);
    show("network : ", UCI_TARGET_NETWORK);
    show("control : ", UCI_TARGET_CONTROL);
    show("softiec : ", UCI_TARGET_SOFTIEC);
    show("http    : ", UCI_TARGET_HTTP);

    printf("\n");
    if (ultimate_has_http(&caps))
        printf("http available\n");
    else
        printf("no http target on this firmware\n");

    return 0;
}
