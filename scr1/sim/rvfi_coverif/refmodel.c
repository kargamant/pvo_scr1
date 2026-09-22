/* refmodel.c - compact rv32im ISA reference model for SCR1 on-chip co-verification (Stage 2).
 *
 * Loads the SAME flat byte image the sim/board runs ($readmemh .hex or raw .bin), executes
 * rv32im from the reset vector, and emits ONE RVFI-lite record per retired instruction in the
 * EXACT format the DUT tb prints:
 *     RVFI <order> <pc> <pc_next> <rd_addr> <rd_wdata> <trap>
 * so the two streams can be diffed by rvfi_compare.py. Golden semantics; NO timing.
 *
 * Portable C (will later cross-compile -static for aarch64 to run on the PS, Stage 4).
 * Scope: RV32IM + Zicsr + Zifencei. Compressed (RVC) not decoded -> build the test ARCH=IM.
 * CSR reads return a modeled value; non-deterministic CSRs (cycle/time/instret) are the
 * comparator's job to mask (it decodes the insn at pc). We model minstret=order for stability.
 *
 * Usage: refmodel <image.hex|.bin> [--reset 0x200] [--max N] [--mem-bytes 65536]
 *   .hex = Verilog $readmemh byte image (@addr + 2-hex-digit bytes). .bin = raw @0.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

static uint8_t  *MEM;
static uint32_t  MEM_BYTES = 65536;
static uint32_t  x[32];

/* Optional CSR value injection: when a non-deterministic CSR (cycle/time/instret + m-/h-
 * variants) is read, use the DUT's rd_wdata for that retire order instead of a modeled 0.
 * This lets self-timing programs (dhrystone/coremark) co-verify: the timer value the DUT
 * observed flows into the model's data path identically. On-chip (Stage 4) the model
 * consumes the DUT RVFI stream from trace-BRAM, so the timer values come from there too. */
/* Full DUT record indexed by retire order (used for both CSR injection and --compare). */
typedef struct { uint32_t pc, pn, rda, rdd, tr; } dutrec_t;
static dutrec_t *dut   = NULL;
static long      dut_n = 0;
static int is_timing_csr(uint32_t csr){
    switch(csr){case 0xC00:case 0xC01:case 0xC02:case 0xC80:case 0xC81:case 0xC82:
                case 0xB00:case 0xB02:case 0xB80:case 0xB82: return 1; default: return 0;}
}
static void load_dut_trace(const char*fn){
    FILE*f=fopen(fn,"r"); if(!f){perror(fn);exit(1);}
    long cap=1<<20; dut=malloc(cap*sizeof(dutrec_t)); dut_n=0;
    char line[256];
    while(fgets(line,sizeof line,f)){
        char*p=strstr(line,"RVFI "); if(!p) continue;
        unsigned long long ord; unsigned pc,pn,rda,rdd,tr;
        if(sscanf(p,"RVFI %llu %x %x %u %x %u",&ord,&pc,&pn,&rda,&rdd,&tr)==6){
            while((long)ord>=cap){ cap*=2; dut=realloc(dut,cap*sizeof(dutrec_t)); }
            dut[ord]=(dutrec_t){pc,pn,rda,rdd,tr};
            if((long)ord+1>dut_n) dut_n=(long)ord+1;
        }
    }
    fclose(f);
}

static uint32_t ld32(uint32_t a){ a&=MEM_BYTES-1; return MEM[a]|(MEM[a+1]<<8)|(MEM[a+2]<<16)|((uint32_t)MEM[a+3]<<24);}
static uint16_t ld16(uint32_t a){ a&=MEM_BYTES-1; return MEM[a]|(MEM[a+1]<<8);}
static uint8_t  ld8 (uint32_t a){ a&=MEM_BYTES-1; return MEM[a];}
static void st32(uint32_t a,uint32_t v){a&=MEM_BYTES-1; MEM[a]=v; MEM[a+1]=v>>8; MEM[a+2]=v>>16; MEM[a+3]=v>>24;}
static void st16(uint32_t a,uint32_t v){a&=MEM_BYTES-1; MEM[a]=v; MEM[a+1]=v>>8;}
static void st8 (uint32_t a,uint32_t v){a&=MEM_BYTES-1; MEM[a]=v;}

/* load a Verilog $readmemh byte image: lines "@hexaddr" set the cursor, tokens are bytes. */
static void load_hex(const char*fn){
    FILE*f=fopen(fn,"r"); if(!f){perror(fn);exit(1);}
    char tok[64]; uint32_t addr=0;
    while(fscanf(f,"%63s",tok)==1){
        if(tok[0]=='@'){ addr=(uint32_t)strtoul(tok+1,0,16); continue; }
        if(tok[0]=='/'||tok[0]=='\0') continue;
        unsigned b=(unsigned)strtoul(tok,0,16);
        if(addr<MEM_BYTES) MEM[addr]=b&0xff;
        addr++;
    }
    fclose(f);
}
static void load_bin(const char*fn){
    FILE*f=fopen(fn,"rb"); if(!f){perror(fn);exit(1);}
    fread(MEM,1,MEM_BYTES,f); fclose(f);
}

static inline int32_t sext(uint32_t v,int b){ int32_t m=1<<(b-1); return (v^m)-m; }

/* ---- RVC (compressed) -> 32-bit expansion. Reuses the tested 32-bit executor. ------------
 * Returns the equivalent 32-bit instruction, or 0 (illegal -> trap) for unsupported/illegal.
 * Encoders match the executor's field extraction exactly. rv32imc integer subset. */
#define RTYPE(f7,r2,r1,f3,rd,op) (((f7)<<25)|((r2)<<20)|((r1)<<15)|((f3)<<12)|((rd)<<7)|(op))
#define ITYPE(im,r1,f3,rd,op)    ((((im)&0xfff)<<20)|((r1)<<15)|((f3)<<12)|((rd)<<7)|(op))
#define STYPE(im,r2,r1,f3,op)    (((((im)>>5)&0x7f)<<25)|((r2)<<20)|((r1)<<15)|((f3)<<12)|(((im)&0x1f)<<7)|(op))
#define UTYPE(im,rd,op)          (((im)&0xfffff000)|((rd)<<7)|(op))
#define BTYPE(im,r2,r1,f3,op)    ((((im)>>12&1)<<31)|(((im)>>5&0x3f)<<25)|((r2)<<20)|((r1)<<15)|((f3)<<12)|(((im)>>1&0xf)<<8)|(((im)>>11&1)<<7)|(op))
#define JTYPE(im,rd,op)          ((((im)>>20&1)<<31)|(((im)>>1&0x3ff)<<21)|(((im)>>11&1)<<20)|(((im)>>12&0xff)<<12)|((rd)<<7)|(op))

static uint32_t rvc_expand(uint16_t c){
    uint32_t op=c&3, f3=(c>>13)&7;
    uint32_t rdp=8+((c>>2)&7), r1p=8+((c>>7)&7), r2p=8+((c>>2)&7);
    uint32_t rd=(c>>7)&0x1f, r2=(c>>2)&0x1f;
    if(c==0) return 0;
    if(op==0){
        if(f3==0){ uint32_t im=((c>>7)&0x30)|((c>>1)&0x3c0)|((c>>4)&4)|((c>>2)&8);
                   return im? ITYPE(im,2,0,rdp,0x13):0; }                 /* C.ADDI4SPN */
        if(f3==2){ uint32_t im=((c>>7)&0x38)|((c<<1)&0x40)|((c>>4)&4);
                   return ITYPE(im,r1p,2,rdp,0x03); }                     /* C.LW  */
        if(f3==6){ uint32_t im=((c>>7)&0x38)|((c<<1)&0x40)|((c>>4)&4);
                   return STYPE(im,r2p,r1p,2,0x23); }                     /* C.SW  */
        return 0;
    }
    if(op==1){
        if(f3==0){ int32_t im=sext(((c>>7)&0x20)|((c>>2)&0x1f),6);
                   return ITYPE((uint32_t)im,rd,0,rd,0x13); }             /* C.ADDI/C.NOP */
        if(f3==1||f3==5){ uint32_t im=((c>>1)&0x800)|((c>>7)&0x10)|((c>>1)&0x300)|((c<<2)&0x400)
                                    |((c>>1)&0x40)|((c<<1)&0x80)|((c>>2)&0xe)|((c<<3)&0x20);
                   int32_t s=sext(im,12); return JTYPE((uint32_t)s, f3==1?1:0, 0x6f); } /* C.JAL/C.J */
        if(f3==2){ int32_t im=sext(((c>>7)&0x20)|((c>>2)&0x1f),6);
                   return ITYPE((uint32_t)im,0,0,rd,0x13); }              /* C.LI */
        if(f3==3){ if(rd==2){ int32_t im=sext(((c>>3)&0x200)|((c>>2)&0x10)|((c<<1)&0x40)|((c<<4)&0x180)|((c<<3)&0x20),10);
                              return ITYPE((uint32_t)im,2,0,2,0x13); }     /* C.ADDI16SP */
                   int32_t s=sext(((c<<5)&0x20000)|((c<<10)&0x1f000),18);
                   return UTYPE((uint32_t)s&0xfffff000,rd,0x37); }        /* C.LUI */
        if(f3==4){ uint32_t sub=(c>>10)&3, sh=(c>>2)&0x1f;
                   if(sub==0) return ITYPE(sh,r1p,5,r1p,0x13);            /* C.SRLI */
                   if(sub==1) return ITYPE(0x400|sh,r1p,5,r1p,0x13);      /* C.SRAI */
                   if(sub==2){ int32_t im=sext(((c>>7)&0x20)|((c>>2)&0x1f),6);
                               return ITYPE((uint32_t)im,r1p,7,r1p,0x13); }/* C.ANDI */
                   switch((c>>5)&3){                                      /* C.SUB/XOR/OR/AND */
                     case 0: return RTYPE(0x20,r2p,r1p,0,r1p,0x33);
                     case 1: return RTYPE(0,r2p,r1p,4,r1p,0x33);
                     case 2: return RTYPE(0,r2p,r1p,6,r1p,0x33);
                     default:return RTYPE(0,r2p,r1p,7,r1p,0x33); } }
        if(f3==6||f3==7){ uint32_t im=((c>>4)&0x100)|((c>>7)&0x18)|((c<<1)&0xc0)|((c>>2)&0x6)|((c<<3)&0x20);
                   int32_t s=sext(im,9); return BTYPE((uint32_t)s,0,r1p,f3==6?0:1,0x63); } /* C.BEQZ/BNEZ */
        return 0;
    }
    if(op==2){
        if(f3==0){ uint32_t sh=(c>>2)&0x1f; return ITYPE(sh,rd,1,rd,0x13); }   /* C.SLLI */
        if(f3==2){ uint32_t im=((c>>7)&0x20)|((c>>2)&0x1c)|((c<<4)&0xc0);
                   return ITYPE(im,2,2,rd,0x03); }                        /* C.LWSP */
        if(f3==4){ uint32_t b12=(c>>12)&1;
                   if(!b12){ if(r2==0) return ITYPE(0,rd,0,0,0x67);       /* C.JR   */
                             return RTYPE(0,r2,0,0,rd,0x33); }            /* C.MV   */
                   if(rd==0&&r2==0) return 0x00100073;                    /* C.EBREAK */
                   if(r2==0) return ITYPE(0,rd,0,1,0x67);                 /* C.JALR */
                   return RTYPE(0,r2,rd,0,rd,0x33); }                     /* C.ADD  */
        if(f3==6){ uint32_t im=((c>>7)&0x3c)|((c>>1)&0xc0);
                   return STYPE(im,r2,2,2,0x23); }                        /* C.SWSP */
        return 0;
    }
    return 0;
}

int main(int argc,char**argv){
    const char*img=0; uint32_t pc=0x200; long maxn=20000000;
    int compare_mode=0;   /* --compare: diff each retire vs the loaded DUT trace, in-C */
    for(int i=1;i<argc;i++){
        if(!strcmp(argv[i],"--reset")) pc=(uint32_t)strtoul(argv[++i],0,0);
        else if(!strcmp(argv[i],"--max")) maxn=strtol(argv[++i],0,0);
        else if(!strcmp(argv[i],"--mem-bytes")) MEM_BYTES=(uint32_t)strtoul(argv[++i],0,0);
        else if(!strcmp(argv[i],"--dut-trace")) load_dut_trace(argv[++i]);
        else if(!strcmp(argv[i],"--compare")){ load_dut_trace(argv[++i]); compare_mode=1; }
        else img=argv[i];
    }
    if(!img){fprintf(stderr,"usage: refmodel <image.hex|.bin> [--reset A] [--max N] [--mem-bytes B]\n"
                            "                [--dut-trace F] [--compare F]\n"
                            "  --compare F: load DUT RVFI trace F, inject its timer CSRs, and diff\n"
                            "               each retired instruction against it (self-contained, no python)\n");return 1;}
    MEM=calloc(MEM_BYTES,1); if(!MEM){perror("calloc");return 1;}
    size_t L=strlen(img);
    if(L>4 && !strcmp(img+L-4,".bin")) load_bin(img); else load_hex(img);

    uint64_t order=0;
    uint32_t prev_pc=~0u; int selfloop=0;
    for(long n=0;n<maxn;n++){
        uint32_t raw=ld16(pc), insn, ilen;
        if((raw&3)!=3){ insn=rvc_expand((uint16_t)raw); ilen=2; }  /* compressed -> expand */
        else          { insn=ld32(pc);                  ilen=4; }
        uint32_t opcode=insn&0x7f, rd=(insn>>7)&0x1f, f3=(insn>>12)&7, rs1=(insn>>15)&0x1f, rs2=(insn>>20)&0x1f, f7=(insn>>25)&0x7f;
        uint32_t a=x[rs1], b=x[rs2];
        uint32_t next=pc+ilen, wv=0; int wen=0, trap=0, mask_rdd=0;

        switch(opcode){
        case 0x37: wv=insn&0xfffff000; wen=1; break;                       /* LUI  */
        case 0x17: wv=pc+(insn&0xfffff000); wen=1; break;                  /* AUIPC*/
        case 0x6f:{ int32_t imm=(sext(((insn>>31)&1),1)<<20)|((insn&0xff000))|(((insn>>20)&1)<<11)|(((insn>>21)&0x3ff)<<1);
                    wv=pc+ilen; wen=1; next=pc+imm; } break;                  /* JAL  */
        case 0x67:{ int32_t imm=sext(insn>>20,12); wv=pc+ilen; wen=1; next=(a+imm)&~1u; } break; /* JALR */
        case 0x63:{ int32_t imm=(sext((insn>>31)&1,1)<<12)|(((insn>>7)&1)<<11)|(((insn>>25)&0x3f)<<5)|(((insn>>8)&0xf)<<1);
                    int t=0; switch(f3){case 0:t=a==b;break;case 1:t=a!=b;break;case 4:t=(int32_t)a<(int32_t)b;break;
                      case 5:t=(int32_t)a>=(int32_t)b;break;case 6:t=a<b;break;case 7:t=a>=b;break;}
                    if(t) next=pc+imm; } break;                            /* BRANCH */
        case 0x03:{ int32_t imm=sext(insn>>20,12); uint32_t ad=a+imm; wen=1;
                    switch(f3){case 0:wv=(int32_t)(int8_t)ld8(ad);break;case 1:wv=(int32_t)(int16_t)ld16(ad);break;
                      case 2:wv=ld32(ad);break;case 4:wv=ld8(ad);break;case 5:wv=ld16(ad);break;} } break; /* LOAD */
        case 0x23:{ int32_t imm=(sext(insn>>25,7)<<5)|((insn>>7)&0x1f); uint32_t ad=a+imm;
                    switch(f3){case 0:st8(ad,b);break;case 1:st16(ad,b);break;case 2:st32(ad,b);break;} } break; /* STORE */
        case 0x13:{ int32_t imm=sext(insn>>20,12); wen=1; uint32_t sh=insn>>20&0x1f;
                    switch(f3){case 0:wv=a+imm;break;case 2:wv=((int32_t)a<imm);break;case 3:wv=(a<(uint32_t)imm);break;
                      case 4:wv=a^imm;break;case 6:wv=a|imm;break;case 7:wv=a&imm;break;
                      case 1:wv=a<<sh;break;case 5:wv=(f7&0x20)?((int32_t)a>>sh):(a>>sh);break;} } break; /* OP-IMM */
        case 0x33:{ wen=1;
                    if(f7==1){ /* M-ext */
                      int64_t sa=(int32_t)a,sb=(int32_t)b; uint64_t ua=a,ub=b;
                      switch(f3){
                        case 0:wv=(uint32_t)(a*b);break;
                        case 1:wv=(uint32_t)(((int64_t)sa*sb)>>32);break;
                        case 2:wv=(uint32_t)(((int64_t)sa*(uint64_t)ub)>>32);break;
                        case 3:wv=(uint32_t)((ua*ub)>>32);break;
                        case 4:wv=(b==0)?0xffffffff:(uint32_t)((int32_t)a==(int32_t)0x80000000&&(int32_t)b==-1?0x80000000:sa/sb);break;
                        case 5:wv=(b==0)?0xffffffff:(uint32_t)(ua/ub);break;
                        case 6:wv=(b==0)?a:(uint32_t)((int32_t)a==(int32_t)0x80000000&&(int32_t)b==-1?0:sa%sb);break;
                        case 7:wv=(b==0)?a:(uint32_t)(ua%ub);break; }
                    } else { uint32_t sh=b&0x1f;
                      switch(f3){case 0:wv=(f7&0x20)?(a-b):(a+b);break;case 1:wv=a<<sh;break;
                        case 2:wv=((int32_t)a<(int32_t)b);break;case 3:wv=(a<b);break;case 4:wv=a^b;break;
                        case 5:wv=(f7&0x20)?((int32_t)a>>sh):(a>>sh);break;case 6:wv=a|b;break;case 7:wv=a&b;break;} }
                  } break;                                                 /* OP */
        case 0x0f: break;                                                  /* FENCE / FENCE.I -> nop */
        case 0x73:{ /* SYSTEM: CSR + ECALL/EBREAK */
                    if(f3==0){ trap=1; /* ecall/ebreak -> trap; test-end. keep next=pc+4 */ }
                    else { uint32_t csr=insn>>20; uint32_t old=0;
                       mask_rdd = is_timing_csr(csr);   /* rd_wdata non-deterministic -> don't diff it */
                       if(dut && is_timing_csr(csr) && (long)order<dut_n){
                           old=dut[order].rdd;                                 /* INJECT DUT timer value */
                       } else if(csr==0xB02||csr==0xC02) old=(uint32_t)order;   /* minstret/instret */
                       else if(csr==0xB82||csr==0xC82) old=(uint32_t)(order>>32);
                       else old=0;
                       uint32_t src=(f3&4)?rs1:a; /* immediate forms use rs1 field as uimm */
                       (void)src; /* CSR side-effects to state not modeled (fine for co-sim of GPR/PC) */
                       if(rd){ wv=old; wen=1; }
                    } } break;
        default: trap=1; break;                                           /* illegal */
        }

        if(rd==0) wen=0;               /* x0 never written */
        uint32_t rd_a = wen?rd:0;
        uint32_t rd_d = wen?wv:0;
        if(compare_mode){
            /* Self-contained diff against the DUT trace. Stop at the DUT's last record. */
            if((long)order>=dut_n) break;   /* matched the whole DUT trace */
            dutrec_t*d=&dut[order];
            int bad = d->pc!=pc || d->pn!=next || d->rda!=rd_a || d->tr!=(uint32_t)trap
                      || (!mask_rdd && d->rdd!=rd_d);
            if(bad){
                printf("MISMATCH at record %llu:\n",(unsigned long long)order);
                printf("  DUT  : pc=%08x pc_next=%08x rd=x%u wdata=%08x trap=%u\n",d->pc,d->pn,d->rda,d->rdd,d->tr);
                printf("  MODEL: pc=%08x pc_next=%08x rd=x%u wdata=%08x trap=%d%s\n",
                       pc,next,rd_a,rd_d,trap, mask_rdd?"  (wdata masked: timing CSR)":"");
                printf("  insn@pc = %08x\n",insn);
                free(MEM); return 2;
            }
        } else {
            /* 7th field = the executed instruction word (from runtime memory, post .data copy).
             * The comparator uses it to mask non-deterministic CSR reads (rdcycle/time/instret)
             * — the static image can't be decoded for copied code (LMA != VMA). */
            printf("RVFI %llu %08x %08x %u %08x %d %08x\n",(unsigned long long)order,pc,next,rd_a,rd_d,trap,insn);
        }
        if(wen) x[rd]=wv; x[0]=0;
        order++;

        /* stop conditions: ecall/illegal trap, or self-loop (test end spin) */
        if(trap) break;
        if(next==pc){ if(pc==prev_pc && ++selfloop>2) break; } else selfloop=0;
        prev_pc=pc; pc=next;
    }
    if(compare_mode)
        printf("MATCH: %lld records identical (DUT=%ld, timing-CSR rd_wdata masked)\n",
               (long long)order, dut_n);
    free(MEM);
    return 0;
}
