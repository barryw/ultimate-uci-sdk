/* Legacy example: HWINFO is deprecated and may disappear. SPDX-License-Identifier: MIT */

#include <stdio.h>
#include <ultimate.h>

int main(void)
{
    ultimate_sid_info info;
    uint8_t err;
    uint8_t i;

    err = ultimate_init();
    if (err == ULTIMATE_OK)
        err = ultimate_legacy_get_sid_info(&info);
    if (err != ULTIMATE_OK) {
        printf("sid info: %s\n", ultimate_strerror(err));
        return 1;
    }

    printf("sid count: %u\n", info.count);
    for (i = 0; i < info.count; ++i) {
        printf("sid %u: $%04x", (uint8_t)(i + 1),
               info.sid[i].primary_address);
        if (info.sid[i].secondary_address != 0)
            printf(" / $%04x", info.sid[i].secondary_address);
        printf(" type $%02x\n", info.sid[i].type);
    }
    return 0;
}
