// doom_hw.h -- SCR1 hardware interface for the DOOM pixel framebuffer + palette
// + PS/2 keyboard. Matches doom/rtl/vga_fb.sv and the ps2_kbd from the snake SoC.
#ifndef DOOM_HW_H
#define DOOM_HW_H

#include <stdint.h>

// ---- pixel framebuffer 320x200 x 8bpp (4 pixels per 32-bit word) ----
#define DOOM_W     320
#define DOOM_H     200
#define FB_BASE    0xFF040000u
#define FB_WORDS   ((DOOM_W * DOOM_H) / 4)          // 16000
#define FB         ((volatile uint32_t *)FB_BASE)
// hardware palette: 256 entries, write 0x00RRGGBB (HW keeps top nibble -> RGB444)
#define PAL        ((volatile uint32_t *)(FB_BASE + 0x10000))

// Blit a 320x200 8-bit paletted frame to the framebuffer, packing 4 px/word.
static inline void fb_blit8(const uint8_t *src) {
    const uint32_t *s = (const uint32_t *)src;      // 4 bytes/pixels at a time
    for (unsigned w = 0; w < FB_WORDS; w++)
        FB[w] = s[w];                               // little-endian: px0 in LSB
}

// Set one palette entry (r,g,b are 0..255; HW uses the top nibble).
static inline void pal_set(unsigned idx, uint8_t r, uint8_t g, uint8_t b) {
    PAL[idx & 0xFF] = ((uint32_t)r << 16) | ((uint32_t)g << 8) | b;
}

// ---- PS/2 keyboard (same slave as snake) ----
#define KBD_BASE   0xFF030000u
#define KBD        ((volatile uint32_t *)KBD_BASE)
#define KBD_STATUS 0
#define KBD_DATA   1
static inline int kbd_has_data(void) { return KBD[KBD_STATUS] & 1u; }
static inline int kbd_pop(void)      { return (int)(KBD[KBD_DATA] & 0xFFu); }

// ---- cycle counter (rv32 rdcycle low 32 bits) ----
static inline uint32_t rdcycle(void) {
    uint32_t v; __asm__ volatile ("rdcycle %0" : "=r"(v)); return v;
}

#endif // DOOM_HW_H
