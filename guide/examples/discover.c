#include <stdio.h>
#include <ultimate.h>

/* The complete program printed in "Start and discover the machine." */
int main(void)
{
    ultimate_capabilities caps;
    char text[64];
    uint16_t length;
    uint8_t err = ultimate_init();

    if (err != ULTIMATE_OK || !ultimate_available()) return 1;
    err = ultimate_detect(&caps);
    if (err == ULTIMATE_OK && ultimate_has_http(&caps))
        puts("http target present");

    err = ultimate_identify(UCI_TARGET_DOS1,
                            text, sizeof text, &length);
    if (err == ULTIMATE_OK) printf("dos: %s\n", text);
    err = ultimate_identify(UCI_TARGET_DOS1,
                            text, sizeof text, NULL);

    err = ultimate_get_model(text, sizeof text, &length);
    if (err == ULTIMATE_OK)
        printf("model received: %u bytes\n", length);
    err = ultimate_get_model(text, sizeof text, NULL);
    return err != ULTIMATE_OK;
}
