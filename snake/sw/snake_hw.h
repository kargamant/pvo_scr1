// snake_hw.h -- hardware interface for the SCR1 snake peripherals.
// Matches snake/doc/hw_contract.md and the vga_ctrl / ps2_kbd RTL.
#ifndef SNAKE_HW_H
#define SNAKE_HW_H

#include <stdint.h>

// ---- VGA tile framebuffer (0xFF02_0000) : word-per-cell, low 4 bits = colour
#define VGA_BASE   0xFF020000u
#define GRID_W     40
#define GRID_H     30
#define VGA        ((volatile uint32_t *)VGA_BASE)
// cell address stride is 64 (row << 6) | col  -- see hw_contract.md
static inline void vga_cell(int x, int y, uint32_t color) {
    VGA[((y) << 6) | (x)] = color;
}

// palette indices (fixed in RTL)
enum {
    C_BG    = 0,   // black background
    C_BODY  = 1,   // green snake body
    C_HEAD  = 2,   // bright green head
    C_APPLE = 3,   // red apple
    C_WALL  = 4,   // grey wall
    C_TEXT  = 5,   // white (score pips)
};

// ---- PS/2 keyboard (0xFF03_0000)
#define KBD_BASE   0xFF030000u
#define KBD        ((volatile uint32_t *)KBD_BASE)
#define KBD_STATUS 0   // word offset 0x00 : bit0 = data_valid
#define KBD_DATA   1   // word offset 0x04 : read pops a scancode

static inline int kbd_has_data(void) { return KBD[KBD_STATUS] & 1u; }
static inline int kbd_pop(void)      { return (int)(KBD[KBD_DATA] & 0xFFu); }

// set-2 scancodes for WASD
#define SC_W   0x1D
#define SC_A   0x1C
#define SC_S   0x1B
#define SC_D   0x23
#define SC_BREAK 0xF0   // key-release prefix (next byte ignored)
#define SC_EXT   0xE0   // extended prefix (arrows etc.) -- skip next

// ---- cycle counter (rv32 rdcycle, low 32 bits) for step timing / rng seed
static inline uint32_t rdcycle(void) {
    uint32_t v;
    __asm__ volatile ("rdcycle %0" : "=r"(v));
    return v;
}

#endif // SNAKE_HW_H
