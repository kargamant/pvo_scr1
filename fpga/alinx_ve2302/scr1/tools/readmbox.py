#!/usr/bin/env python3
"""
readmbox.py - HOST helper: read the SCR1 mailbox (boot-BRAM @0xFFFF E000 -> PS 0x8010E000)
over the /dev/ttyUSB0 console and print the full text report. Use this to re-read the last
run's output if scr1run.py truncated the tail (the CRC lines), or any time to re-check.

Layout: 0x8010E000 = len (bytes), 0x8010E004 = done (0xD09ED09E when finished), 0x8010E008.. = text.
Board must be at a root shell on the serial port. Requires busybox devmem on the board.

Usage: readmbox.py [--port /dev/ttyUSB0]
"""
import os, time, select, termios, re, argparse
import termios as T

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="/dev/ttyUSB0")
    ap.add_argument("--mbox", default="0x8010E000")
    a = ap.parse_args()
    base = int(a.mbox, 16)

    fd = os.open(a.port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    t = termios.tcgetattr(fd)
    t[2] = T.CS8 | T.CLOCAL | T.CREAD; t[0]=0; t[1]=0; t[3]=0; t[4]=T.B115200; t[5]=T.B115200
    termios.tcsetattr(fd, T.TCSANOW, t)
    def w(s): os.write(fd, s.encode()); time.sleep(0.15)
    def rd(sec):
        b=b""; t0=time.time()
        while time.time()-t0<sec:
            if select.select([fd],[],[],0.2)[0]:
                try: b+=os.read(fd,8192)
                except OSError: pass
        return b.decode(errors="replace")

    while select.select([fd],[],[],0.3)[0]: os.read(fd,8192)
    w("stty -echo\n"); rd(0.5)
    # read len + done
    w(f"printf 'DONE='; devmem {hex(base+4)}; printf 'LEN='; devmem {hex(base)}\n")
    hdr = rd(2)
    done = "0xD09ED09E" in hdr.upper()
    m = re.search(r'LEN=0x([0-9A-Fa-f]+)', hdr)
    ln = int(m.group(1),16) if m else 512
    ln = min(max(ln,4), 8192)
    nround = (ln + 3) & ~3
    # dump text words
    w(f"i=0; while [ $i -lt {nround} ]; do devmem $(({hex(base+8)}+$i)); i=$((i+4)); done\n")
    raw = rd(max(6, nround/200)); os.close(fd)
    words = re.findall(r'0x([0-9A-Fa-f]{8})', raw)
    b = bytearray()
    for wd in words:
        v=int(wd,16); b += bytes([v&0xff,(v>>8)&0xff,(v>>16)&0xff,(v>>24)&0xff])
    txt = b[:ln].split(b'\x00',1)[0].decode(errors='replace')
    print(f"[mbox] done={'YES' if done else 'no'} len={ln}")
    print("="*60); print(txt); print("="*60)

if __name__ == "__main__":
    main()
