#!/usr/bin/env python3
"""
Пересчитывает все таблицы отчёта bpred_testcode_20260728_REPORT.md
из CSV-выгрузки захвата ILA.

    python3 bpred_analyze.py bpred_testcode_20260728.csv

CSV получается из .ila так (Vivado 2019.1):
    write_hw_ila_data -force -csv_file out.csv [current_hw_ila_data]
либо просто распаковкой .ila (это zip) -> waveform.csv

Важно: сигналы pred/actual/mispred достоверны ТОЛЬКО в такты brretire=1.
Все подсчёты ниже отфильтрованы по этому условию.
"""
import csv, re, sys, collections

def load(path):
    rows = list(csv.reader(open(path)))
    hdr, data = rows[0], rows[2:]          # строка 1 — заголовки, строка 2 — радиксы
    return hdr, data

def col(hdr, sub):
    for i, c in enumerate(hdr):
        if sub in c:
            return i
    raise KeyError(sub)

def pc_decoder(hdr):
    """32-битный bp_dbg_pc синтезатор дробит на 13 кусков; собираем обратно."""
    frag = []
    for i, c in enumerate(hdr):
        if 'bp_dbg_pc' in c:
            m = re.search(r'\[(\d+):(\d+)\]$', c)
            if m:
                frag.append((i, int(m.group(1)), int(m.group(2))))
    def pc(r):
        v = 0
        for i, _hi, lo in frag:
            v |= int(r[i], 16) << lo
        return v
    return pc, sum(h - l + 1 for _, h, l in frag)

B3 = {0: "beq", 1: "bne", 4: "blt", 5: "bge", 6: "bltu", 7: "bgeu"}
X = ["zero","ra","sp","gp","tp","t0","t1","t2","s0","s1","a0","a1","a2","a3","a4","a5",
     "a6","a7","s2","s3","s4","s5","s6","s7","s8","s9","s10","s11","t3","t4","t5","t6"]

def sx(v, b):
    return v - (1 << b) if v >> (b - 1) else v

def decode(w):
    if (w & 3) != 3:
        return "(сжатая 16-бит)", None
    op = w & 0x7f
    if op == 0x63:
        f3, rs1, rs2 = (w >> 12) & 7, (w >> 15) & 31, (w >> 20) & 31
        imm = ((w >> 31) & 1) << 12 | ((w >> 7) & 1) << 11 | \
              ((w >> 25) & 0x3f) << 5 | ((w >> 8) & 0xf) << 1
        return f"{B3.get(f3,'b?')} {X[rs1]}, {X[rs2]}", sx(imm, 13)
    if op == 0x6f:
        imm = ((w >> 31) & 1) << 20 | ((w >> 12) & 0xff) << 12 | \
              ((w >> 20) & 1) << 11 | ((w >> 21) & 0x3ff) << 1
        return f"jal {X[(w>>7)&31]}", sx(imm, 21)
    if op == 0x67:
        return f"jalr {X[(w>>7)&31]}, {X[(w>>15)&31]}", None
    return f"op=0x{op:02x}", None

def main(path):
    hdr, data = load(path)
    pc, bits = pc_decoder(hdr)
    Ip, Ia = col(hdr, "bp_dbg_pred"), col(hdr, "bp_dbg_actual")
    Im, Ib = col(hdr, "bp_dbg_mispred"), col(hdr, "bp_dbg_brretire")
    Ir = col(hdr, "bp_dbg_redirect")
    Itr, Ita, Ird = col(hdr, "tcm_imem_req"), col(hdr, "tcm_imem_addr"), col(hdr, "tcm_imem_rdata")

    print(f"файл: {path}")
    print(f"тактов: {len(data)}   собрано бит PC: {bits} (должно быть 32)\n")

    br = [i for i, r in enumerate(data) if r[Ib] == '1']
    mis = [i for i in br if data[i][Im] == '1']
    print(f"ретайров переходов: {len(br)}   промахов: {len(mis)} "
          f"= {100*len(mis)/len(br):.2f}%\n")

    print("=== матрица исходов ===")
    m = collections.Counter((data[i][Ip], data[i][Ia]) for i in br)
    lab = {('1','1'):"верно taken", ('0','0'):"верно not-taken",
           ('1','0'):"ПРОМАХ: ждали taken", ('0','1'):"ПРОМАХ: ждали not-taken"}
    for k in sorted(m):
        print(f"  pred={k[0]} actual={k[1]}: {m[k]:5d}  {lab[k]}")

    # карта адрес -> слово команды; задержка выборки TCM = 1 такт
    imap = {}
    for i, r in enumerate(data):
        if r[Itr] == '1' and i + 1 < len(data):
            imap.setdefault(int(r[Ita], 16) * 4, int(data[i+1][Ird], 16))

    print("\n=== переходы: команда, индекс BHT, статистика ===")
    st = collections.defaultdict(lambda: {"n":0,"m":0,"t":0,"p1":0})
    for i in br:
        s = st[pc(data[i])]
        s["n"] += 1
        s["m"] += data[i][Im] == '1'
        s["t"] += data[i][Ia] == '1'
        s["p1"] += data[i][Ip] == '1'
    print(f"{'PC':>10} {'idx':>5} {'команда':<18} {'смещ':>6} {'напр':<6} "
          f"{'ретайр':>7} {'взято':>6} {'pred=1':>7} {'пром':>5}")
    print("-" * 82)
    idx_map = collections.defaultdict(list)
    for p in sorted(st, key=lambda k: -st[k]["n"]):
        s = st[p]
        ix = (p >> 1) & 0x3FF                      # индекс BHT = PC[10:1]
        idx_map[ix].append(p)
        w = imap.get(p)
        mn, imm = decode(w) if w is not None else ("(не выбрана)", None)
        d = "назад" if (imm is not None and imm < 0) else ("вперёд" if imm is not None else "-")
        print(f"0x{p:08x} {ix:5d} {mn:<18} {(f'{imm:+d}' if imm is not None else '-'):>6} "
              f"{d:<6} {s['n']:7d} {s['t']:6d} {s['p1']:7d} {s['m']:5d}")

    coll = {k: v for k, v in idx_map.items() if len(v) > 1}
    print("\n=== наложения индексов BHT ===")
    print("  нет — каждый переход занимает свою запись" if not coll else
          "\n".join(f"  индекс {k}: " + ", ".join(f"0x{x:08x}" for x in v)
                    for k, v in coll.items()))

    print("\n=== выборка команд вокруг каждого промаха (цена промаха) ===")
    for mm in mis:
        fs = [(i, int(data[i][Ita],16)*4) for i in range(max(0,mm-5), mm+5)
              if data[i][Itr] == '1']
        print(f"  такт {mm:5d} PC=0x{pc(data[mm]):08x} "
              f"pred={data[mm][Ip]} actual={data[mm][Ia]} redirect={data[mm][Ir]}")
        print("        " + " ".join(f"{c}:{a & 0xffff:04x}" for c, a in fs))

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "bpred_testcode_20260728.csv")
