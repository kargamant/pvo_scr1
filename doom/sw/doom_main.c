// doom_main.c -- entry point for DOOM on SCR1. doomgeneric provides
// doomgeneric_Create()/doomgeneric_Tick(); our platform layer
// (doomgeneric_scr1.c) provides DG_* and the paletted video hooks.
#include "doomgeneric.h"

int main(void) {
    char *argv[] = { "doom", "-iwad", "doom1.wad", 0 };
    doomgeneric_Create(3, argv);
    for (;;) doomgeneric_Tick();
    return 0;
}
