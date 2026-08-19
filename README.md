# Open-source modification of SCR1 core

## Current core modifications  
- [instruction cache and data cache](https://github.com/kargamant/pvo_scr1/tree/cache/fpga/nexys4ddr/scr1/src/cache) - [Deriglazov E.D.](https://github.com/kargamant)
- [branch predictors](https://github.com/kargamant/pvo_scr1/tree/bpd/scr1) - [Kuricyn M.V.](https://github.com/mihasik258)

## Repository contents
Folder | Description
------ | -----------
docs            | SDK documentation
fpga            | Submodule with SCR1 SDK FPGA projects
images          | Precompiled binary files
scr1            | Submodule with SCR1 core source files
sw              | Software projects for SDK
README.md       | This file

## OpenOCD SCR1 config
You need to update the configuration file `${OOCD_ROOT}/share/openocd/scripts/target/syntacore_riscv.cfg` by downloading it from https://github.com/syntacore/openocd/releases (sc-riscv-0.10.0-1972)
