# Bake-in-BRAM: как зашить загрузчик прямо в boot-BRAM (VD100 / Versal)

Способ БЕЗ PetaLinux/PS: образ (scbl или любой тест) вшивается в boot-BRAM
на этапе синтеза и уже лежит в памяти к моменту программирования PDI.
SCR1 стартует с reset-вектора и исполняет его сразу. Проверка — по ILA.

Все пути ниже — от корня `fpga/alinx_ve2302/scr1/`.

## Файлы, которые для этого нужны

| Файл | Назначение |
|---|---|
| `mem/scbl.mem` | образ в «нормальном» виде (word-array, `@addr` + слова) |
| `mem/scbl_le.mem` | **байт-свопнутый** образ — ЭТО его и зашиваем |
| `tcl/patch_boot_bram.sh` | патчит сгенерённый враппер BRAM, чтобы init-файл не сбросился в NONE |
| `tcl/build_patched.tcl` | пере-синт враппера + impl → write_device_image (PDI), с проверкой что init не сбит |
| `tcl/program_pdi.tcl` | заливка готового PDI на плату по JTAG |
| `tcl/create_project.tcl`, `tcl/create_sopc.tcl` | базовый проект/BD (SCR1 в PL, без PS) — с них создаётся build/ |

Готовый PDI после сборки:
`build/alinx_ve2302_scr1/alinx_ve2302_scr1.runs/impl_1/alinx_ve2302_scr1.pdi`

## Две Versal-специфичные засады (из-за них всё и городилось)

1. **Init-файл сбрасывается в NONE.** boot-BRAM — это `emb_mem_gen` (XPM), init
   применяется через `$readmemh` на СИНТЕЗЕ. При `generate_target` пропагация
   параметров `axi_bram_ctrl → emb_mem_gen` (BD 41-2180) ПРИНУДИТЕЛЬНО ставит
   `C_MEMORY_INIT_FILE = "NONE"` в сгенерённом враппере — даже если ты выставил
   его `set_property` на ячейке BD. `set_property` чинит только `.xci`, а
   синт-враппер `.v` всё равно говорит NONE → BRAM пустая → CPU ловит trap на 0x0.
   **Единственный способ, который держится:** править сгенерённый враппер `.v`
   напрямую и пере-синтить OOC-ран БЕЗ регенерации BD. Этим занимается
   `patch_boot_bram.sh`.

2. **Порядок байт.** `emb_mem_gen $readmemh` читает значение слова как есть, а CPU
   читает то же слово как инструкцию → little-endian инструкции надо
   пред-свопнуть. Поэтому зашивается `scbl_le.mem`, а не `scbl.mem`.
   Проверка свопа: в `scbl.mem` слово `3f3f0000`, в `scbl_le.mem` оно же `00003f3f`.

> `updatemem`/`bootgen` пост-фактум на Versal — ТУПИК: PLM Major Error 0x223e,
> DONE не поднимается. Только пере-синтез.

## ⚠️ Перед первым запуском: поправить зашитые пути в скриптах

Скрипты пока содержат абсолютный путь моей машины `/home/toast/pvo_scr1`.
Замени его на свой путь до `pvo_scr1` в трёх файлах:

- `tcl/patch_boot_bram.sh` — переменная `ORIGIN=...`
- `tcl/build_patched.tcl` — переменная `set proj .../build/alinx_ve2302_scr1`
- `tcl/program_pdi.tcl` — `set_property PROGRAM.FILE .../impl_1/alinx_ve2302_scr1.pdi`

Одной командой из корня `pvo_scr1` (подставит твой текущий путь):
```bash
cd pvo_scr1
grep -rl '/home/toast/pvo_scr1' fpga/alinx_ve2302/scr1/tcl \
  | xargs sed -i "s#/home/toast/pvo_scr1#$PWD#g"
```

## Порядок действий (с нуля)

```bash
cd pvo_scr1/fpga/alinx_ve2302/scr1

# 0) единожды: создать проект (SCR1-в-PL, без PS), сгенерить BD-таргеты,
#    чтобы появился синт-враппер emb_mem_gen. (если build/ уже есть — пропусти)
LC_ALL=C vivado -mode batch -source tcl/create_project.tcl

# 1) пропатчить сгенерённый враппер BRAM нашим байт-свопнутым образом
#    (по умолчанию берёт mem/scbl_le.mem)
./tcl/patch_boot_bram.sh
#    -> печатает "PATCHED: ... .C_MEMORY_INIT_FILE("...scbl_le.mem")"

# 2) пере-синт враппера + impl + write_device_image (PDI).
#    Скрипт САМ проверяет OOC-лог: если init снова стал NONE — прервётся
#    с "INIT_CLOBBERED" ДО impl. Если ок — "INIT_OK: emb_mem_gen loaded ...".
LC_ALL=C vivado -mode batch -source tcl/build_patched.tcl
#    -> в конце "BUILD_DONE", рядом лежит .ltx (probes для ILA)

# 3) залить PDI на плату (JTAG, USB1)
LC_ALL=C vivado -mode batch -source tcl/program_pdi.tcl
#    -> "PROG_DONE"
```

## Зашить СВОЙ тест вместо scbl

1. Собери тест под reset-вектор boot-BRAM (ORIGIN `0xFFFF0000`, reset vector
   `0xFFFFFF00`, MTVEC `0xFFFFFF80`), objcopy → бинарь.
2. Сконвертируй в word-array `.mem` и **байт-свопни** каждое слово (как `scbl_le.mem`).
   Быстрый своп готового `.mem` (нормальный → LE):
   ```bash
   python3 - <<'PY'
   import re
   out=[]
   for l in open('mem/mytest.mem'):
       l=l.strip()
       if l.startswith('@') or not l: out.append(l); continue
       w=int(l,16); out.append(f"{((w&0xff)<<24)|((w>>8&0xff)<<16)|((w>>16&0xff)<<8)|(w>>24):08x}")
   open('mem/mytest_le.mem','w').write('\n'.join(out)+'\n')
   PY
   ```
3. Патчь этим образом и собирай:
   ```bash
   ./tcl/patch_boot_bram.sh "$PWD/mem/mytest_le.mem"   # patch_boot_bram.sh ждёт абсолютный путь
   LC_ALL=C vivado -mode batch -source tcl/build_patched.tcl
   LC_ALL=C vivado -mode batch -source tcl/program_pdi.tcl
   ```

## Проверка исполнения — по ILA 

После заливки открой hw_manager, подгрузи `.ltx`, поставь триггер на выборку из
boot-BRAM и смотри, что core реально фетчит с reset-вектора и уходит в код,
а не крутится на trap/0x0. Именно так мы эмпирически подтвердили, что образ
в памяти и SCR1 стартует.

