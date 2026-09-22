#!/usr/bin/env python3
"""rvfi_ship.py - one-time transfer of the Stage-4 self-hosted co-verification payload to the
board over the serial console (base32, md5-checked), same proven mechanism as scr1run.py.

Ships into /tmp on the board (minimal PetaLinux rootfs, no gcc/scp): the static aarch64
binaries (rvfi_dump, refmodel), the on-board runner (rvfi_verify.sh, scr1load.sh), and the
test image. After this, the WHOLE co-verification runs on the PS:
    ./scr1load.sh <img> --run           # load+run the test into the SCR1 (fills trace BRAM)
    ./rvfi_verify.sh <img> <reset> <mem> # dump trace + diff vs ISA model -> PASS/FAIL

Usage:
  rvfi_ship.py [--port /dev/ttyUSB0] [--dest /tmp] [FILE ...]
  Default FILE set = the Stage-4 payload (binaries + scripts + cm_bram.bin).

Binaries are ~0.6 MB -> base32 ~1 MB over 115200 baud, a few minutes each. One-time.
"""
import os, sys, time, select, termios, base64, hashlib, argparse, textwrap

# tools/ is .../pvo_scr1/fpga/alinx_ve2302/scr1/tools -> up 4 to pvo_scr1, then scr1/sim/rvfi_coverif
COVDIR = os.path.normpath(os.path.join(os.path.dirname(__file__),
                                       "..", "..", "..", "..", "scr1", "sim", "rvfi_coverif"))

DEFAULT_PAYLOAD = [
    os.path.join(COVDIR, "aarch64", "rvfi_dump"),
    os.path.join(COVDIR, "aarch64", "refmodel"),
    os.path.join(os.path.dirname(__file__), "rvfi_verify.sh"),
    os.path.join(os.path.dirname(__file__), "scr1load.sh"),
    os.path.join(COVDIR, "cm_bram.bin"),
]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="/dev/ttyUSB0")
    ap.add_argument("--dest", default="/tmp")
    ap.add_argument("files", nargs="*")
    a = ap.parse_args()
    files = a.files or DEFAULT_PAYLOAD

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

    for path in files:
        if not os.path.isfile(path):
            print(f"[host] SKIP missing {path}"); continue
        data = open(path, "rb").read()
        md5  = hashlib.md5(data).hexdigest()
        name = os.path.basename(path)
        dst  = f"{a.dest}/{name}"
        b32  = "\n".join(textwrap.wrap(base64.b32encode(data).decode(), 76))
        execbit = os.access(path, os.X_OK) or name.endswith((".sh",)) or "." not in name
        print(f"[host] {name}: {len(data)} B (md5 {md5}) -> {dst}")
        w(f"cat > {dst}.b32\n"); time.sleep(0.3)
        w(b32 + "\n"); time.sleep(0.3); w("\x04"); time.sleep(0.6); rd(2)
        w(f"base32 -d {dst}.b32 > {dst}; rm {dst}.b32; md5sum {dst}\n")
        r = rd(6)
        if md5 not in r:
            print("[host] MD5 MISMATCH! board said:", r.strip().splitlines()[-2:]); os.close(fd); sys.exit(1)
        if execbit: w(f"chmod +x {dst}\n"); rd(0.5)
        print(f"[host]   md5 OK{' +x' if execbit else ''}")

    w("stty sane\n"); os.close(fd)
    print("[host] payload shipped. On the board:")
    print("  cd /tmp && ./scr1load.sh cm_bram.bin --run   # (fills trace BRAM)")
    print("  ./rvfi_verify.sh cm_bram.bin 0xFFFFFF00 65536 # dump + compare -> PASS/FAIL")

if __name__ == "__main__":
    main()
