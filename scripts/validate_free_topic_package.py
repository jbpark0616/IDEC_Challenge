"""Audit final payload and make a portable ZIP with slash-separated paths."""
from pathlib import Path
import ast,csv,hashlib,json,zipfile
ROOT=Path(__file__).resolve().parents[1];D=ROOT/'submission/IDEC2026_FREE_TOPIC';C=D/'03_evaluation/01_vgg_layers'
assert (C/'STATUS.txt').read_text().startswith('COMPLETE')
for p in [C/'reproduce.py',C/'run.py']:ast.parse(p.read_text())
manifest=json.loads((C/'results/manifest.json').read_text())
assert hashlib.sha256((C/'assets/core.v').read_bytes()).hexdigest()==manifest['extracted_core_sha256']
assert hashlib.sha256((D/'01_project/evidence/timing_writer_pipeline/netlist/1_2_yosys.v').read_bytes()).hexdigest()==manifest['source_netlist_sha256']
for p,h in json.loads((C/'SHA256.json').read_text()).items():
    assert hashlib.sha256((C/p).read_bytes()).hexdigest()==h,p
rows=list(csv.DictReader((C/'results/comparison.csv').open()))
assert len(rows)==2
for row in rows:
    for mode in ['off','on']:
        assert abs(float(row[f'energy_{mode}_nj'])-float(row[f'power_{mode}_mw'])*float(row[f'latency_{mode}_us']))<1e-5
for c in [10,11]:
    for s in [0,1]:
        assert 'PASS U_LOADING' in (C/f'results/case{c}_sparse{s}/simulation.log').read_text()
sources=(D/'01_project/rtl/sources.f').read_text().splitlines()
assert len(sources)==28
for name in sources:
    assert (D/'01_project'/name).read_bytes()==(ROOT/'free_topic_vgg'/name).read_bytes()
for record in json.loads((D/'SHA256.json').read_text()):
    assert hashlib.sha256((D/record['path']).read_bytes()).hexdigest()==record['sha256'],record['path']
archive=D.parent/'IDEC2026_FREE_TOPIC_OpenROAD.zip'
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for p in sorted(D.rglob('*')):
        if p.is_file():z.write(p,(Path(D.name)/p.relative_to(D)).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert all('\\' not in n for n in z.namelist())
print('PASS: source/netlist hashes, 4 gate PASS logs, PPA arithmetic, manifests, portable ZIP')
print(archive,archive.stat().st_size,'bytes')
