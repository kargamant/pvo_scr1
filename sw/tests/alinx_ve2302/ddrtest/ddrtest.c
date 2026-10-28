// DDR data-integrity self-test for the SCR1 SoC on ALINX VD100 (Versal XCVE2302).
//
// Runs from TCM (link with tcm.ld) and exercises the external DDR window at 0x0 that
// the NoC maps to the hard DDRMC. Because the tester itself lives in TCM, the ENTIRE
// DDR range is free to write/verify. Confirms the SCR1 -> smartconnect -> NoC -> DDRMC
// -> DDR4 path actually stores and returns data (not just that calibration passed).
//
// Load via scbl over XMODEM to the TCM entry, then 'g' it. Output on UART @ 0xff010000.
//
// Build (from tests/ddrtest):
//   make CROSS_PREFIX=riscv64-unknown-elf- SYS_CLK=90000000 MEM=tcm OPT=2

#include <stdint.h>
#include "sc_print.h"
#include "uart.h"

// DDR window under test: base 0x0, length = the range the NoC maps (create_sopc.tcl
// assigns C0_DDR_LOW0 offset 0x0 range 0x08000000 = 128 MiB). Override with -DDDR_SIZE.
#ifndef DDR_BASE
#define DDR_BASE 0x00000000u
#endif
#ifndef DDR_SIZE
#define DDR_SIZE 0x08000000u   // 128 MiB
#endif
// Progress print granularity.
#define STEP     0x01000000u   // 16 MiB

static volatile uint32_t * const ddr = (volatile uint32_t *)DDR_BASE;
#define NWORDS (DDR_SIZE / 4u)

// One write-sweep + read/verify-sweep for a given pattern. `pat==0` selects the
// address-based pattern (each word holds its own byte address), `inv` inverts it.
// Returns the number of mismatches; records the first failing word.
static uint32_t sweep(uint32_t pat, int use_addr, int inv,
                      uint32_t *first_fail_idx, uint32_t *exp_out, uint32_t *got_out)
{
    uint32_t errors = 0;

    for (uint32_t i = 0; i < NWORDS; i++) {
        uint32_t v = use_addr ? (i * 4u + DDR_BASE) : pat;
        if (inv) v = ~v;
        ddr[i] = v;
    }
    for (uint32_t i = 0; i < NWORDS; i++) {
        uint32_t exp = use_addr ? (i * 4u + DDR_BASE) : pat;
        if (inv) exp = ~exp;
        uint32_t got = ddr[i];
        if (got != exp) {
            if (errors == 0) { *first_fail_idx = i; *exp_out = exp; *got_out = got; }
            errors++;
        }
        if ((i & (STEP/4u - 1u)) == 0)
            sc_printf("  ...verify @ 0x%x\r\n", i * 4u + DDR_BASE);
    }
    return errors;
}

int main(void)
{
    sc1f_uart_init();

    sc_printf("\r\n=== SCR1 VD100 DDR self-test ===\r\n");
    sc_printf("window: 0x%x .. 0x%x (%d MiB)\r\n",
              DDR_BASE, DDR_BASE + DDR_SIZE, DDR_SIZE >> 20);

    struct { const char *name; uint32_t pat; int use_addr; int inv; } passes[] = {
        { "address",      0,          1, 0 },
        { "~address",     0,          1, 1 },
        { "0xA5A5A5A5",   0xA5A5A5A5u, 0, 0 },
        { "0x5A5A5A5A",   0x5A5A5A5Au, 0, 0 },
        { "0xFFFFFFFF",   0xFFFFFFFFu, 0, 0 },
        { "0x00000000",   0x00000000u, 0, 0 },
    };

    uint32_t total_err = 0;
    for (unsigned p = 0; p < sizeof(passes)/sizeof(passes[0]); p++) {
        uint32_t fi = 0, exp = 0, got = 0;
        sc_printf("pass '%s' ...\r\n", passes[p].name);
        uint32_t e = sweep(passes[p].pat, passes[p].use_addr, passes[p].inv, &fi, &exp, &got);
        if (e) {
            sc_printf("  FAIL: %d mismatches; first @ 0x%x exp=0x%x got=0x%x\r\n",
                      e, fi * 4u + DDR_BASE, exp, got);
        } else {
            sc_printf("  ok\r\n");
        }
        total_err += e;
    }

    if (total_err == 0)
        sc_printf("=== DDR TEST PASSED ===\r\n");
    else
        sc_printf("=== DDR TEST FAILED: %d total mismatches ===\r\n", total_err);

    // Return to scbl (crt sets up ra); loop as a safety net.
    for (;;) { }
    return 0;
}
