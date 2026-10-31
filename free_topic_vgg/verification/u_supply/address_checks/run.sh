#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
out=verification/u_supply/address_checks
verilator --binary --timing -Wno-fatal -j 4 --top-module tb_u_address \
  --Mdir "$out/obj_address" -f rtl/sources.f \
  third_party/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v \
  "$out/tb_u_address.sv" > "$out/address_build.log" 2>&1
"$out/obj_address/Vtb_u_address" +RESIDENT > "$out/address_resident.log"
"$out/obj_address/Vtb_u_address" > "$out/address_streamed.log"
tail -n 2 "$out/address_resident.log"
tail -n 2 "$out/address_streamed.log"
