# Чат: память, reset vector и запуск SCR1 на Nexys4 DDR

Сохранённая отдельная ветка обсуждения архитектуры памяти SCR1, загрузочной BRAM, секций `.startup`/`.vectors` и установки начального PC.

Связанный подробный материал: [`MEMORY_ARCHITECTURE_RU.md`](./MEMORY_ARCHITECTURE_RU.md).

---

## Вопрос: какие виды памяти предусмотрены этой архитектурой?

### Ответ

В реализации SCR1 для Nexys4 DDR используются три настоящих области памяти:

| Адресный диапазон | Размер | Назначение | Реализация |
|---|---:|---|---|
| `0x00000000`–`0x07FFFFFF` | 128 МиБ | Основная память программ и данных | Внешняя DDR2 на плате, доступ через MIG 7 Series |
| `0xF0000000`–`0xF000FFFF` | 64 КиБ | TCM | Внутренняя Block RAM FPGA, выведенная Vivado из RTL |
| `0xFFFF0000`–`0xFFFFFFFF` | 64 КиБ | Boot SRAM/OCRAM с SCBL | Внутренняя Block RAM FPGA, IP `blk_mem_gen_0` |

Адреса UART, таймера и служебных блоков также находятся в карте адресов, но это MMIO-регистры, а не RAM.

### DDR2

DDR2 — физическая микросхема памяти на плате. Путь обращения:

```text
SCR1 imem/dmem
    -> AXI SmartConnect
    -> AXI Clock Converter
    -> MIG 7 Series
    -> внешняя DDR2
```

MIG инициализирует и калибрует DDR2 и формирует физические команды памяти. Диапазон DDR2 задан в [`nexys4ddr_scr1.tcl`](../nexys4ddr_scr1.tcl):

```tcl
create_bd_addr_seg -range 0x08000000 -offset 0x00000000 \
    [get_bd_addr_spaces axi_dmem] ...
create_bd_addr_seg -range 0x08000000 -offset 0x00000000 \
    [get_bd_addr_spaces axi_imem] ...
```

### TCM

TCM — Tightly-Coupled Memory, непосредственно подключённая к внутренним роутерам памяти SCR1. В этой сборке она занимает:

```text
0xF0000000 ... 0xF000FFFF = 64 КиБ
```

Параметры находятся в [`scr1_arch_custom.svh`](../src/scr1_arch_custom.svh):

```systemverilog
SCR1_TCM_ADDR_MASK    = 'hFFFF0000;
SCR1_TCM_ADDR_PATTERN = 'hF0000000;
```

TCM описана в [`scr1_tcm.sv`](../../../../scr1/src/top/scr1_tcm.sv) и [`scr1_dp_memory.sv`](../../../../scr1/src/top/scr1_dp_memory.sv). Vivado отображает RTL-массив на BRAM кристалла Artix-7.

Запросы к TCM распознаются до внешнего AXI SmartConnect. Поэтому запись загружаемого теста в TCM на выходах SmartConnect не видна.

### Boot SRAM/OCRAM

Память загрузчика занимает:

```text
0xFFFF0000 ... 0xFFFFFFFF = 64 КиБ
```

Она создана IP Xilinx `Block Memory Generator`:

```tcl
set blk_mem_gen_0 [create_bd_cell -type ip \
    -vlnv xilinx.com:ip:blk_mem_gen:8.4 blk_mem_gen_0]
```

Путь доступа:

```text
axi_imem/axi_dmem
    -> SmartConnect M00_AXI
    -> AXI BRAM Controller
    -> blk_mem_gen_0
    -> физические RAMB36/RAMB18 кристалла Artix-7
```

Block RAM — аппаратный ресурс самого FPGA. Это не DDR и не отдельная микросхема SRAM на плате.

### Почему используется `0xFFFFFF00`?

В память не начинают писать с `0xFFFFFF00`. Необходимо различать:

- `0xFFFF0000` — начало boot BRAM;
- `0xFFFFFF00` — reset vector, то есть начальный PC после reset;
- `0xF0000000` или `0x00000000` — возможный адрес загрузки теста в TCM или DDR2.

Reset vector задан в [`scr1_arch_custom.svh`](../src/scr1_arch_custom.svh):

```systemverilog
SCR1_ARCH_RST_VECTOR = 'hFFFFFF00;
```

Он находится внутри последних 256 байт boot BRAM.

Linker script SCBL [`scbl.ld`](../../../../sw/sc-bl/common/scbl.ld) размещает секции так:

```ld
MEMORY {
  RAM (rwx) : ORIGIN = 0-64K, LENGTH = 64K
}

.startup ORIGIN(RAM) + LENGTH(RAM) - 0x800 : { ... }
.vectors ORIGIN(RAM) + LENGTH(RAM) - 0x100 : { ... }
```

Для 32-битного адресного пространства:

```text
ORIGIN(RAM)             = 0xFFFF0000
.startup                = 0xFFFFF800
.vectors                = 0xFFFFFF00
```

### Как загрузчик попадает в BRAM?

SCBL не загружается по UART. Он встраивается в bitstream:

1. Исходники `sw/sc-bl` компилируются и линкуются.
2. Создаётся `scbl.mem`.
3. Vivado реализует дизайн и создаёт обычный `.bit`.
4. [`mem_update.tcl`](../mem_update.tcl) находит `blk_mem_gen_0`.
5. [`write_mmi.tcl`](../write_mmi.tcl) формирует описание физического расположения BRAM.
6. `updatemem` переносит `scbl.mem` в INIT-данные BRAM внутри bitstream.
7. Создаётся `nexys4ddr_scr1_new.bit`.
8. При программировании FPGA загрузчик уже оказывается в boot BRAM.

После reset SCBL принимает тест через UART/XMODEM, записывает его в TCM или DDR2 и по команде `g` передаёт управление на адрес теста.

---

## Вопрос: какого объёма память инструкций и память данных?

### Ответ

`imem` и `dmem` — не две отдельные физические памяти. Это два интерфейса SCR1:

- `imem` — выборка инструкций;
- `dmem` — чтение и запись данных.

У каждого интерфейса 32-битное адресное пространство, то есть теоретически около 4 ГиБ. Это не означает наличие двух микросхем памяти по 4 ГиБ: большая часть адресов передаётся во внешнюю AXI-подсистему или не отображена.

Для Nexys4 DDR физически доступны:

| Память | Объём | Через `imem` | Через `dmem` |
|---|---:|:---:|:---:|
| DDR2 | 128 МиБ | Да | Да |
| TCM | 64 КиБ | Да | Да |
| Boot BRAM | 64 КиБ | Да | Да |

Суммарно реализовано:

```text
128 МиБ + 64 КиБ + 64 КиБ = 128.125 МиБ
```

Но это одна общая физическая память, доступная по двум путям, а не `128.125 МиБ` инструкций плюс ещё `128.125 МиБ` данных.

TCM — одна двухпортовая память объёмом 64 КиБ:

```text
                 +--------------------+
imem-порт ------>|                    |
                 |    TCM 64 КиБ      |
dmem-порт ------>|                    |
                 +--------------------+
```

На типовой схеме SCR1 TCM может быть показана по адресу `0x00480000`. В рассматриваемой FPGA-конфигурации она перенесена в `0xF0000000`–`0xF000FFFF`.

Надпись `AHB/AXI space` на схеме означает не RAM соответствующего размера, а передачу запроса во внешнюю системную шину, где адрес декодируется другими блоками.

---

## Вопрос: что такое секции `.startup` и `.vectors`?

### Ответ

Секции — логические части ELF-файла. Ассемблер и компилятор группируют в них код и данные, а linker script назначает каждой секции адрес в памяти.

`.startup` и `.vectors` — не отдельные виды памяти. Это участки кода загрузчика внутри boot BRAM:

```text
Boot BRAM: 0xFFFF0000 ... 0xFFFFFFFF

0xFFFF0000  обычный код и данные SCBL
     ...
0xFFFFF800  .startup
     ...
0xFFFFFF00  .vectors, reset vector
0xFFFFFFFF  конец BRAM
```

### `.vectors`

Секция содержит короткие аппаратные точки входа. Она объявлена в [`startup.S`](../../../../sw/sc-bl/src/startup.S):

```asm
.section ".vectors","ax",@progbits

.global _start
_start:
    j _crt_start
    nop
```

После reset:

```text
PC = 0xFFFFFF00
    -> _start
    -> j _crt_start
    -> переход в .startup
```

В секции также предусмотрены точки входа для NMI и trap:

```asm
__nmi_trap_entry:
    j bad_trap

__trap_entry:
    j __trap_hander_1v10
```

Linker script помещает `.vectors` в последние 256 байт BRAM и использует `KEEP()`, чтобы линкер не удалил секцию как неиспользуемую.

### `.startup`

Секция содержит код начальной настройки процессора перед вызовом C-функции `main()`:

1. Настраивает `mstatus`.
2. Записывает адрес обработчика в `mtvec`.
3. Настраивает прерывания.
4. Настраивает `gp`.
5. Очищает `.bss`.
6. Создаёт стек `sp`.
7. Инициализирует TLS.
8. Вызывает `main()` загрузчика.

Ключевой фрагмент:

```asm
.section ".startup","ax",@progbits

_crt_start:
    li   t0, 0x1880
    csrw mstatus, t0

    la   t0, __trap_hander_1v10
    csrw mtvec, t0

    ...

    la   sp, __TLS0_BASE__
    ...
    jal  main
```

Общая последовательность:

```text
Reset
  -> PC = 0xFFFFFF00
  -> .vectors: _start
  -> .startup: _crt_start
  -> подготовка регистров, памяти и стека
  -> main() SCBL
```

---

## Вопрос: в каком файле можно посмотреть установку `PC = 0xFFFFFF00`?

### Ответ

Основной файл аппаратной реализации — [`scr1_pipe_exu.sv`](../../../../scr1/src/core/pipeline/scr1_pipe_exu.sv).

Полная цепочка состоит из нескольких файлов.

### 1. Значение reset vector

В [`scr1_arch_custom.svh`](../src/scr1_arch_custom.svh):

```systemverilog
parameter bit [31:0] SCR1_ARCH_RST_VECTOR = 'hFFFFFF00;
```

В [`scr1_csr.svh`](../../../../scr1/src/includes/scr1_csr.svh) оно получает внутреннее имя ядра:

```systemverilog
parameter bit [31:0] SCR1_RST_VECTOR = SCR1_ARCH_RST_VECTOR;
```

### 2. Установка текущего PC

В `scr1_pipe_exu.sv`:

```systemverilog
always_ff @(negedge rst_n, posedge clk) begin
    if (~rst_n) begin
        pc_curr_ff <= SCR1_RST_VECTOR;
    end else if (pc_curr_upd) begin
        pc_curr_ff <= pc_curr_next;
    end
end
```

При активном reset:

```text
rst_n = 0
    -> pc_curr_ff = SCR1_RST_VECTOR
    -> pc_curr_ff = 0xFFFFFF00
```

### 3. Передача reset vector в IFU

После снятия reset логика EXU формирует `init_pc`. Мультиплексор нового PC выбирает reset vector:

```systemverilog
always_comb begin
    case (1'b1)
        init_pc : exu2ifu_pc_new_o = SCR1_RST_VECTOR;
        ...
    endcase
end

assign exu2ifu_pc_new_req_o = init_pc | ...;
```

На интерфейсе EXU–IFU получается:

```text
exu2ifu_pc_new_req_o = 1
exu2ifu_pc_new_o     = 0xFFFFFF00
```

### 4. Формирование адреса памяти инструкций

В [`scr1_pipe_ifu.sv`](../../../../scr1/src/core/pipeline/scr1_pipe_ifu.sv):

```systemverilog
assign ifu2imem_addr_o = exu2ifu_pc_new_req_i
                       ? {exu2ifu_pc_new_i[`SCR1_XLEN-1:2], 2'b00}
                       : {imem_addr_ff, 2'b00};
```

На первом запросе:

```text
ifu2imem_addr_o = 0xFFFFFF00
```

Младшие два бита зануляются для выравнивания 32-битного чтения памяти инструкций.

### 5. Выбор boot BRAM

В [`nexys4ddr_scr1.tcl`](../nexys4ddr_scr1.tcl) для `axi_imem` создан сегмент:

```tcl
create_bd_addr_seg \
    -range  0x00010000 \
    -offset 0xFFFF0000 \
    [get_bd_addr_spaces axi_imem] \
    [get_bd_addr_segs bram_ctrl/S_AXI/Mem0] \
    SEG_bram_ctrl_Mem0
```

Адрес `0xFFFFFF00` входит в диапазон `0xFFFF0000`–`0xFFFFFFFF`, поэтому запрос направляется в `blk_mem_gen_0`.

### 6. Первая инструкция

По адресу `0xFFFFFF00` linker script размещает `_start` из `.vectors`:

```asm
_start:
    j _crt_start
```

Итоговая аппаратно-программная последовательность:

```text
rst_n = 0
    -> pc_curr_ff = 0xFFFFFF00

rst_n снимается
    -> init_pc = 1
    -> EXU передаёт 0xFFFFFF00 в IFU
    -> IFU запрашивает инструкцию по 0xFFFFFF00
    -> AXI-декодер выбирает boot BRAM
    -> из BRAM читается j _crt_start
    -> начинается выполнение .startup
```

---

## Основные файлы обсуждения

- [`scr1_arch_custom.svh`](../src/scr1_arch_custom.svh) — адрес reset vector и карта TCM.
- [`scr1_pipe_exu.sv`](../../../../scr1/src/core/pipeline/scr1_pipe_exu.sv) — установка и изменение PC.
- [`scr1_pipe_ifu.sv`](../../../../scr1/src/core/pipeline/scr1_pipe_ifu.sv) — формирование адреса выборки инструкции.
- [`nexys4ddr_scr1.tcl`](../nexys4ddr_scr1.tcl) — AXI address map и подключение BRAM/DDR2.
- [`startup.S`](../../../../sw/sc-bl/src/startup.S) — `_start`, `.vectors` и `.startup`.
- [`scbl.ld`](../../../../sw/sc-bl/common/scbl.ld) — размещение секций загрузчика.
- [`mem_update.tcl`](../mem_update.tcl) — внедрение `scbl.mem` в bitstream.

