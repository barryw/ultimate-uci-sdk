#include <ultimate.h>

int main(void)
{
    unsigned char color = 2;
    if (ultimate_turbo_available())
        color = 5;
    *(volatile unsigned char *)0xd020 = color;
    return 0;
}
