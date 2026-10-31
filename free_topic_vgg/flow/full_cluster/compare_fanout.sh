#!/usr/bin/env bash
set -euo pipefail
project=$(cd "$(dirname "$0")/../.." && pwd)
orfs=${ORFS_ROOT:-/home/junbeom/OpenROAD-flow-scripts}
cd "$orfs"
source ./env.sh
cd flow
for variant in before after; do
  if [ "$variant" = before ]; then
    source_file="$project/evidence/interconnect_timing/before/vgg_mcast_fanout.v"
  else
    source_file="$project/rtl/interconnect/vgg_mcast_fanout.v"
  fi
  work="$project/build/fanout_timing_$variant"
  mkdir -p "$work"
  make synth-report DESIGN_CONFIG="$project/flow/full_cluster/config_fanout.mk" \
    PROJECT_ROOT="$project" FANOUT_SOURCE="$source_file" WORK_HOME="$work" \
    FLOW_VARIANT=base NUM_CORES=1 > "$work/run.log" 2>&1
  echo "PASS synthesis/STA: $variant"
done
