#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
out=verification/v8
# Generate vectors with the project Python environment before running.
verilator --binary --timing -Wno-fatal -j 2 --top-module tb_v8_packed -GDENSE_U=1 \
  --Mdir "$out/obj" -f rtl/sources.f \
  third_party/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v \
  "$out/tb_v8_packed.sv" > "$out/build.log" 2>&1
"$out/obj/Vtb_v8_packed" +RESIDENT > "$out/run.log"
"$out/obj/Vtb_v8_packed" > "$out/streamed.log"
tail -n 3 "$out/run.log"
tail -n 3 "$out/streamed.log"
