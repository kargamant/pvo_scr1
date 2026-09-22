#!/usr/bin/env bash
# fix_dt.sh - strip the ALINX PL peripherals from a PetaLinux image.ub so the kernel does
# not SError probing AXI-GPIO/VDMA/MIPI addresses that don't exist in our SCR1 PL.
# Removes the whole `amba_pl@0` node (+ its aliases) from the FIT's kernel DTB; keeps the
# PS peripherals. Our devmem targets (0x80100000 boot-BRAM, 0x80200000 reset-gpio) need no
# DT node (raw /dev/mem access), so nothing is added back.
#
# Needs: dtc + u-boot-tools (dumpimage/mkimage).  apt install device-tree-compiler u-boot-tools
# Usage: fix_dt.sh <default_image.ub> [out_image.ub]
set -euo pipefail
IN="${1:?input image.ub}"; OUT="${2:-image_fixed.ub}"
for t in dtc dumpimage mkimage; do command -v $t >/dev/null || { echo "missing $t (apt install device-tree-compiler u-boot-tools)"; exit 1; }; done
IN=$(realpath "$IN"); OUT=$(realpath -m "$OUT")   # absolutize before cd
WD=$(mktemp -d); cp "$IN" "$WD/in.ub"; cd "$WD"

echo ">>> extract kernel + dtb from FIT"
dumpimage -T flat_dt -p 0 -o kernel.gz in.ub >/dev/null
dumpimage -T flat_dt -p 1 -o system.dtb in.ub >/dev/null
dtc -I dtb -O dts system.dtb -o system.dts 2>/dev/null

echo ">>> delete amba_pl@0 node + its aliases; reserve top 256MB DDR for SCR1 (mem=1792M)"
RESERVE="${RESERVE_DDR:-1}"   # set RESERVE_DDR=0 to skip the mem= bootarg
python3 - "$RESERVE" <<'PY'
import sys
reserve=sys.argv[1]=="1"
L=open('system.dts').read().split('\n')
s=next(i for i,l in enumerate(L) if 'amba_pl@0' in l and '{' in l)
depth=0;e=None
for i in range(s,len(L)):
    depth+=L[i].count('{')-L[i].count('}')
    if i>s and depth==0: e=i; break
out=[l for i,l in enumerate(L) if not (s<=i<=e) and 'amba_pl@0/' not in l and not l.strip().startswith('amba_pl =')]
# reserve DDR for SCR1: cap Linux at 1792M so 0x70000000..0x80000000 is free
if reserve:
    for i,l in enumerate(out):
        if 'bootargs' in l and '=' in l and 'mem=' not in l:
            out[i]=l.replace('";', ' mem=1792M";')
            print("bootargs +=' mem=1792M' (SCR1 gets 0x70000000..0x80000000)")
            break
open('system_fixed.dts','w').write('\n'.join(out))
print(f"removed amba_pl@0 lines {s+1}-{e+1}; {len(L)}->{len(out)}")
PY
dtc -I dts -O dtb system_fixed.dts -o system_fixed.dtb 2>/dev/null

echo ">>> repack FIT (mkimage recomputes hashes)"
cat > img.its <<ITS
/dts-v1/;
/ {
    description = "SCR1+PS fitImage (PL peripherals stripped)";
    #address-cells = <1>;
    images {
        kernel-1 { description="Linux kernel"; data=/incbin/("kernel.gz"); type="kernel";
                   arch="arm64"; os="linux"; compression="gzip"; load=<0x00200000>;
                   entry=<0x00200000>; hash-1 { algo="sha256"; }; };
        fdt-1 { description="FDT"; data=/incbin/("system_fixed.dtb"); type="flat_dt";
                arch="arm64"; compression="none"; hash-1 { algo="sha256"; }; };
    };
    configurations {
        default = "conf-1";
        conf-1 { description="1 Linux kernel, FDT blob"; kernel="kernel-1"; fdt="fdt-1";
                 hash-1 { algo="sha256"; }; };
    };
};
ITS
mkimage -f img.its out.ub >/dev/null
cp out.ub "$OUT"; echo ">>> wrote $OUT ($(wc -c < out.ub) B)"
