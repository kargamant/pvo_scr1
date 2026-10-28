# CoreMark bare-metal build for SCR1 FPGA platforms.

.PHONY: all riscv clean inspect

all: riscv

coremark_dir       := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
coremark_src_dir   := $(coremark_dir)/src
tests_common_dir  := $(coremark_dir)/../tests_common

# Defaults can be overridden from the command line.
MARCH      ?= rv32im_zicsr_zifencei
MABI       ?= ilp32
MEM        ?= ddr
OPT        ?= 2
ITERATIONS ?= 0
dst_dir   ?= $(coremark_dir)/build

include $(tests_common_dir)/tests_common.mk

CC      := $(CROSS_PREFIX)gcc
LD      := $(CC)
OBJCOPY := $(CROSS_PREFIX)objcopy
OBJDUMP := $(CROSS_PREFIX)objdump
READELF := $(CROSS_PREFIX)readelf
NM      := $(CROSS_PREFIX)nm
SIZE    := $(CROSS_PREFIX)size

build_dir := $(abspath $(dst_dir))/
linker_script := $(tests_common_dir)/$(MEM).ld

coremark_c_src := \
    core_list_join.c \
    core_matrix.c \
    core_main.c \
    core_util.c \
    core_state.c

port_c_src := core_portme.c syscalls.c

coremark_c_objs := $(addprefix $(build_dir),$(coremark_c_src:.c=.o))
port_c_objs     := $(addprefix $(build_dir),$(port_c_src:.c=.o))
common_c_objs   := $(addprefix $(build_dir),$(common_c_src:.c=.o))
common_asm_objs := $(addprefix $(build_dir),$(common_asm_src:.S=.o))
objs := $(common_asm_objs) $(port_c_objs) $(common_c_objs) $(coremark_c_objs)

coremark_elf  := $(build_dir)coremark$(build_siffix).elf
coremark_bin  := $(build_dir)coremark$(build_siffix).bin
coremark_map  := $(build_dir)coremark$(build_siffix).map
coremark_dump := $(build_dir)coremark$(build_siffix).dump

FLAGS_ := $(PORT_CFLAGS) $(XLFLAGS) -march=$(MARCH) -mabi=$(MABI)

ifeq ($(MEM),ddr)
MEM_LOCATION_NAME := DDR2
else
MEM_LOCATION_NAME := TCM
endif

incs := -I$(coremark_dir) -I$(coremark_src_dir) -I$(tests_common_dir)

CFLAGS := \
    -static \
    -Wa,-march=$(MARCH) \
    -march=$(MARCH) \
    -mabi=$(MABI) \
    -std=gnu99 \
    -mstrict-align \
    -msmall-data-limit=8 \
    -ffunction-sections \
    -fdata-sections \
    -fno-common \
    -fno-builtin-printf \
    -fno-pic \
    -fno-pie \
    $(PORT_CFLAGS) \
    $(XLFLAGS) \
    -DITERATIONS=$(ITERATIONS) \
    -DTOTAL_DATA_SIZE=2000 \
    -DPERFORMANCE_RUN=1 \
    -DFLAGS_STR='"$(FLAGS_)"' \
    -DMEM_LOCATION='"$(MEM_LOCATION_NAME)"'

LFLAGS := \
    -static \
    -no-pie \
    -march=$(MARCH) \
    -mabi=$(MABI) \
    -nostartfiles \
    -nostdlib \
    $(XLFLAGS) \
    -Wl,--gc-sections \
    -Wl,--start-group \
    -lc \
    -lgcc \
    -Wl,--end-group

riscv: $(coremark_elf) $(coremark_bin) $(coremark_dump)

$(coremark_elf): $(linker_script) $(objs)
	@mkdir -p $(build_dir)
	$(LD) $(incs) -o $@ $(objs) -T $(linker_script) $(LFLAGS) -Wl,-Map=$(coremark_map)
	$(SIZE) --format=berkeley $@

$(coremark_bin): $(coremark_elf)
	$(OBJCOPY) -O binary -S $< $@

$(coremark_dump): $(coremark_elf)
	$(OBJDUMP) -w -x -d -s -z -S $< > $@

$(build_dir)%.o: $(coremark_src_dir)/%.c
	@mkdir -p $(build_dir)
	$(CC) $(CFLAGS) $(bmarks_defs) $(incs) -c $< -o $@

$(build_dir)%.o: $(coremark_dir)/%.c
	@mkdir -p $(build_dir)
	$(CC) $(CFLAGS) $(bmarks_defs) $(incs) -c $< -o $@

$(build_dir)%.o: $(tests_common_dir)/%.c
	@mkdir -p $(build_dir)
	$(CC) $(CFLAGS) $(bmarks_defs) $(incs) -c $< -o $@

$(build_dir)%.o: $(tests_common_dir)/%.S
	@mkdir -p $(build_dir)
	$(CC) $(CFLAGS) $(bmarks_defs) $(incs) -D__ASSEMBLY__=1 -c $< -o $@

inspect: $(coremark_elf)
	$(READELF) -h $(coremark_elf)
	$(OBJDUMP) -h $(coremark_elf)
	$(NM) -n $(coremark_elf) | grep -E '(_tmp|machine_trap_entry|_start|__heap_start|__STACK_START__|__C_STACK_TOP__)'

clean:
	rm -f $(coremark_elf) $(coremark_bin) $(coremark_map) $(coremark_dump) $(objs)
