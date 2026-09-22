#include "coremark.h"
#include "core_portme.h"


#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#elif PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0;
volatile ee_s32 seed2_volatile = 0;
volatile ee_s32 seed3_volatile = 0x66;
#elif PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#else
#error "Select CoreMark run type"
#endif

volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

static CORETIMETYPE start_time_val;
static CORETIMETYPE stop_time_val;

ee_u32 default_num_contexts = 1;

static inline CORETIMETYPE barebones_clock(void)
{
    CORETIMETYPE value;
    __asm__ volatile ("csrr %0, 0xB00" : "=r"(value)); /* mcycle */
    return value;
}

void start_time(void)
{
    start_time_val = barebones_clock();
}

void stop_time(void)
{
    stop_time_val = barebones_clock();
}

CORE_TICKS get_time(void)
{
    return (CORE_TICKS)(stop_time_val - start_time_val);
}

secs_ret time_in_secs(CORE_TICKS ticks)
{
    return (secs_ret)(ticks / (CORE_TICKS)RTC_HZ);
}

extern void mbox_init(void);
void portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc;
    (void)argv;

    extern void mbox_init(void);
    mbox_init();                 /* reset mailbox BEFORE the first print (else banner is clipped) */

    ee_printf("CoreMark 1.0 for SCR1 FPGA\n");

    if (sizeof(ee_ptr_int) != sizeof(ee_u8 *))
    {
        ee_printf("ERROR: ee_ptr_int cannot hold a pointer\n");
    }

    if (sizeof(ee_u32) != 4)
    {
        ee_printf("ERROR: ee_u32 is not 32 bits\n");
    }

    p->portable_id = 1;
}

void portable_fini(core_portable *p)
{
    p->portable_id = 0;
    extern void mbox_finish(void); mbox_finish();
}
