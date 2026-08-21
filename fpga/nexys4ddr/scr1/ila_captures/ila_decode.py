#!/usr/bin/env python3
"""
Разбор CSV-захвата ILA (SCR1 на Nexys A7).

Использование:
    python3 ila_decode.py session_full_run.csv            # журнал событий
    python3 ila_decode.py session_full_run.csv --console  # восстановить вывод UART
    python3 ila_decode.py keypress_136us.csv --timing     # тайминги и латентности

Карта памяти платы:
    00000000-07FFFFFF  DDR
    F0000000-F001FFFF  TCM        (внутри ядра -> НА ШИНЕ НЕ ВИДЕН)
    F0040000-F0040FFF  MTimer
    FF000000-FF0FFFFF  MMIO (UART на FF010000)
    FFFF0000-FFFFFFFF  On-Chip RAM (здесь живёт загрузчик)
"""
import csv, sys
from collections import Counter

UART_RBR_THR = "ff010000"   # чтение = принятый байт, запись = байт на экран
UART_IER     = "ff010004"
UART_LSR     = "ff010014"   # бит0 (DR): 1 = есть принятый байт


def load(path):
    rows = list(csv.reader(open(path)))
    hdr, data = rows[0], rows[2:]      # строка 1 = имена, строка 2 = radix
    idx = {}
    for i, n in enumerate(hdr):
        idx[n.strip().split('[')[0]] = i
    return idx, data


def get(row, idx, name, default="0"):
    i = idx.get(name)
    return row[i].strip() if i is not None else default


def region(addr):
    a = int(addr, 16)
    if a < 0x08000000:                     return "DDR"
    if 0xF0000000 <= a <= 0xF001FFFF:      return "TCM"
    if 0xF0040000 <= a <= 0xF0040FFF:      return "MTimer"
    if 0xFF000000 <= a <= 0xFF0FFFFF:      return "MMIO/UART"
    if a >= 0xFFFF0000:                    return "On-Chip RAM"
    return "?"


def ascii_of(word):
    b = int(word, 16) & 0xFF
    if 32 <= b < 127: return f"'{chr(b)}'"
    return {0x06: "ACK", 0x08: "BS", 0x0A: "LF", 0x0D: "CR",
            0x15: "NAK", 0x20: "SPACE", 0x04: "Ctrl-D"}.get(b, f"0x{b:02x}")


def events(idx, data):
    """Список (такт, тип, адрес, данные). Адрес берётся на AR/AW, данные на R/W."""
    rd_addr = [(int(get(r, idx, "Sample in Window")), get(r, idx, "axi_dmem_araddr"))
               for r in data if get(r, idx, "axi_dmem_arvalid") == "1"]
    rd_data = [(int(get(r, idx, "Sample in Window")), get(r, idx, "axi_dmem_rdata"))
               for r in data if get(r, idx, "axi_dmem_rvalid") == "1"]
    ev = []
    for s, a in rd_addr:                       # данные приходят ПОЗЖЕ адреса
        nxt = [(sr, w) for sr, w in rd_data if sr > s]
        ev.append((s, "RD", a, nxt[0][1] if nxt else "?"))
    for r in data:
        if get(r, idx, "axi_dmem_awvalid") == "1":
            ev.append((int(get(r, idx, "Sample in Window")), "WR",
                       get(r, idx, "axi_dmem_awaddr"), get(r, idx, "axi_dmem_wdata")))
    ev.sort()
    return ev


def explain(op, addr, word):
    if addr == UART_LSR and op == "RD":
        v = int(word, 16)
        return "UART LSR: БАЙТ ЕСТЬ" if v & 1 else "UART LSR: пусто (холостой опрос)"
    if addr == UART_RBR_THR:
        return (f"UART RBR: принят {ascii_of(word)}" if op == "RD"
                else f"UART THR: на экран {ascii_of(word)}")
    if addr == UART_IER:  return "UART IER: настройка прерываний"
    r = region(addr)
    return f"{r}: {'чтение' if op=='RD' else 'запись'} данных {ascii_of(word)}"


def cmd_log(idx, data, skip_polls=True):
    print(" такт | оп |  адрес   | данные   | смысл")
    print("------+----+----------+----------+------------------------------")
    polls = 0
    for s, op, a, w in events(idx, data):
        if skip_polls and op == "RD" and a == UART_LSR and (int(w, 16) & 1) == 0:
            polls += 1
            continue
        if polls:
            print(f"      |    |          |          | ... {polls} холостых опросов LSR")
            polls = 0
        print(f" {s:5d}|{op:^4s}| {a} | {w} | {explain(op, a, w)}")
    if polls:
        print(f"      |    |          |          | ... {polls} холостых опросов LSR")


def cmd_console(idx, data):
    out = []
    for r in data:
        if get(r, idx, "axi_dmem_awvalid") == "1" and get(r, idx, "axi_dmem_awaddr") == UART_RBR_THR:
            b = int(get(r, idx, "axi_dmem_wdata"), 16) & 0xFF
            out.append(chr(b) if 32 <= b < 127 else ("\n" if b in (10, 13) else ""))
    print("".join(out))


def cmd_timing(idx, data):
    fetch = [int(get(r, idx, "Sample in Window"))
             for r in data if get(r, idx, "axi_imem_arvalid") == "1"]
    if len(fetch) > 1:
        gaps = Counter(fetch[i+1] - fetch[i] for i in range(len(fetch)-1))
        print("Интервалы между выборками imem (тактов: сколько раз):")
        for g, n in sorted(gaps.items())[:8]:
            print(f"   {g:4d} : x{n}")
    ar = [(int(get(r, idx, "Sample in Window")), get(r, idx, "axi_dmem_araddr"))
          for r in data if get(r, idx, "axi_dmem_arvalid") == "1"]
    rv = [int(get(r, idx, "Sample in Window"))
          for r in data if get(r, idx, "axi_dmem_rvalid") == "1"]
    print("\nЛатентность чтения (AR -> R):")
    for s, a in ar[:8]:
        nxt = [x for x in rv if x > s]
        if nxt:
            print(f"   {a} ({region(a):12s}) : {nxt[0]-s} тактов")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    idx, data = load(sys.argv[1])
    mode = sys.argv[2] if len(sys.argv) > 2 else "--log"
    print(f"# {sys.argv[1]}: {len(data)} сэмплов\n")
    if   mode == "--console": cmd_console(idx, data)
    elif mode == "--timing":  cmd_timing(idx, data)
    else:                     cmd_log(idx, data)
