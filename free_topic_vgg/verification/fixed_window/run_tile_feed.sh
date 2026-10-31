#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/fixed_window
for c in 3 32 128 512; do
 for mode in 0 1 2; do
  if [ "$c" = 3 ] && [ "$mode" != 0 ]; then continue; fi
  sharded=0; pooled=0
  if [ "$mode" != 0 ]; then sharded=1; fi
  if [ "$mode" = 2 ]; then pooled=1; fi
  iverilog -g2012 -s tb_sram_tile_feed -Ptb_sram_tile_feed.C="$c" \
   -Ptb_sram_tile_feed.SHARDED="$sharded" -Ptb_sram_tile_feed.POOLED="$pooled" \
   -Ptb_sram_tile_feed.PHASE="$pooled" -o build/fixed_window/feed.vvp \
   rtl/interconnect/vgg_activation_feed.v verification/fixed_window/tb_sram_tile_feed.sv
  vvp build/fixed_window/feed.vvp
 done
done
