/* ============================================================================
 * syscalls.c — Minimal newlib/libnosys stubs for MIST-ES bare-metal targets.
 *
 * _write    → routes stdout/stderr through a character-by-character tohost
 *             side channel (the harness ignores these, but CoreMark uses
 *             ee_printf which eventually calls write).
 * _sbrk     → bump allocator using _end symbol (heap in DRAM).
 * _exit     → write code to tohost and spin.
 * Others    → return -ENOSYS / sensible defaults.
 * ============================================================================ */


#include <stdint.h>
#include <stddef.h>

/* Provided by linker script */
extern char _end[];

/* ---- _write ---------------------------------------------------------------
 * Each character is written as its ASCII value ORed with a 0x5C00_0000 marker
 * so the harness can distinguish it from cycle-count side-channels and tohost
 * pass/fail codes.  The harness currently ignores these writes (they are for
 * debugging / waveform inspection only).
 */
#define TOHOST_ADDR  0x20000000UL
#define CHAR_MARKER  0x5C000000UL

int _write(int fd, const char* buf, int len)
{
    (void)fd;
#if defined(FPGA_UART)
    // FPGA hardware UART is memory-mapped at 0x10000000
    volatile uint32_t* uart = (volatile uint32_t*)0x10000000;
    for (int i = 0; i < len; i++) {
        // Simple blocking write (assumes UART TX is fast enough or has a FIFO)
        *uart = (unsigned char)buf[i];
    }
#else
    volatile uint32_t* tohost = (volatile uint32_t*)TOHOST_ADDR;
    for (int i = 0; i < len; i++)
        *tohost = (uint32_t)(CHAR_MARKER | (unsigned char)buf[i]);
#endif
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
        d += n;
        s += n;
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
    while ((*d++ = *src++)) ;
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
    long bit = 1L << 30; // 32-bit long
    while (bit > x) bit >>= 2;
    while (bit != 0) {
        if (x >= res + bit) {
            x -= res + bit;
            res = (res >> 1) + bit;
        } else {
            res >>= 1;
        }
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
