#include <stddef.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/types.h>

#define MBOX_BASE   0xFFFFE000u          /* PS sees this at 0x8010E000 */
#define MBOX_MAX    0x0F00u              /* 3840 bytes of text */
#define MBOX_DONE   0xD09ED09Eu
static volatile uint32_t *const mbox_len  = (volatile uint32_t*)(MBOX_BASE + 0x00);
static volatile uint32_t *const mbox_done = (volatile uint32_t*)(MBOX_BASE + 0x04);
static volatile uint8_t  *const mbox_txt  = (volatile uint8_t *)(MBOX_BASE + 0x08);

void mbox_init(void){ *mbox_len = 0; *mbox_done = 0; }
void mbox_finish(void){ *mbox_done = MBOX_DONE; }

extern char __heap_start;
extern char __STACK_START__;
static char *heap_end = &__heap_start;

int _write(int file, const void *buffer, size_t length){
    const char *d = (const char*)buffer; (void)file;
    uint32_t n = *mbox_len;
    for (size_t i=0;i<length;i++){ if(n<MBOX_MAX){ mbox_txt[n++]=(uint8_t)d[i]; } }
    *mbox_len = n;
    return (int)length;
}
void *_sbrk(ptrdiff_t incr){
    char *prev=heap_end; uintptr_t next=(uintptr_t)heap_end+(intptr_t)incr;
    if(incr>0 && next>=(uintptr_t)&__STACK_START__) return (void*)-1;
    heap_end=(char*)next; return prev;
}
int _read(int f,void*b,size_t l){(void)f;(void)b;(void)l;return 0;}
int _close(int f){(void)f;return -1;}
off_t _lseek(int f,off_t o,int w){(void)f;(void)o;(void)w;return 0;}
int _fstat(int f,struct stat*s){(void)f;s->st_mode=S_IFCHR;return 0;}
int _isatty(int f){(void)f;return 1;}
int _getpid(void){return 1;}
int _kill(int p,int s){(void)p;(void)s;return -1;}
void _exit(int st){(void)st; for(;;) __asm__ volatile("wfi");}

/* sc_print.c backend: route its low-level output into the mailbox too */
int putchar(int ch){ unsigned char c=(unsigned char)ch; _write(1,&c,1); return ch; }
void uart_puts(const char *s){ while(*s) putchar((unsigned char)*s++); }
void uart_init(void){}
void sc1f_uart_init(void){}
void sc1f_uart_putchar(int c){ putchar(c); }
void sc1f_uart_tx_flush(void){}
