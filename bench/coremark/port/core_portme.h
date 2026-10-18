/* ============================================================================
 * core_portme.h — CoreMark port header for MIST-ES bare-metal target.
 *
 * CoreMark requires this file to define timing types, iteration counts,
 * memory allocation strategy, and a handful of compile-time switches.
 * ============================================================================ */

#ifndef CORE_PORTME_H
#define CORE_PORTME_H

#include <stdint.h>
#include <stddef.h>

/* ---- Standard data types for CoreMark ------------------------------------ */
typedef uint8_t   ee_u8;
typedef uint16_t  ee_u16;
typedef uint32_t  ee_u32;
typedef int16_t   ee_s16;
typedef int32_t   ee_s32;
typedef uint32_t  ee_ptr_int;
typedef size_t    ee_size_t;

/* ---- Timing type ---------------------------------------------------------
 * We use the 64-bit mcycle counter as our timer tick.
 */
typedef uint64_t CORETIMETYPE;
#define CORE_TICKS CORETIMETYPE

/* Convert raw ticks to seconds for the CoreMark score formula.
 * We run in simulation so there is no real wall-clock second.
 * Return ticks / CLOCKS_PER_SEC where CLOCKS_PER_SEC = 1 → raw cycles.
 * The score printed will be in Iterations/Cycle, interpretable as
 * "CoreMark cycles per iteration" when inverted. */
typedef ee_u32 secs_ret;
#define CLOCKS_PER_SEC  ((CORETIMETYPE)1)

/* ---- Iteration count -----------------------------------------------------
 * Can be overridden at compile time: -DITERATIONS=N
 * Default: 1000 (sufficient for a valid CoreMark score in simulation). */
#ifndef ITERATIONS
#define ITERATIONS      1000
#endif

/* Force CoreMark to use our hardcoded iterations instead of auto-detecting */
#ifndef SEED_METHOD
#define SEED_METHOD     SEED_VOLATILE
#endif

/* ---- Memory allocation ---------------------------------------------------
 * MEM_STATIC: CoreMark uses statically-allocated arrays.
 * MEM_MALLOC: would require a heap (avoid — sbrk is fragile on tiny DRAM).
 */
#define MEM_METHOD      MEM_STATIC
#define MEM_LOCATION    "STATIC"
#define align_mem(x)    (void *)(4 + (((ee_ptr_int)(x) - 1) & ~3))

/* ---- Parallel / threading ------------------------------------------------ */
#define MULTITHREAD     1
#define default_num_contexts 1
#define USE_FORK        0
#define USE_PTHREAD     0
#define USE_SOCKET      0
#define MAIN_HAS_NOARGC 0
#define MAIN_HAS_NORETURN 0

/* ---- HW capability flags ------------------------------------------------- */
#define HAS_FLOAT       0   /* no FPU */
#define HAS_TIME_H      0   /* no OS */
#define USE_CLOCK       0
#define HAS_STDIO       0
#define HAS_PRINTF      1   /* we provide ee_printf in printf.c */

/* Rename core_main.c's main to core_main so we can wrap it */
#define main core_main

int printf(const char *fmt, ...);
int ee_printf(const char *fmt, ...);

/* ---- Compiler flags shown in results banner ------------------------------ */
#ifndef COMPILER_FLAGS
#define COMPILER_FLAGS  "-O2 -march=rv32imc_zicsr -mabi=ilp32"
#endif
#ifndef COMPILER_VERSION
#define COMPILER_VERSION "riscv-gcc"
#endif

/* ---- Portable data structure --------------------------------------------- */
typedef struct {
    uint32_t portable_id;
} core_portable;

/* ---- Prototypes ---------------------------------------------------------- */
void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);

#endif /* CORE_PORTME_H */
