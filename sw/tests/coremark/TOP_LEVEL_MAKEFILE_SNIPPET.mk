.PHONY: coremark_fpga_nexys

coremark_fpga_nexys:
	$(eval export SYS_CLK := 30000000)
	$(info nexys_sys_clk=$(SYS_CLK))
	$(MAKE) -C ./coremark \
		dst_dir=$(root_dir)/../../images/nexys4ddr/scr1 \
		MEM=ddr \
		MARCH=rv32im_zicsr_zifencei \
		MABI=ilp32 \
		ITERATIONS=0 \
		OPT=2 \
		clean all
