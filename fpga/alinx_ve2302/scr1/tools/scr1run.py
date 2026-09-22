#!/usr/bin/env python3
"""
scr1run.py - HOST driver: run a bare-metal image on the SCR1 (in PL) from the PS/Linux
console, end to end. Transfers the image to the board over the serial console (base32,
md5-checked), pushes scr1load.sh, loads it into the SCR1 boot BRAM, releases reset, and
prints the SCR1's mailbox output.

Requires: the board running the COMBINED VD100 image (PetaLinux + our SCR1 + PS bridge)
with a root console on the given serial port. The board busybox has base32/md5sum/od/devmem.

Usage:
  scr1run.py <image.bin> [--port /dev/ttyUSB0] [--load 0x80100000] [--no-run]
  <image.bin> = bare-metal image linked at 0xFFFF0000 (see tests/coremark_bram/bram.ld).

This is the one-command wrapper for the manual devmem/base32 procedure proven on HW.
"""
import os, sys, time, select, termios, base64, hashlib, argparse, textwrap

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--port", default="/dev/ttyUSB0")
    ap.add_argument("--load", default="0x80100000")
    ap.add_argument("--no-run", action="store_true")
    ap.add_argument("--ddr", action="store_true",
                    help="load into reserved DDR (0x70000000, dd/fast) via scr1load_ddr.sh; "
                         "image must be linked with tests/ddr_common/ddr70.ld")
    ap.add_argument("--tcm", action="store_true",
                    help="benchmark from internal single-cycle TCM (0xF0000000) via scr1load_tcm.sh: "
                         "image staged in boot BRAM, a copy-stub relocates it into TCM then jumps; "
                         "image must be linked with tests/tcm_common/tcm.ld")
    a = ap.parse_args()

    img = open(a.image, "rb").read()
    # pad to 4 for od word alignment
    img += b"\x00" * ((-len(img)) % 4)
    md5 = hashlib.md5(img).hexdigest()
    b32 = "\n".join(textwrap.wrap(base64.b32encode(img).decode(), 76))
    loader = "scr1load_tcm.sh" if a.tcm else "scr1load_ddr.sh" if a.ddr else "scr1load.sh"
    loadsh = open(os.path.join(os.path.dirname(__file__), loader)).read()

    fd = os.open(a.port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    t = termios.tcgetattr(fd)
    import termios as T
    t[2] = T.CS8 | T.CLOCAL | T.CREAD; t[0]=0; t[1]=0; t[3]=0; t[4]=T.B115200; t[5]=T.B115200
    termios.tcsetattr(fd, T.TCSANOW, t)

    def w(s):
        b = s.encode() if isinstance(s, str) else s
        i = 0
        while i < len(b):
            os.write(fd, b[i:i+256]); i += 256; time.sleep(0.05)
    def rd(sec):
        buf = b""; t0 = time.time()
        while time.time()-t0 < sec:
            if select.select([fd], [], [], 0.2)[0]:
                try: buf += os.read(fd, 8192)
                except OSError: pass
        return buf.decode(errors="replace")

    time.sleep(0.2)
    while select.select([fd], [], [], 0.3)[0]: os.read(fd, 8192)
    w("stty -echo\n"); rd(0.5)

    print(f"[host] transferring {len(img)} B (md5 {md5}) via base32 ...")
    w("cat > /tmp/scr1_img.b32\n"); time.sleep(0.3)
    w(b32 + "\n"); time.sleep(0.3); w("\x04"); time.sleep(0.5)
    r = rd(3)
    w("base32 -d /tmp/scr1_img.b32 > /tmp/scr1_img.bin; md5sum /tmp/scr1_img.bin\n")
    r = rd(4)
    if md5 not in r:
        print("[host] MD5 MISMATCH on board! got:", r.strip().splitlines()[-2:]); os.close(fd); sys.exit(1)
    print("[host] md5 OK on board")

    print(f"[host] pushing {loader} ...")
    w(f"cat > /tmp/{loader}\n"); time.sleep(0.3)
    w(loadsh + "\n"); time.sleep(0.3); w("\x04"); time.sleep(0.5); rd(1)

    run_flags = "" if a.no_run else "--run --mbox"
    if a.ddr or a.tcm:
        cmd = f"sh /tmp/{loader} /tmp/scr1_img.bin {run_flags}"          # DDR/TCM loaders: no LOAD_PHYS override
    else:
        cmd = f"LOAD_PHYS={a.load} sh /tmp/{loader} /tmp/scr1_img.bin {run_flags}"  # BRAM: devmem loop
    print(f"[host] running: {cmd}")
    w(cmd + "\n")
    done = "[tcm] done" if a.tcm else "[ddr] done" if a.ddr else "[scr1load] done"
    out = ""; t0 = time.time()
    while time.time()-t0 < 300:
        out += rd(3)
        if done in out: break
    w("stty sane\n")
    os.close(fd)
    print("=" * 60)
    print(out)
    print("=" * 60)

if __name__ == "__main__":
    main()
