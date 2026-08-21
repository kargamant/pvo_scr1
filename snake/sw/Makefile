# Snake for SCR1 (TCM, rv32im, picolibc). Loaded on the board via XMODEM.
#   make            -> build/snake.bin  (+ .elf .dump)
#   make clean
CROSS_PREFIX ?= riscv64-unknown-elf-
CC      := $(CROSS_PREFIX)gcc
OBJCOPY := $(CROSS_PREFIX)objcopy
OBJDUMP := $(CROSS_PREFIX)objdump

MARCH   ?= rv32im_zicsr_zifencei
MABI    ?= ilp32
OPT     ?= 2
SYS_CLK ?= 30000000

COMMON  := ../../tests/tests_common
LDS     := $(COMMON)/tcm.ld
BUILD   := build

incs    := -I. -I$(COMMON)
defs    := -DSYS_CLK=$(SYS_CLK) -DUART_BAUDRATE=115200 -DRTC_HZ=1000000

CFLAGS  := -O$(OPT) -g --specs=picolibc.specs \
           -march=$(MARCH) -mabi=$(MABI) -Wa,-march=$(MARCH) \
           -ffreestanding -ffunction-sections -fdata-sections \
           -Wall -Wextra $(incs) $(defs)
LFLAGS  := --specs=picolibc.specs -march=$(MARCH) -mabi=$(MABI) \
           -nostartfiles -Wl,--gc-sections -T $(LDS)

C_SRC   := snake.c $(COMMON)/sc_print.c $(COMMON)/uart.c
ASM_SRC := $(COMMON)/crt-noreloc.S

OBJS    := $(BUILD)/snake.o $(BUILD)/sc_print.o $(BUILD)/uart.o $(BUILD)/crt-noreloc.o

all: $(BUILD)/snake.bin $(BUILD)/snake.dump

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/snake.o: snake.c snake_hw.h | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/sc_print.o: $(COMMON)/sc_print.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/uart.o: $(COMMON)/uart.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/crt-noreloc.o: $(COMMON)/crt-noreloc.S | $(BUILD)
	$(CC) $(CFLAGS) -D__ASSEMBLY__=1 -c $< -o $@

$(BUILD)/snake.elf: $(OBJS)
	$(CC) $(incs) -o $@ $(OBJS) $(LFLAGS) -Wl,-Map=$(BUILD)/snake.map

$(BUILD)/snake.bin: $(BUILD)/snake.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD)/snake.dump: $(BUILD)/snake.elf
	$(OBJDUMP) -D $< > $@

clean:
	rm -rf $(BUILD)

.PHONY: all clean
