# SCR1 caches

Кэши инструкций и данных для SCR1 в проекте Nexys 4 DDR. Wrapper устанавливается
между ядром и роутерами памяти; попадания обслуживаются локально, а промахи и
некэшируемые обращения передаются в TCM, таймер или AXI.

## Возможности

- direct-mapped, blocking;
- строка 16 байт: 4 слова по 32 бита;
- последовательный fill всей строки;
- синхронные одномерные массивы с `ram_style = "block"`;
- I-cache: 2048 строк, 32 КиБ;
- D-cache: 1024 строки, 16 КиБ;
- D-cache: write-through, no-write-allocate, byte-enable для частичных stores;
- bypass для TCM, boot BRAM и MMIO;
- invalidate I-cache и flush D-cache.

## Файлы

| Файл | Назначение |
|---|---|
| [`scr1_icache.sv`](./scr1_icache.sv) | Кэш инструкций |
| [`scr1_dcache.sv`](./scr1_dcache.sv) | Кэш данных |
| [`scr1_cache_wrapper.sv`](./scr1_cache_wrapper.sv) | Общая обёртка и соединение интерфейсов |
| [`CACHE_IMPLEMENTATION_RU.md`](./CACHE_IMPLEMENTATION_RU.md) | Подробное описание архитектуры, FSM и сигналов |

Интеграция выполнена в
[`scr1_top_axi.sv`](../../../../../scr1/src/top/scr1_top_axi.sv), а файлы включены
в [`nexys4ddr_scr1.xpr`](../../nexys4ddr_scr1/nexys4ddr_scr1.xpr).

## Текущая конфигурация

| Кэш | Строк | Размер строки | Ёмкость данных | Cacheable |
|---|---:|---:|---:|---|
| I-cache | 2048 | 16 байт | 32 КиБ | DDR2 `0x0000_0000–0x07FF_FFFF` |
| D-cache | 1024 | 16 байт | 16 КиБ | DDR2 `0x0000_0000–0x07FF_FFFF` |

```systemverilog
.ICACHE_BRAM_ADDR_MASK     ('0),
.ICACHE_BRAM_ADDR_PATTERN  (32'hFFFF_0000), // второе правило отключено
.ICACHE_DDR_ADDR_MASK      (32'hF800_0000),
.ICACHE_DDR_ADDR_PATTERN   ('0),
.DCACHE_ADDR_MASK          (32'hF800_0000),
.DCACHE_ADDR_PATTERN       (32'h0000_0000)
```

Нулевая маска и ненулевой pattern отключают дополнительное правило I-cache:
`(addr & 0) == 0xFFFF_0000` всегда ложно. MMIO нельзя добавлять в cacheable
диапазон D-cache.

## Политики

I-cache принимает только чтения. При miss он последовательно загружает четыре
слова и выставляет valid только после полного fill.

D-cache обслуживает load hit локально. Каждый store отправляется нижней памяти;
после успешного store hit cached copy обновляется через byte-enable. Store miss
не загружает строку.

Массивы data/tag не сбрасываются — reset очищает valid-биты. В текущем
`scr1_top_axi` входы runtime invalidate/flush подключены к `1'b0`, поэтому
обслуживание кэшей доступно только внутри модулей, но пока не управляется ядром.

## Проверка

После synthesis проверьте в utilization hierarchy, что `data_mem` обоих кэшей
использует Block RAM, а в журнале нет сообщения о реализации массива в
registers из-за нескольких write ports.

Тестбенч [`scr1_cache_blocks_tb.sv`](../../tb/cache/scr1_cache_blocks_tb.sv)
пока использует старые имена параметров I-cache и требует актуализации перед
следующим запуском симуляции.

## Ограничения

- один запрос одновременно;
- четыре одиночных чтения на fill, без burst и early restart;
- нет ассоциативности, prefetch и write buffer;
- нет аппаратной когерентности I-cache/D-cache/DMA;
- runtime invalidate/flush не подключены в top.

## Версии  

### Cache_1.0  
> Данная версия кэша является базовой, именно ей соответствует описание, приведённое ранее  
> Следующие версии будут иметь различные улучшения в дополнении к базовой  
> В списке версии с разными размерами кэшей, архитектурно одинаковы  
- i1k_d1k  
- i16k_d1k  
- i32k_d1k  
- i1k_d4k  
- i1k_d16k  
- i32k_d16k  
  
## Бенчмарки  

Результаты бенчмарков представлены в [таблице](https://docs.google.com/spreadsheets/d/1Z09Oc5KWd_BYFXryHQR0jsfkYbIVZM1zehx1FCA-16o/edit?usp=sharing)  