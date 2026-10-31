#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
out=verification/full_model/v8_run
mkdir -p "$out"
python3 verification/full_model/prepare_tb.py --v8
python3 -c 'import json; from pathlib import Path; assert json.loads(Path("verification/full_model/vectors_v8/manifest.json").read_text())["mode"]=="U8_V8"'
verilator --binary --timing -Wno-fatal -j 2 --top-module tb_full_vgg_v8 \
    --Mdir "$out/obj" -f rtl/sources.f \
    third_party/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v \
    verification/full_model/tb_full_vgg_v8.sv > "$out/build.log" 2>&1
# Both improvements are explicit; never overwrite the completed V16 run.
"$out/obj/Vtb_full_vgg_v8" +STREAM_HOST +RESIDENT_U > "$out/run.log"
tail -n 5 "$out/run.log"
