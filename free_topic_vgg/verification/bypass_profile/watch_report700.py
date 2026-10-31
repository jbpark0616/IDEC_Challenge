"""Refresh the report while the already-running cluster experiment completes."""
from pathlib import Path
import json
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[2]
log = root / 'evidence/report_baseline_700mhz/cluster_run.log'
provenance = root / 'evidence/report700/cluster/provenance.json'
deadline = time.monotonic() + 4 * 3600
while True:
    subprocess.run([sys.executable, str(Path(__file__).with_name('report700.py'))], check=True)
    if provenance.exists() and json.loads(provenance.read_text())['completed_runs'] == 8:
        print('All eight cluster runs complete.', flush=True)
        break
    if log.exists() and 'Traceback (most recent call last)' in log.read_text():
        raise RuntimeError('Cluster experiment failed; see cluster_run.log. Partial results preserved.')
    if time.monotonic() >= deadline:
        raise TimeoutError('Report watcher timed out; experiment was not stopped.')
    time.sleep(30)
