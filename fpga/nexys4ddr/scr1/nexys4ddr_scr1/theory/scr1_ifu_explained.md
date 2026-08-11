# Instruction Fetch Unit (IFU) в ядре SCR1 — детальный разбор

> Разбор модуля `scr1/src/core/pipeline/scr1_pipe_ifu.sv`.
> Ссылки на документацию: `scr1_eas.pdf` (Architecture Specification, разделы 4.2, 6.1),
> `scr1_um.pdf` (User Manual).

Документ отвечает на три вопроса:

1. **Как происходит instruction request** — запрос слов инструкций из памяти (IFU ↔ IMEM).
2. **Как происходит первичное декодирование команды (RVC или RVI)** — определение
   границ и типа инструкции по «сырым» 32-битным словам.
3. **Как работает очередь команд** (instruction queue) и её байпас в IDU.

---

## 0. Роль IFU в конвейере SCR1

SCR1 — это простой in-order RISC-V процессор (RV32I/E + опционально M, C). Его конвейер
разбит на фазы (EAS §6.1). IFU реализует **первые две фазы**:

| Фаза (EAS §6.1)          | Что делает                                                        | Модуль |
|--------------------------|-------------------------------------------------------------------|--------|
| 6.1.1 Instruction request| Запрашивает слова инструкций из IMEM по адресу `IMEM_ADDR`         | **IFU** |
| 6.1.2 Instruction receive| Складывает слова в очередь / собирает инструкцию из частей         | **IFU** |
| 6.1.3 Instruction decode | Декодирует инструкцию в управляющие сигналы для EXU                | IDU    |

Ключевая проблема, которую решает IFU (EAS §4.2):

> *«Instruction fetch from memory is physically done as 32-bit words aligned to 4-byte
> boundary ignoring any unnecessary portion of the word during instruction decode.»*

То есть память **всегда читается 32-битными словами, выровненными на 4 байта**, но при
включённом расширении «C» (сжатые команды) инструкции бывают **16-битные (RVC)** и
**32-битные (RVI)** и могут лежать по **любой чётной (2-байтовой) границе**. Поэтому
32-битная RVI-инструкция может «разъехаться» на два соседних слова памяти. Задача IFU —
скрыть это от IDU: собрать корректную инструкцию из кусков и отдать её на декодирование.

### Заголовок модуля и функциональность (из исходника)

```systemverilog
// Functionality:
// - Controls instruction fetching process:
//   - Fetches instructions either from IMEM or from Program Buffer, supporting
//     pending IMEM instructions handling
//   - Handles new PC misalignment and constructs the correct instruction (supports
//     RVI and RVC instructions)
//   - Either stores instructions in the instruction queue or bypasses to the
//     IDU if the corresponding option is used
//   - Flushes instruction queue if requested
//
// Structure:
// - Instruction queue
// - IFU FSM
// - IFU <-> IMEM i/f
// - IFU <-> IDU i/f
// - IFU <-> HDU i/f
```

### Конфигурация в этой FPGA-сборке

В `scr1_arch_description.svh` активна «кастомная» секция, и для IFU важны:

| Define               | Значение | Влияние на IFU |
|----------------------|----------|----------------|
| `SCR1_RVC_EXT`       | вкл.     | поддержка сжатых 16-битных команд → нужна логика сборки RVI из кусков |
| `SCR1_NO_DEC_STAGE`  | вкл.     | **байпас** очереди: свежие данные из IMEM могут идти прямо в IDU, минуя очередь |
| `SCR1_NEW_PC_REG`    | вкл.     | new PC защёлкивается в регистр `imem_addr_ff`, а не выставляется на шину комбинационно |
| `SCR1_CLKCTRL_EN`    | вкл.     | наружу выводится флаг `ifu2pipe_imem_txns_pnd_o` (для клок-гейтинга) |
| `SCR1_DBG_EN`        | вкл.     | интерфейс Program Buffer от HDU (отладка) |

> Дальше по тексту, где логика зависит от define, указано, какая ветка активна в этой сборке.

---

## 1. Интерфейсы модуля (порты)

```systemverilog
module scr1_pipe_ifu
(
    // Control signals
    input   logic                                   rst_n,                      // IFU reset
    input   logic                                   clk,                        // IFU clock
    input   logic                                   pipe2ifu_stop_fetch_i,      // Stop instruction fetch

    // IFU <-> IMEM interface
    input   logic                                   imem2ifu_req_ack_i,         // Instruction memory request acknowledgement
    output  logic                                   ifu2imem_req_o,             // Instruction memory request
    output  type_scr1_mem_cmd_e                     ifu2imem_cmd_o,             // Instruction memory command (READ/WRITE)
    output  logic [`SCR1_IMEM_AWIDTH-1:0]           ifu2imem_addr_o,            // Instruction memory address
    input   logic [`SCR1_IMEM_DWIDTH-1:0]           imem2ifu_rdata_i,           // Instruction memory read data
    input   type_scr1_mem_resp_e                    imem2ifu_resp_i,            // Instruction memory response

    // IFU <-> EXU New PC interface
    input   logic                                   exu2ifu_pc_new_req_i,       // New PC request (jumps, branches, traps etc)
    input   logic [`SCR1_XLEN-1:0]                  exu2ifu_pc_new_i,           // New PC
    ...
    // IFU <-> IDU interface
    input   logic                                   idu2ifu_rdy_i,              // IDU ready for new data
    output  logic [`SCR1_IMEM_DWIDTH-1:0]           ifu2idu_instr_o,            // IFU instruction
    output  logic                                   ifu2idu_imem_err_o,         // Instruction access fault exception
    output  logic                                   ifu2idu_err_rvi_hi_o,       // 1 - imem fault when trying to fetch second half of an unaligned RVI instruction
    output  logic                                   ifu2idu_vd_o                // IFU request
);
```

Порты сгруппированы по трём внешним «собеседникам» IFU:

- **IMEM** (память инструкций) — типы `type_scr1_mem_cmd_e` и `type_scr1_mem_resp_e`
  определены в `scr1_memif.svh`:
  - команда: `SCR1_MEM_CMD_RD` / `SCR1_MEM_CMD_WR` (IFU всегда только читает);
  - ответ: `SCR1_MEM_RESP_NOTRDY` (2'b00), `SCR1_MEM_RESP_RDY_OK` (2'b01),
    `SCR1_MEM_RESP_RDY_ER` (2'b10, ошибка доступа).
  - `SCR1_IMEM_AWIDTH = SCR1_IMEM_DWIDTH = SCR1_XLEN = 32`.
- **EXU** — сигнал `exu2ifu_pc_new_req_i` / `exu2ifu_pc_new_i`: «сброс» текущего потока и
  переход на новый PC (jump, branch, trap, mret, debug-редирект и т.п.).
- **IDU** — выдача собранной инструкции `ifu2idu_instr_o` + флаги валидности/ошибки, и
  handshake через `idu2ifu_rdy_i` (IDU готов принять) / `ifu2idu_vd_o` (у IFU есть данные).

Плюс отдельная группа портов **HDU Program Buffer** (`SCR1_DBG_EN`) — для исполнения
инструкций из программного буфера в режиме отладки.

Handshake одинаков и на шине IMEM, и на шине IDU: **валид + готовность (ready/ack)** →
транзакция происходит, когда обе стороны выставили свой сигнал в одном такте.

---

## 2. Общая структура

Модуль состоит из четырёх крупных блоков (в порядке следования в файле):

```
┌───────────────────────────────────────────────────────────────────┐
│                              IFU                                    │
│                                                                     │
│  EXU new_pc ─► [ IFU FSM ] ──► [ IFU ↔ IMEM i/f ] ──► ifu2imem_*    │
│                    │                 │  ▲                           │
│                    │                 ▼  │ imem2ifu_rdata / resp     │
│                    │        [ Первичный декодер RVC/RVI ]           │
│                    │                 │                              │
│                    ▼                 ▼                              │
│              [ Instruction queue (4 полуслова) ]                    │
│                    │                                                │
│                    ▼                                                │
│              [ IFU ↔ IDU i/f + bypass ] ──► ifu2idu_instr / vd      │
└───────────────────────────────────────────────────────────────────┘
```

Разберём каждый блок.

---

## 3. Instruction request — как запрашиваются инструкции (IFU ↔ IMEM)

Эта часть отвечает на первый вопрос. Она объединяет: **FSM**, **регистр адреса**,
**генерацию запроса**, **счётчик незавершённых транзакций** и **счётчик отбрасываемых
ответов**.

### 3.1. Конечный автомат IFU (IFU FSM)

Автомат из двух состояний — включён fetch или нет:

```systemverilog
typedef enum logic {
    SCR1_IFU_FSM_IDLE,
    SCR1_IFU_FSM_FETCH
} type_scr1_ifu_fsm_e;

assign ifu_fetch_req = exu2ifu_pc_new_req_i & ~pipe2ifu_stop_fetch_i;
assign ifu_stop_req  = pipe2ifu_stop_fetch_i
                     | (imem_resp_er_discard_pnd & ~exu2ifu_pc_new_req_i);

always_comb begin
    case (ifu_fsm_curr)
        SCR1_IFU_FSM_IDLE   : begin
            ifu_fsm_next = ifu_fetch_req ? SCR1_IFU_FSM_FETCH
                                         : SCR1_IFU_FSM_IDLE;
        end
        SCR1_IFU_FSM_FETCH  : begin
            ifu_fsm_next = ifu_stop_req  ? SCR1_IFU_FSM_IDLE
                                         : SCR1_IFU_FSM_FETCH;
        end
    endcase
end

assign ifu_fsm_fetch = (ifu_fsm_curr == SCR1_IFU_FSM_FETCH);
```

- **IDLE → FETCH**: происходит только по `exu2ifu_pc_new_req_i` (запрос нового PC) — то
  есть выборка *начинается* с указания EXU, куда идти (в т.ч. reset-вектор — это первый
  new_pc). Условие подавляется, если пришёл `stop_fetch`.
- **FETCH → IDLE**: по `ifu_stop_req`:
  - `pipe2ifu_stop_fetch_i` — конвейер приказал остановить выборку (например, вход в
    debug halt, WFI и т.п.);
  - либо получена **ошибка доступа**, которую надо обработать
    (`imem_resp_er_discard_pnd`), и при этом нет одновременного нового PC.
- В состоянии FETCH автомат непрерывно генерирует запросы к памяти (пока есть место в
  очереди и не переполнен счётчик незавершённых транзакций).

Обратите внимание: сам по себе `new_pc_req` перезапускает выборку в *любом* состоянии,
поэтому «переприцеливание» на новый адрес не требует прохода через IDLE.

### 3.2. Регистр адреса IMEM (`imem_addr_ff`)

Адрес следующего слова для чтения хранится в регистре (только старшие биты `[31:2]`,
поскольку младшие два всегда нули — доступ выровнен на слово):

```systemverilog
assign imem_addr_upd = imem_handshake_done | exu2ifu_pc_new_req_i;

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        imem_addr_ff <= '0;
    end else if (imem_addr_upd) begin
        imem_addr_ff <= imem_addr_next;
    end
end
```

Логика вычисления следующего адреса (**активна ветка `SCR1_NEW_PC_REG`** в этой сборке):

```systemverilog
`else // SCR1_NEW_PC_REG
assign imem_addr_next = exu2ifu_pc_new_req_i ? exu2ifu_pc_new_i[`SCR1_XLEN-1:2]
                      : &imem_addr_ff[5:2]   ? imem_addr_ff
                                             : {imem_addr_ff[`SCR1_XLEN-1:6], imem_addr_ff[5:2] + imem_handshake_done};
`endif // SCR1_NEW_PC_REG
```

- При `new_pc_req` адрес просто **загружается** новым PC (старшие 30 бит).
- Иначе, при успешном handshake (`imem_handshake_done`), адрес **инкрементируется на 1
  слово**. Инкремент сделан «умно»: складываются только биты `[5:2]`, а `[31:6]` берутся
  без изменения. Условие `&imem_addr_ff[5:2]` (все единицы) означает, что адрес на границе
  64-байтового блока — в этом случае адрес не инкрементируется (защита от перехода через
  границу блока без явного запроса; фактически удержание значения, инкремент придёт со
  следующим handshake после того, как переполнение обработается). Такое ограничение
  инкремента внутри 4-битного поля `[5:2]` — микрооптимизация тайминга сумматора адреса.

> В варианте **без** `SCR1_NEW_PC_REG` new_pc подавался бы на шину адреса комбинационно
> (см. `ifu2imem_addr_o` ниже), а к `imem_addr_next` прибавлялся бы `imem_handshake_done`,
> чтобы учесть возможный handshake в том же такте.

### 3.3. Формирование запроса к памяти

```systemverilog
`else // SCR1_NEW_PC_REG
assign ifu2imem_req_o  = ifu_fsm_fetch & ~imem_pnd_txns_q_full & q_has_free_slots;
assign ifu2imem_addr_o = {imem_addr_ff, 2'b00};
`endif // SCR1_NEW_PC_REG

assign ifu2imem_cmd_o  = SCR1_MEM_CMD_RD;
```

В сборке с `SCR1_NEW_PC_REG` запрос выставляется, когда одновременно:

1. `ifu_fsm_fetch` — автомат в состоянии FETCH;
2. `~imem_pnd_txns_q_full` — счётчик незавершённых транзакций **не** переполнен (нельзя
   выпустить больше запросов, чем сможем принять ответов);
3. `q_has_free_slots` — в очереди есть место под ответы, которые ещё «в полёте».

Адрес — всегда `{imem_addr_ff, 2'b00}` (выровнен на слово), команда — всегда чтение.

> Ассершен `SCR1_SVA_IFU_IMEM_ADDR_ALIGNED` проверяет, что при активном запросе младшие
> два бита адреса нулевые.

### 3.4. Логика ответа памяти

```systemverilog
assign imem_resp_er             = (imem2ifu_resp_i == SCR1_MEM_RESP_RDY_ER);
assign imem_resp_ok             = (imem2ifu_resp_i == SCR1_MEM_RESP_RDY_OK);
assign imem_resp_received       = imem_resp_ok | imem_resp_er;
assign imem_resp_vd             = imem_resp_received & ~imem_resp_discard_req;
assign imem_resp_er_discard_pnd = imem_resp_er & ~imem_resp_discard_req;

assign imem_handshake_done = ifu2imem_req_o & imem2ifu_req_ack_i;
```

- `imem_resp_received` — пришёл *любой* завершённый ответ (успех или ошибка).
- `imem_resp_vd` — ответ **валиден и не подлежит отбрасыванию** (см. §3.6). Только такие
  ответы реально пишутся в очередь и влияют на состояние.
- `imem_handshake_done` — состоялась выдача запроса (наш `req` встретил `ack` памяти).

Важно: интерфейс **конвейерный/расщеплённый (split-transaction)** — адрес принимается
(`req`/`ack`) в одном такте, а данные (`rdata`/`resp`) приходят в этом же или в одном из
следующих тактов. Поэтому нужны счётчики ниже.

### 3.5. Счётчик незавершённых транзакций (`imem_pnd_txns_cnt`)

«Незавершённая» транзакция — запрос принят памятью, но ответ ещё не пришёл.

```systemverilog
assign imem_pnd_txns_cnt_upd  = imem_handshake_done ^ imem_resp_received;

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        imem_pnd_txns_cnt <= '0;
    end else if (imem_pnd_txns_cnt_upd) begin
        imem_pnd_txns_cnt <= imem_pnd_txns_cnt_next;
    end
end

assign imem_pnd_txns_cnt_next = imem_pnd_txns_cnt + (imem_handshake_done - imem_resp_received);
assign imem_pnd_txns_q_full   = &imem_pnd_txns_cnt;
```

- Счётчик увеличивается на выданный запрос и уменьшается на пришедший ответ:
  `+handshake − response`. Обновляется только когда эти события **не совпадают** (XOR),
  иначе значение не меняется.
- Ширина счётчика `SCR1_TXN_CNT_W = 3` → до 7 незавершённых транзакций; `q_full` = все
  единицы (максимум). При заполнении новые запросы блокируются (см. §3.3).

Наружу (для клок-гейтинга) выдаётся флаг наличия незавершённых транзакций:

```systemverilog
`ifdef SCR1_CLKCTRL_EN
assign ifu2pipe_imem_txns_pnd_o = |imem_pnd_txns_cnt;
`endif
```

### 3.6. Счётчик отбрасываемых ответов (`imem_resp_discard_cnt`) — зачем он нужен

Поскольку транзакции конвейерные, к моменту, когда надо «развернуть» поток инструкций,
уже может быть выпущено несколько запросов, ответы на которые **ещё не пришли**. Эти
«догоняющие» ответы больше не нужны — их надо проигнорировать. Комментарий из исходника:

```systemverilog
// IMEM instructions should be discarded in the following 2 cases:
// 1. New PC is requested by jump, branch, mret or other instruction
// 2. IMEM response was erroneous and not discarded
//
// In both cases the number of instructions to be discarded equals to the number
// of pending instructions.
```

Причина 1 — сменили PC (переход/исключение): «старые» слова относятся к неверному пути.
Причина 2 — ошибка доступа: за ошибочным ответом дальнейшие ответы недостоверны.

```systemverilog
assign imem_resp_discard_cnt_upd = exu2ifu_pc_new_req_i | imem_resp_er
                                 | (imem_resp_ok & imem_resp_discard_req);

// ветка SCR1_NEW_PC_REG:
assign imem_resp_discard_cnt_next = exu2ifu_pc_new_req_i | imem_resp_er_discard_pnd
                                  ? imem_pnd_txns_cnt_next
                                  : imem_resp_discard_cnt - 1'b1;

assign imem_vd_pnd_txns_cnt  = imem_pnd_txns_cnt - imem_resp_discard_cnt;
assign imem_resp_discard_req = |imem_resp_discard_cnt;
```

- При новом PC или новой ошибке счётчик отбрасываемых грузится числом текущих
  незавершённых транзакций (`imem_pnd_txns_cnt_next`) — «все, что в полёте, — выбросить».
- Каждый пришедший (и отброшенный) `ok`-ответ уменьшает счётчик на 1.
- `imem_resp_discard_req` = «сейчас надо отбрасывать» (счётчик ненулевой). Именно он
  «маскирует» `imem_resp_vd` в §3.4, чтобы отброшенные ответы не попадали в очередь.
- `imem_vd_pnd_txns_cnt` — сколько *полезных* незавершённых транзакций осталось; это число
  используется в оценке свободного места очереди (`q_has_free_slots`, §5.5), чтобы
  зарезервировать слоты под ещё не пришедшие валидные ответы.

Инварианты счётчика проверяются ассершенами `SCR1_SVA_IFU_DRC_UNDERFLOW` (нет
переполнения вниз) и `SCR1_SVA_IFU_DRC_RANGE` (`0 ≤ discard_cnt ≤ pnd_txns_cnt`).

**Итог по instruction request:** FSM в состоянии FETCH непрерывно шлёт выровненные на слово
запросы чтения, пока в очереди есть место и не переполнен счётчик транзакций; адрес
инкрементируется по слову на каждый принятый запрос; смена PC/ошибка перезагружают адрес и
взводят механизм отбрасывания «догоняющих» ответов.

---

## 4. Первичное декодирование команды: RVC или RVI

Это ответ на второй вопрос. Задача блока — по «сырому» 32-битному слову из памяти (и с
учётом контекста: выровнен ли новый PC, не была ли предыдущая инструкция «разрезана»)
определить, **что именно** лежит в слове: два RVC, один RVI, половинка RVI и т.д. Результат
кодируется перечислением `type_scr1_ifu_instr_e` и используется дальше для управления
записью в очередь.

### 4.1. Признак «это RVI или RVC» по двум младшим битам

По кодировке RISC-V: если **два младших бита = `11`**, это 32-битная (RVI) инструкция;
иначе — 16-битная сжатая (RVC). IFU проверяет это отдельно для нижней и верхней половин
слова:

```systemverilog
assign instr_hi_is_rvi = &imem2ifu_rdata_i[17:16];  // биты [1:0] верхнего полуслова == 11 ?
assign instr_lo_is_rvi = &imem2ifu_rdata_i[1:0];     // биты [1:0] нижнего полуслова == 11 ?
```

- `imem2ifu_rdata_i[1:0]` — младшие 2 бита инструкции, начинающейся на нижней половине
  слова (адрес кратен 4).
- `imem2ifu_rdata_i[17:16]` — младшие 2 бита инструкции, начинающейся на верхней половине
  слова (адрес `+2`).

`&` (редукция И) даёт 1, только если оба бита равны 1 → инструкция RVI.

### 4.2. Флаг невыровненного нового PC (`new_pc_unaligned_ff`)

Если переход выполнен на адрес, кратный 2, но **не** кратный 4 (`PC[1] == 1`), то первое
прочитанное слово содержит *полезную* инструкцию только в **верхней** половине; нижняя
половина относится к предыдущему (не исполняемому) адресу и должна быть отброшена.

```systemverilog
assign new_pc_unaligned_upd = exu2ifu_pc_new_req_i | imem_resp_vd;

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        new_pc_unaligned_ff <= 1'b0;
    end else if (new_pc_unaligned_upd) begin
        new_pc_unaligned_ff <= new_pc_unaligned_next;
    end
end

assign new_pc_unaligned_next = exu2ifu_pc_new_req_i ? exu2ifu_pc_new_i[1]   // бит 1 нового PC
                             : ~imem_resp_vd        ? new_pc_unaligned_ff    // держим
                                                    : 1'b0;                  // сбрасываем после 1-го валидного ответа
```

- При новом PC флаг захватывает `exu2ifu_pc_new_i[1]` — «PC невыровнен на слово».
- Флаг «живёт» до первого валидного ответа памяти, после чего сбрасывается в 0 (дальше PC
  снова выровнен, т.к. читаем последовательно по словам).

### 4.3. Флаг «предыдущее слово содержало нижнюю половину RVI» (`instr_hi_rvi_lo_ff`)

Самый тонкий случай: 32-битная RVI-инструкция лежит **невыровненно** — её младшие 16 бит в
верхней половине слова N, а старшие 16 бит — в нижней половине слова N+1. Обработав слово N
и увидев в его верхней половине «начало RVI», IFU должен запомнить это, чтобы правильно
интерпретировать слово N+1:

```systemverilog
always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        instr_hi_rvi_lo_ff <= 1'b0;
    end else begin
        if (exu2ifu_pc_new_req_i) begin
            instr_hi_rvi_lo_ff <= 1'b0;              // сброс при смене потока
        end else if (imem_resp_vd) begin
            instr_hi_rvi_lo_ff <= instr_hi_rvi_lo_next;
        end
    end
end

assign instr_hi_rvi_lo_next = (instr_type == SCR1_IFU_INSTR_RVI_LO_NV)
                            | (instr_type == SCR1_IFU_INSTR_RVI_LO_RVI_HI)
                            | (instr_type == SCR1_IFU_INSTR_RVI_LO_RVC);
```

То есть если *текущий* тип слова заканчивается тем, что в его верхней половине **начало**
RVI (`..._RVI_LO_...` или `RVI_LO_NV`), то на следующий валидный ответ мы будем ждать
верхнюю половину этой RVI в нижней части нового слова.

### 4.4. Перечисление типов слова и главный декодер

```systemverilog
typedef enum logic [2:0] {
    // SCR1_IFU_INSTR_<UPPER_16_BITS>_<LOWER_16_BITS>
    SCR1_IFU_INSTR_NONE,                // No valid instruction
    SCR1_IFU_INSTR_RVI_HI_RVI_LO,       // Full RV32I instruction (выровненная 32-битная)
    SCR1_IFU_INSTR_RVC_RVC,             // два RVC в одном слове
    SCR1_IFU_INSTR_RVI_LO_RVC,          // низ: RVC; верх: начало RVI
    SCR1_IFU_INSTR_RVC_RVI_HI,          // низ: конец RVI (из прошлого слова); верх: RVC
    SCR1_IFU_INSTR_RVI_LO_RVI_HI,       // низ: конец прошлой RVI; верх: начало новой RVI
    SCR1_IFU_INSTR_RVC_NV,              // после невыровненного new_pc: в верхе RVC
    SCR1_IFU_INSTR_RVI_LO_NV            // после невыровненного new_pc: в верхе начало RVI
} type_scr1_ifu_instr_e;
```

> Имя читается как `<что в старших 16 битах>_<что в младших 16 битах>`. Суффикс `NV`
> (new value) — первое слово после невыровненного перехода, где младшая половина не
> используется.

Сам декодер (комбинационный):

```systemverilog
always_comb begin
    instr_type = SCR1_IFU_INSTR_NONE;

    if (imem_resp_ok & ~imem_resp_discard_req) begin
        if (new_pc_unaligned_ff) begin
            // Первое слово после невыровненного перехода: значима только верхняя половина
            instr_type = instr_hi_is_rvi ? SCR1_IFU_INSTR_RVI_LO_NV
                                         : SCR1_IFU_INSTR_RVC_NV;
        end else begin // ~new_pc_unaligned_ff
            if (instr_hi_rvi_lo_ff) begin
                // Нижняя половина — это верхняя половина RVI, начатой в прошлом слове
                instr_type = instr_hi_is_rvi ? SCR1_IFU_INSTR_RVI_LO_RVI_HI
                                             : SCR1_IFU_INSTR_RVC_RVI_HI;
            end else begin // обычный случай: нижняя половина — начало новой инструкции
                case ({instr_hi_is_rvi, instr_lo_is_rvi})
                    2'b00   : instr_type = SCR1_IFU_INSTR_RVC_RVC;      // низ RVC, верх RVC
                    2'b10   : instr_type = SCR1_IFU_INSTR_RVI_LO_RVC;   // низ RVC, верх — начало RVI
                    default : instr_type = SCR1_IFU_INSTR_RVI_HI_RVI_LO;// низ — начало RVI (32-битная выровненная)
                endcase
            end
        end
    end
end
```

Логику удобно читать как дерево решений на три уровня контекста:

1. **`new_pc_unaligned_ff`?** — только что перешли на нечётное полуслово → используем
   только верхнюю половину (`_NV`).
2. **`instr_hi_rvi_lo_ff`?** — прошлое слово «начало» RVI в своей верхней половине →
   нижняя половина текущего слова достраивает эту RVI (`_RVI_HI`).
3. **иначе** — нижняя половина начинает новую инструкцию; по `{hi,lo}_is_rvi` различаем
   RVC+RVC / RVC+RVI-начало / выровненную RVI.

Заметьте: `instr_type` формируется только при **валидном** `ok`-ответе, который **не**
отбрасывается; в остальных случаях он `NONE`.

### 4.5. Как тип превращается в размер записи в очередь

Тип слова напрямую задаёт, **сколько полуслов** и **какую половину** писать в очередь.
Ниже — активная ветка `SCR1_NO_DEC_STAGE` (с байпасом):

```systemverilog
type_scr1_ifu_queue_wr_e            q_wr_size;   // NONE / FULL (32 бита) / HI (верхние 16)

always_comb begin
    q_wr_size = SCR1_IFU_QUEUE_WR_NONE;
    if (~imem_resp_discard_req) begin
        if (imem_resp_ok) begin
`ifdef SCR1_NO_DEC_STAGE
            case (instr_type)
                SCR1_IFU_INSTR_NONE         : q_wr_size = SCR1_IFU_QUEUE_WR_NONE;
                SCR1_IFU_INSTR_RVI_LO_NV    : q_wr_size = SCR1_IFU_QUEUE_WR_HI;
                SCR1_IFU_INSTR_RVC_NV       : q_wr_size = (instr_bypass_vd & idu2ifu_rdy_i)
                                                        ? SCR1_IFU_QUEUE_WR_NONE   // ушло байпасом — в очередь не пишем
                                                        : SCR1_IFU_QUEUE_WR_HI;
                SCR1_IFU_INSTR_RVI_HI_RVI_LO: q_wr_size = (instr_bypass_vd & idu2ifu_rdy_i)
                                                        ? SCR1_IFU_QUEUE_WR_NONE
                                                        : SCR1_IFU_QUEUE_WR_FULL;
                SCR1_IFU_INSTR_RVC_RVC,
                SCR1_IFU_INSTR_RVI_LO_RVC,
                SCR1_IFU_INSTR_RVC_RVI_HI,
                SCR1_IFU_INSTR_RVI_LO_RVI_HI: q_wr_size = (instr_bypass_vd & idu2ifu_rdy_i)
                                                        ? SCR1_IFU_QUEUE_WR_HI     // младшее полуслово ушло байпасом, верхнее — в очередь
                                                        : SCR1_IFU_QUEUE_WR_FULL;
            endcase
`else // без байпаса — проще:
            case (instr_type)
                SCR1_IFU_INSTR_NONE         : q_wr_size = SCR1_IFU_QUEUE_WR_NONE;
                SCR1_IFU_INSTR_RVC_NV,
                SCR1_IFU_INSTR_RVI_LO_NV    : q_wr_size = SCR1_IFU_QUEUE_WR_HI;
                default                     : q_wr_size = SCR1_IFU_QUEUE_WR_FULL;
            endcase
`endif
        end else if (imem_resp_er) begin
            q_wr_size = SCR1_IFU_QUEUE_WR_FULL;   // ошибку тоже «пишем» целым словом (см. §6)
        end
    end
end
```

Ключевые правила:

- `*_NV` (первое слово после невыровненного перехода) → пишем только **верхнее** полуслово
  (`WR_HI`), потому что нижнее к делу не относится.
- Обычные полные слова → `WR_FULL` (оба полуслова).
- Ошибочный ответ (`imem_resp_er`) → `WR_FULL`, чтобы флаг ошибки покрыл оба полуслова
  очереди.
- При включённом байпасе (`SCR1_NO_DEC_STAGE`): если младшую инструкцию слова удалось
  **прямо сейчас** отдать в IDU (`instr_bypass_vd & idu2ifu_rdy_i`), то её в очередь не
  пишем — либо не пишем ничего (`NONE`), либо пишем только оставшееся верхнее полуслово
  (`WR_HI`).

---

## 5. Очередь команд (instruction queue)

Это ответ на третий вопрос. Очередь — небольшой циклический буфер, организованный по
**полусловам (16 бит)**, а не по инструкциям. Это ключевая идея: раз инструкции бывают 16-
и 32-битные и лежат по 2-байтовым границам, естественная «атомарная ячейка» очереди —
полуслово.

### 5.1. Размеры и указатели

```systemverilog
localparam SCR1_IFU_Q_SIZE_WORD     = 2;                      // 2 слова
localparam SCR1_IFU_Q_SIZE_HALF     = SCR1_IFU_Q_SIZE_WORD * 2; // = 4 полуслова

localparam SCR1_IFU_QUEUE_ADR_W     = $clog2(SCR1_IFU_Q_SIZE_HALF);   // = 2 бита (адрес полуслова 0..3)
localparam SCR1_IFU_QUEUE_PTR_W     = SCR1_IFU_QUEUE_ADR_W + 1;       // = 3 бита (указатель с доп. битом)
```

- Ёмкость очереди — **4 полуслова = 2 слова = до 4 RVC или до 2 RVI** инструкций.
- Указатели чтения (`q_rptr`) и записи (`q_wptr`) **на 1 бит шире** адреса. Дополнительный
  старший бит — классический приём кольцевого буфера: он позволяет отличить «пусто» от
  «полно» и корректно считать заполнение через вычитание указателей (по модулю 2·размер).
  Собственно адрес полуслова в массиве — младшие `SCR1_IFU_QUEUE_ADR_W` бит указателя
  (приведение `SCR1_IFU_QUEUE_ADR_W'(...)`).

Данные и флаги ошибок хранятся в двух массивах по 4 полуслова:

```systemverilog
logic [`SCR1_IMEM_DWIDTH/2-1:0]     q_data  [SCR1_IFU_Q_SIZE_HALF];   // 4 x 16 бит
logic                               q_err   [SCR1_IFU_Q_SIZE_HALF];   // 4 x флаг ошибки
```

### 5.2. Указатель записи

```systemverilog
assign q_flush_req = exu2ifu_pc_new_req_i | pipe2ifu_stop_fetch_i;

assign q_wptr_upd  = q_flush_req | ~q_wr_none;

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        q_wptr <= '0;
    end else if (q_wptr_upd) begin
        q_wptr <= q_wptr_next;
    end
end

assign q_wptr_next = q_flush_req ? '0
                   : ~q_wr_none  ? q_wptr + (q_wr_full ? SCR1_IFU_QUEUE_PTR_W'('b010)   // +2 полуслова
                                                       : SCR1_IFU_QUEUE_PTR_W'('b001))  // +1 полуслово
                                 : q_wptr;
```

- **Flush** (`q_flush_req` = новый PC или stop_fetch) → указатель сбрасывается в 0
  (очередь мгновенно «опустошается»).
- Иначе на запись: `WR_FULL` двигает указатель на **2** полуслова, `WR_HI` — на **1**.

### 5.3. Указатель чтения

```systemverilog
assign q_rptr_upd  = q_flush_req | ~q_rd_none;

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        q_rptr <= '0;
    end else if (q_rptr_upd) begin
        q_rptr <= q_rptr_next;
    end
end

assign q_rptr_next = q_flush_req ? '0
                   : ~q_rd_none  ? q_rptr + (q_rd_hword ? SCR1_IFU_QUEUE_PTR_W'('b001)   // +1 (прочитали RVC)
                                                        : SCR1_IFU_QUEUE_PTR_W'('b010))  // +2 (прочитали RVI)
                                 : q_rptr;
```

Размер чтения определяется тем, что «на голове» очереди:

```systemverilog
assign q_rd_vd    = ~q_is_empty & ifu2idu_vd_o & idu2ifu_rdy_i;   // есть что читать и IDU забрал
assign q_rd_hword = q_head_is_rvc | q_err_head
`ifdef SCR1_NO_DEC_STAGE
                  | (q_head_is_rvi & instr_bypass_vd)
`endif
                  ;
assign q_rd_size  = ~q_rd_vd   ? SCR1_IFU_QUEUE_RD_NONE
                  : q_rd_hword ? SCR1_IFU_QUEUE_RD_HWORD
                               : SCR1_IFU_QUEUE_RD_WORD;
assign q_rd_none  = (q_rd_size == SCR1_IFU_QUEUE_RD_NONE);
```

- Чтение происходит **только** при фактической передаче в IDU (`ifu2idu_vd_o &
  idu2ifu_rdy_i`) — очередь продвигается синхронно с приёмом инструкции декодером.
- Если голова — RVC (или помечена ошибкой) → читаем **1 полуслово** (`RD_HWORD`), иначе
  (RVI) → **слово** (`RD_WORD`, 2 полуслова).

### 5.4. Запись данных и флагов ошибок

```systemverilog
assign imem_rdata_hi = imem2ifu_rdata_i[31:16];
assign imem_rdata_lo = imem2ifu_rdata_i[15:0];

assign q_wr_en = imem_resp_vd & ~q_flush_req;   // пишем только валидный, не-сбрасываемый ответ

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        q_data  <= '{SCR1_IFU_Q_SIZE_HALF{'0}};
        q_err   <= '{SCR1_IFU_Q_SIZE_HALF{1'b0}};
    end else if (q_wr_en) begin
        case (q_wr_size)
            SCR1_IFU_QUEUE_WR_HI    : begin
                q_data[SCR1_IFU_QUEUE_ADR_W'(q_wptr)]        <= imem_rdata_hi;
                q_err [SCR1_IFU_QUEUE_ADR_W'(q_wptr)]        <= imem_resp_er;
            end
            SCR1_IFU_QUEUE_WR_FULL  : begin
                q_data[SCR1_IFU_QUEUE_ADR_W'(q_wptr)]        <= imem_rdata_lo;
                q_err [SCR1_IFU_QUEUE_ADR_W'(q_wptr)]        <= imem_resp_er;
                q_data[SCR1_IFU_QUEUE_ADR_W'(q_wptr + 1'b1)] <= imem_rdata_hi;
                q_err [SCR1_IFU_QUEUE_ADR_W'(q_wptr + 1'b1)] <= imem_resp_er;
            end
        endcase
    end
end
```

- `WR_FULL`: нижнее полуслово слова → в ячейку `q_wptr`, верхнее → в `q_wptr+1`. Так
  сохраняется порядок «младший адрес — раньше».
- `WR_HI` (для `*_NV`): только верхнее полуслово → в `q_wptr`.
- Флаг ошибки `q_err` пишется одинаковым значением `imem_resp_er` во все затрагиваемые
  полуслова — при ошибочном ответе оба полуслова помечаются как «ошибочные».

Чтение «головы» очереди — комбинационное, читаются две ячейки (голова и следующая), чтобы
собрать RVI-инструкцию:

```systemverilog
assign q_data_head = q_data [SCR1_IFU_QUEUE_ADR_W'(q_rptr)];
assign q_data_next = q_data [SCR1_IFU_QUEUE_ADR_W'(q_rptr + 1'b1)];
assign q_err_head  = q_err  [SCR1_IFU_QUEUE_ADR_W'(q_rptr)];
assign q_err_next  = q_err  [SCR1_IFU_QUEUE_ADR_W'(q_rptr + 1'b1)];
```

### 5.5. Статус очереди

```systemverilog
assign q_ocpd_h         = SCR1_IFU_Q_FREE_H_W'(q_wptr - q_rptr);                       // занято полуслов
assign q_free_h_next    = SCR1_IFU_Q_FREE_H_W'(SCR1_IFU_Q_SIZE_HALF - (q_wptr - q_rptr_next)); // свободно полуслов (с учётом чтения в этом такте)
assign q_free_w_next    = SCR1_IFU_Q_FREE_W_W'(q_free_h_next >> 1'b1);                 // свободно слов

assign q_is_empty       = (q_rptr == q_wptr);
assign q_has_free_slots = (SCR1_TXN_CNT_W'(q_free_w_next) > imem_vd_pnd_txns_cnt);
assign q_has_1_ocpd_hw  = (q_ocpd_h == SCR1_IFU_Q_FREE_H_W'(1));

assign q_head_is_rvi    = &(q_data_head[1:0]);   // голова — RVI, если её [1:0]==11
assign q_head_is_rvc    = ~q_head_is_rvi;
```

- `q_is_empty` — указатели совпали. (После flush оба = 0 → очередь пуста; ассершен
  `SCR1_SVA_IFU_NEW_PC_REQ_BEH` требует, чтобы после `new_pc_req` очередь была пуста.)
- `q_has_free_slots` — **ключевое** условие для генерации новых запросов (§3.3): свободных
  *слов* должно быть **больше**, чем валидных незавершённых транзакций
  (`imem_vd_pnd_txns_cnt`). Это резервирует место под ответы, которые ещё «в полёте», и
  гарантирует, что очередь не переполнится приходящими данными. Ассершен
  `SCR1_SVA_IFU_QUEUE_OVF` формально проверяет отсутствие переполнения.
- `q_has_1_ocpd_hw` — в очереди занято ровно 1 полуслово (важный краевой случай: одинокое
  полуслово может быть либо целой RVC, либо «половинкой» RVI, для которой ещё не пришла
  вторая половина).
- `q_head_is_rvc/rvi` — тип инструкции на голове определяется так же, как в §4.1, по двум
  младшим битам полуслова-головы.

---

## 6. Интерфейс IFU ↔ IDU и байпас (`SCR1_NO_DEC_STAGE`)

В этой сборке `SCR1_NO_DEC_STAGE` **включён**, поэтому активна ветка с байпасом: свежие
данные из IMEM могут отдаваться в IDU напрямую, не проходя через очередь (когда это
возможно). Это экономит такт на «горячем» пути.

### 6.1. Декодер типа байпаса

```systemverilog
assign instr_bypass_vd  = (instr_bypass_type != SCR1_BYPASS_NONE);

always_comb begin
    instr_bypass_type = SCR1_BYPASS_NONE;

    if (imem_resp_vd) begin
        if (q_is_empty) begin
            // Очередь пуста — можно попробовать отдать инструкцию прямо из rdata
            case (instr_type)
                SCR1_IFU_INSTR_RVC_NV,
                SCR1_IFU_INSTR_RVC_RVC,
                SCR1_IFU_INSTR_RVI_LO_RVC   : instr_bypass_type = SCR1_BYPASS_RVC;        // младшая — целая RVC
                SCR1_IFU_INSTR_RVI_HI_RVI_LO: instr_bypass_type = SCR1_BYPASS_RVI_RDATA;  // целая выровненная RVI прямо из rdata
                default : begin end
            endcase
        end else if (q_has_1_ocpd_hw & q_head_is_rvi) begin
            // В очереди 1 полуслово — младшая половина RVI; верхняя пришла сейчас в rdata
            if (instr_hi_rvi_lo_ff) begin
                instr_bypass_type = SCR1_BYPASS_RVI_RDATA_QUEUE;   // склеиваем: [rdata_lo, q_head]
            end
        end
    end
end
```

Три вида байпаса:

| Тип                          | Когда                                        | Что отдаём в IDU |
|------------------------------|----------------------------------------------|------------------|
| `SCR1_BYPASS_RVC`            | очередь пуста, младшая инструкция слова — RVC | одно полуслово из rdata |
| `SCR1_BYPASS_RVI_RDATA`     | очередь пуста, выровненная RVI                | всё слово rdata целиком |
| `SCR1_BYPASS_RVI_RDATA_QUEUE`| в очереди 1 полуслово (низ RVI), верх — в rdata | склейка `{rdata_lo, q_head}` |

### 6.2. Флаги валидности и ошибки для IDU

```systemverilog
always_comb begin
    ifu2idu_vd_o         = 1'b0;
    ifu2idu_imem_err_o   = 1'b0;
    ifu2idu_err_rvi_hi_o = 1'b0;

    if (ifu_fsm_fetch | ~q_is_empty) begin
        if (instr_bypass_vd) begin
            ifu2idu_vd_o          = 1'b1;
            ifu2idu_imem_err_o    = (instr_bypass_type == SCR1_BYPASS_RVI_RDATA_QUEUE)
                                  ? (imem_resp_er | q_err_head)
                                  : imem_resp_er;
            ifu2idu_err_rvi_hi_o  = (instr_bypass_type == SCR1_BYPASS_RVI_RDATA_QUEUE) & imem_resp_er;
        end else if (~q_is_empty) begin
            if (q_has_1_ocpd_hw) begin
                // Единственное полуслово: валидно только если это целая RVC или ошибка
                ifu2idu_vd_o         = q_head_is_rvc | q_err_head;
                ifu2idu_imem_err_o   = q_err_head;
                ifu2idu_err_rvi_hi_o = ~q_err_head & q_head_is_rvi & q_err_next;
            end else begin
                ifu2idu_vd_o         = 1'b1;
                ifu2idu_imem_err_o   = q_err_head ? 1'b1 : (q_head_is_rvi & q_err_next);
            end
        end
    end
`ifdef SCR1_DBG_EN
    if (hdu2ifu_pbuf_fetch_i) begin        // режим Program Buffer перекрывает обычные источники
        ifu2idu_vd_o          = hdu2ifu_pbuf_vd_i;
        ifu2idu_imem_err_o    = hdu2ifu_pbuf_err_i;
    end
`endif
end
```

Особо стоит выделить `ifu2idu_err_rvi_hi_o` — «ошибка доступа при попытке дочитать **вторую
половину** невыровненной RVI-инструкции». Он взводится, когда сама голова корректна
(`~q_err_head`), голова — RVI (`q_head_is_rvi`), а вот верхнее полуслово ошибочно
(`q_err_next`). Этот флаг важен для точного репортирования исключения «instruction access
fault» именно на нужном PC (см. IDU — там формируется код исключения). Ассершен
`SCR1_SVA_IFU_IMEM_FAULT_RVI_HI` гарантирует, что `err_rvi_hi` не бывает без `imem_err`.

### 6.3. Мультиплексор выходной инструкции

```systemverilog
always_comb begin
    case (instr_bypass_type)
        SCR1_BYPASS_RVC            : begin
            ifu2idu_instr_o = `SCR1_IMEM_DWIDTH'(new_pc_unaligned_ff ? imem_rdata_hi
                                                                     : imem_rdata_lo);
        end
        SCR1_BYPASS_RVI_RDATA      : begin
            ifu2idu_instr_o = imem2ifu_rdata_i;
        end
        SCR1_BYPASS_RVI_RDATA_QUEUE: begin
            ifu2idu_instr_o = {imem_rdata_lo, q_data_head};   // верх из rdata, низ из очереди
        end
        default                    : begin                    // из очереди
            ifu2idu_instr_o = `SCR1_IMEM_DWIDTH'(q_head_is_rvc ? q_data_head
                                                               : {q_data_next, q_data_head});
        end
    endcase
`ifdef SCR1_DBG_EN
    if (hdu2ifu_pbuf_fetch_i) begin
        ifu2idu_instr_o = `SCR1_IMEM_DWIDTH'({'0, hdu2ifu_pbuf_instr_i});
    end
`endif
end
```

- Байпас RVC: 16 бит из нужной половины rdata (если PC невыровнен — из верхней), дополнены
  до 32 бит (IDU по битам `[1:0]==11?` сам поймёт, что это RVC).
- Байпас RVI из rdata: всё слово как есть.
- Байпас «rdata+queue»: старшая половина RVI из свежего rdata, младшая — из головы очереди.
- Иначе — из очереди: либо одно полуслово (RVC), либо склейка головы и следующей ячейки
  (RVI).

> **Как IDU понимает RVC vs RVI?** IFU уже отдаёт «выровненную» 32-битную величину; IDU
> сам смотрит на младшие два бита (`scr1_pipe_idu.sv`):
> ```systemverilog
> assign instr_type = type_scr1_instr_type_e'(instr[1:0]);   // RVI / RVC
> assign funct3     = (instr_type == SCR1_INSTR_RVI) ? instr[14:12] : instr[15:13];
> ```
> Для RVC значимы только младшие 16 бит; старшие 16 при этом игнорируются.

### 6.4. Вариант без байпаса (`SCR1_NO_DEC_STAGE` выключен)

Для полноты — если бы регистр между IFU и IDU присутствовал, логика была бы проще: нет
байпаса, инструкция всегда берётся из очереди, а `ifu2idu_vd_o`/ошибки формируются только
по состоянию очереди:

```systemverilog
always_comb begin
    ifu2idu_vd_o = 1'b0; ifu2idu_imem_err_o = 1'b0; ifu2idu_err_rvi_hi_o = 1'b0;
    if (~q_is_empty) begin
        if (q_has_1_ocpd_hw) begin
            ifu2idu_vd_o       = q_head_is_rvc | q_err_head;
            ifu2idu_imem_err_o = q_err_head;
        end else begin
            ifu2idu_vd_o         = 1'b1;
            ifu2idu_imem_err_o   = q_err_head ? 1'b1 : (q_head_is_rvi & q_err_next);
            ifu2idu_err_rvi_hi_o = ~q_err_head & q_head_is_rvi & q_err_next;
        end
    end
    ...
end
// выходная инструкция — всегда из очереди:
assign ifu2idu_instr_o = q_head_is_rvc ? q_data_head : {q_data_next, q_data_head};
```

---

## 7. Обработка ошибок доступа к памяти

RISC-V различает исключение «Instruction access fault» (код 1, EAS Table 25). В IFU оно
проходит так:

1. Память отвечает `SCR1_MEM_RESP_RDY_ER` → `imem_resp_er = 1`.
2. Ошибочный ответ, если он не отбрасывается, записывается в очередь как `WR_FULL` с
   установленными флагами `q_err` в обоих полусловах (§5.4).
3. Одновременно `imem_resp_er_discard_pnd` останавливает FSM (FETCH→IDLE) и взводит
   отбрасывание всех «догоняющих» ответов (§3.6) — за ошибкой доступа дальнейшие данные
   недостоверны.
4. При выдаче в IDU флаг `ifu2idu_imem_err_o` (и, для второй половины невыровненной RVI, —
   `ifu2idu_err_rvi_hi_o`) сообщает декодеру/EXU, что нужно возбудить исключение вместо
   исполнения.

Ассершен `SCR1_SVA_IFU_IMEM_ERR_BEH` формально фиксирует поведение: после невыровненной
необрабатываемой ошибки в следующем такте FSM обязан быть в IDLE, а `discard_cnt` должен
сравняться с `pnd_txns_cnt`.

---

## 8. Program Buffer (режим отладки, `SCR1_DBG_EN`)

Когда HDU (Hart Debug Unit) просит исполнить инструкции из программного буфера
(`hdu2ifu_pbuf_fetch_i`), IFU **перекрывает** обычный источник инструкций: `vd`, `err` и
сама инструкция берутся из полей `hdu2ifu_pbuf_*`, а готовность IFU транслируется как
`ifu2hdu_pbuf_rdy_o = idu2ifu_rdy_i`. Это видно во всех трёх `always_comb`-блоках выдачи
выше (ветки под `SCR1_DBG_EN`). Подробности механизма — в EAS §8.4.7 «Program Buffer».

```systemverilog
`ifdef SCR1_DBG_EN
assign ifu2hdu_pbuf_rdy_o = idu2ifu_rdy_i;
`endif
```

---

## 9. Сквозной пример: невыровненная RVI-инструкция

Пусть в памяти по адресам (полусловами):

```
addr:   0x100      0x102      0x104      0x106
data:   RVC_a      RVI_b_lo   RVI_b_hi   RVC_c
```

и мы переходим (`new_pc`) на `0x100` (выровнен на слово):

1. **Такт запроса**: FSM входит в FETCH, `imem_addr_ff = 0x100>>2`, выставляется
   `ifu2imem_req_o`, адрес `0x100`. Через ack — handshake, `imem_addr_ff` → `0x104>>2`.
2. **Ответ на слово 0x100** (`{RVI_b_lo, RVC_a}`): `instr_lo_is_rvi=0` (RVC_a),
   `instr_hi_is_rvi=1` (начало RVI_b) → `instr_type = SCR1_IFU_INSTR_RVI_LO_RVC`.
   - RVC_a можно отдать байпасом (`SCR1_BYPASS_RVC`) прямо в IDU (если очередь пуста и IDU
     готов); в очередь тогда пишется только верхнее полуслово `RVI_b_lo` (`WR_HI`).
   - `instr_hi_rvi_lo_next = 1` → на следующий валидный ответ ждём верхнюю половину RVI_b.
3. **Ответ на слово 0x104** (`{RVC_c, RVI_b_hi}`): `instr_hi_rvi_lo_ff=1`,
   `instr_hi_is_rvi=0` (RVC_c) → `instr_type = SCR1_IFU_INSTR_RVC_RVI_HI`.
   - Теперь в очереди голова = `RVI_b_lo`, а `RVI_b_hi` пришёл в rdata_lo →
     `SCR1_BYPASS_RVI_RDATA_QUEUE`: в IDU уходит `{RVI_b_hi, RVI_b_lo}` — собранная RVI_b.
   - `RVC_c` (rdata_hi) пишется в очередь.
4. Дальше `RVC_c` выдаётся из очереди как одиночное полуслово (`RD_HWORD`).

Так IFU собрал невыровненную 32-битную RVI из двух разных слов памяти, ни разу не заставив
IDU думать о выравнивании.

---

## 10. Сводная таблица ключевых сигналов

| Сигнал                     | Назначение |
|----------------------------|------------|
| `ifu_fsm_curr`             | Состояние FSM: IDLE / FETCH |
| `imem_addr_ff`             | Адрес следующего слова для чтения (биты [31:2]) |
| `ifu2imem_req_o`           | Запрос чтения к IMEM (FETCH & есть место & не переполнены транзакции) |
| `imem_pnd_txns_cnt`        | Число незавершённых (выданных, но без ответа) транзакций |
| `imem_resp_discard_cnt`    | Сколько ещё «догоняющих» ответов надо отбросить |
| `imem_resp_vd`             | Пришёл валидный, не-отбрасываемый ответ памяти |
| `new_pc_unaligned_ff`      | Новый PC был невыровнен на слово (PC[1]=1) |
| `instr_hi_rvi_lo_ff`       | Прошлое слово содержало начало RVI в верхней половине |
| `instr_type`               | Тип содержимого слова (RVC/RVI-комбинация) |
| `q_wr_size` / `q_rd_size`  | Размер записи (NONE/HI/FULL) и чтения (NONE/HWORD/WORD) очереди |
| `q_wptr` / `q_rptr`        | Указатели записи/чтения очереди (в полусловах, +1 бит) |
| `q_data[]` / `q_err[]`     | Данные (4×16 бит) и флаги ошибок очереди |
| `q_is_empty` / `q_has_free_slots` / `q_has_1_ocpd_hw` | Статус очереди |
| `instr_bypass_type`        | Вид байпаса очереди в IDU (RVC / RVI_RDATA / RVI_RDATA_QUEUE) |
| `ifu2idu_instr_o` / `ifu2idu_vd_o` | Собранная инструкция и её валидность для IDU |
| `ifu2idu_imem_err_o` / `ifu2idu_err_rvi_hi_o` | Флаги ошибки доступа (весь фетч / вторая половина RVI) |

---

## 11. Ассершены (SVA, только при `SCR1_TRGT_SIMULATION`)

В конце модуля собраны проверки, полезные для понимания инвариантов:

- `SCR1_SVA_IFU_XCHECK`, `..._XCHECK_REQ` — нет `x`/`z` на управляющих входах и на
  адресе/команде при активном запросе.
- `SCR1_SVA_IFU_DRC_UNDERFLOW`, `..._DRC_RANGE` — счётчик отбрасываний не уходит вниз и
  всегда `0 ≤ discard ≤ pnd`.
- `SCR1_SVA_IFU_QUEUE_OVF` — очередь не переполняется.
- `SCR1_SVA_IFU_IMEM_ERR_BEH` — корректная реакция на ошибку памяти (FSM→IDLE, discard=pnd).
- `SCR1_SVA_IFU_NEW_PC_REQ_BEH` — после нового PC очередь пуста (flush отработал).
- `SCR1_SVA_IFU_IMEM_ADDR_ALIGNED` — запрос к IMEM всегда выровнен на слово.
- `SCR1_SVA_IFU_STOP_FETCH` — после `stop_fetch` FSM в IDLE.
- `SCR1_SVA_IFU_IMEM_FAULT_RVI_HI` — `err_rvi_hi` не бывает без `imem_err`.

---

## Итог

IFU в SCR1 решает три взаимосвязанные задачи:

1. **Instruction request** — FSM в состоянии FETCH непрерывно шлёт выровненные на слово
   запросы чтения в IMEM, пока в очереди есть место; расщеплённый (split) характер шины
   отслеживается счётчиком незавершённых транзакций, а смена PC/ошибка — счётчиком
   отбрасываемых «догоняющих» ответов.
2. **Первичное декодирование RVC/RVI** — по двум младшим битам каждой половины слова и
   двум битам контекста (`new_pc_unaligned_ff`, `instr_hi_rvi_lo_ff`) слово
   классифицируется в `instr_type`, что определяет, как писать его в очередь и как собирать
   инструкцию.
3. **Очередь команд** — кольцевой буфер на 4 полуслова с указателями на полусловах;
   поддерживает запись слова/полуслова, чтение слова/полуслова, флаги ошибок и мгновенный
   flush. При включённом `SCR1_NO_DEC_STAGE` очередь дополняется байпасом, отдающим свежие
   данные прямо в IDU и экономящим такт.

В результате IDU всегда получает «выровненную» 32-битную величину и не заботится о том,
как инструкция была разложена в памяти.
