#!/usr/bin/env bash
set -euo pipefail
project=$(cd "$(dirname "$0")/../.." && pwd)
orfs=${ORFS_ROOT:-/home/junbeom/OpenROAD-flow-scripts}
work=${SYNTH_WORK_HOME:-"$project/build/single_core_sram_fixed_window"}
mkdir -p "$work"
date -u '+STARTED %Y-%m-%dT%H:%M:%SZ' > "$work/STATUS.txt"
trap 'result=$?; printf "EXIT_CODE=%s\nELAPSED_SECONDS=%s\n" "$result" "$SECONDS" >> "$work/STATUS.txt"' EXIT
python3 - "$project" "$work" <<'PY'
import hashlib,json,sys
from pathlib import Path
r,w=map(Path,sys.argv[1:])
# The production cluster accepts only 4/16 cores. Relax only its cluster-size
# guards in this synthesis-only shell; otherwise constant folding removes MACs.
s=(r/'rtl/vgg_ab_layer_cluster.v').read_text()
for old,new in [
 ('module vgg_ab_layer_cluster #(', 'module vgg_single_core_shell #('),
 ('CORES!=16 || cmd_channels', '(CORES!=1 && CORES!=16) || cmd_channels'),
 ('(CORES!=4 && CORES!=16)', '(CORES!=1 && CORES!=4 && CORES!=16)')]:
 assert s.count(old)==1, old
 s=s.replace(old,new)
(r/'flow/single_core/vgg_single_core_shell.v').write_text(s)
files=[r/x for x in (r/'rtl/sources.f').read_text().splitlines() if x.strip()]
files += list((r/'flow/single_core').glob('*'))
files += list((r/'third_party/asap7_sram/generated/LIB').glob('*.lib'))
files += list((r/'third_party/asap7_sram/generated/LEF').glob('*.lef'))
(w/'source_sha256.json').write_text(json.dumps({str(p.relative_to(r)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files if p.is_file()},indent=2))
PY
cd "$orfs"
source ./env.sh
cd flow
make synth-report DESIGN_CONFIG="$project/flow/single_core/config.mk" \
 PROJECT_ROOT="$project" WORK_HOME="$work" FLOW_VARIANT=base NUM_CORES=4 \
 2>&1 | tee "$work/run.log"
