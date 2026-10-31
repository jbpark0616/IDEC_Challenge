"""Select representative layers only after every OFF/ON pair has passed."""
from pathlib import Path
import json, subprocess, sys, time
R=Path(__file__).resolve().parents[2]
evidence=R/'evidence/report700/cluster_all'
log=R/'evidence/report_baseline_700mhz/cluster_all_run.log'
deadline=time.monotonic()+12*3600
last=-1
while time.monotonic()<deadline:
    if log.exists() and 'Traceback (most recent call last)' in log.read_text():
        raise RuntimeError('Experiment failed. No selected figure generated; inspect cluster_all_run.log.')
    p=evidence/'provenance.json'
    if p.exists():
        n=json.loads(p.read_text())['completed_runs']
        if n!=last:
            print(f'Completed {n}/26 runs',flush=True);last=n
        if n==26:
            script=R.parent/'docs/figures/free_topic/fig03_vgg_layer_effect/generate.py'
            subprocess.run([sys.executable,str(script),'--selected'],check=True)
            print('All layers passed. Ranked table and selected SVG/PDF/PNG generated.',flush=True)
            break
    time.sleep(30)
else:
    raise TimeoutError('Selection watcher timed out; simulation was not stopped.')
