#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
out=build/fixed_window
mkdir -p "$out"
verilator --binary --timing -Wno-fatal -j 2 --top-module tb_v8_packed -GDENSE_U=1 -GTILE_INPUT=1 \
 --Mdir "$out/obj_core" -f rtl/sources.f \
 third_party/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v \
 verification/v8/tb_v8_packed.sv > "$out/core_build.log" 2>&1
"$out/obj_core/Vtb_v8_packed" +RESIDENT > "$out/core_resident.log"
"$out/obj_core/Vtb_v8_packed" > "$out/core_streamed.log"
