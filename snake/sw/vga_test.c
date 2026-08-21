// vga_test.c -- static VGA self-test: draws an unmistakable image and halts.
// If the monitor shows a white border, green field and a red centre square,
// the whole VGA path (AXI write -> framebuffer -> 25 MHz readout -> palette)
// works. Independent of game logic and keyboard.
#include "snake_hw.h"
#include "sc_print.h"

int main(void) {
    sc_printf("VGA self-test: white border, green field, red square\n");

    for (int y = 0; y < GRID_H; y++)
        for (int x = 0; x < GRID_W; x++)
            vga_cell(x, y, C_BODY);              // green field everywhere

    for (int x = 0; x < GRID_W; x++) {           // white top/bottom border
        vga_cell(x, 0,          C_TEXT);
        vga_cell(x, GRID_H - 1, C_TEXT);
    }
    for (int y = 0; y < GRID_H; y++) {           // white left/right border
        vga_cell(0,          y, C_TEXT);
        vga_cell(GRID_W - 1, y, C_TEXT);
    }
    for (int y = 12; y <= 17; y++)               // red centre square
        for (int x = 17; x <= 22; x++)
            vga_cell(x, y, C_APPLE);

    sc_printf("done drawing, holding image\n");
    for (;;) { }
}
