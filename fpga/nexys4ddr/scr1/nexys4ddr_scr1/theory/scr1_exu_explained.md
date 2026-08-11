# Как работает EXU (Execution Unit) в SCR1

> Файл RTL: `scr1/src/core/pipeline/scr1_pipe_exu.sv`
> Подмодули: `scr1_pipe_ialu.sv` (АЛУ), `scr1_pipe_lsu.sv` (Load/Store), `scr1_pipe_mprf.sv` (регистровый файл)
> Типы: `scr1_riscv_isa_decoding.svh`, `scr1_arch_types.svh`
> Документация: `scr1_eas.pdf` §6.3 (Execute), `scr1_um.pdf`

Продолжение разбора конвейера после [scr1_ifu_explained.md](scr1_ifu_explained.md) и [scr1_idu_explained.md](scr1_idu_explained.md). EXU — это «рабочая лошадь» ядра: он **исполняет** уже декодированную IDU команду. Здесь сходится почти всё: чтение регистров, арифметика, обращения к памяти, вычисление адреса следующей инструкции, исключения, прерывания, запись результата.

Документ построен вокруг пяти этапов, которые ты просил разобрать:

1. **Operand Fetch** — чтение операндов из регистрового файла;
2. **ALU** — вычисление результата и адресов (модуль IALU);
3. **Load/Store** — работа с памятью данных (модуль LSU);
4. **Flow control** — вычисление PC, переходы, исключения/прерывания;
5. **Write Back** — запись результата в регистр `rd`.

---

## 0. Важный контекст: наша конфигурация

В этой сборке заданы `SCR1_NO_DEC_STAGE` **и** `SCR1_NO_EXE_STAGE`. Это значит, что **между IDU и EXU нет конвейерного регистра**, а операнды читаются из MPRF **асинхронно** (распределённая логика, не блочная RAM). Практический итог:

> Для простой инструкции (`ADD`, `XORI`, `LUI`, `BEQ`…) весь путь **выборка → декодирование → чтение регистров → АЛУ → запись результата → вычисление нового PC происходит комбинационно за один такт.** Отдельные «стадии» — это логические этапы внутри одного такта, а не конвейерные ступени.

Многотактными остаются только:
- **загрузки/записи** в память (ждём ответ DMEM) — модуль LSU;
- **деление** `DIV/REM` (итеративный алгоритм, ~32 такта) — в IALU. Умножение при `SCR1_FAST_MUL` — за 1 такт.

Поэтому «очередь команд EXU», о которой говорят комментарии в коде, в нашей конфигурации вырождается в простой комбинационный проброс:

```systemverilog
`else // ~SCR1_NO_EXE_STAGE  ← активная ветка в нашей сборке
assign exu_queue_barrier = wfi_halted_ff | wfi_run_start_ff
                         | hdu2exu_dbg_halted_i | dbg_run_start_npbuf;
assign exu_queue_vd  = idu2exu_req_i & ~exu_queue_barrier;  // есть валидная команда для исполнения
assign exu_queue     = idu2exu_cmd_i;                       // сама команда = выход IDU, без регистра
`endif
```

- `exu_queue` — та самая структура `type_scr1_exu_cmd_s` от IDU (см. §5 в [scr1_idu_explained.md](scr1_idu_explained.md)), напрямую.
- `exu_queue_vd` — «есть что исполнять»: IDU выставил запрос, и нет **барьера** (ядро не в состоянии WFI-halt и не остановлено отладчиком).

Дальше всюду `exu_queue.<поле>` — это управляющие сигналы от декодера, а `exu_queue_vd` — флаг «команда валидна».

---

## 1. Общая структура и интерфейсы

EXU — крупный модуль. Его порты сгруппированы по интерфейсам:

| Интерфейс | Назначение |
|---|---|
| **EXU ↔ IDU** | приём команды (`idu2exu_cmd_i`, `idu2exu_req_i`) и отдача готовности (`exu2idu_rdy_o`) |
| **EXU ↔ MPRF** | чтение `rs1`/`rs2`, запись `rd` (регистровый файл) |
| **EXU ↔ IALU** | операнды и команда в АЛУ, результат обратно (внутренний подмодуль) |
| **EXU ↔ LSU/DMEM** | загрузки/записи в память данных (через подмодуль LSU) |
| **EXU ↔ CSR** | чтение/запись CSR, события (исключения/IRQ/MRET) |
| **PC interface** | текущий и новый PC, запрос нового PC к IFU |
| **EXU ↔ HDU/TDU** | отладка и аппаратные точки останова (при `SCR1_DBG_EN`/`SCR1_TDU_EN`) |

Внутренние функциональные блоки (по комментарию в шапке файла):
IALU · логика исключений · логика WFI · логика Program Counter · LSU · логика статуса/готовности · интерфейсы к MPRF, CSR, TDU.

Разберём их в порядке потока данных.

---

## 2. Operand Fetch — чтение операндов

### 2.1. Запрос адресов в MPRF

EXU выставляет в регистровый файл адреса `rs1`/`rs2`. В нашей конфигурации (`SCR1_NO_EXE_STAGE`, без RAM) это делается напрямую из текущей команды:

```systemverilog
assign mprf_rs1_req = exu_queue_vd & idu2exu_use_rs1_i;   // читаем rs1, только если инструкция его использует
assign mprf_rs2_req = exu_queue_vd & idu2exu_use_rs2_i;

assign mprf_rs1_addr = exu_queue.rs1_addr[`SCR1_MPRF_AWIDTH-1:0];
assign mprf_rs2_addr = exu_queue.rs2_addr[`SCR1_MPRF_AWIDTH-1:0];

// Клок-гейтинг: если операнд не нужен — подаём адрес 0 (регистр x0), чтобы не «дёргать» шину
assign exu2mprf_rs1_addr_o = mprf_rs1_req ? mprf_rs1_addr : '0;
assign exu2mprf_rs2_addr_o = mprf_rs2_req ? mprf_rs2_addr : '0;
```

Здесь работают те самые подсказки `idu2exu_use_rs1_i`/`use_rs2_i` из IDU (§2 в [scr1_idu_explained.md](scr1_idu_explained.md)): не нужен операнд — адрес принудительно 0, чтения нет.

Регистровый файл MPRF в нашей сборке — **распределённая логика с асинхронным чтением**:

```systemverilog
// scr1_pipe_mprf.sv
assign mprf2exu_rs1_data_o = (rs1_addr_vd) ? mprf_int[exu2mprf_rs1_addr_i] : '0;  // x0 -> 0
assign mprf2exu_rs2_data_o = (rs2_addr_vd) ? mprf_int[exu2mprf_rs2_addr_i] : '0;
```

Асинхронность важна: данные `mprf2exu_rs1_data_i`/`rs2_data_i` приходят в EXU **в том же такте**, поэтому АЛУ успевает посчитать результат сразу. (Про bypass коллизии «запись+чтение» в MPRF — см. врезку в §4 [scr1_idu_explained.md](scr1_idu_explained.md).)

### 2.2. Формирование операндов АЛУ

Прочитанные данные раскладываются на **две пары** операндов — для главного АЛУ и для адресного сумматора.

**Главные операнды** (результат арифметики/логики) — выбор между «регистр-регистр» и «регистр-immediate» по полю `ialu_op`:

```systemverilog
if (exu_queue.ialu_op == SCR1_IALU_OP_REG_REG) begin
    ialu_main_op1 = mprf2exu_rs1_data_i;   // op1 = rs1
    ialu_main_op2 = mprf2exu_rs2_data_i;   // op2 = rs2   (ADD, SUB, AND, ...)
end else begin
    ialu_main_op1 = mprf2exu_rs1_data_i;   // op1 = rs1
    ialu_main_op2 = exu_queue.imm;         // op2 = imm   (ADDI, ANDI, ...)
end
```

**Адресные операнды** (адреса памяти и цели переходов) — выбор по полю `sum2_op`:

```systemverilog
if (exu_queue.sum2_op == SCR1_SUM2_OP_REG_IMM) begin
    ialu_addr_op1 = mprf2exu_rs1_data_i;   // rs1 + imm  → адрес LOAD/STORE, цель JALR
    ialu_addr_op2 = exu_queue.imm;
end else begin
    ialu_addr_op1 = pc_curr_ff;            // PC + imm   → AUIPC, цель JAL и веток
    ialu_addr_op2 = exu_queue.imm;
end
```

То есть EXU **всегда** готовит и «данные», и «адрес» — а дальше уже решается, что из этого пригодится.

---

## 3. ALU — модуль IALU

Все вычисления делает подмодуль `scr1_pipe_ialu`. Он инстанцируется в EXU и получает обе пары операндов плюс команду `exu_queue.ialu_cmd`:

```systemverilog
scr1_pipe_ialu i_ialu(
    .clk(clk), .rst_n(rst_n),
    .exu2ialu_rvm_cmd_vd_i (ialu_vd),          // валидна ли MUL/DIV команда
    .ialu2exu_rvm_res_rdy_o(ialu_rdy),         // готов ли результат MUL/DIV
    // главное АЛУ
    .exu2ialu_main_op1_i(ialu_main_op1),
    .exu2ialu_main_op2_i(ialu_main_op2),
    .exu2ialu_cmd_i     (exu_queue.ialu_cmd),
    .ialu2exu_main_res_o(ialu_main_res),       // результат арифметики/логики/сдвига/умножения
    .ialu2exu_cmp_res_o (ialu_cmp),            // результат сравнения (для веток)
    // адресный сумматор
    .exu2ialu_addr_op1_i(ialu_addr_op1),
    .exu2ialu_addr_op2_i(ialu_addr_op2),
    .ialu2exu_addr_res_o(ialu_addr_res)        // адрес/цель перехода
);
```

Внутри IALU — четыре независимых вычислителя.

### 3.1. Главный сумматор (add/sub/сравнения)

Один сумматор шириной `XLEN+1` считает и сложение, и вычитание. Всё, кроме `ADD`, реализовано как вычитание (для сравнений тоже нужно вычитание):

```systemverilog
main_sum_res = (exu2ialu_cmd_i != SCR1_IALU_CMD_ADD)
             ? ({1'b0, op1} - {1'b0, op2})   // SUB и все сравнения
             : ({1'b0, op1} + {1'b0, op2});  // ADD
```

Из результата вычитания извлекаются **флаги** (как в «настоящем» процессоре):

```systemverilog
main_sum_flags.c = main_sum_res[`SCR1_XLEN];        // перенос/заём
main_sum_flags.z = ~|main_sum_res[`SCR1_XLEN-1:0];  // ноль (равенство)
main_sum_flags.s = main_sum_res[`SCR1_XLEN-1];      // знак
main_sum_flags.o = ...положительное/отрицательное переполнение...
```

Эти флаги дают все нужные сравнения RISC-V: `EQ`(z), `NE`(~z), `LTU`(c), `LT`(s^o), `GE`(~(s^o)), `GEU`(~c).

### 3.2. Адресный сумматор

Отдельный простой сумматор — **всегда** просто складывает свои операнды:

```systemverilog
assign ialu2exu_addr_res_o = exu2ialu_addr_op1_i + exu2ialu_addr_op2_i;
```

Именно он вычисляет адрес для `LOAD`/`STORE`, цель для `JAL`/`JALR`/веток и результат `AUIPC`. Он отдельный, чтобы адрес считался **параллельно** с основной арифметикой.

### 3.3. Сдвиги

Логический влево (`SLL`), логический вправо (`SRL`), арифметический вправо (`SRA`):

```systemverilog
case (shft_cmd)
    2'b10   : shft_res = shft_op1  >> shft_op2;   // SRL
    2'b11   : shft_res = shft_op1 >>> shft_op2;   // SRA (op1 объявлен signed)
    default : shft_res = shft_op1  << shft_op2;   // SLL
endcase
```

### 3.4. MUL/DIV (расширение M, в нашей сборке включено)

При `SCR1_RVM_EXT`:
- **Умножение** с `SCR1_FAST_MUL` — за **один такт**, обычным `*`:
  ```systemverilog
  assign mul_res = mdu_cmd_mul ? mul_op1 * mul_op2 : $signed('0);
  ```
- **Деление** `DIV/DIVU/REM/REMU` — **итеративное**, через отдельный автомат (non-restoring алгоритм). FSM с тремя состояниями:
  ```systemverilog
  SCR1_IALU_MDU_FSM_IDLE → ITER → (CORR) → IDLE
  ```
  Пока идёт деление, IALU держит `ialu2exu_rvm_res_rdy_o = 0`, и EXU **останавливает конвейер** (см. §6.1). Занимает ~`XLEN` тактов.

Валидность MUL/DIV поднимается только когда команда действительно арифметическая от M:
```systemverilog
assign ialu_vd = exu_queue_vd & (exu_queue.ialu_cmd != SCR1_IALU_CMD_NONE) & ~tdu2exu_ibrkpt_exc_req_i;
```

### 3.5. Сборка результата

Финальный `always_comb` выбирает по `ialu_cmd`, что положить в `ialu2exu_main_res_o` и `ialu2exu_cmp_res_o`:

```systemverilog
case (exu2ialu_cmd_i)
    SCR1_IALU_CMD_AND : ialu2exu_main_res_o = op1 & op2;
    SCR1_IALU_CMD_ADD : ialu2exu_main_res_o = main_sum_res[XLEN-1:0];
    SCR1_IALU_CMD_SUB_LT : begin
        ialu2exu_main_res_o = XLEN'(s ^ o);   // результат SLT
        ialu2exu_cmp_res_o  = s ^ o;          // ← этот бит пойдёт в логику веток
    end
    SCR1_IALU_CMD_SLL, SRL, SRA : ialu2exu_main_res_o = shft_res;
    // ... MUL/DIV ...
endcase
```

`ialu_cmp` — ключевой сигнал для условных переходов: для `BEQ` это флаг «равны», для `BLT` — «меньше» и т.д.

---

## 4. Load/Store — модуль LSU

Обращения к памяти данных инкапсулированы в `scr1_pipe_lsu`. EXU формирует запрос и подаёт адрес (из адресного сумматора!) и данные для записи (из `rs2`):

```systemverilog
assign lsu_req = (exu_queue.lsu_cmd != SCR1_LSU_CMD_NONE) & exu_queue_vd;

scr1_pipe_lsu i_lsu(
    .exu2lsu_req_i   (lsu_req            ),
    .exu2lsu_cmd_i   (exu_queue.lsu_cmd  ),   // LB/LH/LW/LBU/LHU/SB/SH/SW
    .exu2lsu_addr_i  (ialu_addr_res      ),   // адрес = результат адресного сумматора (rs1+imm)
    .exu2lsu_sdata_i (mprf2exu_rs2_data_i),   // что записать = rs2
    .lsu2exu_rdy_o   (lsu_rdy            ),   // память ответила
    .lsu2exu_ldata_o (lsu_l_data         ),   // загруженные данные
    .lsu2exu_exc_o   (lsu_exc_req        ),   // исключение
    .lsu2exu_exc_code_o(lsu_exc_code     ),
    // ... интерфейс к DMEM ...
);
```

### 4.1. FSM и интерфейс к памяти

LSU — двухтактный автомат `IDLE ↔ BUSY`, управляющий split-transaction интерфейсом DMEM:

```systemverilog
SCR1_LSU_FSM_IDLE: lsu_fsm_next = dmem_req_vd        ? SCR1_LSU_FSM_BUSY : SCR1_LSU_FSM_IDLE;
SCR1_LSU_FSM_BUSY: lsu_fsm_next = dmem_resp_received ? SCR1_LSU_FSM_IDLE : SCR1_LSU_FSM_BUSY;
```

Запрос выставляется, пока нет исключения и автомат свободен; команда/ширина выводятся из `lsu_cmd`:

```systemverilog
assign lsu2dmem_req_o   = exu2lsu_req_i & ~lsu_exc_req & lsu_fsm_idle;
assign lsu2dmem_cmd_o   = dmem_cmd_store ? SCR1_MEM_CMD_WR : SCR1_MEM_CMD_RD;
assign lsu2dmem_width_o = dmem_wdth_byte  ? SCR1_MEM_WIDTH_BYTE
                        : dmem_wdth_hword ? SCR1_MEM_WIDTH_HWORD
                                          : SCR1_MEM_WIDTH_WORD;
assign lsu2exu_rdy_o    = dmem_resp_received;   // ← это уходит в exu_rdy и держит конвейер, пока память не ответит
```

### 4.2. Расширение загруженных данных

Для загрузок LSU знаково/беззнаково расширяет пришедшее из памяти значение по типу команды:

```systemverilog
case (lsu_cmd_ff)
    SCR1_LSU_CMD_LH : lsu2exu_ldata_o = {{16{rdata[15]}}, rdata[15:0]};   // знаковое пол-слово
    SCR1_LSU_CMD_LHU: lsu2exu_ldata_o = {16'b0,           rdata[15:0]};   // беззнаковое
    SCR1_LSU_CMD_LB : lsu2exu_ldata_o = {{24{rdata[7]}},  rdata[7:0]};    // знаковый байт
    SCR1_LSU_CMD_LBU: lsu2exu_ldata_o = {24'b0,           rdata[7:0]};    // беззнаковый
    default         : lsu2exu_ldata_o = rdata;                            // LW — целое слово
endcase
```

### 4.3. Исключения LSU

LSU сам ловит две категории ошибок памяти:

- **Невыровненный адрес** (`misalign`) — проверяется комбинационно по младшим битам адреса и ширине доступа (то самое выравнивание, о котором мы говорили отдельно):
  ```systemverilog
  assign dmem_addr_mslgn = exu2lsu_req_i & ( (dmem_wdth_hword & exu2lsu_addr_i[0])       // half по нечётному
                                           | (dmem_wdth_word  & |exu2lsu_addr_i[1:0]) ); // word не по кратному 4
  ```
- **Access fault** — если DMEM вернула ошибочный ответ (`SCR1_MEM_RESP_RDY_ER`).

Код исключения кодируется отдельно для load/store:
```systemverilog
dmem_resp_er     : ... = lsu_cmd_ff_load ? SCR1_EXC_CODE_LD_ACCESS_FAULT : SCR1_EXC_CODE_ST_ACCESS_FAULT;
dmem_addr_mslgn_l: ... = SCR1_EXC_CODE_LD_ADDR_MISALIGN;
dmem_addr_mslgn_s: ... = SCR1_EXC_CODE_ST_ADDR_MISALIGN;
```

Эти `lsu_exc_req`/`lsu_exc_code` уходят обратно в EXU и вливаются в общую логику исключений (§5.3).

---

## 5. Flow control — вычисление PC, переходы, исключения

Это самая «диспетчерская» часть EXU: где взять адрес следующей инструкции.

### 5.1. Регистр текущего PC

Текущий PC хранится в `pc_curr_ff`, сбрасывается в вектор сброса и обновляется при **завершении** (retire) инструкции:

```systemverilog
always_ff @(negedge rst_n, posedge clk) begin
    if (~rst_n)            pc_curr_ff <= SCR1_RST_VECTOR;   // в нашей сборке 0x200
    else if (pc_curr_upd)  pc_curr_ff <= pc_curr_next;
end

// на сколько увеличить PC: сжатая команда → +2, обычная → +4
assign inc_pc = pc_curr_ff + (exu_queue.instr_rvc ? `SCR1_XLEN'd2 : `SCR1_XLEN'd4);
```

После сброса небольшой сдвиговый регистр `init_pc_v` формирует одиночный импульс `init_pc`, который заставляет загрузить в PC вектор сброса и стартовать выборку.

### 5.2. Переходы (jump/branch)

Переход «сработал», если это безусловный `jump`, либо условная ветка, чьё условие подтвердил IALU (`ialu_cmp`):

```systemverilog
assign branch_taken = exu_queue.branch_req & ialu_cmp;      // ветка + условие истинно
assign jb_taken     = exu_queue.jump_req  | branch_taken;   // любой состоявшийся переход
assign jb_new_pc    = ialu_addr_res & SCR1_JUMP_MASK;       // цель (маска сбрасывает бит 0)
```

`SCR1_JUMP_MASK = 0xFFFF_FFFE` обнуляет младший бит — требование RISC-V для `JALR`.

### 5.3. Мультиплексор нового PC

Куда прыгнуть — решает приоритетный `case` (сброс → трапы → отладка → возобновление WFI → `fence.i` → обычный переход):

```systemverilog
always_comb begin
    case (1'b1)
        init_pc              : exu2ifu_pc_new_o = SCR1_RST_VECTOR;    // старт после сброса
        exu2csr_take_exc_o,
        exu2csr_take_irq_o,
        exu2csr_mret_instr_o : exu2ifu_pc_new_o = csr2exu_new_pc_i;   // трап/возврат — адрес из CSR
        dbg_run_start_npbuf  : exu2ifu_pc_new_o = hdu2exu_dbg_new_pc_i;
        wfi_run_start_ff     : exu2ifu_pc_new_o = pc_curr_ff;         // проснулись из WFI
        exu_queue.fencei_req : exu2ifu_pc_new_o = inc_pc;             // FENCE.I — перезапуск выборки
        default              : exu2ifu_pc_new_o = ialu_addr_res & SCR1_JUMP_MASK;  // цель jump/branch
    endcase
end
```

И собственно **запрос нового PC** к IFU (`exu2ifu_pc_new_req_o`) поднимается по любой из этих причин: сброс, IRQ, исключение, `MRET`, `FENCE.I`, возобновление WFI, состоявшийся переход `jb_taken`. Именно этот сигнал разворачивает IFU на новый адрес (см. IFU-док).

### 5.4. Исключения, прерывания, MRET, WFI

**Единый запрос исключения** собирает все источники — от IDU (нелегальная инструкция, `ECALL`/`EBREAK`), от LSU, от CSR, от аппаратных точек останова:

```systemverilog
assign exu_exc_req = exu_queue_vd & ( exu_queue.exc_req      // исключение, найденное ещё в IDU
                                    | lsu_exc_req            // ошибка памяти из LSU
                                    | csr2exu_rw_exc_i       // недопустимый доступ к CSR
                                    | ... hw breakpoint ... );
```

Дальше приоритетный энкодер выбирает **код** (`exc_code`), а отдельный мультиплексор — **trap value** (`exc_trap_val`, попадёт в CSR `mtval`): для ошибок памяти это адрес доступа (`ialu_addr_res`), для access fault на старшей половине RVI — `inc_pc` и т.д.

Готовые события уходят в CSR-подсистему:
```systemverilog
assign exu2csr_take_exc_o = exu_exc_req & ~hdu2exu_dbg_halted_i;    // взять исключение
assign exu2csr_take_irq_o = csr2exu_irq_i & ~exu2pipe_exu_busy_o ...; // взять прерывание (не в середине многотактной операции!)
assign exu2csr_mret_instr_o = exu_queue_vd & exu_queue.mret_req ...;  // выполняется MRET
```

Обрати внимание: прерывание берётся только когда `~exu_busy` — нельзя прервать наполовину выполненную загрузку или деление.

**WFI (wait for interrupt).** Отдельный автомат «усыпляет» ядро до появления ожидающего прерывания:
```systemverilog
assign wfi_halt_cond = ~csr2exu_ip_ie_i & ((exu_queue_vd & exu_queue.wfi_req) | wfi_run_start_ff) ...;
assign wfi_halt_req  = ~wfi_halted_ff & wfi_halt_cond;   // уснуть
assign wfi_run_req   =  wfi_halted_ff & csr2exu_ip_ie_i; // проснуться
```
В состоянии `wfi_halted_ff` поднимается барьер `exu_queue_barrier` (см. §0) — конвейер стоит, а при `SCR1_CLKCTRL_EN` можно ещё и погасить такт.

---

## 6. Write Back — запись результата в rd

### 6.1. Когда пишем

Запись в регистровый файл разрешается, только если инструкция реально пишет `rd`, **завершилась** и **без исключения**:

```systemverilog
assign exu2mprf_w_req_o = (exu_queue.rd_wb_sel != SCR1_RD_WB_NONE)   // инструкция пишет rd
                        & exu_queue_vd
                        & ~exu_exc_req                               // не было исключения
                        & ~hdu2exu_no_commit_i                       // отладчик не запрещает коммит
                        & ((exu_queue.rd_wb_sel == SCR1_RD_WB_CSR) ? csr_access_init : exu_rdy);
assign exu2mprf_rd_addr_o = `SCR1_MPRF_AWIDTH'(exu_queue.rd_addr);
```

Ключевой множитель здесь — `exu_rdy` (для CSR — `csr_access_init`): пока инструкция не готова (ждём память или деление), запись не происходит. Это и есть механизм, не дающий записать «полусырой» результат.

### 6.2. Откуда берётся значение

Мультиплексор выбирает источник данных по полю `rd_wb_sel`, которое проставил IDU:

```systemverilog
case (exu_queue.rd_wb_sel)
    SCR1_RD_WB_SUM2  : exu2mprf_rd_data_o = ialu_addr_res;   // AUIPC (PC+imm)
    SCR1_RD_WB_IMM   : exu2mprf_rd_data_o = exu_queue.imm;   // LUI
    SCR1_RD_WB_INC_PC: exu2mprf_rd_data_o = inc_pc;          // JAL/JALR — адрес возврата
    SCR1_RD_WB_LSU   : exu2mprf_rd_data_o = lsu_l_data;      // загрузка из памяти
    SCR1_RD_WB_CSR   : exu2mprf_rd_data_o = csr2exu_r_data_i;// чтение CSR
    default          : exu2mprf_rd_data_o = ialu_main_res;   // обычная арифметика/логика/сдвиг
endcase
```

Итак, все «нити» сходятся здесь: результат IALU, адрес из адресного сумматора, данные из LSU, значение CSR или immediate — что-то одно записывается в `rd`.

---

## 7. Готовность и завершение инструкции (handshake)

Центральный сигнал — `exu_rdy` («EXU закончил текущую инструкцию»):

```systemverilog
always_comb begin
    case (1'b1)
        lsu_req                 : exu_rdy = lsu_rdy | lsu_exc_req;  // загрузка/запись: ждём память
        ialu_vd                 : exu_rdy = ialu_rdy;              // MUL/DIV: ждём IALU (деление)
        csr2exu_mstatus_mie_up_i: exu_rdy = 1'b0;                  // обновление MSTATUS: +такт
        default                 : exu_rdy = 1'b1;                  // всё остальное — за 1 такт
    endcase
end

assign exu2idu_rdy_o       = exu_rdy & ~exu_queue_barrier;   // готовность назад к IDU/IFU (backpressure)
assign exu2pipe_exu_busy_o = exu_queue_vd & ~exu_rdy;        // EXU занят (многотактная операция)
assign exu2pipe_instret_o  = exu_queue_vd &  exu_rdy;        // ИНСТРУКЦИЯ ЗАВЕРШЕНА (retired)
```

- `exu2pipe_instret_o` — «инструкция вышла из конвейера»: по нему обновляется PC (`pc_curr_upd`) и счётчики.
- `exu2idu_rdy_o` — обратное давление: пока EXU занят (`exu_rdy=0`), IDU/IFU не подадут следующую команду.

Именно так одна и та же логика обслуживает и однотактные инструкции (за такт `exu_rdy=1`), и многотактные (загрузка/деление держат `exu_rdy=0`, конвейер ждёт).

---

## 8. Интерфейс к CSR (кратко)

Инструкции `CSRRW/CSRRS/CSRRC(I)` обслуживаются здесь же. EXU формирует запросы чтения/записи CSR и данные:

```systemverilog
assign exu2csr_rw_addr_o = exu_queue.imm[SCR1_CSR_ADDR_WIDTH-1:0];   // адрес CSR (IDU положил его в imm)
assign exu2csr_w_data_o  = (exu_queue.csr_op == SCR1_CSR_OP_REG)
                         ? mprf2exu_rs1_data_i        // источник — регистр rs1
                         : {'0, exu_queue.rs1_addr};  // либо zimm (для CSRRxI)
assign exu2csr_w_cmd_o   = exu_queue.csr_cmd;         // WRITE / SET / CLEAR
```

Небольшой автомат `csr_access_ff` (`INIT → RDY`) разводит чтение и запись CSR по тактам, чтобы корректно обработать обновление `MSTATUS`/`MIE`. Прочитанное значение CSR при этом идёт в write-back как источник данных для `rd` (§6.2).

---

## 9. Ассершены (в симуляции)

Под `SCR1_TRGT_SIMULATION` EXU проверяет корректность, например:

```systemverilog
// нельзя одновременно jump, branch и обращение к памяти
SCR1_SVA_EXU_ONEHOT : assert property ( ... $onehot0({exu_queue.jump_req, exu_queue.branch_req, lsu_req}) ... );

// не более одного исключения за такт
SCR1_SVA_EXU_ONEHOT_EXC : assert property ( ... $onehot0({exu_queue.exc_req, lsu_exc_req, csr2exu_rw_exc_i ...}) ... );

// нельзя обновлять/запрашивать PC до окончания сброса
SCR1_SVA_EXU_NEW_PC_REQ_BEFORE_INIT : assert property ( ... ~&init_pc_v |-> ~(exu2ifu_pc_new_req_o & ~init_pc) ... );
```

Плюс X-checks (нет ли неизвестных значений на управляющих сигналах). В IALU и LSU — свои наборы ассершенов (корректность FSM деления, one-hot исключений памяти и т.д.).

---

## 10. Итог: полный путь одной инструкции

Соберём всё вместе на примере `ADD x5, x6, x7` — всё происходит **за один такт**:

1. **Operand Fetch.** IDU выставил `rs1=x6`, `rs2=x7`, `use_rs1=use_rs2=1`. EXU подаёт адреса в MPRF, тот асинхронно возвращает данные. `ialu_op=REG_REG` → `main_op1=x6`, `main_op2=x7`.
2. **ALU.** `ialu_cmd=ADD` → главный сумматор считает `x6+x7`, результат в `ialu_main_res`. Параллельно адресный сумматор что-то считает, но он не понадобится.
3. **Load/Store.** `lsu_cmd=NONE` → `lsu_req=0`, LSU молчит.
4. **Flow control.** `jump_req=branch_req=0` → `jb_taken=0`, исключений нет → `exu_rdy=1`, `instret=1`, PC увеличивается на 4 (`inc_pc`).
5. **Write Back.** `rd_wb_sel=IALU` → в `rd=x5` записывается `ialu_main_res`. `exu2mprf_w_req_o=1`.

Для `LW x5, 8(x6)` шаги 1–2 аналогичны (адрес считает **адресный** сумматор: `x6+8`), но на шаге 3 LSU выставляет запрос в DMEM и держит `exu_rdy=0`, пока память не ответит — инструкция становится **многотактной**; на write-back в `rd` пойдёт `lsu_l_data` (расширенные данные из памяти). Для `BEQ` результат сравнения `ialu_cmp` определит `branch_taken`, и при истинном условии EXU запросит у IFU новый PC = цель ветки.

**Одним абзацем.** EXU берёт декодированную IDU команду, асинхронно читает операнды из MPRF, прогоняет их через IALU (главный сумматор + флаги, адресный сумматор, сдвиги, MUL/DIV), при необходимости обращается к памяти через LSU, вычисляет адрес следующей инструкции (инкремент, переход, трап, MRET, WFI, fence.i) и записывает результат в `rd`. В нашей конфигурации без конвейерных регистров всё это для простых инструкций укладывается в один такт; многотактными остаются лишь обращения к памяти и деление, на время которых `exu_rdy` останавливает конвейер.
