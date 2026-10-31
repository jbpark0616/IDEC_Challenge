#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
out=verification/v8
macro=third_party/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v
iverilog -g2012 -s tb_quantizer -o "$out/quantizer.vvp" \
  rtl/core/vgg_v8_quantizer.v "$out/tb_quantizer.sv"
vvp "$out/quantizer.vvp" > "$out/quantizer.log"
python3 verification/full_model/prepare_tb.py --v8
verilator --lint-only --timing -Wno-fatal --top-module tb_full_vgg_v8 \
  -f rtl/sources.f "$macro" verification/full_model/tb_full_vgg_v8.sv > "$out/cluster_lint.log" 2>&1
verilator --binary --timing -Wno-fatal -j 2 --top-module tb_u_resident \
  --Mdir "$out/obj_v16" -f rtl/sources.f "$macro" verification/u_supply/tb_u_resident.sv > "$out/v16_build.log" 2>&1
"$out/obj_v16/Vtb_u_resident" +RESIDENT > "$out/v16_regression.log"
verilator --binary --timing -Wno-fatal -j 2 --top-module tb_fc_v8_regression \
  --Mdir "$out/obj_fc" -f rtl/sources.f "$macro" "$out/tb_fc_v8_regression.sv" > "$out/fc_build.log" 2>&1
"$out/obj_fc/Vtb_fc_v8_regression" > "$out/fc_run.log"
python3 "$out/report.py"
