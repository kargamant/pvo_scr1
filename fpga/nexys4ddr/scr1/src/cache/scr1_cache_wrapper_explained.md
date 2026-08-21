# Почти построчное объяснение `scr1_cache_wrapper.sv`

## 1. Что представляет собой этот файл

`scr1_cache_wrapper.sv` — это только интеграционная обёртка. Она описывает, как два будущих блока кэша должны быть подключены между ядром SCR1 и существующей подсистемой памяти.

Обёртка не содержит:

- массива данных кэша;
- массива тегов;
- valid- и dirty-битов;
- логики определения hit/miss;
- автомата загрузки cache line;
- логики вытеснения;
- реальных определений модулей `scr1_icache` и `scr1_dcache`.

Предполагаемая структура системы:

```text
                         scr1_cache_wrapper
                    +---------------------------+
                    |                           |
scr1_core_top IMEM ->| scr1_icache -> lower IMEM|-> imem_router / scr1_mem_axi
                    |                           |
scr1_core_top DMEM ->| scr1_dcache -> lower DMEM|-> dmem_router / scr1_mem_axi
                    |                           |
                    +---------------------------+
```

Слова `core`, `cpu` и `processor side` ниже означают сторону ядра. Слова `mem`, `lower memory` и `memory side` означают сторону роутера, AXI-моста и внешней памяти.

## 2. Откуда взялись `scr1_icache` и `scr1_dcache`

Модули `scr1_icache` и `scr1_dcache` **не были взяты из исходного репозитория SCR1**. В просмотренных исходниках проекта таких модулей нет. Это предложенные имена и предложенный интерфейсный контракт для будущих реализаций кэша.

В исходном SCR1 ядро непосредственно подключено к `scr1_imem_router`/`scr1_dmem_router`, а затем к `scr1_mem_axi`. Поэтому для добавления кэшей потребовалась точка расширения между ядром и роутерами. Обёртка описывает эту точку, а названия `scr1_icache` и `scr1_dcache` были выбраны по принятому в проекте стилю имён `scr1_*`.

Следовательно, после инстанцирования wrapper Vivado сообщит примерно следующее:

```text
module 'scr1_icache' not found
module 'scr1_dcache' not found
```

Это ожидаемо до тех пор, пока не будут написаны реальные файлы:

```text
scr1_icache.sv
scr1_dcache.sv
```

Их порты должны совпасть с портами, использованными внутри wrapper, либо wrapper необходимо адаптировать под интерфейс реально выбранных кэшей.

## 3. Заголовочные комментарии

```systemverilog
/// SCR1 instruction/data cache integration wrapper.
///
/// This file intentionally contains no cache implementation.
```

Строки, начинающиеся с `///`, являются комментариями. Для компилятора они не создают никакой логики. Тройной слеш часто используется для документации модулей и сигналов.

## 4. Директивы `include`

```systemverilog
`include "scr1_arch_description.svh"
`include "scr1_memif.svh"
```

Символ перед `include` — это обратный апостроф `` ` ``, а не обычная одинарная кавычка.

`include` — директива препроцессора SystemVerilog. До компиляции содержимое указанного файла текстуально подставляется в текущий файл.

Из `scr1_arch_description.svh` используются макросы ширины шин:

```systemverilog
`SCR1_IMEM_AWIDTH
`SCR1_IMEM_DWIDTH
`SCR1_DMEM_AWIDTH
`SCR1_DMEM_DWIDTH
```

В текущей 32-битной конфигурации SCR1 они соответствуют ширине XLEN, то есть 32 битам.

Из `scr1_memif.svh` используются типы:

```systemverilog
type_scr1_mem_cmd_e
type_scr1_mem_width_e
type_scr1_mem_resp_e
```

Они описывают команду памяти, размер доступа и состояние ответа.

## 5. Объявление модуля и конструкция `#(...)`

```systemverilog
module scr1_cache_wrapper #(
    parameter logic [`SCR1_IMEM_AWIDTH-1:0] ICACHE_ADDR_MASK     = '0,
    parameter logic [`SCR1_IMEM_AWIDTH-1:0] ICACHE_ADDR_PATTERN  = '0,
    parameter logic [`SCR1_DMEM_AWIDTH-1:0] DCACHE_ADDR_MASK     = '0,
    parameter logic [`SCR1_DMEM_AWIDTH-1:0] DCACHE_ADDR_PATTERN  = '0
) (
```

`module scr1_cache_wrapper` начинает описание модуля с именем `scr1_cache_wrapper`.

Конструкция с решёткой `#(...)` после имени модуля называется **списком параметров модуля**. Параметр — это константа времени elaboration. Она задаётся до синтеза и не становится входным электрическим сигналом.

Различие между параметром и входом:

```text
parameter  — постоянная конфигурация экземпляра;
input      — сигнал, который может меняться во время работы схемы.
```

Например, один и тот же wrapper можно создать с разными областями кэшируемой памяти:

```systemverilog
scr1_cache_wrapper #(
    .ICACHE_ADDR_MASK    (32'hF0000000),
    .ICACHE_ADDR_PATTERN (32'h80000000),
    .DCACHE_ADDR_MASK    (32'hF0000000),
    .DCACHE_ADDR_PATTERN (32'h80000000)
) i_cache_wrapper (...);
```

Здесь конструкция `#(...)` уже не объявляет, а **переопределяет параметры конкретного экземпляра**.

Запись:

```systemverilog
.ICACHE_ADDR_MASK(32'hF0000000)
```

означает: параметру экземпляра с именем `ICACHE_ADDR_MASK` присвоить значение `32'hF0000000`.

### Что означает `parameter logic [N-1:0]`

```systemverilog
parameter logic [`SCR1_IMEM_AWIDTH-1:0] ICACHE_ADDR_MASK = '0
```

Части конструкции:

- `parameter` — константа конфигурации;
- `logic` — четырёхсостоянийный тип SystemVerilog (`0`, `1`, `X`, `Z`);
- `[N-1:0]` — вектор из `N` бит;
- `ICACHE_ADDR_MASK` — имя параметра;
- `= '0` — значение по умолчанию: заполнить все биты нулями.

Апостроф в `'0` означает автоматически расширяемый литерал. Если слева 32 бита, `'0` превращается в `32'b0`. Аналогично `'1` заполнил бы все биты единицами.

### Назначение четырёх параметров

Кэшируемость адреса предполагается определять выражением:

```systemverilog
cacheable = (address & ADDR_MASK) == ADDR_PATTERN;
```

| Параметр | Назначение |
|---|---|
| `ICACHE_ADDR_MASK` | Указывает, какие биты адреса проверяет I$ |
| `ICACHE_ADDR_PATTERN` | Значения проверяемых битов для I$ |
| `DCACHE_ADDR_MASK` | Указывает, какие биты адреса проверяет D$ |
| `DCACHE_ADDR_PATTERN` | Значения проверяемых битов для D$ |

Значения по умолчанию `'0` означают, что выражение `(address & 0) == 0` истинно для любого адреса. Но фактическая семантика определяется будущими `scr1_icache` и `scr1_dcache`. Перед использованием необходимо задать настоящую карту памяти и исключить MMIO.

## 6. Общие входы

```systemverilog
input logic clk,
input logic rst_n,
```

### `clk`

- Направление: в wrapper и оба кэша.
- Источник: системный/core clock верхнего модуля.
- Получатели: `scr1_icache` и `scr1_dcache`.
- Назначение: синхронизация регистров, автоматов, tag/data RAM и счётчиков.

Wrapper передаёт его без изменения:

```systemverilog
.clk (clk)
```

### `rst_n`

- Направление: в wrapper и оба кэша.
- Источник: обычно `core_rst_n_local` в `scr1_top_axi.sv`.
- Суффикс `_n`: сигнал активен низким уровнем.
- `rst_n = 0`: кэш находится в reset.
- `rst_n = 1`: нормальная работа.

Во время reset реализации кэшей должны как минимум сбросить valid-биты и внутренние автоматы. Содержимое data RAM физически очищать необязательно, потому что строки с `valid = 0` считаются недействительными.

## 7. Сигналы обслуживания кэшей

```systemverilog
input  logic icache_invalidate_i,
output logic icache_invalidate_ack_o,
input  logic dcache_flush_i,
output logic dcache_flush_ack_o,
```

Суффиксы здесь читаются относительно wrapper:

- `_i` — вход wrapper;
- `_o` — выход wrapper.

### `icache_invalidate_i`

- Отправитель: внешняя управляющая логика.
- Получатель: `scr1_icache` через порт `invalidate_i`.
- Значение `1`: запросить инвалидирование I$.
- Ожидаемое действие I$: завершить уже принятый запрос, затем очистить valid-биты.
- Типичный источник: обработка инструкции RISC-V `FENCE.I`.

В существующем `scr1_core_top` готового внешнего сигнала `FENCE.I` для кэша нет. Поэтому для первого подключения этот вход можно привязать к `1'b0`.

### `icache_invalidate_ack_o`

- Отправитель: `scr1_icache` через `invalidate_ack_o`.
- Получатель: внешняя управляющая логика.
- Значение `1`: инвалидирование закончено, I$ снова готов к работе.

### `dcache_flush_i`

- Отправитель: внешняя управляющая логика.
- Получатель: `scr1_dcache` через `flush_i`.
- Значение `1`: запросить flush D$.
- Для write-back D$ ожидаемое действие: записать dirty-строки в нижнюю память, затем инвалидировать их.
- Для write-through D$ обычно достаточно инвалидировать строки, потому что память уже актуальна.

### `dcache_flush_ack_o`

- Отправитель: `scr1_dcache` через `flush_ack_o`.
- Получатель: внешняя управляющая логика.
- Значение `1`: flush полностью закончен.

Для временного подключения допустимо:

```systemverilog
.icache_invalidate_i     (1'b0),
.icache_invalidate_ack_o (),
.dcache_flush_i          (1'b0),
.dcache_flush_ack_o      (),
```

Пустые скобки у выходного порта означают, что выход экземпляра никуда не подключён.

## 8. Верхний интерфейс I$: ядро → кэш инструкций

```systemverilog
output logic                        imem2core_req_ack_o,
input  logic                        core2imem_req_i,
input  type_scr1_mem_cmd_e          core2imem_cmd_i,
input  logic [`SCR1_IMEM_AWIDTH-1:0] core2imem_addr_i,
output logic [`SCR1_IMEM_DWIDTH-1:0] imem2core_rdata_o,
output type_scr1_mem_resp_e         imem2core_resp_o,
```

Имена показывают направление информации:

- `core2imem` — от ядра к instruction memory;
- `imem2core` — от instruction memory к ядру.

### `core2imem_req_i`

- Отправитель: `scr1_core_top.core2imem_req_o`.
- Получатель: wrapper, затем `scr1_icache.cpu_req_i`.
- Значение `1`: ядро предъявляет запрос выборки инструкции.
- Пока запрос не принят, ядро должно удерживать запрос и связанные с ним поля стабильными согласно протоколу SCR1.

### `core2imem_cmd_i`

- Отправитель: ядро.
- Получатель: `scr1_icache.cpu_cmd_i`.
- Тип: `type_scr1_mem_cmd_e`.
- Для обычной выборки инструкции ожидается `SCR1_MEM_CMD_RD`.
- Наличие команды сохраняет интерфейс совместимым со штатным IMEM SCR1.

### `core2imem_addr_i`

- Отправитель: ядро IFU.
- Получатель: `scr1_icache.cpu_addr_i`.
- Содержит адрес требуемой инструкции.
- Реализация I$ разделяет адрес на tag, index и offset cache line.

### `imem2core_req_ack_o`

- Отправитель: `scr1_icache.cpu_req_ack_o`.
- Получатель: `scr1_core_top.imem2core_req_ack_i`.
- Значение `1`: I$ принял текущий запрос ядра и сохранил нужные поля.
- Это подтверждение принятия, а не обязательно окончательный ответ с данными.

### `imem2core_rdata_o`

- Отправитель: I$.
- Получатель: ядро.
- При hit содержит слово инструкции из I$.
- При miss после заполнения содержит нужное слово из загруженной строки.
- Поле считается значимым при готовом ответе `imem2core_resp_o`.

### `imem2core_resp_o`

- Отправитель: I$.
- Получатель: ядро.
- Тип: `type_scr1_mem_resp_e`.

Возможные значения:

```systemverilog
SCR1_MEM_RESP_NOTRDY // операция ещё не закончена
SCR1_MEM_RESP_RDY_OK // инструкция готова, ошибки нет
SCR1_MEM_RESP_RDY_ER // нижняя память вернула ошибку
```

## 9. Верхний интерфейс D$: ядро → кэш данных

```systemverilog
output logic                        dmem2core_req_ack_o,
input  logic                        core2dmem_req_i,
input  type_scr1_mem_cmd_e          core2dmem_cmd_i,
input  type_scr1_mem_width_e        core2dmem_width_i,
input  logic [`SCR1_DMEM_AWIDTH-1:0] core2dmem_addr_i,
input  logic [`SCR1_DMEM_DWIDTH-1:0] core2dmem_wdata_i,
output logic [`SCR1_DMEM_DWIDTH-1:0] dmem2core_rdata_o,
output type_scr1_mem_resp_e         dmem2core_resp_o,
```

### `core2dmem_req_i`

- Отправитель: `scr1_core_top.core2dmem_req_o`.
- Получатель: `scr1_dcache.cpu_req_i`.
- Значение `1`: ядро предъявляет load или store.

### `core2dmem_cmd_i`

- Отправитель: ядро LSU.
- Получатель: `scr1_dcache.cpu_cmd_i`.
- `SCR1_MEM_CMD_RD`: load.
- `SCR1_MEM_CMD_WR`: store.

### `core2dmem_width_i`

- Отправитель: ядро LSU.
- Получатель: `scr1_dcache.cpu_width_i`.
- Определяет число обрабатываемых байтов.

```systemverilog
SCR1_MEM_WIDTH_BYTE  // 1 байт
SCR1_MEM_WIDTH_HWORD // 2 байта
SCR1_MEM_WIDTH_WORD  // 4 байта
```

D$ использует ширину и младшие биты адреса для выбора изменяемых байтов cache line.

### `core2dmem_addr_i`

- Отправитель: ядро LSU.
- Получатель: `scr1_dcache.cpu_addr_i`.
- Адрес load/store.
- D$ также должен проверить, относится ли адрес к cacheable-памяти или MMIO.

### `core2dmem_wdata_i`

- Отправитель: ядро LSU.
- Получатель: `scr1_dcache.cpu_wdata_i`.
- Данные операции store.
- Для load это поле не используется.

### `dmem2core_req_ack_o`

- Отправитель: `scr1_dcache.cpu_req_ack_o`.
- Получатель: `scr1_core_top.dmem2core_req_ack_i`.
- Подтверждает, что D$ принял запрос и ядро может больше не удерживать его на интерфейсе.

### `dmem2core_rdata_o`

- Отправитель: D$.
- Получатель: ядро LSU.
- Содержит результат load.
- Для store значение несущественно.
- Достоверно при `dmem2core_resp_o == SCR1_MEM_RESP_RDY_OK`.

### `dmem2core_resp_o`

- Отправитель: D$.
- Получатель: ядро LSU.
- `NOTRDY`: операция продолжается.
- `RDY_OK`: load/store завершён.
- `RDY_ER`: ошибка доступа.

## 10. Нижний интерфейс I$: кэш инструкций → память

```systemverilog
input  logic                        mem2icache_req_ack_i,
output logic                        icache2mem_req_o,
output type_scr1_mem_cmd_e          icache2mem_cmd_o,
output logic [`SCR1_IMEM_AWIDTH-1:0] icache2mem_addr_o,
input  logic [`SCR1_IMEM_DWIDTH-1:0] mem2icache_rdata_i,
input  type_scr1_mem_resp_e         mem2icache_resp_i,
```

Этот интерфейс активируется при miss или при другом обращении, которое I$ не может обслужить самостоятельно.

### `icache2mem_req_o`

- Отправитель: `scr1_icache.mem_req_o`.
- Получатель: `scr1_imem_router` либо непосредственно `scr1_mem_axi`.
- Значение `1`: I$ запрашивает слово нижней памяти.
- Для заполнения многоcловной cache line кэш последовательно делает несколько запросов, потому что штатный SCR1-интерфейс имеет ширину одного слова и не содержит burst length.

### `icache2mem_cmd_o`

- Отправитель: I$.
- Получатель: нижняя память.
- Обычно всегда `SCR1_MEM_CMD_RD`.

### `icache2mem_addr_o`

- Отправитель: I$.
- Получатель: нижняя память.
- При заполнении строки принимает адрес каждого читаемого слова.

### `mem2icache_req_ack_i`

- Отправитель: router/AXI bridge.
- Получатель: `scr1_icache.mem_req_ack_i`.
- Значение `1`: нижний уровень принял запрос I$.

### `mem2icache_rdata_i`

- Отправитель: нижняя память.
- Получатель: I$.
- Содержит прочитанное слово для заполнения строки.
- Значимо вместе с готовым `mem2icache_resp_i`.

### `mem2icache_resp_i`

- Отправитель: нижняя память.
- Получатель: I$.
- `RDY_OK`: слово успешно получено.
- `RDY_ER`: ошибка; I$ должен прекратить fill и передать ошибку ядру.

## 11. Нижний интерфейс D$: кэш данных → память и MMIO

```systemverilog
input  logic                        mem2dcache_req_ack_i,
output logic                        dcache2mem_req_o,
output type_scr1_mem_cmd_e          dcache2mem_cmd_o,
output type_scr1_mem_width_e        dcache2mem_width_o,
output logic [`SCR1_DMEM_AWIDTH-1:0] dcache2mem_addr_o,
output logic [`SCR1_DMEM_DWIDTH-1:0] dcache2mem_wdata_o,
input  logic [`SCR1_DMEM_DWIDTH-1:0] mem2dcache_rdata_i,
input  type_scr1_mem_resp_e         mem2dcache_resp_i
```

### `dcache2mem_req_o`

- Отправитель: `scr1_dcache.mem_req_o`.
- Получатель: `scr1_dmem_router`.
- Используется для cache-line fill, write-through, write-back и некэшируемого MMIO-доступа.

### `dcache2mem_cmd_o`

- Отправитель: D$.
- Получатель: `dmem_router`.
- `RD`: загрузка строки или некэшируемый load.
- `WR`: запись dirty-строки, write-through или некэшируемый store.

### `dcache2mem_width_o`

- Отправитель: D$.
- Получатель: нижняя память.
- При заполнении или вытеснении строки обычно `WORD`.
- При прозрачном MMIO-доступе должна сохраняться исходная ширина byte/halfword/word.

### `dcache2mem_addr_o`

- Отправитель: D$.
- Получатель: `dmem_router`.
- Адрес очередного нижнего доступа.
- Router по адресу выбирает AXI memory, TCM, timer или другой mapped slave.

### `dcache2mem_wdata_o`

- Отправитель: D$.
- Получатель: нижняя память.
- Данные записи при `dcache2mem_cmd_o == SCR1_MEM_CMD_WR`.
- При чтении значение игнорируется.

### `mem2dcache_req_ack_i`

- Отправитель: `dmem_router`/нижний slave.
- Получатель: D$.
- Подтверждение принятия запроса.

### `mem2dcache_rdata_i`

- Отправитель: нижняя память или MMIO slave.
- Получатель: D$.
- Данные load или данные для заполнения cache line.

### `mem2dcache_resp_i`

- Отправитель: нижняя память.
- Получатель: D$.
- Сообщает о завершении или ошибке операции.

Router должен находиться ниже D$, поскольку D$ обязан передавать некэшируемые обращения к таймеру и периферии дальше по адресной карте.

## 12. Завершение списка портов

```systemverilog
);
```

Закрывающая скобка завершает список портов, а `;` завершает заголовок модуля. После неё начинается тело модуля.

## 13. Создание экземпляра `scr1_icache`

```systemverilog
scr1_icache #(
    .CACHEABLE_ADDR_MASK    (ICACHE_ADDR_MASK),
    .CACHEABLE_ADDR_PATTERN (ICACHE_ADDR_PATTERN)
) i_icache (
```

Эта конструкция создаёт внутри wrapper экземпляр модуля типа `scr1_icache` с именем `i_icache`.

Общий синтаксис:

```systemverilog
имя_типа_модуля #(
    .ИМЯ_ПАРАМЕТРА(значение)
) имя_экземпляра (
    .имя_порта(сигнал)
);
```

Здесь:

- `scr1_icache` — тип модуля, который должен быть определён в другом `.sv` файле;
- `#(...)` — значения параметров этого экземпляра;
- `i_icache` — уникальное имя экземпляра;
- `.порт(сигнал)` — именованное соединение порта дочернего модуля с сигналом wrapper.

Например:

```systemverilog
.cpu_req_i(core2imem_req_i)
```

означает: вход `cpu_req_i` дочернего `scr1_icache` подключён к входу wrapper `core2imem_req_i`.

Полное соответствие портов I$:

| Порт `scr1_icache` | Сигнал wrapper |
|---|---|
| `clk` | `clk` |
| `rst_n` | `rst_n` |
| `invalidate_i` | `icache_invalidate_i` |
| `invalidate_ack_o` | `icache_invalidate_ack_o` |
| `cpu_req_ack_o` | `imem2core_req_ack_o` |
| `cpu_req_i` | `core2imem_req_i` |
| `cpu_cmd_i` | `core2imem_cmd_i` |
| `cpu_addr_i` | `core2imem_addr_i` |
| `cpu_rdata_o` | `imem2core_rdata_o` |
| `cpu_resp_o` | `imem2core_resp_o` |
| `mem_req_ack_i` | `mem2icache_req_ack_i` |
| `mem_req_o` | `icache2mem_req_o` |
| `mem_cmd_o` | `icache2mem_cmd_o` |
| `mem_addr_o` | `icache2mem_addr_o` |
| `mem_rdata_i` | `mem2icache_rdata_i` |
| `mem_resp_i` | `mem2icache_resp_i` |

Wrapper не преобразует эти сигналы, а только соединяет внешние имена SCR1 с более короткими именами портов будущего I$.

## 14. Создание экземпляра `scr1_dcache`

```systemverilog
scr1_dcache #(
    .CACHEABLE_ADDR_MASK    (DCACHE_ADDR_MASK),
    .CACHEABLE_ADDR_PATTERN (DCACHE_ADDR_PATTERN)
) i_dcache (
```

Это экземпляр будущего D$ с именем `i_dcache`. Параметры D$ независимы от I$, поэтому области кэшируемых инструкций и данных при необходимости могут различаться.

Полное соответствие портов D$:

| Порт `scr1_dcache` | Сигнал wrapper |
|---|---|
| `clk` | `clk` |
| `rst_n` | `rst_n` |
| `flush_i` | `dcache_flush_i` |
| `flush_ack_o` | `dcache_flush_ack_o` |
| `cpu_req_ack_o` | `dmem2core_req_ack_o` |
| `cpu_req_i` | `core2dmem_req_i` |
| `cpu_cmd_i` | `core2dmem_cmd_i` |
| `cpu_width_i` | `core2dmem_width_i` |
| `cpu_addr_i` | `core2dmem_addr_i` |
| `cpu_wdata_i` | `core2dmem_wdata_i` |
| `cpu_rdata_o` | `dmem2core_rdata_o` |
| `cpu_resp_o` | `dmem2core_resp_o` |
| `mem_req_ack_i` | `mem2dcache_req_ack_i` |
| `mem_req_o` | `dcache2mem_req_o` |
| `mem_cmd_o` | `dcache2mem_cmd_o` |
| `mem_width_o` | `dcache2mem_width_o` |
| `mem_addr_o` | `dcache2mem_addr_o` |
| `mem_wdata_o` | `dcache2mem_wdata_o` |
| `mem_rdata_i` | `mem2dcache_rdata_i` |
| `mem_resp_i` | `mem2dcache_resp_i` |

## 15. `endmodule`

```systemverilog
endmodule
```

Завершает определение `scr1_cache_wrapper`.

## 16. Два этапа SCR1-транзакции

Интерфейс SCR1 разделяет принятие запроса и завершение операции.

### Этап 1: request/acknowledge

Инициатор выставляет:

```text
req = 1
cmd, width, addr, wdata = стабильны
```

Получатель отвечает:

```text
req_ack = 1
```

После этого запрос считается принятым.

### Этап 2: response

Получатель позднее выдаёт:

```text
resp = SCR1_MEM_RESP_RDY_OK
```

или:

```text
resp = SCR1_MEM_RESP_RDY_ER
```

Для чтения одновременно выдаётся `rdata`. Пока операция не закончена, ответ равен `SCR1_MEM_RESP_NOTRDY`.

Кэш должен хранить параметры уже принятой транзакции внутри собственных регистров. Ядро после `req_ack` не обязано продолжать удерживать старый адрес.

## 17. Типичные последовательности

### I$ hit

```text
Ядро -> I$: req, RD, address
I$ -> Ядро: req_ack
I$ -> Ядро: rdata, RDY_OK
```

Нижний IMEM-интерфейс не используется.

### I$ miss

```text
Ядро -> I$: req, RD, address
I$ -> Ядро: req_ack
I$ -> память: один или несколько RD-запросов
Память -> I$: слова cache line
I$: записывает data/tag/valid
I$ -> Ядро: требуемое rdata, RDY_OK
```

### D$ load hit

```text
Ядро -> D$: req, RD, width, address
D$ -> Ядро: req_ack
D$ -> Ядро: rdata, RDY_OK
```

### D$ store при write-back

```text
Ядро -> D$: req, WR, width, address, wdata
D$ -> Ядро: req_ack
D$: изменяет байты строки и устанавливает dirty
D$ -> Ядро: RDY_OK
```

### Некэшируемый MMIO-доступ

```text
Ядро -> D$: запрос
D$: определяет cacheable = 0
D$ -> dmem_router: тот же запрос
dmem_router -> периферия: запрос
периферия -> dmem_router -> D$: ответ
D$ -> Ядро: ответ без создания cache line
```

## 18. Что необходимо сделать до синтеза

1. Реализовать или подключить реальные `scr1_icache` и `scr1_dcache`.
2. Согласовать их порты с контрактом wrapper.
3. Выбрать размер строки, количество sets, associativity и write policy.
4. Задать настоящие `ADDR_MASK` и `ADDR_PATTERN` по карте памяти.
5. Гарантированно исключить timer, UART и прочее MMIO из D$.
6. Инстанцировать wrapper между `scr1_core_top` и существующими роутерами.
7. Подключить reset и решить, откуда приходят invalidate/flush.
8. Добавить все `.sv` файлы в Vivado и обновить compile order.

До выполнения первого пункта wrapper является точным описанием предполагаемых соединений, но не законченной синтезируемой подсистемой кэша.
