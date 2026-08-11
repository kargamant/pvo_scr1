# Как работает IDU (Instruction Decode Unit) в SCR1

> Файл RTL: `scr1/src/core/pipeline/scr1_pipe_idu.sv`
> Типы и структура команды: `scr1/src/includes/scr1_riscv_isa_decoding.svh`
> Документация: `scr1_eas.pdf` §6.2 (Instruction Decode), `scr1_um.pdf`

Это продолжение разбора конвейера после [scr1_ifu_explained.md](scr1_ifu_explained.md). IDU намного проще IFU: **у него нет ни FSM, ни очереди, ни счётчиков транзакций**. Это, по сути, один большой комбинационный дешифратор: «на входе 32 бита инструкции — на выходе набор управляющих сигналов для EXU». Поэтому и разбор короче.

---

## 1. Место IDU в конвейере

```
IFU  ──ifu2idu_instr──►  IDU  ──idu2exu_cmd──►  EXU
 ▲                        │                       │
 └──── idu2ifu_rdy ───────┘◄──── exu2idu_rdy ─────┘
```

- **IFU** отдаёт «сырое» 32-битное слово инструкции (уже выровненное и собранное из очереди — для RVC там младшие 16 бит значимы).
- **IDU** разбирает это слово: определяет тип (RVI/RVC), опкод, номера регистров, immediate, что за операция для АЛУ / LSU / CSR, нужно ли прыгать/ветвиться, не является ли инструкция нелегальной.
- **EXU** получает готовую «разжёванную» команду `type_scr1_exu_cmd_s` и просто исполняет её.

Ключевой момент: **IDU не хранит состояние**. Всё, что он делает — это `assign`-ы и один `always_comb`. Такты и сброс (`clk`, `rst_n`) заходят в модуль **только для ассершенов** в симуляции:

```systemverilog
module scr1_pipe_idu
(
`ifdef SCR1_TRGT_SIMULATION
    input   logic                           rst_n,   // нужен ТОЛЬКО для assert
    input   logic                           clk,     // нужен ТОЛЬКО для assert
`endif // SCR1_TRGT_SIMULATION
    ...
```

В синтезируемой сборке этих портов у IDU нет вообще.

---

## 2. Порты: два простых интерфейса

### IFU → IDU (вход)
```systemverilog
output  logic                         idu2ifu_rdy_o,        // IDU готов принять новое слово
input   logic [`SCR1_IMEM_DWIDTH-1:0] ifu2idu_instr_i,      // само 32-битное слово инструкции
input   logic                         ifu2idu_imem_err_i,   // ошибка доступа к памяти инструкций
input   logic                         ifu2idu_err_rvi_hi_i, // ошибка при догрузке старшей половины невыровненной RVI
input   logic                         ifu2idu_vd_i,         // инструкция валидна
```

### IDU → EXU (выход)
```systemverilog
output  logic               idu2exu_req_o,     // есть команда для EXU
output  type_scr1_exu_cmd_s idu2exu_cmd_o,     // САМА команда (большая packed-структура)
output  logic               idu2exu_use_rs1_o, // инструкция реально использует rs1
output  logic               idu2exu_use_rs2_o, // ... rs2
`ifndef SCR1_NO_EXE_STAGE
output  logic               idu2exu_use_rd_o,  // ... rd
output  logic               idu2exu_use_imm_o, // ... immediate
`endif
input   logic               exu2idu_rdy_i      // EXU готов принять команду
```

Сигналы `use_rs1/rs2/rd/imm` — это **подсказки для клок-гейтинга**: они сообщают дальше по конвейеру (регистровому файлу MPRF и EXU), какие операнды реально нужны данной инструкции, чтобы не читать/не защёлкивать лишнее и экономить энергию. Часть из них (`use_rd`, `use_imm`) существует только если есть стадия EXE (`SCR1_NO_EXE_STAGE` не задан).

---

## 3. Handshake: IDU полностью «прозрачный»

Так как IDU комбинационный, он не задерживает поток и просто пробрасывает управление между IFU и EXU:

```systemverilog
assign idu2ifu_rdy_o  = exu2idu_rdy_i;   // «IDU готов» = «EXU готов» (IDU сам никогда не тормозит)
assign idu2exu_req_o  = ifu2idu_vd_i;    // «есть команда для EXU» = «IFU дал валидное слово»
assign instr          = ifu2idu_instr_i; // рабочая копия слова инструкции
```

То есть готовность IDU напрямую равна готовности EXU, а запрос к EXU — это валидность от IFU. Никаких «своих» стопов IDU не вносит: он либо мгновенно декодирует то, что дал IFU, либо ждёт вместе со всеми.

---

## 4. Bypass: как инструкция попадает в IDU без лишнего такта

В нашей конфигурации задан **`SCR1_NO_DEC_STAGE`** — это значит, что **между IFU и IDU нет отдельного конвейерного регистра (стадии декодирования)**. IFU выставляет слово, а IDU дешифрирует его комбинационно в том же такте. Чтобы при этом не терять такт на «сначала записать инструкцию в очередь IFU, а на следующем такте прочитать её обратно», в IFU встроен механизм **bypass (обход очереди)**: только что пришедшее из памяти слово может пойти прямо на вход IDU, минуя очередь.

> Важно: **вся логика bypass живёт в IFU, а не в IDU.** Для самого IDU это полностью прозрачно — он всегда видит одни и те же 4 входа (`ifu2idu_instr_i`, `ifu2idu_vd_i`, `ifu2idu_imem_err_i`, `ifu2idu_err_rvi_hi_i`) и не знает, пришла инструкция из очереди или в обход неё. Но раз именно bypass формирует вход IDU, разберём его здесь. Полный разбор очереди — в [scr1_ifu_explained.md](scr1_ifu_explained.md).

### Зачем это нужно

Без bypass путь «выборка → декодирование» был бы таким: слово из памяти → защёлкнуть в очередь → на следующем такте прочитать из очереди → отдать в IDU. Это лишний такт задержки для каждой инструкции, приходящей в пустую очередь (например, сразу после перехода или сброса очереди). Bypass позволяет отдать такое слово в IDU **в том же такте**, когда пришёл ответ памяти.

### Четыре варианта обхода

Тип обхода выбирает декодер `instr_bypass_type` (`scr1_pipe_ifu.sv`):

```systemverilog
typedef enum logic [1:0] {
    SCR1_BYPASS_NONE,            // обхода нет — инструкция берётся из очереди
    SCR1_BYPASS_RVC,             // напрямую отдаём сжатую (16-бит) инструкцию
    SCR1_BYPASS_RVI_RDATA_QUEUE, // RVI: младшая половина уже в очереди, старшая только что пришла
    SCR1_BYPASS_RVI_RDATA        // RVI: обе половины целиком в только что пришедшем слове
} type_scr1_bypass_e;

assign instr_bypass_vd = (instr_bypass_type != SCR1_BYPASS_NONE);
```

Обход возможен только когда в этом такте валиден ответ памяти (`imem_resp_vd`):

```systemverilog
if (imem_resp_vd) begin
    if (q_is_empty) begin
        // очередь пуста — можно отдать пришедшее слово напрямую
        case (instr_type)
            SCR1_IFU_INSTR_RVC_NV,
            SCR1_IFU_INSTR_RVC_RVC,
            SCR1_IFU_INSTR_RVI_LO_RVC    : instr_bypass_type = SCR1_BYPASS_RVC;       // это сжатая
            SCR1_IFU_INSTR_RVI_HI_RVI_LO : instr_bypass_type = SCR1_BYPASS_RVI_RDATA; // целая RVI в слове
            default : ;
        endcase
    end else if (q_has_1_ocpd_hw & q_head_is_rvi) begin
        // в очереди лежит только младшая половина невыровненной RVI, а старшая пришла сейчас
        if (instr_hi_rvi_lo_ff) instr_bypass_type = SCR1_BYPASS_RVI_RDATA_QUEUE;
    end
end
```

### Что именно уходит в IDU

Выходной мультиплексор собирает `ifu2idu_instr_o` (= вход `ifu2idu_instr_i` для IDU) по типу обхода:

```systemverilog
case (instr_bypass_type)
    SCR1_BYPASS_RVC            : ifu2idu_instr_o = new_pc_unaligned_ff ? imem_rdata_hi   // сжатая из старшей...
                                                                       : imem_rdata_lo;  // ...или младшей половины слова
    SCR1_BYPASS_RVI_RDATA      : ifu2idu_instr_o = imem2ifu_rdata_i;                     // целые 32 бита из памяти
    SCR1_BYPASS_RVI_RDATA_QUEUE: ifu2idu_instr_o = {imem_rdata_lo, q_data_head};         // старшая (память) + младшая (очередь)
    default /* NONE */         : ifu2idu_instr_o = q_head_is_rvc ? q_data_head           // всё из очереди
                                                                 : {q_data_next, q_data_head};
endcase
```

- **`SCR1_BYPASS_RVC`** — сжатая 16-битная команда: берётся половина только что пришедшего слова (старшая или младшая — зависит от выравнивания `new_pc_unaligned_ff`).
- **`SCR1_BYPASS_RVI_RDATA`** — полная 32-битная команда целиком лежит в пришедшем слове → отдаём слово как есть.
- **`SCR1_BYPASS_RVI_RDATA_QUEUE`** — невыровненная RVI, разорванная на два слова: младшие 16 бит уже были защёлкнуты в очередь (`q_data_head`), старшие 16 только что пришли (`imem_rdata_lo`) → склеиваем `{старшая, младшая}`.
- **`SCR1_BYPASS_NONE`** — обхода нет, обычный путь: инструкция читается из очереди (`q_data_head` для RVC либо `{q_data_next, q_data_head}` для RVI).

Ошибки доступа тоже корректно прокидываются: при `RVI_RDATA_QUEUE` учитывается и ошибка пришедшего слова (`imem_resp_er`), и ошибка уже лежащей в очереди половины (`q_err_head`) — именно поэтому у IDU есть отдельный вход `ifu2idu_err_rvi_hi_i` («ошибка случилась на старшей половине RVI»).

### Вывод для IDU

С `SCR1_NO_DEC_STAGE` IDU работает «впритык» к IFU без промежуточного регистра, а bypass в IFU гарантирует, что свежая инструкция доедет до дешифратора без лишнего такта. Со стороны IDU при этом ничего не меняется — он просто декодирует то, что стоит на входе. Именно поэтому в §3 готовность IDU напрямую равна готовности EXU: IDU нигде не «копит» инструкции, он лишь мгновенное комбинационное звено между обходной логикой IFU и исполнением в EXU.

> **Не путать с другим bypass в ядре.** В регистровом файле **MPRF** (`scr1_pipe_mprf.sv`) есть свой, независимый bypass — обход коллизии «запись и чтение одного регистра в одном такте» (read-during-write). Если EXU в этом же такте пишет результат в `rd` и читает тот же регистр как `rs1`/`rs2`, MPRF отдаёт на чтение только что записанные данные:
> ```systemverilog
> // bypass new wr_data to the read output if write/read collision occurs
> assign mprf2exu_rs1_data_o = (rs1_new_data_req_ff) ? rd_data_ff : ...;
> ```
> Это касается **операндов** (`rs1_addr`/`rs2_addr`/`rd_addr`), которые декодирует IDU, но происходит уже в MPRF/EXU, а не в самом IDU. Тот bypass — про данные регистров, а bypass из этого раздела — про сам поток инструкций IFU→IDU. Это два разных механизма с одинаковым названием.

---

## 5. Извлечение полей инструкции

Перед основным дешифратором несколько `assign` вытаскивают стандартные поля RISC-V прямо из битов слова:

```systemverilog
// Тип: два младших бита. 2'b11 => RVI (32-бит), иначе RVC-квадрант 0/1/2
assign instr_type = type_scr1_instr_type_e'(instr[1:0]);

// Поля
assign rvi_opcode = type_scr1_rvi_opcode_e'(instr[6:2]);                          // опкод RVI
assign funct3     = (instr_type == SCR1_INSTR_RVI) ? instr[14:12] : instr[15:13]; // funct3 у RVI и RVC живёт в РАЗНЫХ битах
assign funct7     = instr[31:25];                                                 // RVI (R-тип)
assign funct12    = instr[31:20];                                                 // RVI (SYSTEM: ECALL/EBREAK/MRET/WFI)
assign shamt      = instr[24:20];                                                 // RVI (сдвиги SLLI/SRLI/SRAI)
```

Обратите внимание на `funct3`: у 32-битных RVI-инструкций это биты `[14:12]`, а у сжатых 16-битных RVC — биты `[15:13]`. Одна строчка тернарника решает эту разницу.

`type_scr1_instr_type_e` (из `scr1_riscv_isa_decoding.svh`):
```systemverilog
typedef enum logic [1:0] {
    SCR1_INSTR_RVC0 = 2'b00,   // сжатые, квадрант 0
    SCR1_INSTR_RVC1 = 2'b01,   // сжатые, квадрант 1
    SCR1_INSTR_RVC2 = 2'b10,   // сжатые, квадрант 2
    SCR1_INSTR_RVI  = 2'b11    // полные 32-битные
} type_scr1_instr_type_e;
```

Это ровно то же различение RVC/RVI по двум младшим битам, что делает первичный декодер в IFU — только IFU использует его, чтобы понять длину и упаковать очередь, а IDU — чтобы выбрать ветку декодирования.

---

## 6. Что на выходе: структура команды `type_scr1_exu_cmd_s`

Весь смысл IDU — заполнить эту packed-структуру (из `scr1_riscv_isa_decoding.svh`):

```systemverilog
typedef struct packed {
    logic                        instr_rvc;   // 1 = сжатая (влияет на PC+2 vs PC+4);
                                              // при imem-fault переиспользуется под err_rvi_hi
    type_scr1_ialu_op_sel_e      ialu_op;     // операнды главного АЛУ: REG_IMM или REG_REG
    type_scr1_ialu_cmd_sel_e     ialu_cmd;    // операция главного АЛУ (ADD/SUB/SLL/.../MUL...)
    type_scr1_ialu_sum2_op_sel_e sum2_op;     // операнды доп. сумматора SUM2: PC+imm или rs1+imm
    type_scr1_lsu_cmd_sel_e      lsu_cmd;     // команда LSU (LB/LH/LW/SB/SW/...)
    type_scr1_csr_op_sel_e       csr_op;      // источник для CSR: регистр или zimm
    type_scr1_csr_cmd_sel_e      csr_cmd;     // операция CSR (WRITE/SET/CLEAR)
    type_scr1_rd_wb_sel_e        rd_wb_sel;   // ОТКУДА писать в rd (АЛУ/SUM2/imm/PC+.../LSU/CSR)
    logic                        jump_req;    // безусловный переход (JAL/JALR/C.J...)
    logic                        branch_req;  // условный переход (BEQ/BNE/...)
    logic                        mret_req;    // MRET
    logic                        fencei_req;  // FENCE.I
    logic                        wfi_req;     // WFI
    logic [4:0]                  rs1_addr;    // номер rs1 (или zimm для CSRRxI)
    logic [4:0]                  rs2_addr;    // номер rs2
    logic [4:0]                  rd_addr;     // номер rd
    logic [`SCR1_XLEN-1:0]       imm;         // immediate (или {funct3,CSR-адрес}, или тело нелегальной инструкции)
    logic                        exc_req;     // возникла исключительная ситуация
    type_scr1_exc_code_e         exc_code;    // код исключения
} type_scr1_exu_cmd_s;
```

Каждое поле — это «ручка», которой EXU управляет своими блоками. Задача декодера — по битам инструкции выставить эти ручки в нужные положения. Вспомогательные enum-ы (значения операций):

```systemverilog
// главное АЛУ
SCR1_IALU_CMD_NONE/AND/OR/XOR/ADD/SUB/SUB_LT/SUB_LTU/SUB_EQ/SUB_NE/SUB_GE/SUB_GEU/SLL/SRL/SRA (+ MUL... при RVM)
// куда пишем rd
SCR1_RD_WB_NONE/IALU/SUM2/IMM/INC_PC/LSU/CSR
// доп. сумматор (адреса и цели переходов)
SCR1_SUM2_OP_PC_IMM   // PC + imm  (AUIPC, цель JAL/веток)
SCR1_SUM2_OP_REG_IMM  // rs1 + imm (цель JALR, адрес LOAD/STORE)
```

---

## 7. Ядро: один `always_comb`

Вся логика декодирования — в единственном `always_comb`, и он устроен по чёткой схеме из трёх шагов:

### Шаг 1. Значения по умолчанию (безопасный NOP)

В начале блока **всё** обнуляется/ставится в нейтральное состояние, чтобы не было защёлок и чтобы неописанные случаи давали безобидную команду:

```systemverilog
// Defaults
idu2exu_cmd_o.instr_rvc  = 1'b0;
idu2exu_cmd_o.ialu_op    = SCR1_IALU_OP_REG_REG;
idu2exu_cmd_o.ialu_cmd   = SCR1_IALU_CMD_NONE;   // АЛУ не работает
idu2exu_cmd_o.sum2_op    = SCR1_SUM2_OP_PC_IMM;
idu2exu_cmd_o.lsu_cmd    = SCR1_LSU_CMD_NONE;    // памяти не касаемся
idu2exu_cmd_o.csr_op     = SCR1_CSR_OP_REG;
idu2exu_cmd_o.csr_cmd    = SCR1_CSR_CMD_NONE;    // CSR не трогаем
idu2exu_cmd_o.rd_wb_sel  = SCR1_RD_WB_NONE;      // в rd ничего не пишем
idu2exu_cmd_o.jump_req   = 1'b0;
idu2exu_cmd_o.branch_req = 1'b0;
...
idu2exu_cmd_o.exc_req    = 1'b0;
// Clock gating — по умолчанию операнды не нужны
idu2exu_use_rs1_o        = 1'b0;
idu2exu_use_rs2_o        = 1'b0;
...
rvi_illegal              = 1'b0;   // «флаги нелегальности»
```

Дальше каждая конкретная ветка **лишь переопределяет то, что ей нужно**. Это классический и очень читаемый приём: defaults + переопределения.

### Шаг 2. Сначала — проверка ошибки памяти инструкций

Если IFU сообщил об ошибке доступа (`ifu2idu_imem_err_i`), декодировать нечего — сразу формируется исключение, а сами биты инструкции игнорируются:

```systemverilog
if (ifu2idu_imem_err_i) begin
    idu2exu_cmd_o.exc_req   = 1'b1;
    idu2exu_cmd_o.exc_code  = SCR1_EXC_CODE_INSTR_ACCESS_FAULT;
    idu2exu_cmd_o.instr_rvc = ifu2idu_err_rvi_hi_i;  // здесь instr_rvc НЕ «сжатая»,
                                                     // а «ошибка была на старшей половине RVI»
end else begin
    // ... нормальное декодирование ...
end
```

Здесь видно то самое двойное назначение поля `instr_rvc`: при исключении доступа оно несёт информацию, на какой половине невыровненной RVI-инструкции случилась ошибка (это нужно, чтобы правильно посчитать адрес возврата).

### Шаг 3. Нормальное декодирование — `case (instr_type)`

Если ошибки нет, выбирается одна из четырёх больших веток по типу инструкции:

```systemverilog
case (instr_type)
    SCR1_INSTR_RVI  : begin ... end   // 32-битные — самая большая ветка
`ifdef SCR1_RVC_EXT
    SCR1_INSTR_RVC0 : begin ... end   // сжатые, квадрант 0
    SCR1_INSTR_RVC1 : begin ... end   // сжатые, квадрант 1
    SCR1_INSTR_RVC2 : begin ... end   // сжатые, квадрант 2
`endif
    default         : ...
endcase
```

Внутри `SCR1_INSTR_RVI` идёт вложенный `case (rvi_opcode)` по стандартным опкодам RISC-V (`LOAD`, `OP`, `OP_IMM`, `BRANCH`, `JAL`, `JALR`, `SYSTEM`, `MISC_MEM`, …), а внутри — ещё `case (funct3)` / `case (funct7)`. Ветки RVC разбираются по `funct3` и дополнительным битам (у сжатых кодировка плотнее, поэтому больше вложенных условий).

---

## 8. Разбор конкретных примеров декодирования

Чтобы «прочитать» дешифратор, достаточно посмотреть, как заполняется структура для нескольких инструкций.

### Пример A — RVI `ADD rd, rs1, rs2` (опкод OP, funct7=0, funct3=0)

```systemverilog
SCR1_OPCODE_OP : begin
    idu2exu_use_rs1_o       = 1'b1;              // нужен rs1
    idu2exu_use_rs2_o       = 1'b1;              // нужен rs2
    idu2exu_use_rd_o        = 1'b1;              // пишем rd
    idu2exu_cmd_o.ialu_op   = SCR1_IALU_OP_REG_REG;  // op1=rs1, op2=rs2
    idu2exu_cmd_o.rd_wb_sel = SCR1_RD_WB_IALU;   // rd = результат АЛУ
    case (funct7)
        7'b0000000 : case (funct3)
            3'b000 : idu2exu_cmd_o.ialu_cmd = SCR1_IALU_CMD_ADD;  // ← ADD
            ...
```
Номера регистров берутся из фиксированных полей R-типа выше по коду:
```systemverilog
idu2exu_cmd_o.rs1_addr = instr[19:15];
idu2exu_cmd_o.rs2_addr = instr[24:20];
idu2exu_cmd_o.rd_addr  = instr[11:7];
```

### Пример B — RVI `LW rd, imm(rs1)` (опкод LOAD, funct3=010)

```systemverilog
SCR1_OPCODE_LOAD : begin
    idu2exu_use_rs1_o       = 1'b1;
    idu2exu_use_rd_o        = 1'b1;
    idu2exu_use_imm_o       = 1'b1;
    idu2exu_cmd_o.sum2_op   = SCR1_SUM2_OP_REG_IMM;  // адрес = rs1 + imm
    idu2exu_cmd_o.rd_wb_sel = SCR1_RD_WB_LSU;        // rd = данные из памяти
    idu2exu_cmd_o.imm       = {{21{instr[31]}}, instr[30:20]};  // I-immediate, знаковое расширение
    case (funct3)
        3'b010 : idu2exu_cmd_o.lsu_cmd = SCR1_LSU_CMD_LW;  // ← LW
        ...
```
Видно, как декодер сам собирает immediate из разбросанных битов и знаково расширяет его.

### Пример C — RVI `BEQ rs1, rs2, offset` (опкод BRANCH, funct3=000)

```systemverilog
SCR1_OPCODE_BRANCH : begin
    idu2exu_use_rs1_o       = 1'b1;
    idu2exu_use_rs2_o       = 1'b1;
    idu2exu_cmd_o.imm       = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0}; // B-immediate
    idu2exu_cmd_o.branch_req = 1'b1;                 // это условный переход
    idu2exu_cmd_o.sum2_op   = SCR1_SUM2_OP_PC_IMM;   // цель = PC + imm
    idu2exu_cmd_o.ialu_op   = SCR1_IALU_OP_REG_REG;
    case (funct3)
        3'b000 : idu2exu_cmd_o.ialu_cmd = SCR1_IALU_CMD_SUB_EQ;  // условие rs1 == rs2
        ...
```
АЛУ здесь используется не для результата, а для **вычисления условия** (`SUB_EQ` = «равны ли»), а `branch_req` говорит EXU, что переход условный.

### Пример D — RVC `C.ADDI rd, imm` (квадрант 1, funct3=000)

Показывает, как из плотной 16-битной кодировки разворачивается обычная операция:

```systemverilog
SCR1_INSTR_RVC1 : begin
    idu2exu_cmd_o.instr_rvc = 1'b1;            // отмечаем: сжатая (PC += 2)
    ...
    case (funct3)
        3'b000 : begin
            // C.ADDI / C.NOP
            idu2exu_use_rs1_o       = 1'b1;
            idu2exu_cmd_o.ialu_cmd  = SCR1_IALU_CMD_ADD;
            idu2exu_cmd_o.ialu_op   = SCR1_IALU_OP_REG_IMM;   // rd = rs1 + imm
            idu2exu_cmd_o.rd_wb_sel = SCR1_RD_WB_IALU;
            idu2exu_cmd_o.rs1_addr  = instr[11:7];   // rs1 = rd (кодировка C.ADDI: rd/rs1 совпадают)
            idu2exu_cmd_o.rd_addr   = instr[11:7];
            idu2exu_cmd_o.imm       = {{27{instr[12]}}, instr[6:2]};  // 6-битный знаковый imm
        end
```

Смысл: **`C.ADDI` декодируется в ровно такую же команду для EXU, как обычная `ADDI`** — просто immediate и номера регистров собираются из других битов, а флаг `instr_rvc` подсказывает, что PC надо увеличить на 2, а не на 4. Сжатые команды «прозрачны» для EXU: он их не отличает от полных.

### Пример E — RVC `C.LWSP rd, imm(sp)` (квадрант 2, funct3=010)

Хороший пример «зашитого» регистра — базой всегда является `sp` (x2):

```systemverilog
SCR1_INSTR_RVC2 : begin
    ...
    3'b010 : begin
        // C.LWSP
        idu2exu_cmd_o.lsu_cmd   = SCR1_LSU_CMD_LW;
        idu2exu_cmd_o.rd_wb_sel = SCR1_RD_WB_LSU;
        idu2exu_cmd_o.rs1_addr  = SCR1_MPRF_SP_ADDR;   // база = sp (x2), зашито
        idu2exu_cmd_o.rd_addr   = instr[11:7];
        idu2exu_cmd_o.imm       = {24'd0, instr[3:2], instr[12], instr[6:4], 2'b00};
```

Константы «зашитых» регистров объявлены в начале модуля:
```systemverilog
localparam SCR1_MPRF_ZERO_ADDR = 5'd0;  // x0
localparam SCR1_MPRF_RA_ADDR   = 5'd1;  // ra (x1) — для C.JAL/C.JALR
localparam SCR1_MPRF_SP_ADDR   = 5'd2;  // sp (x2) — для стековых C.*SP
```

---

## 9. Обработка исключений и нелегальных инструкций

IDU — это место, где ловится сразу несколько типов исключений.

**Флаги нелегальности.** По ходу декодирования, если кодировка не соответствует ни одному валидному варианту, ветка `default` выставляет флаг:
```systemverilog
default : rvi_illegal = 1'b1;   // (аналогично rvc_illegal в ветках RVC)
```

**Явные системные исключения** формируются прямо в дешифраторе — например, `ECALL`/`EBREAK` в ветке `SYSTEM`:
```systemverilog
12'h000 : begin  // ECALL
    idu2exu_cmd_o.exc_req  = 1'b1;
    idu2exu_cmd_o.exc_code = SCR1_EXC_CODE_ECALL_M;
end
12'h001 : begin  // EBREAK
    idu2exu_cmd_o.exc_req  = 1'b1;
    idu2exu_cmd_o.exc_code = SCR1_EXC_CODE_BREAKPOINT;
end
```

**Финальная проверка нелегальности** стоит в самом конце `always_comb` и имеет наивысший приоритет — она «стирает» любую ранее собранную команду и превращает её в исключение `ILLEGAL_INSTR`:

```systemverilog
if (rvi_illegal
`ifdef SCR1_RVC_EXT
    | rvc_illegal
`endif
`ifdef SCR1_RVE_EXT
    | rve_illegal
`endif
   ) begin
    // всё аннулируем: никакого АЛУ/LSU/CSR/записи rd/переходов
    idu2exu_cmd_o.ialu_cmd   = SCR1_IALU_CMD_NONE;
    idu2exu_cmd_o.lsu_cmd    = SCR1_LSU_CMD_NONE;
    idu2exu_cmd_o.csr_cmd    = SCR1_CSR_CMD_NONE;
    idu2exu_cmd_o.rd_wb_sel  = SCR1_RD_WB_NONE;
    idu2exu_cmd_o.jump_req   = 1'b0;
    idu2exu_cmd_o.branch_req = 1'b0;
    ...
    idu2exu_cmd_o.exc_req    = 1'b1;
    idu2exu_cmd_o.exc_code   = SCR1_EXC_CODE_ILLEGAL_INSTR;
`ifdef SCR1_MTVAL_ILLEGAL_INSTR_EN
    idu2exu_cmd_o.imm        = instr;  // тело инструкции кладётся в imm — попадёт в mtval
`endif
end
```

Итого приоритет исключений в IDU: **imem access fault** (проверяется первым, отключает декодирование) → системные (`ECALL`/`EBREAK`/`misalign`) → **illegal instruction** (проверяется последним, перекрывает всё).

Три источника нелегальности:
- `rvi_illegal` — неверная RVI-кодировка;
- `rvc_illegal` — неверная RVC-кодировка (только при `SCR1_RVC_EXT`);
- `rve_illegal` — обращение к регистрам x16..x31 в конфигурации RV32E (только при `SCR1_RVE_EXT`); в нашей сборке RVE выключен, поэтому эти проверки скомпилированы «в ноль».

---

## 10. Ассершены (только в симуляции)

В самом конце модуля под `SCR1_TRGT_SIMULATION` — две проверки корректности:

```systemverilog
// На входах не должно быть X (неизвестных) на valid/ready
SCR1_SVA_IDU_XCHECK : assert property (
    @(negedge clk) disable iff (~rst_n)
    !$isunknown({ifu2idu_vd_i, exu2idu_rdy_i})
) else $error("IDU Error: unknown values");

// Команда АЛУ всегда в допустимом диапазоне enum
SCR1_SVA_IDU_IALU_CMD_RANGE : assert property (
    @(negedge clk) disable iff (~rst_n)
    (ifu2idu_vd_i & ~ifu2idu_imem_err_i) |->
    ((idu2exu_cmd_o.ialu_cmd >= SCR1_IALU_CMD_NONE) &
     (idu2exu_cmd_o.ialu_cmd <= SCR1_IALU_CMD_SRA /* или REMU при RVM */))
) else $error("IDU Error: IALU_CMD out of range");
```

Это те самые ассершены, ради которых в модуль и заведены `clk`/`rst_n`.

---

## 11. Сводная таблица сигналов

| Сигнал | Направление | Назначение |
|---|---|---|
| `ifu2idu_instr_i` | вход | 32-битное слово инструкции от IFU |
| `ifu2idu_vd_i` | вход | инструкция валидна |
| `ifu2idu_imem_err_i` | вход | ошибка доступа к памяти инструкций |
| `ifu2idu_err_rvi_hi_i` | вход | ошибка на старшей половине невыровненной RVI |
| `exu2idu_rdy_i` | вход | EXU готов принять команду |
| `idu2ifu_rdy_o` | выход | IDU готов принять слово (= готовности EXU) |
| `idu2exu_req_o` | выход | есть команда для EXU (= валидности от IFU) |
| `idu2exu_cmd_o` | выход | **декодированная команда** (`type_scr1_exu_cmd_s`) |
| `idu2exu_use_rs1_o/rs2_o` | выход | подсказка клок-гейтинга: нужны ли rs1/rs2 |
| `idu2exu_use_rd_o/imm_o` | выход | подсказка: нужны ли rd/immediate (есть при наличии стадии EXE) |

---

## 12. Итог одним абзацем

IDU в SCR1 — это **чисто комбинационный дешифратор без состояния**. Он берёт 32-битное слово от IFU, по двум младшим битам определяет тип (RVI или один из трёх квадрантов RVC), а затем большим вложенным `case`-ом раскладывает инструкцию в единую управляющую структуру `type_scr1_exu_cmd_s`: какую операцию делать в АЛУ, какие регистры читать, какой immediate использовать, откуда писать результат в `rd`, нужен ли переход/ветвление/обращение к памяти или CSR. Сжатые RVC-команды он «разворачивает» в те же команды, что и их 32-битные аналоги, так что EXU их не различает. Поверх этого IDU обрабатывает исключения (ошибка доступа к памяти, ECALL/EBREAK, нелегальная инструкция) и выдаёт подсказки для клок-гейтинга операндов. Готовность и запрос он просто пробрасывает между IFU и EXU, ничего не задерживая.
