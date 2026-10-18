/* ============================================================================
 * syscalls_fpga.c — Minimal runtime stubs for FPGA Hardware-in-the-Loop targets.
 *
 * Key difference from bench/common/syscalls.c:
 *   _write() routes stdout/stderr to the real UART at 0x1000_0000 (TX register)
 *   instead of the tohost side-channel.  This makes printf() output appear on
 *   the host's serial terminal at 115200 baud.
 *
 * UART register map (mist_es_uart.sv):
 *   0x10000000 R : status  — bit0 = tx_busy
 *   0x10000000 W : TX data byte
 * ============================================================================ */

#include <stdint.h>
#include <stddef.h>

/* Provided by linker script */
extern char _end[];

/* ---- MMIO addresses ------------------------------------------------------- */
#define UART_BASE    0x10000000UL
#define TOHOST_ADDR  0x20000000UL

/* Inline UART TX: poll tx_busy then write byte */
static inline void uart_putchar(char c)
{
    volatile uint32_t* uart = (volatile uint32_t*)UART_BASE;
    while (uart[0] & 1u)  /* bit0 = tx_busy */
        ;
    uart[0] = (uint8_t)c;
}

/* ---- _write --------------------------------------------------------------- */
/* Routes all stdout/stderr through the MMIO UART so printf output appears
 * on the host serial terminal (picocom / pyserial). */
int _write(int fd, const char* buf, int len)
{
    (void)fd;
    for (int i = 0; i < len; i++)
        uart_putchar(buf[i]);
    return len;
}

/* ---- _sbrk ---------------------------------------------------------------- */
void* _sbrk(ptrdiff_t incr)
{
    static char* heap_end = 0;
    if (!heap_end) heap_end = _end;
    char* prev = heap_end;
    heap_end += incr;
    return (void*)prev;
}

/* ---- string.h implementations ----------------------------------------------- */
void* memset(void* s, int c, size_t n) {
    unsigned char* p = (unsigned char*)s;
    while (n--) *p++ = (unsigned char)c;
    return s;
}

void* memcpy(void* dest, const void* src, size_t n) {
    unsigned char* d = (unsigned char*)dest;
    const unsigned char* s = (const unsigned char*)src;
    while (n--) *d++ = *s++;
    return dest;
}

void* memmove(void* dest, const void* src, size_t n) {
    unsigned char* d = (unsigned char*)dest;
    const unsigned char* s = (const unsigned char*)src;
    if (d < s) {
        while (n--) *d++ = *s++;
    } else if (d > s) {
        d += n; s += n;
        while (n--) *--d = *--s;
    }
    return dest;
}

int memcmp(const void* s1, const void* s2, size_t n) {
    const unsigned char* p1 = (const unsigned char*)s1;
    const unsigned char* p2 = (const unsigned char*)s2;
    while (n--) {
        if (*p1 != *p2) return *p1 - *p2;
        p1++; p2++;
    }
    return 0;
}

size_t strlen(const char* s) {
    size_t len = 0;
    while (*s++) len++;
    return len;
}

char* strcpy(char* dest, const char* src) {
    char* d = dest;
    while ((*d++ = *src++));
    return dest;
}

int strcmp(const char* s1, const char* s2) {
    while (*s1 && (*s1 == *s2)) { s1++; s2++; }
    return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}

char* strchr(const char* s, int c) {
    while (*s) {
        if (*s == (char)c) return (char*)s;
        s++;
    }
    if (c == '\0') return (char*)s;
    return 0;
}

long sqrt(long x) {
    if (x <= 1) return x;
    long res = 0;
    long bit = 1L << 30;
    while (bit > x) bit >>= 2;
    while (bit != 0) {
        if (x >= res + bit) { x -= res + bit; res = (res >> 1) + bit; }
        else res >>= 1;
        bit >>= 2;
    }
    return res;
}

/* ---- stubs that return harmless defaults ---------------------------------- */
int _read(int fd, char* buf, int len) { (void)fd; (void)buf; (void)len; return -1; }
int _close(int fd)                    { (void)fd; return -1; }
int _fstat(int fd, void* st)          { (void)fd; (void)st; return -1; }
int _isatty(int fd)                   { (void)fd; return 1;  }
int _lseek(int fd, int off, int w)    { (void)fd; (void)off; (void)w; return -1; }
int _kill(int pid, int sig)           { (void)pid; (void)sig; return -1; }
int _getpid(void)                     { return 1; }
