#!/usr/bin/env python3
"""Verify frozen b1_g1 hashes and run the official-interface 1000-image RTL test (WSL)."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / 'docs/experiment_results/designated/designated_final/rtl_sha256.json').read_text())
rtl = sorted((ROOT / 'verilog').glob('*.v'))
actual = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in rtl}
assert actual == manifest, 'Final RTL differs from frozen b1_g1 manifest'
out = ROOT / 'build/designated_final/rtl'
out.mkdir(parents=True, exist_ok=True)
tb = (ROOT / 'verification/winograd_chip_1000_tb.v').read_text()
tb = tb.replace('../../../', ROOT.as_posix() + '/')
(out / 'tb.v').write_text(tb)
subprocess.run(['iverilog', '-g2012', '-DTEST_M_FIFO_DEPTH_1',
                '-s', 'winograd_chip_1000_tb', '-o', str(out / 'sim.vvp'),
                *map(str, rtl), str(out / 'tb.v')], check=True)
with (out / 'run.log').open('w') as log:
    subprocess.run(['vvp', '-n', str(out / 'sim.vvp')], cwd=out,
                   stdout=log, stderr=subprocess.STDOUT, check=True, timeout=1200)
result = (out / 'run.log').read_text()
print(result, flush=True)
assert 'PASS' in result and 'FAIL' not in result and 'ERROR' not in result
print('PASS: frozen b1_g1 source hashes and 1000-image RTL regression')
