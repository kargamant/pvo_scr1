// wad_blob.S -- embed the DOOM IWAD into the binary as a rodata blob.
// Drop `doom1.wad` (shareware, freely distributable) next to this file.
// syscalls_doom.c serves file reads from doom_wad[] .. doom_wad_end[].
//
// Only assembled by the `doom` Makefile target (needs doom1.wad present).
    .section .rodata
    .balign 4
    .global doom_wad
doom_wad:
    .incbin "doom1.wad"
    .balign 4
    .global doom_wad_end
doom_wad_end:
