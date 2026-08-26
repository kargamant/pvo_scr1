// ============================================================================
// doomgeneric_scr1.c -- doomgeneric platform layer for the SCR1 SoC.
//
// Provides the DG_* entry points doomgeneric requires, plus the paletted
// fast-path hooks the engine's i_video.c should call (this SoC has a HARDWARE
// 256-colour palette + 8bpp framebuffer, so we do NOT use the 32-bit
// DG_ScreenBuffer path -- see doom/INTEGRATION.md for the two i_video hooks).
//
// Build against doomgeneric: needs doomgeneric.h + doomkeys.h on the include
// path. CPU is 30 MHz (SYS_CLK); adjust if you re-clock.
// ============================================================================
#include <stdint.h>
#include <string.h>
#include "doom_hw.h"
#include "doomgeneric.h"
#include "doomkeys.h"
#ifdef DOOM_FPS
#include <stdio.h>          // printf -> UART (via picolibc stdout = dg_putc)
#endif

#ifndef SYS_CLK
#define SYS_CLK 30000000u
#endif
#define CYC_PER_MS (SYS_CLK / 1000u)

// ---------------------------------------------------------------- timing ----
void DG_Init(void) {
    // clear the framebuffer to palette index 0
    for (unsigned w = 0; w < FB_WORDS; w++) FB[w] = 0;
}

uint32_t DG_GetTicksMs(void) {
    static uint64_t acc = 0;
    static uint32_t last = 0;
    static int init = 0;
    uint32_t now = rdcycle();
    if (!init) { last = now; init = 1; }
    acc += (uint32_t)(now - last);      // unsigned diff handles 32-bit wrap
    last = now;
    return (uint32_t)(acc / CYC_PER_MS);
}

void DG_SleepMs(uint32_t ms) {
    uint32_t t0 = rdcycle();
    uint32_t target = ms * CYC_PER_MS;
    while ((uint32_t)(rdcycle() - t0) < target) { /* spin */ }
}

void DG_SetWindowTitle(const char *title) { (void)title; }

// stock doomgeneric calls DG_DrawFrame after filling the 32-bit DG_ScreenBuffer;
// we render via the paletted hook instead, so this is a no-op.
void DG_DrawFrame(void) { }

// --------------------------------------------------- paletted video hooks ----
// Call from the engine's i_video.c I_SetPalette(): `palette` is 256*3 bytes,
// each channel 0..255 (already gamma-applied by the engine).
void SCR1_SetPalette(const uint8_t *palette) {
    for (int i = 0; i < 256; i++) {
        uint8_t r = palette[3*i + 0];
        uint8_t g = palette[3*i + 1];
        uint8_t b = palette[3*i + 2];
        pal_set(i, r, g, b);
    }
}

// Call per palette entry from I_SetPalette() with the gamma-corrected RGB.
void SCR1_SetPaletteEntry(int idx, unsigned char r, unsigned char g, unsigned char b) {
    pal_set((unsigned)idx, r, g, b);
}

// Call from I_FinishUpdate(): `screen` is the 320x200 8bpp buffer (screens[0]).
void SCR1_FinishUpdate(const uint8_t *screen) {
    fb_blit8(screen);
#ifdef DOOM_FPS
    // Frame counter -> UART: once ~1 s of cycles elapse, print averaged FPS
    // (one decimal). rdcycle is 32-bit; unsigned diff is wrap-safe over 1 s.
    static uint32_t frames = 0, t0 = 0; static int init = 0;
    uint32_t now = rdcycle();
    if (!init) { t0 = now; init = 1; }
    frames++;
    uint32_t dt = now - t0;
    if (dt >= SYS_CLK) {                                     // ~1 second window
        uint32_t fps10 = (uint32_t)(((uint64_t)frames * 10u * SYS_CLK) / dt);
        printf("[FPS] %u.%u\n", (unsigned)(fps10 / 10u), (unsigned)(fps10 % 10u));
        frames = 0; t0 = now;
    }
#endif
}

// ---------------------------------------------------------------- keyboard ---
// PS/2 set-2 -> doom keys, with 0xF0 (break) and 0xE0 (extended) handling.
// A small ring buffer feeds DG_GetKey().
static struct { unsigned char pressed, key; } kq[64];
static int kq_head = 0, kq_tail = 0;

static void kq_push(int pressed, int key) {
    int n = (kq_head + 1) & 63;
    if (n != kq_tail) { kq[kq_head].pressed = pressed; kq[kq_head].key = key; kq_head = n; }
}

static int map_plain(int sc) {          // non-extended set-2 make codes
    switch (sc) {
        case 0x1D: return KEY_UPARROW;      // W
        case 0x1B: return KEY_DOWNARROW;    // S
        case 0x1C: return KEY_LEFTARROW;    // A
        case 0x23: return KEY_RIGHTARROW;   // D
        case 0x14: return KEY_FIRE;         // L-Ctrl
        case 0x29: return KEY_USE;          // Space
        case 0x12: return KEY_RSHIFT;       // L-Shift (run)
        case 0x11: return KEY_STRAFE_L;     // L-Alt (hold strafe)  [approx]
        case 0x5A: return KEY_ENTER;
        case 0x76: return KEY_ESCAPE;
        case 0x0D: return KEY_TAB;
        case 0x66: return KEY_BACKSPACE;
        case 0x1A: return KEY_STRAFE_L;     // Z
        case 0x22: return KEY_STRAFE_R;     // X
        case 0x16: return '1'; case 0x1E: return '2'; case 0x26: return '3';
        case 0x25: return '4'; case 0x2E: return '5'; case 0x36: return '6';
        case 0x3D: return '7'; case 0x3E: return '8'; case 0x46: return '9';
        case 0x35: return 'y'; case 0x31: return 'n';
        default:   return 0;
    }
}

static int map_ext(int sc) {            // 0xE0-prefixed
    switch (sc) {
        case 0x75: return KEY_UPARROW;
        case 0x72: return KEY_DOWNARROW;
        case 0x6B: return KEY_LEFTARROW;
        case 0x74: return KEY_RIGHTARROW;
        case 0x14: return KEY_FIRE;         // R-Ctrl
        default:   return 0;
    }
}

// pump the PS/2 FIFO into the event ring; call each frame / tic
void SCR1_KbdPump(void) {
    static int ext = 0, brk = 0;
    while (kbd_has_data()) {
        int c = kbd_pop();
        if (c == 0xE0) { ext = 1; continue; }
        if (c == 0xF0) { brk = 1; continue; }
        int key = ext ? map_ext(c) : map_plain(c);
        if (key) kq_push(brk ? 0 : 1, key);
        ext = 0; brk = 0;
    }
}

int DG_GetKey(int *pressed, unsigned char *doomKey) {
    SCR1_KbdPump();
    if (kq_head == kq_tail) return 0;
    *pressed  = kq[kq_tail].pressed;
    *doomKey  = kq[kq_tail].key;
    kq_tail   = (kq_tail + 1) & 63;
    return 1;
}
