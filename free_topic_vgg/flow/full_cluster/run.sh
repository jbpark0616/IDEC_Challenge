#!/usr/bin/env bash
set -euo pipefail
project=$(cd "$(dirname "$0")/../.." && pwd)
orfs=${ORFS_ROOT:-/home/junbeom/OpenROAD-flow-scripts}
work=${SYNTH_WORK_HOME:-"$project/build/full_cluster_timing"}
config=${SYNTH_CONFIG:-"$project/flow/full_cluster/config.mk"}
mkdir -p "$work"
date -u '+STARTED %Y-%m-%dT%H:%M:%SZ' > "$work/STATUS.txt"
trap 'result=$?; printf "EXIT_CODE=%s\nELAPSED_SECONDS=%s\n" "$result" "$SECONDS" >> "$work/STATUS.txt"' EXIT
python3 - "$project" "$work" "$config" <<'PY'
from pathlib import Path
import hashlib,json,sys
r,w,config=map(Path,sys.argv[1:])
files=[r/p for p in (r/'rtl/sources.f').read_text().splitlines() if p.strip()]
files+=[r/'rtl/sources.f',r/'flow/full_cluster/config.mk',r/'flow/single_core/constraint.sdc']
files+=[config]
(w/'source_sha256.json').write_text(json.dumps({str(p.relative_to(r)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files},indent=2))
PY
cd "$orfs"
source ./env.sh
set -euo pipefail
cd flow
make synth-report DESIGN_CONFIG="$config" \
 PROJECT_ROOT="$project" WORK_HOME="$work" FLOW_VARIANT=base NUM_CORES=2 \
 2>&1 | tee "$work/run.log"
test -s "$work/results/asap7/vgg_sixteen_core_cluster/base/1_2_yosys.v"
test -s "$work/reports/asap7/vgg_sixteen_core_cluster/base/1_Post_synthesis.rpt"
echo 'ARTIFACTS_PRESENT=netlist_and_STA' >> "$work/STATUS.txt"
