/* ============================================================================
 * mist_es_io.h — Hardware I/O macros for MIST-ES bare-metal benchmarks.
 *
 * CSR addresses used:
 *   0xB00  mcycle   — machine-mode cycle counter low 32 bits
 *   0xB80  mcycleh  — machine-mode cycle counter high 32 bits
 * ============================================================================ */

#ifndef MIST_ES_IO_H
#define MIST_ES_IO_H

#include <stdint.h>

/* ---- tohost ---------------------------------------------------------------- */
#define TOHOST_ADDR  0x20000000UL

static inline void write_tohost(uint32_t val)
{
    volatile uint32_t* p = (volatile uint32_t*)TOHOST_ADDR;
    *p = val;
}

/* ---- 64-bit cycle counter ------------------------------------------------- */
/* Read mcycle / mcycleh with mid-rollover protection. */
static inline uint64_t read_mcycle64(void) {
    uint32_t lo, hi, hi_check;
    do {
        __asm__ volatile ("csrr %0, mcycleh" : "=r" (hi));
        __asm__ volatile ("csrr %0, mcycle"  : "=r" (lo));
        __asm__ volatile ("csrr %0, mcycleh" : "=r" (hi_check));
    } while (hi != hi_check);
    return ((uint64_t)hi << 32) | lo;
}

static inline uint32_t read_mcycle(void)
{
    uint32_t v;
    __asm__ volatile ("csrrs %0, 0xC00, zero" : "=r"(v)); /* cycle */
    return v;
}

/* ---- side-channel cycle report (used by the CoreMark port) ---------------- */
/*
 * Reports a 60-bit cycle count via two tohost writes before the final PASS:
 *   tohost = 0xC0000000 | upper_30_bits   (marker = 2'b11)
 *   tohost = 0x80000000 | lower_30_bits   (marker = 2'b10)
 * The Verilator harness reconstructs the 64-bit value.
 */
static inline void report_cycles(uint64_t cycles)
{
    uint32_t hi = (uint32_t)(cycles >> 30) & 0x3FFFFFFFu;
    uint32_t lo = (uint32_t)(cycles)       & 0x3FFFFFFFu;
    write_tohost(0xC0000000u | hi);
    write_tohost(0x80000000u | lo);
}

#endif /* MIST_ES_IO_H */
