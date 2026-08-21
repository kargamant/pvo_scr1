// vga_rwtest.c -- write known values to specific cells, read them back over
// AXI, and print via UART. Decides whether the CPU<->framebuffer addressing is
// self-consistent (isolates write-path bugs from display/readout bugs).
#include "snake_hw.h"
#include "sc_print.h"

static const struct { int x, y, v; } T[] = {
    {0,0,1}, {1,0,2}, {2,0,3}, {0,1,4}, {0,2,5},
    {5,5,6}, {20,15,7}, {39,29,4}, {39,0,5}, {0,29,6},
};
#define N (int)(sizeof(T)/sizeof(T[0]))

int main(void) {
    sc_printf("VGA read/write test\n");
    for (int i = 0; i < N; i++)
        vga_cell(T[i].x, T[i].y, T[i].v);

    int bad = 0;
    for (int i = 0; i < N; i++) {
        unsigned idx = ((unsigned)T[i].y << 6) | (unsigned)T[i].x;
        unsigned rd  = VGA[idx] & 0xFF;
        int ok = ((int)rd == T[i].v);
        if (!ok) bad++;
        sc_printf("(%2d,%2d) idx=%4u wrote=%d read=%u %s\n",
                  T[i].x, T[i].y, idx, T[i].v, rd, ok ? "OK" : "MISMATCH");
    }
    sc_printf("result: %d/%d ok, %d mismatch\n", N - bad, N, bad);
    for (;;) { }
}
