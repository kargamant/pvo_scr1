#!/usr/bin/env python3
"""rvfi_compare.py - diff two RVFI-lite traces (DUT vs reference model) record by record.

Both traces are lines: RVFI <order> <pc> <pc_next> <rd_addr> <rd_wdata> <trap>
Reports the FIRST divergence (the exact retire where DUT and model disagree) with context.

Non-deterministic CSR reads (cycle/time/instret/mcycle/minstret + high halves) produce a
rd_wdata the model can't match, so their rd_wdata is MASKED: we load the program image and
decode the instruction at each pc; if it's a `csrr rd, <timing-csr>` we skip only rd_wdata
(pc/pc_next/rd_addr/trap are still checked).

Usage: rvfi_compare.py <dut.rvfi> <model.rvfi> [--image prog.hex] [--limit N]
"""
import sys, argparse, re

TIMING_CSR = {0xC00,0xC01,0xC02,0xC80,0xC81,0xC82,0xB00,0xB02,0xB80,0xB82}

def load_trace(fn):
    recs=[]
    for line in open(fn):
        i=line.find("RVFI ")
        if i<0: continue                 # tolerate a stray UART char prefixing the line
        p=line[i:].split()
        # order pc pc_next rd_addr rd_wdata trap [insn]
        insn = int(p[7],16) if len(p)>7 else None
        recs.append((int(p[1]), int(p[2],16), int(p[3],16), int(p[4]), int(p[5],16), int(p[6]), insn))
    return recs

def load_image(fn):
    if fn is None: return None
    mem=bytearray(1<<20); addr=0
    for tok in open(fn).read().split():
        if tok.startswith('@'): addr=int(tok[1:],16); continue
        if len(tok)==2:
            try: b=int(tok,16)
            except ValueError: continue
            if addr<len(mem): mem[addr]=b
            addr+=1
    return mem

def insn_at(mem,pc):
    if mem is None or pc+3>=len(mem): return None
    return mem[pc]|(mem[pc+1]<<8)|(mem[pc+2]<<16)|(mem[pc+3]<<24)

def is_timing_csr_read(insn):
    if insn is None: return False
    if (insn&0x7f)!=0x73: return False
    f3=(insn>>12)&7
    if f3==0: return False           # ecall/ebreak
    csr=(insn>>20)&0xfff
    return csr in TIMING_CSR

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("dut"); ap.add_argument("model")
    ap.add_argument("--image", default=None)
    ap.add_argument("--limit", type=int, default=0)
    a=ap.parse_args()
    D=load_trace(a.dut); M=load_trace(a.model); mem=load_image(a.image)
    n=min(len(D),len(M))
    if a.limit: n=min(n,a.limit)
    fields=["order","pc","pc_next","rd_addr","rd_wdata","trap"]
    mism=0
    for i in range(n):
        d=D[i]; m=M[i]
        # Prefer the executed instruction word from the model trace (post .data copy,
        # correct for LMA!=VMA); fall back to static-image decode only if absent.
        insn = m[6] if m[6] is not None else insn_at(mem,d[1])
        mask_rdd = is_timing_csr_read(insn)
        for k in range(6):
            if k==4 and mask_rdd: continue          # skip rd_wdata for timing-CSR reads
            if d[k]!=m[k]:
                print(f"MISMATCH at record {i} (DUT order={d[0]}):")
                print(f"  field '{fields[k]}':  DUT={d[k]:#x}  MODEL={m[k]:#x}")
                print(f"  DUT  : pc={d[1]:#010x} pc_next={d[2]:#010x} rd=x{d[3]} wdata={d[4]:#010x} trap={d[5]}")
                print(f"  MODEL: pc={m[1]:#010x} pc_next={m[2]:#010x} rd=x{m[3]} wdata={m[4]:#010x} trap={m[5]}")
                if insn is not None: print(f"  insn@pc = {insn:#010x}")
                # a little context
                lo=max(0,i-3)
                print("  --- preceding DUT records ---")
                for j in range(lo,i+1):
                    dj=D[j]; print(f"    [{j}] pc={dj[1]:#010x} ->{dj[2]:#010x} rd=x{dj[3]}={dj[4]:#010x} trap={dj[5]}")
                sys.exit(2)
    print(f"MATCH: {n} records identical (DUT={len(D)}, MODEL={len(M)}"
          + (", masked timing-CSR rd_wdata" if mem is not None else ", no image -> rd_wdata NOT masked") + ")")
    if len(D)!=len(M):
        print(f"NOTE: trace lengths differ (DUT {len(D)} vs MODEL {len(M)}); compared first {n}.")

if __name__=="__main__":
    main()
