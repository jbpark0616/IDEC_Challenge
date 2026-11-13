"""Replay archived Conv1/Conv2 inputs using the submitted gate-level flow."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys

D = Path(__file__).resolve().parent
ROOT = D.parents[3]
package = ROOT / 'submission/IDEC2026_FREE_TOPIC'
shared = package / '03_evaluation/01_vgg_layers'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true', help='verify archived hashes without running tools')
parser.add_argument('--cases', nargs='+', type=int, choices=[12, 13], default=[12, 13])
args = parser.parse_args()
for rel, digest in json.loads((D / 'SHA256.json').read_text()).items():
    assert hashlib.sha256((D / rel).read_bytes()).hexdigest() == digest, rel
if args.check:
    print('PASS: archived inputs, measured netlist/testbench, and result hashes')
    sys.exit(0)

W = D / 'work'
O = D / 'reproduced_results'
W.mkdir(exist_ok=True)
O.mkdir(exist_ok=True)
for name in ['core.v', 'extra.v']:
    shutil.copyfile(D / 'assets' / name, W / name)
for name in ['asap7_functional_cells.v', 'asap7_final_extra_cells.v', 'sram.v']:
    shutil.copyfile(shared / 'assets' / name, W / name)
shutil.copytree(D / 'assets/vectors', W / 'vectors', dirs_exist_ok=True)
(W / 'tb.sv').write_text((D / 'assets/tb_template.sv').read_text().replace('@VECTORS@', (W / 'vectors').as_posix()))
shutil.copyfile(D / 'results/manifest.json', O / 'manifest.json')
subprocess.run(['iverilog', '-g2012', '-s', 'tb_v8_packed', '-o', str(W / 'sim.vvp')]
               + [str(W / n) for n in ['core.v', 'asap7_functional_cells.v',
                  'asap7_final_extra_cells.v', 'extra.v', 'sram.v', 'tb.sv']], check=True)
env = dict(os.environ, PPA_PROJECT=str(package / '01_project'), PPA_WORK=str(W), PPA_RESULTS=str(O))
subprocess.run([sys.executable, str(shared / 'run.py'), '--cases', *map(str, args.cases)], env=env, check=True)
