# Интеграция snake-периферии в SoC (Nexys A7-100T, SCR1)

Пошаговый рецепт: как `vga_ctrl` + `ps2_kbd` добавляются в block design
`nexys4ddr_sopc` проекта `fpga-sdk-prj/nexys4ddr/scr1`. Ядро SCR1 не трогается —
это только AXI-обвязка. Проверено на реальной плате: змейка играется на силиконе.

Требования: Vivado 2019.1, `LC_ALL=C`, RISC-V toolchain (`riscv64-unknown-elf-`),
`minicom` + `lrzsz`. Репозиторий должен лежать по пути `/home/toast/scr1_sber`
(BD ссылается на snake-RTL абсолютными путями) — либо поправьте пути к
`snake/rtl/*` в `sources_1` после открытия проекта.

Карта памяти после интеграции: **VGA `0xFF02_0000`**, **клавиатура `0xFF03_0000`**
(рядом с UART `0xFF01_0000`). Детали регистров — `doc/hw_contract.md`.

---

## 0. Бэкап (обязательно)
Правится рабочий SoC. Сохраните оригиналы до начала:
```
cp fpga-sdk-prj/nexys4ddr/scr1/src/nexys4ddr_scr1.sv                        <backup>/
cp fpga-sdk-prj/nexys4ddr/scr1/constrs/nexys4ddr_scr1_physical.xdc          <backup>/
cp fpga-sdk-prj/nexys4ddr/scr1/.../bd/nexys4ddr_sopc/nexys4ddr_sopc.bd      <backup>/
```

## 1. Правки в топ-RTL и XDC (делаются в файлах, вне Vivado)
Уже применены в репозитории; если разворачиваете с чистого upstream — повторите:

**`src/nexys4ddr_scr1.sv`** — добавить в список портов модуля:
```systemverilog
    output logic [3:0] VGA_R, output logic [3:0] VGA_G, output logic [3:0] VGA_B,
    output logic       VGA_HS, output logic VGA_VS,
    input  logic       PS2_CLK, input logic PS2_DATA
```
и в инстанс `nexys4ddr_sopc` — подключения:
```systemverilog
    .vga_r(VGA_R), .vga_g(VGA_G), .vga_b(VGA_B), .vga_hs(VGA_HS), .vga_vs(VGA_VS),
    .ps2_clk_pin(PS2_CLK), .ps2_data_pin(PS2_DATA)
```

**`constrs/nexys4ddr_scr1_physical.xdc`** — добавить пины (см. тот же файл в репо):
VGA_R A3/B4/C5/A4, VGA_G C6/A5/B6/A6, VGA_B B7/C7/D7/D8, VGA_HS B11, VGA_VS B12,
PS2_CLK F4, PS2_DATA B2 (все `IOSTANDARD LVCMOS33`).

## 2. Правки block design (Vivado TCL)
Запустить `LC_ALL=C vivado -mode tcl` и выполнить. `$ROOT` — корень репозитория.

```tcl
set ROOT /home/toast/scr1_sber
open_project $ROOT/fpga-sdk-prj/nexys4ddr/scr1/nexys4ddr_scr1/nexys4ddr_scr1.xpr

# module-reference требует автоматического режима компиляции
set_property source_mgmt_mode All [current_project]

# добавить snake-RTL (Verilog-обёртки ОБЯЗАТЕЛЬНЫ: IPI не берёт .sv как top ref)
set S $ROOT/snake/rtl
add_files -norecurse -fileset sources_1 [list \
  $S/vga_timing.sv $S/vga_ctrl.sv $S/vga_ctrl_soc.sv $S/vga_soc_wrap.v \
  $S/ps2_rx.sv $S/ps2_kbd.sv $S/ps2_kbd_wrap.v]
update_compile_order -fileset sources_1

open_bd_design [get_files nexys4ddr_sopc.bd]

# 2.1 ячейки периферии (интерфейс s_axi инферится из имён портов)
create_bd_cell -type module -reference vga_soc_wrap vga
create_bd_cell -type module -reference ps2_kbd_wrap kbd

# 2.2 smartconnect: 6 -> 8 master-портов, подключить AXI
set_property CONFIG.NUM_MI {8} [get_bd_cells smartconnect_0]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M06_AXI] [get_bd_intf_pins vga/s_axi]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M07_AXI] [get_bd_intf_pins kbd/s_axi]

# 2.3 клоки/резеты: AXI = clk_RISCV(30МГц), reset = peripheral_aresetn
#     (присоединяемся к существующим сетям через пины UART)
connect_bd_net [get_bd_pins vga/aclk]    [get_bd_pins uart/s_axi_aclk]
connect_bd_net [get_bd_pins kbd/aclk]    [get_bd_pins uart/s_axi_aclk]
connect_bd_net [get_bd_pins vga/aresetn] [get_bd_pins uart/s_axi_aresetn]
connect_bd_net [get_bd_pins kbd/aresetn] [get_bd_pins uart/s_axi_aresetn]

# 2.4 пиксельный клок 25 МГц: ОТДЕЛЬНЫЙ выход clk_out4 (НЕ трогаем clk_out2 —
#     он No_buffer для DDR MIG; вешать на него fabric нельзя -> DRC RTRES-1)
set_property -dict [list \
  CONFIG.CLKOUT4_USED {true} CONFIG.CLKOUT4_REQUESTED_OUT_FREQ {25.000} \
  CONFIG.NUM_OUT_CLKS {4}] [get_bd_cells clk_wiz_0]
connect_bd_net [get_bd_pins vga/pclk] [get_bd_pins clk_wiz_0/clk_out4]

# 2.5 внешние порты BD -> пойдут в топ-обёртку
create_bd_port -dir O -from 3 -to 0 vga_r
create_bd_port -dir O -from 3 -to 0 vga_g
create_bd_port -dir O -from 3 -to 0 vga_b
create_bd_port -dir O vga_hs
create_bd_port -dir O vga_vs
create_bd_port -dir I ps2_clk_pin
create_bd_port -dir I ps2_data_pin
connect_bd_net [get_bd_ports vga_r]  [get_bd_pins vga/vga_r]
connect_bd_net [get_bd_ports vga_g]  [get_bd_pins vga/vga_g]
connect_bd_net [get_bd_ports vga_b]  [get_bd_pins vga/vga_b]
connect_bd_net [get_bd_ports vga_hs] [get_bd_pins vga/vga_hs]
connect_bd_net [get_bd_ports vga_vs] [get_bd_pins vga/vga_vs]
connect_bd_net [get_bd_ports ps2_clk_pin]  [get_bd_pins kbd/ps2_clk]
connect_bd_net [get_bd_ports ps2_data_pin] [get_bd_pins kbd/ps2_data]

# 2.6 адреса
assign_bd_address -offset 0xFF020000 -range 64K [get_bd_addr_segs {vga/s_axi/*}]
assign_bd_address -offset 0xFF030000 -range 64K [get_bd_addr_segs {kbd/s_axi/*}]

# 2.7 проверить/сохранить/сгенерировать обёртку
validate_bd_design
save_bd_design
generate_target all [get_files nexys4ddr_sopc.bd]
```

## 3. Сборка битстрима
```tcl
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 6
wait_on_run impl_1
```
Проверьте тайминг (должно быть WNS > 0). В timing-репорте должен появиться
`clk_out4_… = 40 ns` (25 МГц) и `CPU_CLK = 33.333 ns` (30 МГц).

## 4. Инъекция загрузчика в BRAM
Битстрим из `write_bitstream` НЕ содержит sc-bootloader — без него плата не
примет XMODEM. Инъектировать `scbl.mem` в `blk_mem_gen_0`:
```tcl
cd $ROOT/fpga-sdk-prj/nexys4ddr/scr1
source mem_update.tcl
# -> nexys4ddr_scr1.runs/impl_1/nexys4ddr_scr1_new.bit  (это и прошиваем)
```

## 5. Прошивка
```tcl
open_hw; connect_hw_server; open_hw_target
current_hw_device [lindex [get_hw_devices] 0]
set_property PROGRAM.FILE \
  $ROOT/fpga-sdk-prj/nexys4ddr/scr1/nexys4ddr_scr1/nexys4ddr_scr1.runs/impl_1/nexys4ddr_scr1_new.bit \
  [current_hw_device]
program_hw_devices [current_hw_device]
```

## 6. Сборка и загрузка софта
```
cd $ROOT/snake/sw && LC_ALL=C make        # -> build/snake.bin (TCM, entry 0xF0000200)
```
Загрузка вручную через minicom (`minicom -D /dev/ttyUSB1 -b 115200`):
1. нажать на плате **CPU RESET** → появится меню загрузчика;
2. `1` → адрес `0xF0000000`;
3. `Ctrl-A S` → `xmodem` → путь к `build/snake.bin`;
4. `g` → адрес `0xF0000200`.

Змейка стартует. **USB-клавиатура — в USB-HOST порт (type-A), не в micro-USB**;
работает параллельно с UART. Управление WASD.

---

## Грабли (важно)
- **Verilog-обёртки обязательны**: IPI не принимает `.sv` как top module-reference
  (`vga_soc_wrap.v`, `ps2_kbd_wrap.v` — тонкие pass-through к SV-модулям).
- **Пиксельный клок — только отдельный buffered выход** clk_wiz. `clk_out2`
  (100 МГц) — `No_buffer` для DDR MIG; нагрузка fabric на него = DRC `RTRES-1`,
  битстрим не соберётся.
- **Кастомный AXI4-Lite слейв: `awready`/`wready` — РЕГИСТРОВЫЕ**, не
  комбинационно-зависимые от `awvalid/wvalid`. Иначе петля valid→ready со
  SmartConnect корёжит AWADDR (симптом: все записи уходят в клетку 0). Адрес —
  латчить. Уже сделано в `vga_ctrl.sv`/`ps2_kbd.sv`.
- **`close_project`** перед сменой конфигурации — иначе Vivado откатывается на
  устаревший `.xpr`.
- **Откат**: восстановить 3 файла из бэкапа (top .sv, physical .xdc, .bd),
  `reset_run`, пересобрать.
```
