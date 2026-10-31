"""Run independent final-layer group8 cases ahead of the sequential collector."""
from pathlib import Path
import subprocess
R=Path(__file__).resolve().parents[2];O=R/'evidence/feed_group_sweep'
exe=R/'build/feed_hwc8/obj/Vtb_report_layer'
for sparse in (0,1):
    target=O/f'conv11_group8_sparse{sparse}.log'
    if target.exists() and 'PASS ISOLATED_LAYER' in target.read_text():continue
    temp=O/f'conv11_group8_sparse{sparse}.pending'
    with temp.open('w') as f:
        subprocess.run([str(exe),'+LAYER=10','+STREAM_HOST','+RESIDENT_U']+(['+SPARSE'] if sparse else []),cwd=R,stdout=f,stderr=subprocess.STDOUT,check=True,timeout=1800)
    assert 'PASS ISOLATED_LAYER' in temp.read_text()
    temp.replace(target)
    print(f'Completed Conv11 group8 sparse={sparse}',flush=True)
