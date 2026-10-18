/* ============================================================================
 * core_portme_fpga.c — CoreMark portability layer for FPGA HIL targets.
 *
 * Differences from coremark/port/core_portme.c (simulation version):
 *   - Timing is still measured via the mcycle CSR (hardware counter).
 *   - At the end portable_fini() EXPLICITLY prints the raw mcycle delta over
 *     UART so the host run_hil_bench.py script can parse it.
 *   - Output format (appended after CoreMark's own output):
 *       CYCLES:<decimal>\r\n
 *       ITERS:<decimal>\r\n
 * ============================================================================ */

#include "coremark.h"
#include "../../bench/common/mist_es_io.h"

/* The FPGA CoreMark build defines FPGA_HIL so this file is selected instead
 * of the standard port. */

/* Global timing state */
CORETIMETYPE start_time_val;
CORETIMETYPE stop_time_val;

/* Required by SEED_METHOD = SEED_VOLATILE in core_portme.h */
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

/* ---- CoreMark timing API ------------------------------------------------- */

void start_time(void)
{
    start_time_val = read_mcycle64();
}

void stop_time(void)
{
    stop_time_val = read_mcycle64();
}

CORETIMETYPE get_time(void)
{
    return stop_time_val - start_time_val;
}

secs_ret time_in_secs(CORETIMETYPE ticks)
{
    /* Return raw cycle count (CLOCKS_PER_SEC = 1).
     * CoreMark computes: score = ITERATIONS / time_in_secs(elapsed).
     * Multiply by target clock (MHz) to get CoreMark/MHz on the host. */
    return (secs_ret)ticks;
}

/* ---- Portable init / fini ------------------------------------------------ */

void portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc; (void)argv;
    p->portable_id = 0x4D495354u; /* 'MIST' */
}

void portable_fini(core_portable *p)
{
    (void)p;
    /* CoreMark already printed its summary via ee_printf → _write → UART.
     * Now append the raw machine-readable cycle count so the host script
     * can extract it without parsing the human-readable CoreMark output. */
    uint64_t elapsed = stop_time_val - start_time_val;

    /* Print:  CYCLES:<decimal>\r\n
     * (Cast to uint32_t because our ee_printf doesn't support 64-bit varargs,
     * which causes register misalignment on RV32 ILP32 and prints garbage.) */
    ee_printf("CYCLES:%u\r\n", (uint32_t)elapsed);
    ee_printf("ITERS:%d\r\n",   (int)ITERATIONS);
}

/* ---- main ---------------------------------------------------------------- */
extern int core_main(void);

#undef main
int main(void)
{
    int rc = core_main();   /* runs benchmark, prints results, calls portable_fini */

    /* Signal done to any attached debugger / sim harness */
    volatile uint32_t* tohost = (volatile uint32_t*)0x20000000UL;
    *tohost = (rc == 0) ? 1u : 2u;
    return rc;
}
