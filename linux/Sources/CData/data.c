#include "ember_data.h"

#define INCBIN(name, file) \
    __asm__(".section .rodata\n.balign 16\n.global " #name "\n" #name ":\n.incbin \"" EMBER_DATA_DIR "/" file "\"\n.global " #name "_end\n" #name "_end:\n.byte 0\n.previous\n"); \
    extern const unsigned char name[], name##_end[];

INCBIN(ember_light, "iris-light.jpg")
INCBIN(ember_dark, "iris-dark.jpg")

const unsigned char *ember_wallpaper(int dark, size_t *size) {
    if (dark) { *size = (size_t)(ember_dark_end - ember_dark); return ember_dark; }
    *size = (size_t)(ember_light_end - ember_light);
    return ember_light;
}
