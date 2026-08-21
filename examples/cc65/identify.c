/*
 * identify.c - the Ultimate SDK vertical slice, from cc65.
 *
 * Finds the Ultimate, asks every target whether it exists, and prints what it
 * found. This is the whole "is there an Ultimate, and what can it do?" question
 * answered in about thirty lines.
 *
 * Build:  make
 * Run:    load the .prg on any Ultimate with the command interface enabled.
 *
 * SPDX-License-Identifier: MIT
 */

#include <stdio.h>
#include <ultimate.h>

/*
 * Written lowercase on purpose. cc65 applies the c64 charmap to string
 * literals exactly as ca65 does: source 'A'-'Z' becomes PETSCII $C1-$DA, which
 * CHROUT renders as *graphics symbols*, and source 'a'-'z' becomes $41-$5A,
 * which renders as letters. Every display string in this repo is lowercase for
 * that reason, and tools/test_charmap.py fails the build if one is not.
 */
static const struct {
    uint8_t     id;
    const char *name;
} targets[] = {
    { UCI_TARGET_DOS1,    "dos 1"   },
    { UCI_TARGET_DOS2,    "dos 2"   },
    { UCI_TARGET_NETWORK, "network" },
    { UCI_TARGET_CONTROL, "control" },
    { UCI_TARGET_SOFTIEC, "softiec" },
    { UCI_TARGET_HTTP,    "http"    },
};


/*
 * The Ultimate speaks ASCII. Target identification strings are uppercase and
 * print as-is, but the model name from deprecated CTRL_CMD_GET_HWINFO is mixed case
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

int main(void)
{
    ultimate_capabilities caps;
    char    name[48];
    uint8_t i;
    uint8_t err;

    printf("ultimate sdk - identify\n\n");

    err = ultimate_init();
    if (err != ULTIMATE_OK) {
        printf("no ultimate: %s\n", ultimate_strerror(err));
        printf("is the command interface enabled\n");
        printf("in the ultimate settings menu?\n");
        return 1;
    }

    ultimate_detect(&caps);

    if (ultimate_get_model(name, sizeof(name), NULL) == ULTIMATE_OK) {
        ascii_upper(name);
        printf("model   : %s\n", name);
    } else
        printf("model   : unknown (old firmware)\n");
    printf("id reg  : $%02x\n\n", caps.ident);

    for (i = 0; i < sizeof(targets) / sizeof(targets[0]); ++i) {
        err = ultimate_identify(targets[i].id, name, sizeof(name), NULL);
        if (err == ULTIMATE_OK)
            printf("%-8s: %s\n", targets[i].name, name);
        else
            printf("%-8s: -\n", targets[i].name);
    }

    printf("\n");
    if (ultimate_has_http(&caps))
        printf("http available: fw 3.15 or newer\n");
    else
        printf("no http target on this firmware\n");

    return 0;
}
