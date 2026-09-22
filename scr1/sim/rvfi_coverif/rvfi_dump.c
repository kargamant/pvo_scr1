/* rvfi_dump.c - on-chip RVFI trace dumper (Stage 4, runs on the PS/aarch64).
 *
 * Reads the SCR1 RVFI capture buffer straight out of PL memory via mmap(/dev/mem) - orders
 * of magnitude faster than the per-word `devmem` console loop used to bring Stage 3 up - and
 * prints it in the EXACT RVFI-lite text format the model/comparator consume:
 *     RVFI <order> <pc> <pc_next> <rd_addr> <rd_wdata> <trap>
 *
 * PL memory map (see fpga/.../tcl/create_sopc_ps.tcl, RVFI_EN=1):
 *   0x80300000  trace BRAM, 8192 x 128-bit records (16 B each, 128 KiB window)
 *               word0=[31:0]pc  word1=[63:32]pc_next  word2=[95:64]rd_wdata
 *               word3: [4:0]=rd_addr  [5]=trap        (matches scr1_rvfi_lite.sv)
 *   0x80400000  axi_gpio, data reg @off 0 = record count (saturates at 8192 = capture full)
 *
 * Build (native on the PS if it had gcc, or cross for the minimal rootfs):
 *   aarch64-linux-gnu-gcc -O2 -static -o rvfi_dump rvfi_dump.c
 * Run on the board:
 *   ./rvfi_dump                 # dump all captured records to stdout
 *   ./rvfi_dump -n 1000         # first 1000 only
 *   ./rvfi_dump -o hw.rvfi      # to a file
 *   ./rvfi_dump -c              # print just the record count and exit
 *
 * Pure observation: only reads PL memory, never writes. Overridable bases via -t/-g for a
 * different address map.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>

#define TRACE_BASE_DEF 0x80300000UL   /* trace BRAM  */
#define GPIO_BASE_DEF  0x80400000UL   /* record-count axi_gpio */
#define TRACE_WIN      0x20000UL      /* 128 KiB = 8192 * 16 B  */
#define GPIO_WIN       0x1000UL
#define MAX_RECS       8192

static void *map_phys(int fd, unsigned long base, unsigned long len)
{
    void *p = mmap(NULL, len, PROT_READ, MAP_SHARED, fd, (off_t)base);
    if (p == MAP_FAILED) { perror("mmap"); exit(1); }
    return p;
}

int main(int argc, char **argv)
{
    unsigned long trace_base = TRACE_BASE_DEF, gpio_base = GPIO_BASE_DEF;
    long limit = 0;            /* 0 = all captured */
    int count_only = 0;
    const char *outfn = NULL;

    for (int i = 1; i < argc; i++) {
        if      (!strcmp(argv[i], "-n") && i+1 < argc) limit = strtol(argv[++i], 0, 0);
        else if (!strcmp(argv[i], "-o") && i+1 < argc) outfn = argv[++i];
        else if (!strcmp(argv[i], "-t") && i+1 < argc) trace_base = strtoul(argv[++i], 0, 0);
        else if (!strcmp(argv[i], "-g") && i+1 < argc) gpio_base  = strtoul(argv[++i], 0, 0);
        else if (!strcmp(argv[i], "-c")) count_only = 1;
        else { fprintf(stderr, "usage: %s [-n N] [-o file] [-c] [-t trace_base] [-g gpio_base]\n", argv[0]); return 2; }
    }

    int fd = open("/dev/mem", O_RDONLY | O_SYNC);
    if (fd < 0) { perror("/dev/mem (run as root)"); return 1; }

    volatile uint32_t *gpio  = map_phys(fd, gpio_base,  GPIO_WIN);
    uint32_t count = gpio[0];
    if (count > MAX_RECS) count = MAX_RECS;   /* saturates when capture is full */

    if (count_only) { printf("%u\n", count); return 0; }

    volatile uint32_t *trace = map_phys(fd, trace_base, TRACE_WIN);

    long n = count;
    if (limit && limit < n) n = limit;

    FILE *out = outfn ? fopen(outfn, "w") : stdout;
    if (!out) { perror(outfn); return 1; }

    for (long i = 0; i < n; i++) {
        volatile uint32_t *r = &trace[i * 4];
        uint32_t pc      = r[0];
        uint32_t pc_next = r[1];
        uint32_t rd_wdata= r[2];
        uint32_t w3      = r[3];
        unsigned rd_addr = w3 & 0x1f;
        unsigned trap    = (w3 >> 5) & 1;
        fprintf(out, "RVFI %ld %08x %08x %u %08x %u\n",
                i, pc, pc_next, rd_addr, rd_wdata, trap);
    }
    if (outfn) { fclose(out); fprintf(stderr, "wrote %ld records to %s (count=%u)\n", n, outfn, count); }
    return 0;
}
