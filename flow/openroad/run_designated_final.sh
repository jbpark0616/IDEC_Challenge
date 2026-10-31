#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
orfs=${ORFS_ROOT:-/home/junbeom/OpenROAD-flow-scripts}
work="$root/build/designated_final/openroad"
mkdir -p "$work"
cd "$orfs"
source ./env.sh
cd flow
export ASIC_CLK_PERIOD_PS=${ASIC_CLK_PERIOD_PS:-1000} ASIC_CLK_IO_PCT=0.2
make synth-report DESIGN_CONFIG="$root/flow/openroad/designated_final.mk" \
 PROJECT_ROOT="$root" WORK_HOME="$work" FLOW_VARIANT=matched_v1 NUM_CORES=4 \
 VERILOG_DEFINES='-DOPENROAD_CLKGATE' \
 DONT_USE_CELLS='*x1p*_ASAP7* *xp*_ASAP7* SDF*' \
 2>&1 | tee "$work/run_synth.log"
mkdir -p "$root/build/asic/chip"
cp "$work/results/asap7/chip_row_sparse_fixed/matched_v1/1_2_yosys.v" "$root/build/asic/chip/netlist.v"
