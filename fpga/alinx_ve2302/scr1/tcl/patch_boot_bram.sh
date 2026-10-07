#!/usr/bin/env bash
# patch_boot_bram.sh — make the boot BRAM actually load our image on Versal VD100.
#
# WHY THIS EXISTS (Versal-specific gotcha):
#   The boot BRAM is an emb_mem_gen (XPM) whose init is applied at SYNTHESIS via $readmemh.
#   During `generate_target`, Vivado's axi_bram_ctrl->emb_mem_gen parameter propagation
#   (BD 41-2180) FORCES C_MEMORY_INIT_FILE back to "NONE" on the *generated wrapper* even
#   though we set_property it on the BD cell / IP. set_property only fixes the .xci; the
#   generated synth wrapper .v still says NONE -> BRAM boots empty -> CPU traps on 0x0.
#   The ONLY override that sticks is editing the generated wrapper .v directly, THEN
#   re-running OOC synth without regenerating the BD. (updatemem/bootgen post-build is a
#   DEAD path on Versal: PLM Major Error 0x223e, DONE stays low.)
#
# USAGE:
#   ./patch_boot_bram.sh [/abs/path/to/image_le.mem]
#   ./patch_boot_bram.sh ps [/abs/path/to/image_le.mem]
#   (`--ps` is accepted as an alias for `ps`.)
#   image must be a WORD-array .mem, byte-SWAPPED (emb_mem_gen $readmemh reads word values;
#   the CPU reads the .mem word as-is, so little-endian instructions must be pre-swapped).
#   Default image: mem/scbl_le.mem
#   After patching, rebuild with: LC_ALL=C vivado -mode batch -source tcl/build_patched.tcl
set -euo pipefail

ORIGIN="$(cd "$(dirname "$0")/.." && pwd)"                 # fpga/alinx_ve2302/scr1

MODE="standalone"
case "${1:-}" in
  ps|--ps)
    MODE="ps"
    shift
    ;;
esac

MEM="${1:-$ORIGIN/mem/scbl_le.mem}"
if [ "$MODE" = "ps" ]; then
  # TODO: replace this placeholder with the generated wrapper path for the PS project.
  # It can also be supplied without editing the script:
  #   PS_WRAPPER=/absolute/path/to/wrapper.v ./patch_boot_bram.sh ps
  W="${PS_WRAPPER:-$ORIGIN/REPLACE_WITH_PS_WRAPPER_PATH}"
else
  W="$ORIGIN/build/alinx_ve2302_scr1/alinx_ve2302_scr1.gen/sources_1/bd/alinx_ve2302_sopc/ip/alinx_ve2302_sopc_emb_mem_gen_0_0/synth/alinx_ve2302_sopc_emb_mem_gen_0_0.v"
fi

[ -f "$W" ] || { echo "ERROR: wrapper not found (generate the BD first): $W"; exit 1; }
[ -f "$MEM" ] || { echo "ERROR: mem image not found: $MEM"; exit 1; }
[ -f "$W.bak" ] || cp "$W" "$W.bak"

# Replace the C_MEMORY_INIT_FILE(...) argument on the instantiation line with our image.
sed -i -E "s#\\.C_MEMORY_INIT_FILE\\(\"[^\"]*\"\\)#.C_MEMORY_INIT_FILE(\"$MEM\")#" "$W"
echo "PATCHED:"
grep -n '\.C_MEMORY_INIT_FILE(' "$W"

if [ "$MODE" = "ps" ]; then
  echo "Now: cd $ORIGIN && LC_ALL=C vivado -mode batch -source tcl/build_patched.tcl -tclargs ps"
else
  echo "Now: cd $ORIGIN && LC_ALL=C vivado -mode batch -source tcl/build_patched.tcl"
fi
echo "(build_patched.tcl aborts if the OOC log shows MEMORY_INIT_FILE(NONE), i.e. the patch was clobbered.)"
