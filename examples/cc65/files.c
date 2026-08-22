/*
 * files.c - what is on the medium, and what the machine is holding.
 *
 * Prints the current directory with a size against every entry, then reports
 * the emulated drives, the clock, and the RAM expansion. Nothing here writes
 * to the medium or changes the machine.
 *
 * Build:  make
 * Run:    load the .prg on any Ultimate with the command interface enabled.
 *
 * SPDX-License-Identifier: MIT
 */

#include <stdio.h>
#include <string.h>
#include <ultimate.h>

/*
 * Every display string is lowercase. cc65 applies the c64 charmap to string
 * literals: source 'A'-'Z' becomes PETSCII $C1-$DA, which CHROUT renders as
 * graphics symbols, and source 'a'-'z' becomes $41-$5A, which renders as
 * letters. tools/test_charmap.py fails the build on an uppercase one.
 */

static ultimate_capabilities caps;
static ultimate_fileinfo     info;
static ultimate_drives       drives;
static char                  path[64];
static char                  name[ULTIMATE_NAME_MAX + 1];
static char                  clock[ULTIMATE_TIME_BUFFER];

/* The drive type codes CTRL_CMD_GET_DRVINFO reports, as words. */
static const char *drive_type(uint8_t type)
{
    switch (type) {
    case CTRL_DRVTYPE_1541:      return "1541";
    case CTRL_DRVTYPE_1571:      return "1571";
    case CTRL_DRVTYPE_1581:      return "1581";
    case CTRL_DRVTYPE_UNDECIDED: return "undecided";
    case CTRL_DRVTYPE_SOFTIEC:   return "softiec";
    case CTRL_DRVTYPE_PRINTER:   return "printer";
    default:                     return "unknown";
    }
}

/*
 * One directory, one line per entry.
 *
 * A walk is a single live exchange with the Ultimate: the firmware sends one
 * entry per reply block and holds each one until it is released, so no other
 * command may be issued until the walk has finished. That is why the names are
 * collected first and stat'ed afterwards - a stat in the middle of the loop
 * would end the walk.
 *
 * ULTIMATE_END is how a walk finishes. It is a result of its own so that a
 * caller never has to tell "no more entries" apart from "something broke".
 */
#define MAX_ENTRIES 24

static char    entries[MAX_ENTRIES][ULTIMATE_NAME_MAX + 1];
static uint8_t attribs[MAX_ENTRIES];

static uint8_t list_directory(void)
{
    uint8_t err;
    uint8_t count = 0;

    err = ultimate_opendir();
    if (err != ULTIMATE_OK) {
        printf("cannot read this directory: %s\n", ultimate_strerror(err));
        return 0;
    }

    /*
     * The whole directory is read even when there is no room left for it: the
     * walk has to reach its end, or the firmware is left holding a block. What
     * does not fit is dropped rather than the loop stopping early.
     */
    for (;;) {
        uint8_t attrib = 0;

        err = ultimate_readdir(name, sizeof(name), &attrib);
        if (err != ULTIMATE_OK)
            break;
        if (count < MAX_ENTRIES) {
            strcpy(entries[count], name);
            attribs[count] = attrib;
            ++count;
        }
    }

    /*
     * A walk read to ULTIMATE_END needs nothing further. One given up part way
     * through leaves the firmware holding a reply block, and until that block
     * is released no command can be issued at all - uci_abort() releases it.
     */
    if (err != ULTIMATE_END)
        uci_abort();

    return count;
}

int main(void)
{
    uint8_t  err;
    uint8_t  i;
    uint8_t  count;
    uint16_t banks;

    printf("ultimate sdk - files\n\n");

    err = ultimate_init();
    if (err != ULTIMATE_OK) {
        printf("no ultimate: %s\n", ultimate_strerror(err));
        printf("is the command interface enabled\n");
        printf("in the ultimate settings menu?\n");
        return 1;
    }
    ultimate_detect(&caps);

    if (ultimate_getpath(path, sizeof(path), NULL) == ULTIMATE_OK)
        printf("in %s\n\n", path);

    count = list_directory();
    for (i = 0; i < count; ++i) {
        if (attribs[i] & DOS_ATTR_DIR) {
            printf("%-16s <dir>\n", entries[i]);
            continue;
        }
        /*
         * The size is what a program usually wants from a directory: how much
         * room to reserve before loading. It costs one command per entry, so a
         * lister that only needs names should not ask for it.
         */
        if (ultimate_stat(entries[i], &info) == ULTIMATE_OK)
            printf("%-16s %lu\n", entries[i], info.size);
        else
            printf("%-16s ?\n", entries[i]);
    }

    /* The clock. Firmware without one answers ULTIMATE_ERR_NOT_SUPPORTED. */
    printf("\n");
    if (ultimate_get_time(ULTIMATE_TIME_PLAIN, clock, sizeof(clock), NULL)
            == ULTIMATE_OK)
        printf("time    : %s\n", clock);
    else
        printf("time    : no clock on this firmware\n");

    /*
     * The emulated drives. The device number is the one ultimate_mount() takes,
     * so this is how a program finds out where to mount a disk image without
     * asking its user.
     */
    if (ultimate_drive_info(&drives) == ULTIMATE_OK) {
        for (i = 0; i < drives.count; ++i)
            printf("drive %u : device %u, %s, %s\n",
                   i, drives.drive[i].device,
                   drive_type(drives.drive[i].type),
                   drives.drive[i].power ? "running" : "off");
    } else {
        printf("drives  : no drive commands on this firmware\n");
    }

    banks = ultimate_reu_size();
    if (banks != 0)
        printf("reu     : %u banks of 64k\n", banks);
    else
        printf("reu     : none\n");

    return 0;
}
