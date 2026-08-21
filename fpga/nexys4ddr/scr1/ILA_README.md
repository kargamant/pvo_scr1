# Отладка SCR1 через ILA на Nexys A7 — шины imem / dmem и UART

Цель: увидеть на живой плате, как тест по UART загружается в память и затем
исполняется ядром, а заодно посмотреть поток выборки инструкций предсказателя.

## Что добавлено

- `src/nexys4ddr_scr1.sv` — `(* mark_debug="true" *)` на 24 нета:
  - imem: `araddr, arvalid, arready, arlen, rdata, rvalid, rready, rlast, rresp`
  - dmem: `awaddr, awvalid, awready, wdata, wstrb, wvalid, wlast, bvalid, araddr, arvalid, rdata, rvalid`
  - uart: `uart_rxd, uart_txd, uart_irq`
- `scr1_ila_debug.tcl` — вставляет один ILA (`u_ila_0`) на `cpu_clk`, подключённый к этим нетам.

Карта памяти для триггеров: сброс/загрузчик `0x200` · TCM (тесты бегут здесь) `0xF000_0000`
· регистры UART `0xFF01_0000` · MMIO `0xFF00_0000`.

---

## Путь A — GUI «Set Up Debug» (рекомендуется, встраивается в твой поток сборки)

Для этого пути нужен только патч `mark_debug`; `.tcl` здесь необязателен.

1. Открой проект, **Run Synthesis**.
2. Открой synthesized design → меню **Tools ▸ Set Up Debug**.
3. Мастер сам покажет все неты с `mark_debug`. Next.
4. **Clock domain**: для всех нетов тактовый домен = `cpu_clk` (должен подставиться сам).
5. **Sample depth** = `4096` (можно `8192`, если влезет). Включи **Capture control**
   и **Advanced trigger**. Finish.
6. Vivado сам запишет debug-ядро в файл ограничений.
   **Generate Bitstream** как обычно → `impl_1/nexys4ddr_scr1.bit` теперь содержит ILA.
7. Запусти свой обычный шаг запекания загрузчика (`mem_update.tcl` / updatemem)
   ровно как раньше — ILA лежит в том же битстриме, больше ничего не меняется.

## Путь B — полностью скриптовый (headless, консоль Tcl)

1. Патч `mark_debug` уже применён; дальше в консоли Tcl (Vivado):
   ```tcl
   reset_run synth_1
   launch_runs synth_1 -jobs 8
   wait_on_run synth_1
   open_run synth_1
   source ./scr1_ila_debug.tcl        ;# при необходимости поправь путь
   opt_design
   place_design
   route_design
   write_bitstream -force ./nexys4ddr_scr1_ila.bit
   write_debug_probes -force ./nexys4ddr_scr1_ila.ltx
   ```
2. Запеки загрузчик в `nexys4ddr_scr1_ila.bit` своим updatemem-потоком
   (наведи `bit_file` в `mem_update.tcl` на этот битстрим), затем прошивай.

> Альтернатива: переименуй `scr1_ila_debug.tcl` в `.xdc`, добавь в `constrs_1` с
> `set_property USED_IN_SYNTHESIS false [get_files scr1_ila_debug.xdc]` — тогда ILA
> вставляется автоматически на каждом Generate Bitstream (скриптово, но интегрировано
> в проект, как в Пути A).

---

## Прошивка и открытие анализатора

1. **Open Hardware Manager ▸ Open Target ▸ Auto Connect**.
2. Прошей плату запечённым битстримом; укажи файл щупов `.ltx`
   (`Hardware ▸ ПКМ по устройству ▸ specify probes file`), чтобы имена сигналов подтянулись.
3. Появится дашборд `hw_ila_1` со всеми 24 щупами.

## Рецепты триггеров (задаются в дашборде ILA)

Поставь radix адресных щупов `*addr` в **Hex**. Позиция триггера ~50%, чтобы видеть
и до, и после события.

1. **Стык boot → тест** (управление прыгнуло в загруженный тест):
   `axi_imem_arvalid == 1` И `axi_imem_araddr == F0000000`
2. **Образ ложится в TCM** (загрузчик пишет тест):
   `axi_dmem_awvalid == 1` И `axi_dmem_awaddr == Fxxxxxxx`  (value `F0000000`, mask `F0000000`)
3. **Загрузка по UART / доступ к консоли** (ядро трогает FIFO UART):
   `axi_dmem_arvalid == 1` И `axi_dmem_araddr == FF010000`
4. **Сырой стартовый бит** (первый принятый байт): `uart_rxd == 0`
   (асинхронен к `cpu_clk` — наблюдать можно спокойно; если триггерить по нему,
   жди дрожание ±1 такт).

**Capture control** (storage qualification) — чтобы буфер не забивался простоями:
- Шины: сохранять только когда `axi_imem_arvalid==1 || axi_dmem_awvalid==1 || axi_dmem_arvalid==1`.
- UART: сохранять только когда `uart_rxd==0 || uart_txd==0` (есть активность).

## Что смотреть

- **Фаза boot**: `axi_imem_araddr` крутится в районе `0x200…` (загрузчик из BRAM).
- **Фаза загрузки**: пачки `axi_dmem_awaddr`, монотонно растущие от `0xF0000000`,
  `axi_dmem_wdata` = слова программы; сопоставь с приходящими байтами `uart_rxd`.
  Посчитай записи → размер образа; проверь, что адреса идут подряд.
- **Фаза исполнения**: `axi_imem_araddr` прыгает на `0xF0000000` и остаётся там;
  load/store по dmem; `uart_txd` печатает строку результата.
- **Предсказатель на железе**: на потоке imem правильно предсказанная взятая ветка
  видна как прыжок `araddr` сразу на цель без повторной выборки; мисспредикт — как
  редирект (адрес прыгнул, затем повторный fetch с правильного). Это живой аналог
  цифр тактов из verilator.

## Заметки / тюнинг

- 24 щупа ≈ 221 бит. Глубина 4096 ≈ 25 BRAM36 (~18% от xc7a100t); 8192 ≈ 50 (~37%).
  Если импл упрётся в BRAM (часть занимает MIG) — уменьши глубину или разбей щупы.
- Тайминг: щупы ILA на `cpu_clk`; `C_INPUT_PIPE_STAGES 1` уже стоит, чтобы разгрузить
  fan-in щупов. Если увидишь setup-ошибки у ILA — подними до 2.

## Откат

Убери префиксы `(* mark_debug="true" *)` в `nexys4ddr_scr1.sv` (grep `mark_debug`),
удали файл debug-ограничений (Путь A) или не подключай tcl (Путь B) и пересобери —
дизайн вернётся в исходное состояние.
