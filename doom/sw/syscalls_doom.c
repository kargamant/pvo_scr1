// ============================================================================
// syscalls_doom.c -- bare-metal libc + POSIX glue for DOOM on SCR1 (DDR build).
//   * picolibc stdio streams (stdin/stdout/stderr) -> UART
//   * heap over DDR (sbrk)
//   * in-memory file layer: DOOM's open()/read()/lseek() on the IWAD are served
//     from the WAD blob embedded by wad_blob.S (doom_wad/doom_wad_end).
//   * filesystem write ops (config/savegame) are accepted and discarded.
// picolibc calls the POSIX names (open/read/write/lseek/close/sbrk), not the
// newlib "_"-prefixed ones.
// ============================================================================
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/types.h>
#include "uart.h"

extern char __heap_start;
extern char __STACK_START__;

extern const unsigned char doom_wad[]     __attribute__((weak));
extern const unsigned char doom_wad_end[] __attribute__((weak));

// ---------------------------------------------------------- stdio -> UART ----
static int dg_putc(char c, FILE *f) { (void)f; sc1f_uart_putchar((unsigned char)c); return c; }
static int dg_getc(FILE *f)         { (void)f; return EOF; }
static FILE __uart = FDEV_SETUP_STREAM(dg_putc, dg_getc, NULL, _FDEV_SETUP_RW);
FILE *const stdin  = &__uart;
FILE *const stdout = &__uart;
FILE *const stderr = &__uart;

// ---------------------------------------------------------------- heap -------
void *sbrk(ptrdiff_t incr) {
    static char *heap = &__heap_start;
    char *prev = heap;
    uintptr_t next = (uintptr_t)heap + (intptr_t)incr;
    if (incr > 0 && next >= (uintptr_t)&__STACK_START__) { errno = ENOMEM; return (void *)-1; }
    heap = (char *)next;
    return prev;
}

// ------------------------------------------------ in-memory file table -------
#define FD_BASE 3
#define MAXF    8
static struct { int used, is_wad, discard; size_t pos, size; } ft[MAXF];

static size_t wad_size(void) {
    return (&doom_wad && &doom_wad_end) ? (size_t)(doom_wad_end - doom_wad) : 0;
}
static int fidx(int fd) { int i = fd - FD_BASE; return (i >= 0 && i < MAXF && ft[i].used) ? i : -1; }

int open(const char *name, int flags, ...) {
    int wr = (flags & (O_WRONLY | O_RDWR | O_CREAT)) != 0;
    for (int i = 0; i < MAXF; i++) if (!ft[i].used) {
        ft[i].used = 1; ft[i].pos = 0; ft[i].discard = 0; ft[i].is_wad = 0;
        if (wr) { ft[i].discard = 1; ft[i].size = 0; return FD_BASE + i; }
        if (strstr(name, ".wad") || strstr(name, ".WAD")) {
            if (wad_size() == 0) { ft[i].used = 0; errno = ENOENT; return -1; }
            ft[i].is_wad = 1; ft[i].size = wad_size(); return FD_BASE + i;
        }
        ft[i].used = 0; errno = ENOENT; return -1;
    }
    errno = EMFILE; return -1;
}

ssize_t read(int fd, void *buf, size_t len) {
    int i = fidx(fd);
    if (i < 0 || ft[i].discard) return 0;
    if (ft[i].is_wad) {
        size_t rem = ft[i].size - ft[i].pos, n = len < rem ? len : rem;
        memcpy(buf, doom_wad + ft[i].pos, n);
        ft[i].pos += n;
        return (ssize_t)n;
    }
    return 0;
}

ssize_t write(int fd, const void *buf, size_t len) {
    if (fd == 1 || fd == 2) {
        const char *d = (const char *)buf;
        for (size_t i = 0; i < len; i++) sc1f_uart_putchar((unsigned char)d[i]);
    }
    return (ssize_t)len;   // files (fd>=3) discarded
}

off_t lseek(int fd, off_t off, int whence) {
    int i = fidx(fd);
    if (i < 0) return 0;
    size_t base = (whence == SEEK_CUR) ? ft[i].pos : (whence == SEEK_END) ? ft[i].size : 0;
    ft[i].pos = base + off;
    return (off_t)ft[i].pos;
}

int close(int fd) { int i = fidx(fd); if (i < 0) return (fd <= 2) ? 0 : -1; ft[i].used = 0; return 0; }

int fstat(int fd, struct stat *st) {
    int i = fidx(fd);
    if (i >= 0) { st->st_mode = S_IFREG; st->st_size = (off_t)ft[i].size; return 0; }
    st->st_mode = S_IFCHR; return 0;
}
int isatty(int fd) { return (fd >= 0 && fd <= 2); }

// filesystem ops DOOM calls for config/savegames -- accept & no-op
int unlink(const char *p)            { (void)p; return 0; }
int rename(const char *a, const char *b) { (void)a; (void)b; return 0; }
int mkdir(const char *p, mode_t m)   { (void)p; (void)m; return 0; }

void _exit(int s) { (void)s; for (;;) __asm__ volatile ("wfi"); }
int  getpid(void) { return 1; }
int  kill(int p, int s) { (void)p; (void)s; errno = EINVAL; return -1; }

// ---------------------------------------------- excluded backends: stubs -----
void I_InitJoystick(void)          {}
void I_ShutdownJoystick(void)      {}
void I_UpdateJoystick(void)        {}
void I_BindJoystickVariables(void) {}
