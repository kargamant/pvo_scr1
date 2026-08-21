#!/usr/bin/env python3
"""Drive the SCR1 bootloader over UART: XMODEM-load snake.bin into TCM and run.
Waits for the bootloader menu (trigger it by (re)configuring the FPGA), then
loads @0xF0000000 and starts @0xF0000200. Prints captured UART output."""
import sys, time, os
os.environ["TERM"] = "vt100"   # minicom (curses) exits without a usable TERM
os.environ.setdefault("LC_ALL", "C")
sys.path.insert(0, "/home/toast/scr1_sber/minicom_mcp")
from minicom_session import MinicomSession

BIN   = "/home/toast/scr1_sber/snake/sw/build/snake.bin"
LOAD  = "0xF0000000"
START = "0xF0000200"

s = MinicomSession(device="/dev/ttyUSB1", baud=115200)
print("[drv] starting minicom session...", flush=True)
print("[drv] start:", s.start().__dict__, flush=True)

print("[drv] waiting for bootloader menu (reprogram/reset the FPGA now)...", flush=True)
r = s.wait_for_bootloader_menu(timeout=90)
print("[drv] menu:", r.success, repr(r.output[-200:] if r.output else ""), flush=True)
if not r.success:
    s.stop(); sys.exit("no menu")

print("[drv] select xmodem load @", LOAD, flush=True)
r = s.select_xmodem_load(LOAD)
print("[drv] xmodem armed:", r.success, repr((r.output or '')[-120:]), flush=True)

print("[drv] uploading", BIN, flush=True)
r = s.xmodem_upload(BIN, timeout=120)
print("[drv] upload:", r.success, repr((r.message or '')[-200:]), flush=True)

print("[drv] run @", START, flush=True)
r = s.run_at_address(START, capture_timeout=10)
print("[drv] ==== program output ====", flush=True)
print(r.output, flush=True)
print("[drv] ==========================", flush=True)

s.stop()
print("[drv] done", flush=True)
