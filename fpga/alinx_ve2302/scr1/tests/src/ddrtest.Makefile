# DDR self-test bare-metal build for the SCR1 SoC on ALINX VD100.
# Tester links to TCM (MEM=tcm) and exercises the DDR window at 0x0.
#   make CROSS_PREFIX=riscv64-unknown-elf- SYS_CLK=90000000 MEM=tcm OPT=2

.PHONY: all riscv clean

all: riscv

ddrtest_dir      := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
tests_common_dir := $(ddrtest_dir)/../tests_common

MARCH ?= rv32im_zicsr_zifencei
MABI  ?= ilp32
MEM   ?= tcm
OPT   ?= 2
dst_dir ?= $(ddrtest_dir)/build

include $(tests_common_dir)/tests_common.mk

CC      := $(CROSS_PREFIX)gcc
OBJCOPY := $(CROSS_PREFIX)objcopy
OBJDUMP := $(CROSS_PREFIX)objdump
SIZE    := $(CROSS_PREFIX)size

build_dir     := $(abspath $(dst_dir))/
linker_script := $(tests_common_dir)/$(MEM).ld

app_c_src   := ddrtest.c
app_objs    := $(addprefix $(build_dir),$(app_c_src:.c=.o))
common_objs := $(addprefix $(build_dir),$(common_c_src:.c=.o)) \
               $(addprefix $(build_dir),$(common_asm_src:.S=.o))
objs := $(common_objs) $(app_objs)

elf  := $(build_dir)ddrtest$(build_siffix).elf
bin  := $(build_dir)ddrtest$(build_siffix).bin
dump := $(build_dir)ddrtest$(build_siffix).dump
map  := $(build_dir)ddrtest$(build_siffix).map

incs := -I$(ddrtest_dir) -I$(tests_common_dir)

CFLAGS := -static --specs=picolibc.specs -Wa,-march=$(MARCH) -march=$(MARCH) -mabi=$(MABI) \
          -std=gnu99 -mstrict-align -msmall-data-limit=8 -ffunction-sections -fdata-sections \
          -fno-common -fno-builtin-printf -fno-pic -fno-pie $(PORT_CFLAGS) $(XLFLAGS)

LFLAGS := -static --specs=picolibc.specs -no-pie -march=$(MARCH) -mabi=$(MABI) \
          -nostartfiles -nostdlib $(XLFLAGS) -Wl,--gc-sections \
          -Wl,--start-group -lc -lgcc -Wl,--end-group

riscv: $(bin) $(dump)

$(elf): $(linker_script) $(objs)
	@mkdir -p $(build_dir)
	$(CC) $(incs) -o $@ $(objs) -T $(linker_script) $(LFLAGS) -Wl,-Map=$(map)
	$(SIZE) --format=berkeley $@

$(bin): $(elf)
	$(OBJCOPY) -O binary -S $< $@

$(dump): $(elf)
	$(OBJDUMP) -w -x -d -S $< > $@

$(build_dir)%.o: $(ddrtest_dir)/%.c
	@mkdir -p $(build_dir)
	$(CC) $(CFLAGS) $(bmarks_defs) $(incs) -c $< -o $@

$(build_dir)%.o: $(tests_common_dir)/%.c
	@mkdir -p $(build_dir)
	$(CC) $(CFLAGS) $(bmarks_defs) $(incs) -c $< -o $@

$(build_dir)%.o: $(tests_common_dir)/%.S
	@mkdir -p $(build_dir)
	$(CC) $(CFLAGS) $(bmarks_defs) $(incs) -D__ASSEMBLY__=1 -c $< -o $@

clean:
	rm -rf $(build_dir)
