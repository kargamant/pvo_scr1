// fb_test.c -- vga_fb self-test: draws colour bars + grayscale gradient + white
// border straight into the 320x200 framebuffer, then holds. Proves the pixel
// framebuffer + HW palette + 25 MHz readout independently of the DOOM engine.
#include "doom_hw.h"
#include "sc_print.h"

static inline uint8_t color_at(int x, int y) {
    if (x < 2 || x >= DOOM_W - 2 || y < 2 || y >= DOOM_H - 2) return 255; // white border
    if (y < DOOM_H / 2)  return (uint8_t)(1 + (x / 40));                  // 8 colour bars
    return (uint8_t)(16 + (x * 239) / DOOM_W);                           // grayscale ramp
}

int main(void) {
    sc_printf("vga_fb self-test: 8 colour bars + gray ramp + white border\n");

    // palette: 1..8 = distinct colours, 16..255 = grayscale, 255 = white
    pal_set(0,   0,   0,   0);
    pal_set(1, 255,   0,   0);  pal_set(2,   0, 255,   0);  pal_set(3,   0,   0, 255);
    pal_set(4, 255, 255,   0);  pal_set(5,   0, 255, 255);  pal_set(6, 255,   0, 255);
    pal_set(7, 255, 128,   0);  pal_set(8, 128, 128, 255);
    for (int i = 16; i < 256; i++) { uint8_t g = (uint8_t)i; pal_set(i, g, g, g); }
    pal_set(255, 255, 255, 255);

    // draw, packing 4 pixels per 32-bit word
    for (int y = 0; y < DOOM_H; y++) {
        for (int x = 0; x < DOOM_W; x += 4) {
            uint32_t w = (uint32_t)color_at(x + 0, y)
                       | ((uint32_t)color_at(x + 1, y) << 8)
                       | ((uint32_t)color_at(x + 2, y) << 16)
                       | ((uint32_t)color_at(x + 3, y) << 24);
            FB[(y * DOOM_W + x) >> 2] = w;
        }
    }

    sc_printf("held\n");
    for (;;) { }
}
