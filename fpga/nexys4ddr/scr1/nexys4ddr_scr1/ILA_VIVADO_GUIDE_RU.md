# ILA в Xilinx Vivado: краткий гайд

**ILA (Integrated Logic Analyzer)** — встроенный в FPGA логический анализатор. Он записывает внутренние сигналы схемы в BRAM на частоте исследуемого тактового домена, а Vivado считывает результат через JTAG.

## 1. Выберите сигналы

Пометьте нужные сигналы в RTL:

```systemverilog
(* MARK_DEBUG = "TRUE" *) logic [31:0] data;
(* MARK_DEBUG = "TRUE" *) logic        valid;
```

Запустите **Synthesis**, откройте **Synthesized Design**, затем выберите:

**Tools → Set Up Debug**

Задайте:

- `Clock Domain` — такт, которым будут сниматься значения;
- `Data Depth` — глубину буфера, например 1024–8192 отсчётов;
- назначение probe: `Data`, `Trigger` или `Data and Trigger`.

Vivado обычно создаёт отдельную ILA для каждого тактового домена. Правильный выбор такта критичен. См. [описание Set Up Debug](https://docs.amd.com/r/2025.1-English/ug908-vivado-programming-debugging/Using-the-Set-Up-Debug-Wizard-to-Insert-Debug-Cores).

Альтернативный способ — добавить **ILA IP** через IP Catalog и явно подключить его в RTL:

```systemverilog
ila_0 u_ila (
    .clk    (clk),
    .probe0 (data),
    .probe1 (valid)
);
```

## 2. Соберите и загрузите проект

Выполните:

1. **Implementation**.
2. **Generate Bitstream**.
3. **Open Hardware Manager**.
4. **Open Target → Auto Connect**.
5. **Program Device**.

Используйте согласованную пару файлов:

- `.bit` — конфигурация FPGA;
- `.ltx` — описание ILA-проб.

После изменения ILA оба файла нужно обновлять, иначе Vivado может сообщить о несовпадении debug cores. Файл `.ltx` обычно создаётся автоматически вместе с bitstream. См. [работу с probes-файлом](https://docs.amd.com/r/en-US/ug908-vivado-programming-debugging/Reading-ILA-Probes-Information).

## 3. Настройте захват

В окне **ILA Dashboard**:

- добавьте probes в `Waveform`;
- в `Trigger Setup` задайте условие, например `valid == 1`, `state == 5` или `address == 0x80000000`;
- установите `Trigger Position`:
  - начало — почти вся история после события;
  - середина — данные до и после события;
  - конец — почти вся история перед событием.

Затем нажмите:

- **Run Trigger** — ждать заданного события;
- **Run Trigger Immediate** — захватить данные немедленно.

После срабатывания Vivado автоматически выгрузит осциллограмму. См. [настройку позиции триггера](https://docs.amd.com/r/en-US/ug908-vivado-programming-debugging/Setting-the-Trigger-Position-in-the-Capture-Window).

## Практические советы

- Начинайте с небольшой глубины: большая ILA расходует BRAM и может ухудшить timing.
- Для разных clock domain используйте разные ILA либо заранее синхронизируйте сигналы.
- Добавляйте к данным управляющие признаки: `valid`, `ready`, состояние FSM, счётчики и флаги ошибок.
- Если ILA не появляется, проверьте наличие такта на `.clk`, соответствие `.bit` и `.ltx`, а также доступность debug hub через JTAG.
- После добавления ILA повторно проверьте **Timing Summary**: отладочная логика может изменить размещение проекта.

Основной справочник: [Vivado Design Suite User Guide: Programming and Debugging (UG908)](https://docs.amd.com/r/en-US/ug908-vivado-programming-debugging).
