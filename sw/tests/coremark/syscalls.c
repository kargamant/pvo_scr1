#include <stddef.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/types.h>

#include "uart.h"

extern char __heap_start;
extern char __STACK_START__;

static char *heap_end = &__heap_start;

void *_sbrk(ptrdiff_t increment)
{
    char *previous = heap_end;
    uintptr_t next = (uintptr_t)heap_end + (intptr_t)increment;

    if ((increment > 0) && (next >= (uintptr_t)&__STACK_START__))
    {
        return (void *)-1;
    }

    heap_end = (char *)next;
    return previous;
}

int _write(int file, const void *buffer, size_t length)
{
    const char *data = (const char *)buffer;
    size_t i;

    (void)file;

    for (i = 0; i < length; ++i)
    {
        sc1f_uart_putchar((unsigned char)data[i]);
    }

    return (int)length;
}

int _read(int file, void *buffer, size_t length)
{
    (void)file;
    (void)buffer;
    (void)length;
    return 0;
}

int _close(int file)
{
    (void)file;
    return -1;
}

off_t _lseek(int file, off_t offset, int whence)
{
    (void)file;
    (void)offset;
    (void)whence;
    return 0;
}

int _fstat(int file, struct stat *status)
{
    (void)file;
    status->st_mode = S_IFCHR;
    return 0;
}

int _isatty(int file)
{
    (void)file;
    return 1;
}

int _getpid(void)
{
    return 1;
}

int _kill(int pid, int signal)
{
    (void)pid;
    (void)signal;
    return -1;
}

void _exit(int status)
{
    (void)status;

    for (;;)
    {
        __asm__ volatile ("wfi");
    }
}
