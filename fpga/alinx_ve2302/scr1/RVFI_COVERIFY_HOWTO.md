# On-chip RVFI co-verification of SCR1 (VD100) — HOWTO & change log

Self-hosted, per-instruction co-verification of the SCR1 core running in the VD100's
programmable logic: an ISA **reference model** on the PS (ARM/Linux) is diffed, retire by
retire, against the real core via an **RVFI** trace. Everything runs on the board.

```
 SCR1 (PL) ── RVFI-lite tap ──► trace BRAM (PL, 8192×128b) ──► PS reads (mmap /dev/mem)
                                                                    │
                          refmodel executes the SAME image ◄────────┘
                          diff record-by-record ─► first mismatch = the bug
```

This is **purely additive and default-off**. With no env switch the design is byte-for-byte
the tested cache build (`build/sdcard_cache/`). Everything below is gated behind
`SCR1_RVFI_EN` (RTL define) / `RVFI_EN` (block design), both driven by one env var.

> Proven on silicon: CoreMark on SCR1 → tap → trace BRAM → PS dump → model compare =
> **1000/1000 records identical** (and the full self-hosted C compare reproduces it).

---

## 1. What changed (the additive observation path)

### 1.1 RTL — the retire tap
- **`scr1/src/core/pipeline/scr1_rvfi_lite.sv`** (new) — synthesizable tap. One 128-bit
  record per retired instruction, driving a **capture-until-full** buffer (writes from reset
  until 8192 records, then freezes; never back-pressures the pipeline). Record layout:

  | bits     | field    | notes                              |
  |----------|----------|------------------------------------|
  | `[31:0]`   | `pc`       | retiring instruction PC            |
  | `[63:32]`  | `pc_next`  | architectural next PC              |
  | `[95:64]`  | `rd_wdata` | 0 if no write / write x0           |
  | `[100:96]` | `rd_addr`  | 0 if no write / write x0           |
  | `[101]`    | `trap`     | retired with exception             |
  | `[127:102]`| reserved | 0                                  |

- **`scr1/src/core/pipeline/scr1_pipe_top.sv`** — instantiates `i_rvfi` under
  `` `ifdef SCR1_RVFI_EN``, fed from existing retire signals: `curr_pc`, `next_pc`,
  `instret`, `instret_nexc`, `exu2mprf_w_req/rd_addr/rd_data`. Exposes the tap bus as ports.
  **Critical:** the tap reset is `pipe_rst_n` (the reset every other pipe submodule uses),
  **not** `rst_n` — see the bug note in §6.
- **`scr1_core_top.sv`, `scr1_top_axi.sv`** — thread the tap bus
  (`rvfi_trace_we/waddr[12:0]/wdata[127:0]/count[31:0]`) up to the top, all under the ifdef.
- **`fpga/alinx_ve2302/scr1/src/alinx_ve2302_scr1.sv`** — connects the tap bus to `i_soc`
  and holds the **trace RAM in RTL** (inferred BRAM):
  ```systemverilog
  (* ram_style="block" *) logic [127:0] rvfi_trace_ram[0:8191];
  // port A: tap write @cpu_clk;  port B: PS read (byte addr → word: trace_bram_addr[16:4])
  ```

### 1.2 Block design — the PS bridge (guarded by `RVFI_EN`)
`fpga/alinx_ve2302/scr1/tcl/create_sopc_ps.tcl`, all inside `if {$RVFI_EN} { ... }`:
- `trace_bram_ctrl_ps` — `axi_bram_ctrl` (128-bit) on `axi_smc` **M02**; its BRAM master is
  externalized (`make_bd_intf_pins_external -name trace_bram`) so the RTL RAM backs it.
  Needs `set_property CONFIG.READ_WRITE_MODE {READ_WRITE}` on the external port.
- `trace_count_gpio` — `axi_gpio` (all inputs) on **M03** exposing the live record count
  (`NUM_MI` 2 → 4).
- **Address map:** trace BRAM `@0x8030_0000` (128 KiB), record count `@0x8040_0000`.

`create_project_ps.tcl` adds `SCR1_RVFI_EN=1` to `verilog_define` **and** flips BD `RVFI_EN`
when `SCR1_RVFI_EN` is in the environment — one switch does both.

### 1.3 Cost / timing
Tap + trace BRAM cost ≈ 0.15 ns of slack; the RVFI bitstream still **meets timing** at
80 MHz (WNS +0.577 ns). BOOT.BIN staged in `build/sdcard_rvfi/` so the tested
`build/sdcard_cache/` is never overwritten.

---

## 2. The reference model & host tools (`scr1/sim/rvfi_coverif/`)

| file             | role |
|------------------|------|
| `refmodel.c`     | compact **rv32imc + Zicsr** ISA model. Emits `RVFI <order> <pc> <pc_next> <rd_addr> <rd_wdata> <trap> [insn]`. `--compare F` diffs in-C (no python); `--dut-trace F` injects the DUT's timer-CSR values so self-timing programs (CoreMark/Dhrystone) line up; `--reset`, `--mem-bytes` for the board memory map. |
| `rvfi_dump.c`    | **on-board** trace dumper (new). `mmap(/dev/mem)` reads the trace BRAM + count directly (vs the slow per-word `devmem` console loop). Emits the same RVFI text the model consumes. |
| `rvfi_compare.py`| stand-alone diff (laptop flow); masks timing-CSR `rd_wdata`. Equivalent to `refmodel --compare`. |
| `co_verify.sh`   | Verilator flow: build DUT rv32imc + file-trace, run model, compare (sim regression). |
| `aarch64/{refmodel,rvfi_dump}` | **static aarch64** builds for the minimal PetaLinux rootfs (no gcc/libs on board). Rebuild: see §5. |

The model is a complete rv32imc reference (RVC expanded to 32-bit equivalents; C.JAL/C.JALR
link = pc+2). Validated in sim: hello 9611/9611, dhrystone 164892/164892 exact.

---

## 3. Fully self-hosted run (Stage 4 — everything on the board)

One-time: build the RVFI bitstream, flash it, ship the static binaries.

```bash
# (laptop) build the RVFI bitstream — additive, tested build kept in build/sdcard_cache/
cd fpga/alinx_ve2302/scr1 && tools/build_rvfi_all.sh   # -> build/sdcard_rvfi/BOOT.BIN

# flash build/sdcard_rvfi/{BOOT.BIN,image.ub,boot.scr} to the SD FAT partition, boot.

# (laptop) ship the payload to /tmp on the board over the console (base32, md5-checked)
tools/rvfi_ship.py --port /dev/ttyUSB0
#   ships: aarch64/rvfi_dump, aarch64/refmodel, rvfi_verify.sh, scr1load.sh, cm_bram.bin
```

Then, entirely on the PS console:

```sh
cd /tmp
./scr1load.sh cm_bram.bin --run           # load+run the test into SCR1 -> fills trace BRAM
./rvfi_verify.sh cm_bram.bin 0xFFFFFF00 65536
#   -> [board] captured records: 8192
#   -> MATCH: N records identical (DUT=N, timing-CSR rd_wdata masked)
#   -> [board] RVFI CO-VERIFICATION: PASS
```

`rvfi_verify.sh <image.bin> <reset_hex> <mem_bytes> [max_records]` = dump the trace
(`rvfi_dump`) + diff vs the model (`refmodel --compare`), self-contained.

**Reset / memory notes:** the boot-BRAM image resets at `0xFFFFFF00` and the model masks
memory to 64 KiB (`--mem-bytes 65536`); for a TCM-linked image adjust `--reset`/`--mem-bytes`
to match. The sim uses reset `0x200` — the model handles both via flags.

---

## 4. Laptop-side run (Stage 3 style, no board dumper)

If you prefer to compare on the laptop: read the trace over the console with `devmem`
(count `@0x80400000`, records `@0x80300000`, 4 words/record = pc, pc_next, rd_wdata,
`{[5]trap,[4:0]rd_addr}`), save as `hw.rvfi`, then:
```bash
cd scr1/sim/rvfi_coverif
./refmodel cm_bram.bin --reset 0xFFFFFF00 --mem-bytes 65536 --compare hw.rvfi
# or:  python3 rvfi_compare.py hw.rvfi <(./refmodel cm_bram.bin --reset ... --dut-trace hw.rvfi)
```

---

## 5. Rebuilding the static aarch64 binaries

```bash
cd scr1/sim/rvfi_coverif
aarch64-linux-gnu-gcc -O2 -static -o aarch64/rvfi_dump rvfi_dump.c
aarch64-linux-gnu-gcc -O2 -static -o aarch64/refmodel refmodel.c
aarch64-linux-gnu-strip aarch64/rvfi_dump aarch64/refmodel
```
Static so they run on the minimal rootfs (no shared libs). One-time on a networked host
(`apt install gcc-aarch64-linux-gnu`).

---

## 6. Lessons / gotchas

- **`pipe_rst_n`, not `rst_n`** — the S3c silicon bug: the tap was wired to `rst_n`, an
  undriven implicit net → synth tied it to 0 → the capture counter was held in reset, so
  every write hit address 0 and `count` read 0. `pipe_rst_n` is pipe_top's real reset. It was
  invisible in the S3a sim because the testbench only read the *combinational* record, never
  the capture counter. **Any RVFI sim check must exercise the cnt/waddr capture path.**
- **BRAM width** — `emb_mem_gen` in the BD forces an externalized port back to 32-bit via
  parameter propagation; we get a true 128-bit port by externalizing the `axi_bram_ctrl`
  BRAM master and inferring the RAM in RTL.
- **Timing-CSR contamination** — self-timing programs read `rdcycle`/`mcycle`, store then
  reload it; the timer value flows into the data path and a timer-less model can't match.
  Fix: inject the DUT's `rd_wdata` for timing-CSR reads by retire order (`--compare`/`--dut-trace`).
- **Console dump is slow** — 8192 records via per-word `devmem` is ~10-15 min; `rvfi_dump`
  (mmap) makes it instant. That's the whole point of Stage 4.
