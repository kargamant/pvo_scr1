// vga_bands.c -- VGA calibration: 6 full-width horizontal colour bands.
// Reveals (a) which palette indices render, (b) vertical tile scale/extent,
// (c) horizontal extent. Bands (5 rows each, top->bottom):
//   y 0-4 red(3)  5-9 green(1)  10-14 brightgreen(2)
//   y15-19 blue(7) 20-24 white(5) 25-29 yellow(6)
// Corner markers: (0,0) and (39,29) = grey(4).
#include "snake_hw.h"
#include "sc_print.h"

int main(void) {
    static const unsigned char band[6] = {3, 1, 2, 7, 5, 6};
    sc_printf("VGA bands: red/green/brightgreen/blue/white/yellow top->bottom\n");

    for (int y = 0; y < GRID_H; y++) {
        int b = y / 5;                 // 0..5
        unsigned c = band[b];
        for (int x = 0; x < GRID_W; x++)
            vga_cell(x, y, c);
    }
    vga_cell(0, 0, C_WALL);            // grey corner markers
    vga_cell(GRID_W - 1, GRID_H - 1, C_WALL);

    sc_printf("held\n");
    for (;;) { }
}
