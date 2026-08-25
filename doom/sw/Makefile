# DOOM-on-SCR1 software.
#   make fb_test       -> build/fb_test.bin      (TCM self-test for vga_fb)
#   make fb_test_ddr   -> build/fb_test_ddr.bin  (same, linked in DDR)
#   make doom          -> build/doom.bin         (needs doomgeneric engine + WAD)
CROSS_PREFIX ?= riscv64-unknown-elf-
CC      := $(CROSS_PREFIX)gcc
OBJCOPY := $(CROSS_PREFIX)objcopy
OBJDUMP := $(CROSS_PREFIX)objdump

MARCH   ?= rv32im_zicsr_zifencei
MABI    ?= ilp32
SYS_CLK ?= 40000000
# pvo_scr1 keeps tests_common under sw/tests/ ; ddr.ld is bundled locally here
COMMON  := ../../sw/tests/tests_common
DDR_LD  := ddr.ld
BUILD   := build
incs    := -I. -I$(COMMON)
defs    := -DSYS_CLK=$(SYS_CLK) -DUART_BAUDRATE=115200 -DRTC_HZ=1000000

CFLAGS  := -O2 -g --specs=picolibc.specs -march=$(MARCH) -mabi=$(MABI) \
           -Wa,-march=$(MARCH) -ffreestanding -ffunction-sections -fdata-sections \
           -Wall -Wextra $(incs) $(defs)
LF_TCM  := --specs=picolibc.specs -march=$(MARCH) -mabi=$(MABI) \
           -nostartfiles -Wl,--gc-sections -T $(COMMON)/tcm.ld
LF_DDR  := --specs=picolibc.specs -march=$(MARCH) -mabi=$(MABI) \
           -nostartfiles -Wl,--gc-sections -T $(DDR_LD)

COMMON_OBJ := $(BUILD)/sc_print.o $(BUILD)/uart.o $(BUILD)/crt-noreloc.o

$(BUILD):
	mkdir -p $(BUILD)
$(BUILD)/%.o: $(COMMON)/%.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@
$(BUILD)/crt-noreloc.o: $(COMMON)/crt-noreloc.S | $(BUILD)
	$(CC) $(CFLAGS) -D__ASSEMBLY__=1 -c $< -o $@
$(BUILD)/%.o: %.c doom_hw.h | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

# ---- vga_fb self-test (TCM) ----
fb_test: $(BUILD)/fb_test.bin
$(BUILD)/fb_test.elf: $(BUILD)/fb_test.o $(COMMON_OBJ)
	$(CC) $(incs) -o $@ $^ $(LF_TCM) -Wl,-Map=$(BUILD)/fb_test.map

# ---- vga_fb self-test (DDR) -- validates the DOOM execution path ----
fb_test_ddr: $(BUILD)/fb_test_ddr.bin
$(BUILD)/fb_test_ddr.elf: $(BUILD)/fb_test.o $(COMMON_OBJ)
	$(CC) $(incs) -o $@ $^ $(LF_DDR) -Wl,-Map=$(BUILD)/fb_test_ddr.map

$(BUILD)/%.bin: $(BUILD)/%.elf
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -D $< > $(basename $@).dump

# ============================================================================
# Full DOOM (DDR). Point DOOMGEN_DIR at the doomgeneric engine sources and put
# doom1.wad in this directory. See ../INTEGRATION.md for the two i_video hooks.
# ============================================================================
DOOMGEN_DIR ?= ../doomgeneric/doomgeneric
# engine .c files, minus doomgeneric's PC platform backends (we supply our own)
# exclude PC platform backends AND sound/joystick/cdmus backends that need
# SDL/Allegro (we build no-sound: FEATURE_SOUND is left undefined -> i_sound.c
# is a stub; joystick/cd functions are stubbed in doomgeneric_scr1.c).
DOOM_ENGINE := $(filter-out %/doomgeneric_sdl.c %/doomgeneric_xlib.c %/doomgeneric_win.c \
                            %/doomgeneric_soso.c %/doomgeneric_sosox.c %/doomgeneric_allegro.c \
                            %/doomgeneric_emscripten.c %/doomgeneric_linuxvt.c \
                            %/i_sdlsound.c %/i_sdlmusic.c %/i_allegrosound.c %/i_allegromusic.c \
                            %/i_cdmus.c %/i_joystick.c,\
                 $(wildcard $(DOOMGEN_DIR)/*.c))
DOOM_LOCAL  := doom_main.c doomgeneric_scr1.c
DOOM_OBJ    := $(patsubst %.c,$(BUILD)/doomobj/%.o,$(notdir $(DOOM_ENGINE)) $(DOOM_LOCAL)) \
               $(BUILD)/uart.o $(BUILD)/crt-noreloc.o $(BUILD)/syscalls_doom.o $(BUILD)/wad_blob.o
DOOM_CF     := $(CFLAGS) -I$(DOOMGEN_DIR) -DNORMALUNIX -DLINUX -Wno-unused -Wno-sign-compare

doom: $(BUILD)/doom.bin
$(BUILD)/doomobj/%.o: $(DOOMGEN_DIR)/%.c | $(BUILD)
	@mkdir -p $(dir $@)
	$(CC) $(DOOM_CF) -c $< -o $@
$(BUILD)/doomobj/%.o: %.c | $(BUILD)
	@mkdir -p $(dir $@)
	$(CC) $(DOOM_CF) -c $< -o $@
$(BUILD)/syscalls_doom.o: syscalls_doom.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@
$(BUILD)/wad_blob.o: wad_blob.S doom1.wad | $(BUILD)
	$(CC) $(CFLAGS) -I. -c $< -o $@
$(BUILD)/doom.elf: $(DOOM_OBJ)
	$(CC) $(incs) -o $@ $^ $(LF_DDR) -lm -Wl,-Map=$(BUILD)/doom.map

clean:
	rm -rf $(BUILD)
.PHONY: fb_test fb_test_ddr doom clean
