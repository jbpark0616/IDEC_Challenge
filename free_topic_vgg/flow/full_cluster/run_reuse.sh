#!/usr/bin/env bash
set -euo pipefail
project=$(cd "$(dirname "$0")/../.." && pwd)
export SYNTH_CONFIG="$project/flow/full_cluster/config_reuse.mk"
export SYNTH_WORK_HOME="$project/build/full_cluster_reuse"
exec bash "$project/flow/full_cluster/run.sh"
