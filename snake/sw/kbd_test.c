// kbd_test.c -- print every PS/2 scancode received, as hex, over UART.
// Press W/A/S/D (and others) to see the actual codes the board delivers.
// Expected set-2 make codes: W=1d A=1c S=1b D=23 (release prefixed by f0).
#include "snake_hw.h"
#include "sc_print.h"

int main(void) {
    sc_printf("Keyboard test. Press keys; scancodes (hex) follow.\n");
    sc_printf("expect make: W=1d A=1c S=1b D=23 ; release=f0 xx\n");
    int n = 0;
    for (;;) {
        if (kbd_has_data()) {
            int c = kbd_pop();
            sc_printf("%02x ", c);
            if (++n % 16 == 0) sc_printf("\n");
        }
    }
}
