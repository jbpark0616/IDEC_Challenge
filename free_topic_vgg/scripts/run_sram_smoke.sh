#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=artifacts/sram_smoke
mkdir -p "$out"
macro=srambank_256x4x64_6t122
vendor=third_party/asap7_sram/generated
iverilog -g2012 -s tb_sram_8k -o "$out/sim.vvp" \
    "${vendor}/verilog/${macro}.v" rtl/memory/vgg_sram_8k.v tests/tb_sram_8k.sv
vvp "$out/sim.vvp" | tee "$out/simulation.log"
# DO NOT read the behavioral SRAM module in synthesis.
yosys -Q -T -l "$out/synthesis.log" -p "read_liberty -lib ${vendor}/LIB/${macro}.lib; read_verilog rtl/memory/vgg_sram_8k.v; hierarchy -check -top vgg_sram_8k; synth -top vgg_sram_8k; stat; write_json ${out}/netlist.json; write_verilog -noattr -noexpr ${out}/netlist.v" > "$out/yosys_console.log"
ORFS_ROOT=${ORFS_ROOT:-/home/junbeom/OpenROAD-flow-scripts}
export ORFS_ROOT
OPENROAD_BIN=${OPENROAD_BIN:-$ORFS_ROOT/tools/install/OpenROAD/bin/openroad}
"$OPENROAD_BIN" -exit scripts/sram_smoke.tcl > "$out/openroad.log" 2>&1
python3 scripts/audit_sram_smoke.py
