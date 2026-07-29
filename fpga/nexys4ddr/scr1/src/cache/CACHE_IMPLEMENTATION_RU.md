# Реализация `scr1_icache` и `scr1_dcache`

## 1. Где находятся файлы и почему они не участвуют в синтезе

Реализации размещены в отдельном каталоге:

```text
cache_staging/
├── scr1_icache.sv
├── scr1_dcache.sv
└── CACHE_IMPLEMENTATION_RU.md
```

Каталог находится вне `nexys4ddr_scr1.srcs` и файлы не добавлялись командой `add_files`. Файл проекта `nexys4ddr_scr1.xpr` также не изменялся. Поэтому текущий synthesis run Vivado эти модули не видит.

Наличие `.sv` файла рядом с `.xpr` само по себе не добавляет его в проект: Vivado компилирует только файлы, зарегистрированные в fileset, а также явно подключённые через `include`.

## 2. Общая архитектура

Реализованы два независимых блокирующих кэша:

- `scr1_icache` — кэш инструкций;
- `scr1_dcache` — кэш данных.

Оба кэша:

- direct-mapped;
- имеют 64 строки по умолчанию;
- содержат 4 слова по 32 бита в строке;
- имеют строку размером 16 байт;
- имеют полезную ёмкость 1024 байта каждый;
- одновременно обслуживают только один запрос ядра;
- используют штатный протокол SCR1 `req/req_ack/resp`;
- при miss выполняют четыре отдельных чтения по 32 бита;
- не требуют изменения AXI-моста.

`scr1_dcache` дополнительно использует политику:

- write-through;
- no-write-allocate.

Это означает:

- каждый store всегда отправляется в нижнюю память;
- при store hit копия слова в D$ также обновляется;
- при store miss новая строка в D$ не загружается;
- dirty-битов нет;
- flush не записывает данные, а только очищает valid-биты.

## 3. Почему выбрана блокирующая архитектура

Штатный IFU SCR1 умеет иметь несколько ожидающих транзакций. Однако простая первая версия кэша может ограничить число принятых запросов до одного, управляя `cpu_req_ack_o`.

После принятия запроса кэш снимает `cpu_req_ack_o` и не принимает следующий запрос, пока текущая операция не завершится. Это снижает производительность, но сохраняет корректность и сильно упрощает:

- обработку miss;
- сопоставление ответа с запросом;
- обработку ошибок;
- invalidate/flush;
- подключение к существующим router и `scr1_mem_axi`.

Позже производительность можно увеличить добавлением hit-under-miss, request FIFO или нескольких MSHR, не меняя внешний wrapper.

## 4. Параметры модулей

Оба модуля имеют одинаковые параметры геометрии:

```systemverilog
parameter logic [AWIDTH-1:0] CACHEABLE_ADDR_MASK    = '0,
parameter logic [AWIDTH-1:0] CACHEABLE_ADDR_PATTERN = '0,
parameter int unsigned       NUM_LINES              = 64,
parameter int unsigned       LINE_WORDS             = 4
```

### `CACHEABLE_ADDR_MASK`

Определяет, какие биты адреса участвуют в проверке кэшируемости.

### `CACHEABLE_ADDR_PATTERN`

Содержит ожидаемое значение выбранных битов.

Проверка выполняется так:

```systemverilog
(address & CACHEABLE_ADDR_MASK)
    == (CACHEABLE_ADDR_PATTERN & CACHEABLE_ADDR_MASK)
```

### `NUM_LINES`

Количество строк кэша. Значение должно быть степенью двойки и не меньше двух.

### `LINE_WORDS`

Количество 32-битных слов в строке. Значение должно быть степенью двойки и не меньше двух.

При стандартных значениях:

```text
NUM_LINES  = 64
LINE_WORDS = 4
```

ёмкость равна:

```text
64 × 4 × 4 байта = 1024 байта
```

## 5. Разделение 32-битного адреса

При строке 16 байт и 64 строках адрес разделяется так:

```text
31                         10 9            4 3       2 1       0
+----------------------------+---------------+---------+---------+
|            TAG             |     INDEX     |  WORD   |  BYTE   |
+----------------------------+---------------+---------+---------+
            22 бита                6 бит        2 бита    2 бита
```

### `BYTE`, биты `[1:0]`

Выбирают байт внутри 32-битного слова. Используются D$ для byte и halfword load/store.

### `WORD`, биты `[3:2]`

Выбирают одно из четырёх слов строки.

### `INDEX`, биты `[9:4]`

Выбирают одну из 64 физических строк кэша.

### `TAG`, биты `[31:10]`

Определяют, какой участок памяти сейчас находится в выбранной строке.

В исходном коде размеры вычисляются, а не фиксируются вручную:

```systemverilog
localparam BYTE_OFFSET_BITS = 2;
localparam WORD_INDEX_BITS  = $clog2(LINE_WORDS);
localparam LINE_OFFSET_BITS = BYTE_OFFSET_BITS + WORD_INDEX_BITS;
localparam LINE_INDEX_BITS  = $clog2(NUM_LINES);
localparam TAG_BITS         = AWIDTH - LINE_OFFSET_BITS - LINE_INDEX_BITS;
```

`$clog2(N)` возвращает число бит, необходимое для адресации `N` элементов.

## 6. Массивы кэша

В каждом кэше объявлены:

```systemverilog
logic [31:0]         data_mem [0:NUM_LINES-1][0:LINE_WORDS-1];
logic [TAG_BITS-1:0] tag_mem  [0:NUM_LINES-1];
logic [NUM_LINES-1:0] valid_q;
```

### `data_mem`

Хранит сами слова. Первый индекс выбирает строку, второй — слово внутри строки:

```systemverilog
data_mem[line_index][word_index]
```

### `tag_mem`

Хранит tag для каждой физической строки.

### `valid_q`

По одному valid-биту на строку. Если бит равен нулю, содержимое `data_mem` и `tag_mem` этой строки игнорируется.

Данные и tags во время reset физически не очищаются. Очищаются только valid-биты:

```systemverilog
valid_q <= '0;
```

Это достаточно для логической очистки кэша и не создаёт ненужную схему сброса большой памяти.

## 7. Определение hit

Hit вычисляется одинаково в I$ и D$:

```systemverilog
req_hit = valid_q[req_line_index]
       && (tag_mem[req_line_index] == req_tag);
```

Необходимы оба условия:

1. строка действительна;
2. tag сохранённой строки совпадает с tag адреса запроса.

Одного совпадения index недостаточно: разные адреса памяти могут отображаться в одну физическую строку direct-mapped кэша.

## 8. Регистры принятого запроса

После handshake с ядром параметры запроса сохраняются:

```systemverilog
if (cpu_req_i && cpu_req_ack_o) begin
    req_addr_q <= cpu_addr_i;
    req_cmd_q  <= cpu_cmd_i;
end
```

D$ дополнительно сохраняет:

```systemverilog
req_width_q <= cpu_width_i;
req_wdata_q <= cpu_wdata_i;
```

Это обязательно, потому что после `req_ack` ядро может изменить внешние сигналы. Все последующие стадии работают только с регистрами `req_*_q`.

## 9. Интерфейс процессорной стороны

### Общие сигналы I$ и D$

| Сигнал | Направление | Значение |
|---|---|---|
| `cpu_req_i` | ядро → кэш | Ядро предъявляет запрос |
| `cpu_req_ack_o` | кэш → ядро | Кэш принимает запрос |
| `cpu_cmd_i` | ядро → кэш | `RD` или `WR` |
| `cpu_addr_i` | ядро → кэш | Адрес операции |
| `cpu_rdata_o` | кэш → ядро | Результат чтения |
| `cpu_resp_o` | кэш → ядро | Не готово, успех или ошибка |

### Дополнительные сигналы D$

| Сигнал | Направление | Значение |
|---|---|---|
| `cpu_width_i` | ядро → D$ | Byte, halfword или word |
| `cpu_wdata_i` | ядро → D$ | Данные store в младших битах |

`cpu_req_ack_o` равен единице только в `IDLE`, когда нет maintenance-запроса. Handshake происходит на фронте:

```systemverilog
cpu_req_i && cpu_req_ack_o
```

`cpu_resp_o` является отдельной фазой и выдаётся позднее:

```systemverilog
SCR1_MEM_RESP_NOTRDY
SCR1_MEM_RESP_RDY_OK
SCR1_MEM_RESP_RDY_ER
```

## 10. Интерфейс нижней памяти

### Общие сигналы

| Сигнал | Направление | Значение |
|---|---|---|
| `mem_req_o` | кэш → router | Запрос нижней транзакции |
| `mem_req_ack_i` | router → кэш | Нижняя сторона приняла запрос |
| `mem_cmd_o` | кэш → router | Чтение или запись |
| `mem_addr_o` | кэш → router | Адрес слова/операции |
| `mem_rdata_i` | router → кэш | Прочитанные данные |
| `mem_resp_i` | router → кэш | Завершение или ошибка |

D$ также передаёт:

| Сигнал | Назначение |
|---|---|
| `mem_width_o` | Размер записи или bypass-чтения |
| `mem_wdata_o` | Данные записи |

Кэш удерживает `mem_req_o`, адрес и команду в состоянии `*_REQ`, пока не увидит `mem_req_ack_i`. После подтверждения он переходит в `*_WAIT`, снимает `mem_req_o` и ожидает `mem_resp_i`.

## 11. Автомат `scr1_icache`

I$ имеет десять состояний.

### `IC_IDLE`

- Кэш готов принять запрос.
- `cpu_req_ack_o = 1`, если нет invalidate.
- При handshake адрес и команда записываются в `req_addr_q` и `req_cmd_q`.
- Следующее состояние — `IC_LOOKUP`.

### `IC_LOOKUP`

Выполняются три проверки:

1. Команда должна быть `RD`. Запись через instruction port считается ошибкой.
2. Некэшируемый адрес направляется в `IC_BYPASS_REQ`.
3. Кэшируемый hit направляется в `IC_RESP_OK`.
4. Кэшируемый miss начинает fill через `IC_FILL_REQ`.

При hit выбранное слово синхронно записывается в `response_data_q`.

### `IC_FILL_REQ`

I$ выставляет:

```text
mem_req_o  = 1
mem_cmd_o  = RD
mem_addr_o = адрес очередного слова cache line
```

После `mem_req_ack_i = 1` переходит в `IC_FILL_WAIT`.

### `IC_FILL_WAIT`

При `RDY_OK`:

- `mem_rdata_i` записывается в `data_mem`;
- если это слово первоначального запроса, оно сохраняется в `response_data_q`;
- счётчик `fill_word_q` увеличивается;
- после последнего слова записываются tag и valid.

При `RDY_ER` fill прекращается и ядру возвращается ошибка. Valid-бит строки был заранее очищен, поэтому частично заполненная строка никогда не будет считаться действительной.

### `IC_BYPASS_REQ`

Формирует одно чтение точно по адресу ядра, без создания cache line.

### `IC_BYPASS_WAIT`

Ожидает ответ нижней памяти. Успешные данные сохраняются в `response_data_q`, но не записываются в массив кэша.

### `IC_RESP_OK`

На один такт выдаёт:

```text
cpu_rdata_o = response_data_q
cpu_resp_o  = SCR1_MEM_RESP_RDY_OK
```

### `IC_RESP_ERR`

На один такт выдаёт `SCR1_MEM_RESP_RDY_ER`.

### `IC_INVALIDATE`

Очищает все valid-биты. Data RAM и tag RAM не очищаются.

### `IC_INVALIDATE_ACK`

Удерживает `invalidate_ack_o = 1`, пока управляющая логика не снимет `invalidate_i`.

### Как FSM разделена в коде

Автомат I$ реализован в классическом стиле из трёх частей:

1. регистр текущего состояния `state_q`;
2. комбинационная логика следующего состояния `state_d`;
3. комбинационная логика выходов и последовательная логика данных.

Тип и два сигнала состояния объявлены так:

```systemverilog
typedef enum logic [3:0] {
    IC_IDLE,
    IC_LOOKUP,
    IC_FILL_REQ,
    IC_FILL_WAIT,
    IC_BYPASS_REQ,
    IC_BYPASS_WAIT,
    IC_RESP_OK,
    IC_RESP_ERR,
    IC_INVALIDATE,
    IC_INVALIDATE_ACK
} icache_state_e;

icache_state_e state_q;
icache_state_e state_d;
```

`state_q` — состояние, в котором автомат находится сейчас. Оно хранится в триггерах и изменяется только по положительному фронту `clk`.

`state_d` — вычисленное комбинационной логикой состояние, в которое автомат должен перейти на следующем фронте.

Запись состояния находится в `always_ff`:

```systemverilog
always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
        state_q <= IC_IDLE;
        // ...
    end else begin
        state_q <= state_d;
        // ...
    end
end
```

При активном низком reset автомат немедленно возвращается в `IC_IDLE`. В нормальном режиме каждый фронт копирует `state_d` в `state_q`.

Важно различать момент вычисления и момент перехода. Если в текущем такте комбинационная логика присвоила:

```systemverilog
state_d = IC_LOOKUP;
```

то `state_q` останется прежним до ближайшего фронта `clk`. Только после фронта выходная логика увидит, что текущее состояние стало `IC_LOOKUP`.

### Логика следующего состояния

Второй блок отвечает только на вопрос: «Куда перейти дальше?»

```systemverilog
always_comb begin
    state_d = state_q;

    unique case (state_q)
        // переходы состояний
    endcase
end
```

Строка:

```systemverilog
state_d = state_q;
```

задаёт поведение по умолчанию — остаться в текущем состоянии. Например, если I$ находится в `IC_FILL_WAIT`, а ответ памяти ещё не пришёл, ни одно условие перехода не выполняется и автомат продолжает ждать.

Такое значение по умолчанию также гарантирует полное присваивание `state_d` в комбинационном блоке и предотвращает появление нежелательной latch-логики.

Ключевое слово:

```systemverilog
unique case
```

показывает, что в каждый момент ожидается ровно один подходящий вариант состояния. Оно также помогает симулятору и синтезатору обнаруживать некорректные или неизвестные значения `state_q`.

Ветка:

```systemverilog
default: begin
    state_d = IC_IDLE;
end
```

является защитным возвратом в `IC_IDLE`, если состояние оказалось повреждено или содержит неожиданное значение.

### Логика выходов зависит от `state_q`

Отдельный `always_comb` формирует сигналы ядру и нижней памяти:

```systemverilog
always_comb begin
    cpu_req_ack_o    = 1'b0;
    cpu_rdata_o      = response_data_q;
    cpu_resp_o       = SCR1_MEM_RESP_NOTRDY;
    invalidate_ack_o = 1'b0;

    mem_req_o        = 1'b0;
    mem_cmd_o        = SCR1_MEM_CMD_RD;
    mem_addr_o       = '0;

    // Изменение выходов в конкретных состояниях
end
```

Сначала всем выходам задаются безопасные значения по умолчанию:

- новый CPU-запрос не подтверждён;
- ответ ядру ещё не готов;
- запрос в нижнюю память отсутствует;
- команда нижней памяти по умолчанию — чтение;
- invalidate ещё не подтверждён.

После этого конкретное состояние переопределяет только необходимые сигналы. Например:

```systemverilog
if ((state_q == IC_IDLE) && !invalidate_i) begin
    cpu_req_ack_o = 1'b1;
end
```

I$ сообщает о готовности принять запрос только в `IC_IDLE`. Во всех остальных состояниях он занят предыдущей транзакцией, поэтому `cpu_req_ack_o = 0`.

Выходы в основном зависят от `state_q`, поэтому это близко к автомату Мура. Исключение — готовность в `IC_IDLE` дополнительно блокируется входом `invalidate_i`.

### Приём запроса в `IC_IDLE`

Логика переходов задаёт приоритет invalidate:

```systemverilog
IC_IDLE: begin
    if (invalidate_i) begin
        state_d = IC_INVALIDATE;
    end else if (cpu_req_i) begin
        state_d = IC_LOOKUP;
    end
end
```

Если одновременно пришли invalidate и запрос инструкции, кэш сначала инвалидируется. `cpu_req_ack_o` в этот момент равен нулю, поэтому запрос ядра не считается принятым.

Нормальный handshake происходит при:

```systemverilog
cpu_req_i && cpu_req_ack_o
```

На том же фронте запрос сохраняется:

```systemverilog
if ((state_q == IC_IDLE) && cpu_req_i && cpu_req_ack_o) begin
    req_addr_q <= cpu_addr_i;
    req_cmd_q  <= cpu_cmd_i;
end
```

После фронта:

- `state_q` становится `IC_LOOKUP`;
- `req_addr_q` содержит стабильную копию адреса;
- `req_cmd_q` содержит стабильную копию команды;
- ядро больше не обязано удерживать старые входные сигналы.

Именно поэтому lookup и fill используют `req_addr_q`, а не непосредственно `cpu_addr_i`.

### Вычисление lookup-признаков

Из сохранённого адреса постоянно вычисляются части адреса:

```systemverilog
assign req_word_index = req_addr_q[BYTE_OFFSET_BITS +: WORD_INDEX_BITS];
assign req_line_index = req_addr_q[LINE_OFFSET_BITS +: LINE_INDEX_BITS];
assign req_tag        = req_addr_q[`SCR1_IMEM_AWIDTH-1 -: TAG_BITS];
```

Также вычисляются cacheability и hit:

```systemverilog
assign req_cacheable = (req_addr_q & CACHEABLE_ADDR_MASK)
                     == (CACHEABLE_ADDR_PATTERN & CACHEABLE_ADDR_MASK);

assign req_hit = valid_q[req_line_index]
              && (tag_mem[req_line_index] == req_tag);
```

В состоянии `IC_LOOKUP` автомат выбирает один из четырёх путей:

```systemverilog
IC_LOOKUP: begin
    if (req_cmd_q != SCR1_MEM_CMD_RD) begin
        state_d = IC_RESP_ERR;
    end else if (!req_cacheable) begin
        state_d = IC_BYPASS_REQ;
    end else if (req_hit) begin
        state_d = IC_RESP_OK;
    end else begin
        state_d = IC_FILL_REQ;
    end
end
```

Порядок условий имеет значение:

1. неправильная команда немедленно даёт ошибку;
2. некэшируемый адрес не проверяется как обычный hit, а отправляется в bypass;
3. кэшируемый hit возвращается из массива;
4. всё остальное является кэшируемым miss.

### Путь cache hit

Если `req_hit = 1`, комбинационная логика выбирает `IC_RESP_OK`. Одновременно последовательная логика считывает нужное слово:

```systemverilog
if ((state_q == IC_LOOKUP) && req_cacheable && req_hit
    && (req_cmd_q == SCR1_MEM_CMD_RD)) begin
    response_data_q <= data_mem[req_line_index][req_word_index];
end
```

На фронте, завершающем `IC_LOOKUP`, происходят сразу два действия:

```text
state_q         ← IC_RESP_OK
response_data_q ← выбранное слово data_mem
```

После фронта выходной блок видит `IC_RESP_OK`:

```systemverilog
if (state_q == IC_RESP_OK) begin
    cpu_resp_o = SCR1_MEM_RESP_RDY_OK;
end
```

А `cpu_rdata_o` всё время подключён к регистру результата:

```systemverilog
cpu_rdata_o = response_data_q;
```

Поэтому в течение состояния `IC_RESP_OK` ядро одновременно видит корректные данные и успешный ответ. На следующем фронте автомат возвращается в `IC_IDLE`:

```systemverilog
IC_RESP_OK,
IC_RESP_ERR: begin
    state_d = IC_IDLE;
end
```

### Начало miss и подготовка строки

При кэшируемом miss `IC_LOOKUP` выбирает `IC_FILL_REQ`. На фронте перехода последовательная логика выполняет подготовку:

```systemverilog
if ((state_q == IC_LOOKUP) && req_cacheable && !req_hit) begin
    fill_word_q             <= '0;
    valid_q[req_line_index] <= 1'b0;
end
```

Здесь:

- `fill_word_q = 0` начинает заполнение с первого слова;
- valid-бит выбранной строки очищается до записи новых данных.

Если строка раньше содержала другой TAG, она с этого момента считается вытесненной. Пока fill не закончен, частично записанные данные не могут дать hit.

### Пара `IC_FILL_REQ` и `IC_FILL_WAIT`

Протокол нижней памяти имеет две отдельные фазы:

```text
REQ  → запрос принят через mem_req_ack_i
WAIT → операция закончена через mem_resp_i
```

В `IC_FILL_REQ` кэш удерживает запрос:

```systemverilog
if (state_q == IC_FILL_REQ) begin
    mem_req_o  = 1'b1;
    mem_addr_o = fill_addr;
end
```

`mem_cmd_o` уже установлен в `SCR1_MEM_CMD_RD` значением по умолчанию. `fill_addr` указывает на очередное слово заполняемой строки.

Автомат остаётся в `IC_FILL_REQ`, пока нижняя память не подтвердит принятие:

```systemverilog
IC_FILL_REQ: begin
    if (mem_req_ack_i) begin
        state_d = IC_FILL_WAIT;
    end
end
```

После handshake `mem_req_o` снимается, потому что в `IC_FILL_WAIT` условие его установки уже ложно. Кэш ждёт завершения принятой транзакции:

```systemverilog
IC_FILL_WAIT: begin
    if (mem_resp_i == SCR1_MEM_RESP_RDY_ER) begin
        state_d = IC_RESP_ERR;
    end else if (mem_resp_i == SCR1_MEM_RESP_RDY_OK) begin
        if (fill_word_q == WORD_INDEX_BITS'(LINE_WORDS - 1)) begin
            state_d = IC_RESP_OK;
        end else begin
            state_d = IC_FILL_REQ;
        end
    end
end
```

Возможны три ситуации:

- `NOTRDY` — оставаться в `IC_FILL_WAIT`;
- `RDY_ER` — прекратить fill и вернуть ошибку;
- `RDY_OK` — принять слово и либо запросить следующее, либо завершить fill.

### Запись пришедшего слова

Фактическое изменение массива выполняется не в комбинационном FSM-блоке, а в `always_ff`:

```systemverilog
if ((state_q == IC_FILL_WAIT)
    && (mem_resp_i == SCR1_MEM_RESP_RDY_OK)) begin
    data_mem[req_line_index][fill_word_q] <= mem_rdata_i;

    if (fill_word_q == req_word_index) begin
        response_data_q <= mem_rdata_i;
    end

    if (fill_word_q == WORD_INDEX_BITS'(LINE_WORDS - 1)) begin
        tag_mem[req_line_index] <= req_tag;
        valid_q[req_line_index] <= 1'b1;
    end else begin
        fill_word_q <= fill_word_q + 1'b1;
    end
end
```

Каждый успешный ответ делает следующее:

1. записывает `mem_rdata_i` в позицию `fill_word_q`;
2. при совпадении с `req_word_index` отдельно запоминает слово, которое просило ядро;
3. после непоследнего слова увеличивает счётчик;
4. после последнего слова записывает TAG и устанавливает VALID.

Хотя нужное ядру слово может прийти раньше остальных, автомат всё равно завершает всю строку. Например, для запроса второго слова:

```text
fill_word_q = 0 → записать WORD0
fill_word_q = 1 → записать WORD1 и response_data_q
fill_word_q = 2 → записать WORD2
fill_word_q = 3 → записать WORD3, TAG, VALID
```

Только после `WORD3` выполняется переход в `IC_RESP_OK`. Это упрощает автомат, но увеличивает miss latency по сравнению с critical-word-first кэшем.

### Цикл заполнения строки

Для четырёх слов основная петля состояний выглядит так:

```text
IC_FILL_REQ  --ack-->  IC_FILL_WAIT  --WORD0 OK--> IC_FILL_REQ
IC_FILL_REQ  --ack-->  IC_FILL_WAIT  --WORD1 OK--> IC_FILL_REQ
IC_FILL_REQ  --ack-->  IC_FILL_WAIT  --WORD2 OK--> IC_FILL_REQ
IC_FILL_REQ  --ack-->  IC_FILL_WAIT  --WORD3 OK--> IC_RESP_OK
```

Если `mem_req_ack_i` или `mem_resp_i` задерживаются, соответствующее состояние автоматически растягивается на нужное количество тактов.

### Обработка ошибки во время fill

При `RDY_ER` автомат переходит из `IC_FILL_WAIT` в `IC_RESP_ERR`. TAG и VALID не устанавливаются, потому что их запись выполняется только при успешном последнем слове:

```systemverilog
if (fill_word_q == WORD_INDEX_BITS'(LINE_WORDS - 1)) begin
    tag_mem[req_line_index] <= req_tag;
    valid_q[req_line_index] <= 1'b1;
end
```

Часть `data_mem` могла уже измениться, но valid-бит был очищен в начале miss. Поэтому частично загруженная строка логически недействительна и не может породить ложный hit.

В `IC_RESP_ERR` выходной блок выдаёт:

```systemverilog
cpu_resp_o = SCR1_MEM_RESP_RDY_ER;
```

а затем автомат возвращается в `IC_IDLE`.

### Bypass-путь

Некэшируемый адрес не должен занимать строку. Поэтому из `IC_LOOKUP` выполняется переход:

```text
IC_BYPASS_REQ → IC_BYPASS_WAIT → IC_RESP_OK/IC_RESP_ERR
```

В `IC_BYPASS_REQ` формируется один запрос по исходному адресу:

```systemverilog
if (state_q == IC_BYPASS_REQ) begin
    mem_req_o  = 1'b1;
    mem_addr_o = req_addr_q;
end
```

После `mem_req_ack_i` автомат ожидает ответ:

```systemverilog
IC_BYPASS_WAIT: begin
    if (mem_resp_i == SCR1_MEM_RESP_RDY_ER) begin
        state_d = IC_RESP_ERR;
    end else if (mem_resp_i == SCR1_MEM_RESP_RDY_OK) begin
        state_d = IC_RESP_OK;
    end
end
```

Успешные данные сохраняются только в регистр ответа:

```systemverilog
if ((state_q == IC_BYPASS_WAIT)
    && (mem_resp_i == SCR1_MEM_RESP_RDY_OK)) begin
    response_data_q <= mem_rdata_i;
end
```

`data_mem`, `tag_mem` и `valid_q` не изменяются. Поэтому повторное обращение к такому адресу снова пойдёт в bypass.

### Логика invalidate

Invalidate принимается только из свободного состояния `IC_IDLE`. Поэтому он не прерывает уже принятый fill или bypass на середине.

Путь выглядит так:

```text
IC_IDLE → IC_INVALIDATE → IC_INVALIDATE_ACK → IC_IDLE
```

В `IC_INVALIDATE` последовательная логика очищает все valid-биты:

```systemverilog
if (state_q == IC_INVALIDATE) begin
    for (line = 0; line < NUM_LINES; line = line + 1) begin
        valid_q[line] <= 1'b0;
    end
end
```

На следующем фронте автомат переходит в `IC_INVALIDATE_ACK`, где выставляет:

```systemverilog
invalidate_ack_o = 1'b1;
```

Он остаётся там, пока инициатор не снимет `invalidate_i`:

```systemverilog
IC_INVALIDATE_ACK: begin
    if (!invalidate_i) begin
        state_d = IC_IDLE;
    end
end
```

Это level-handshake: запрос удерживается до появления acknowledge, после чего инициатор снимает запрос, а кэш возвращается в `IC_IDLE`.

### Полная схема переходов I$

```text
                         invalidate_i
                    +--------------------+
                    |                    v
                +---------+       +---------------+       +-------------------+
          +---->| IC_IDLE |------>| IC_INVALIDATE |------>| IC_INVALIDATE_ACK |
          |     +---------+       +---------------+       +-------------------+
          |          | cpu_req_i                                  |
          |          v                                            | !invalidate_i
          |     +-----------+                                     |
          |     | IC_LOOKUP |                                     |
          |     +-----------+                                     |
          |       |    |    |                                      |
          |  hit  |    |    | miss                                 |
          |       |    |    v                                      |
          |       |    |  +-------------+  ack  +--------------+  |
          |       |    |  | IC_FILL_REQ |------>| IC_FILL_WAIT |--+
          |       |    |  +-------------+       +--------------+
          |       |    |          ^                 | OK, not last
          |       |    |          +-----------------+
          |       |    |
          |       |    | uncached
          |       |    v
          |       |  +---------------+ ack +----------------+
          |       |  | IC_BYPASS_REQ |---->| IC_BYPASS_WAIT |
          |       |  +---------------+     +----------------+
          |       |                              |
          |       v                              v
          |  +------------+                +-------------+
          +--| IC_RESP_OK |                | IC_RESP_ERR |
          |  +------------+                +-------------+
          |                                      |
          +--------------------------------------+
```

Условие `RDY_ER` из `IC_FILL_WAIT` и `IC_BYPASS_WAIT` ведёт в `IC_RESP_ERR`. Успешный последний fill и успешный bypass ведут в `IC_RESP_OK`. Оба response-состояния однотактные и затем возвращаются в `IC_IDLE`.

### Пример по тактам: cache hit

Если запрос появился перед фронтом `T0`:

```text
До T0:  state_q=IC_IDLE, cpu_req_ack_o=1, cpu_req_i=1
T0:     сохранить addr/cmd, перейти в IC_LOOKUP
T0–T1:  вычислить INDEX, TAG, hit
T1:     записать выбранное слово в response_data_q,
        перейти в IC_RESP_OK
T1–T2:  cpu_resp_o=RDY_OK, cpu_rdata_o=response_data_q
T2:     вернуться в IC_IDLE
```

### Пример по тактам: первый запрос fill

При miss:

```text
T0: принять CPU-запрос
T1: обнаружить miss, сбросить VALID, fill_word_q=0
после T1: state_q=IC_FILL_REQ, mem_req_o=1, mem_addr_o=адрес WORD0
T2: если mem_req_ack_i=1, перейти в IC_FILL_WAIT
после T2: mem_req_o=0, ожидать mem_resp_i
Tn: при RDY_OK записать WORD0, fill_word_q=1, перейти в IC_FILL_REQ
```

Далее эта пара состояний повторяется для `WORD1–WORD3`. Точное число тактов зависит от задержек `mem_req_ack_i` и `mem_resp_i`.

## 12. Последовательность I$ miss

Для запроса `0x00001234` строка начинается с `0x00001230`:

```text
fill_word=0: read 0x00001230
fill_word=1: read 0x00001234
fill_word=2: read 0x00001238
fill_word=3: read 0x0000123C
```

После четвёртого успешного ответа:

```text
tag_mem[index] = tag
valid_q[index] = 1
```

Ядро получает слово, которое пришло при `fill_word=1`.

## 13. Автомат `scr1_dcache`

Структура похожа на I$, но решение в `DC_LOOKUP` учитывает команду.

### `DC_IDLE`

Принимает один запрос ядра и сохраняет `addr`, `cmd`, `width`, `wdata`.

### `DC_LOOKUP`

Решение принимается так:

```text
store                         -> BYPASS_REQ
uncached load                 -> BYPASS_REQ
cached load + hit             -> RESP_OK
cached load + miss            -> FILL_REQ
```

Термин `BYPASS_REQ` для store означает не «игнорировать кэш», а «обязательно отправить write-through транзакцию в нижнюю память». При store hit cached copy обновляется после успешного ответа памяти.

### `DC_FILL_REQ` и `DC_FILL_WAIT`

Используются только для кэшируемого read miss. D$ читает четыре выровненных 32-битных слова, записывает строку и после последнего ответа устанавливает valid/tag.

### `DC_BYPASS_REQ`

Передаёт без изменения сохранённые поля:

```text
mem_cmd_o   = req_cmd_q
mem_width_o = req_width_q
mem_addr_o  = req_addr_q
mem_wdata_o = req_wdata_q
```

Используется для:

- всех stores;
- некэшируемых loads;
- MMIO.

### `DC_BYPASS_WAIT`

При успешном load данные нижней памяти возвращаются ядру.

При успешном store hit обновляется cached copy. При ошибке store cached copy не изменяется, поэтому она остаётся согласованной со старым содержимым памяти.

### `DC_RESP_OK` и `DC_RESP_ERR`

Выдают ядру однотактный результат операции.

### `DC_FLUSH`

Очищает valid-биты. Записывать строки в память не требуется: write-through гарантирует отсутствие dirty-данных.

### `DC_FLUSH_ACK`

Удерживает `flush_ack_o = 1` до снятия `flush_i`.

## 14. Обработка byte и halfword load

Cache line хранит полные 32-битные слова. При cache hit или fill нужные байты сдвигаются в младшую часть результата:

```systemverilog
word_data >> (8 * byte_offset)
```

Примеры для слова `32'h44332211`:

```text
адрес +0 -> 0x44332211
адрес +1 -> 0x00443322
адрес +2 -> 0x00004433
адрес +3 -> 0x00000044
```

Сам D$ не выполняет знаковое расширение. LSU SCR1 знает конкретную инструкцию `LB/LBU/LH/LHU` и выполняет необходимое расширение после получения данных.

При bypass нижний `scr1_mem_axi` или TCM уже сдвигает результат к младшим битам, поэтому повторный сдвиг в D$ не выполняется.

## 15. Обработка byte и halfword store

Функция `merge_store_data` обновляет только нужные байты cached word.

Например, было:

```text
old_word = 0x11223344
```

Store byte `0xAA` по смещению 1 создаёт маску:

```text
mask     = 0x0000FF00
new_word = 0x1122AA44
```

Store halfword `0xBEEF` по смещению 2 создаёт:

```text
mask     = 0xFFFF0000
new_word = 0xBEEF3344
```

Невыровненные halfword/word запросы до D$ обычно не доходят: LSU SCR1 формирует исключение misaligned access.

## 16. Политика write-through/no-write-allocate

### Store hit

```text
ядро -> D$: store
D$ -> lower memory: store
lower memory -> D$: RDY_OK
D$: обновляет cached word
D$ -> ядро: RDY_OK
```

Ответ ядру задерживается до подтверждения нижней памяти. Поэтому отдельный write buffer не нужен.

### Store miss

```text
ядро -> D$: store
D$ -> lower memory: store
lower memory -> D$: RDY_OK
D$ не загружает cache line
D$ -> ядро: RDY_OK
```

No-write-allocate хорошо подходит для простой первой версии: store miss не требует сначала читать целую строку.

### Почему нет dirty-бита

После каждого успешного store нижняя память уже содержит актуальное значение. В кэше нет более новых данных, которые отсутствуют в памяти. Следовательно, dirty-бит и автомат write-back не требуются.

## 17. Некэшируемая память и MMIO

В текущем block design:

| Область | Диапазон |
|---|---|
| DDR2 | `0x00000000–0x07FFFFFF` |
| GPIO | с `0xFF000000` |
| build ID | с `0xFF001000` |
| core clock registers | с `0xFF002000` |
| UART | с `0xFF010000` |
| BRAM | `0xFFFF0000–0xFFFFFFFF` |

Чтобы кэшировать только 128 MiB DDR2, следует использовать:

```systemverilog
.ICACHE_ADDR_MASK     (32'hF8000000),
.ICACHE_ADDR_PATTERN  (32'h00000000),
.DCACHE_ADDR_MASK     (32'hF8000000),
.DCACHE_ADDR_PATTERN  (32'h00000000)
```

Проверка будет истинна только для адресов, у которых верхние пять бит равны нулю, то есть `0x00000000–0x07FFFFFF`.

BRAM при такой настройке будет некэшируемой. Это безопасная исходная конфигурация, хотя позже при необходимости можно расширить декодер до нескольких cacheable regions.

Нельзя использовать нулевую маску в готовой системе с MMIO: нулевая маска считает кэшируемыми все адреса, включая UART и GPIO.

## 18. Invalidate, flush и когерентность I$/D$

I$ и D$ независимы и аппаратно когерентность друг с другом не поддерживают.

Если программа записала новый машинный код через D$, возможна ситуация:

```text
DDR содержит новую инструкцию
I$ всё ещё содержит старую инструкцию
```

Перед выполнением изменённого кода необходимо выполнить последовательность, эквивалентную:

1. дождаться завершения stores D$;
2. запросить `icache.invalidate_i`;
3. дождаться `invalidate_ack_o`;
4. снять `invalidate_i`;
5. продолжить выборку инструкций.

В текущем `scr1_core_top` эти maintenance-сигналы наружу не выведены автоматически. Их источник нужно реализовать отдельно либо временно привязать входы к нулю.

## 19. Ошибки нижней памяти

Если во время fill приходит `SCR1_MEM_RESP_RDY_ER`:

- операция fill прекращается;
- valid-бит строки остаётся нулевым;
- частично записанные слова не могут дать hit;
- ядру возвращается `SCR1_MEM_RESP_RDY_ER`.

Если ошибка приходит во время store:

- cached copy не обновляется;
- ядро получает ошибку;
- старое значение кэша соответствует старому состоянию памяти.

## 20. Ограничения реализации

Текущая версия намеренно проста и имеет следующие ограничения:

- только одна активная CPU-транзакция;
- direct-mapped, поэтому возможны частые conflict misses;
- fill выполняется четырьмя одиночными запросами, без burst;
- нет critical-word-first: ответ ядру выдаётся после заполнения всей строки;
- нет prefetch;
- нет write buffer;
- нет ECC/parity;
- нет аппаратной когерентности между I$ и D$;
- cacheability задаётся одной парой mask/pattern;
- поддерживается только 32-битная шина данных;
- `LINE_WORDS` и `NUM_LINES` должны быть степенями двойки.

Это функциональная отправная точка, а не высокопроизводительная микроархитектура.

## 21. Что проверено

Оба файла вместе с `scr1_cache_wrapper.sv` отдельно разобраны SystemVerilog-компилятором Vivado 2019.1 (`xvlog`). Компилятор успешно распознал:

```text
scr1_icache
scr1_dcache
scr1_cache_wrapper
```

Проверка выполнялась вне проектного fileset. Текущий `.xpr` и запущенный synthesis run не изменялись.

Дополнительно создан автономный testbench:

```text
cache_staging/tb/scr1_cache_blocks_tb.sv
```

Он выполнен в XSim Vivado 2019.1 и проверяет:

- I$ miss и fill четырьмя словами;
- последующий I$ hit без обращения к памяти;
- I$ invalidate и повторный miss;
- D$ read miss и read hit;
- write-through byte store hit;
- обновление cached copy после успешного store;
- store miss с no-write-allocate;
- повторный MMIO bypass;
- D$ flush и повторный miss.

Результат автономного запуска:

```text
PASS: all cache tests completed successfully
```

Перед включением в FPGA всё равно рекомендуется выполнить полный SoC testbench: автономная модель проверяет протокол и выбранные сценарии, но не заменяет совместную проверку с реальными router, TCM и AXI bridge.

## 22. Как добавить позже

После завершения текущего синтеза и перед интеграцией нужно добавить в Vivado:

```text
cache_staging/scr1_icache.sv
cache_staging/scr1_dcache.sv
```

Затем wrapper следует инстанцировать между `scr1_core_top` и router. Для текущей карты DDR параметры wrapper рекомендуется задать так:

```systemverilog
scr1_cache_wrapper #(
    .ICACHE_ADDR_MASK     (32'hF8000000),
    .ICACHE_ADDR_PATTERN  (32'h00000000),
    .DCACHE_ADDR_MASK     (32'hF8000000),
    .DCACHE_ADDR_PATTERN  (32'h00000000)
) i_cache_wrapper (...);
```

Только после добавления файлов и инстанцирования wrapper они начнут участвовать в synthesis.
