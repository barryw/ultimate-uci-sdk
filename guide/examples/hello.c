#include <stdio.h>
#include <ultimate.h>

int main(void)
{
    uint8_t err = ultimate_init();

    if (err != ULTIMATE_OK)
        printf("ultimate: %s\n", ultimate_strerror(err));
    return err != ULTIMATE_OK;
}
