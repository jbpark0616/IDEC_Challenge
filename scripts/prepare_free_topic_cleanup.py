"""Inventory and archive retired experiments. Does NOT delete or move files.

Deletion is performed separately by native PowerShell after path and archive
verification. Active RTL, designated topic, datasets and Colab are protected.
"""
from pathlib import Path
import hashlib
import json
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'free_topic_vgg'
OUT = ROOT / 'archive/free_topic_cleanup_20261028'
KEEP = {'wide_channels', 'v_reuse_lifetime', 'winograd_quantization'}
OUT.mkdir(parents=True, exist_ok=True)
retired = sorted(p for p in (PROJECT/'experiments').iterdir() if p.is_dir() and p.name not in KEEP)
names = [p.name for p in retired]


def rel(p):
    return p.relative_to(ROOT).as_posix()


def sha(p):
    with p.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def generated(p):
    parts = p.relative_to(PROJECT).parts
    if any(s.startswith('obj_') or s in {'obj_dir','verilated','xsim.dir','.Xil','__pycache__'} for s in parts):
        return True
    return p.suffix.lower() in {'.vvp','.vcd','.fst','.wdb','.o','.a','.pyc','.exe','.pb'}


scripts = []
for p in (PROJECT/'scripts').iterdir():
    if not p.is_file():
        continue
    content = p.read_text(encoding='utf-8-sig', errors='replace')
    # Retire experiment-specific automation, retaining the general model,
    # memory, interface and module regression utilities.
    if any('experiments/'+name in content for name in names):
        scripts.append(p)
for name in ['build_channel_fifo_cluster_test.py','build_channel_fifo_tests.py',
             'generate_ab_chain_vectors.py','generate_pool_chain_vectors.py',
             'generate_fixed_four_core_capacity.py','generate_fixed_four_core_vectors.py',
             'implement_result_pipeline.py','implement_sram_lines.py',
             'extend_cluster_core_count.py','split_generator_output.py']:
    p = PROJECT/'scripts'/name
    if p.exists() and p not in scripts:
        scripts.append(p)

targets = list(retired) + sorted(scripts)
# Drop only rebuildable products from otherwise retained result directories.
for base in [PROJECT/'experiments', PROJECT/'artifacts']:
    for p in base.rglob('*'):
        if any(p==r or r in p.parents for r in retired):
            continue
        if (PROJECT/'experiments/winograd_quantization') in p.parents:
            continue
        if p.is_dir() and (p.name.startswith('obj_') or p.name in {'obj_dir','verilated','xsim.dir','.Xil','__pycache__'}):
            targets.append(p)
        elif p.is_file() and generated(p):
            targets.append(p)
for base in [PROJECT, PROJECT/'scripts', PROJECT/'tests']:
    p = base/'__pycache__'
    if p.exists():
        targets.append(p)
targets = sorted(set(targets), key=lambda p:(len(p.parts), str(p)))
minimal = []
for p in targets:
    if not any(t in p.parents for t in minimal):
        minimal.append(p)
targets = minimal

deleted_files = []
for p in targets:
    deleted_files.extend(sorted(p.rglob('*')) if p.is_dir() else [p])
deleted_files = [p for p in deleted_files if p.is_file()]
preserved = [p for p in deleted_files if not generated(p)]
# Keep the pre-cleanup project navigation and historical report generator.
preserved += [ROOT/'PROJECTS.txt', PROJECT/'README.txt', PROJECT/'experiments/wide_channels/report.py']
preserved = sorted(set(preserved))
archive = OUT/'retired_experiments.zip'
if archive.exists():
    raise RuntimeError('Existing archive found; refusing to replace cleanup evidence')
entries = []
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for p in preserved:
        digest = sha(p)
        z.write(p, rel(p))
        entries.append(dict(path=rel(p), sha256=digest, bytes=p.stat().st_size))
with zipfile.ZipFile(archive) as z:
    for entry in entries:
        with z.open(entry['path']) as stream:
            assert hashlib.file_digest(stream,'sha256').hexdigest()==entry['sha256']

protected = []
for directory in ['rtl', 'experiments/winograd_quantization', 'weights', 'reference', 'third_party']:
    for p in sorted((PROJECT/directory).rglob('*')):
        if p.is_file() and '__pycache__' not in p.parts:
            protected.append(dict(path=rel(p),sha256=sha(p)))
for path in ['model.py','config.json','artifacts/integer_vgg/integer_parameters.pt',
             'artifacts/integer_vgg/manifest.json','data/cifar-10-python.tar.gz']:
    p=PROJECT/path
    protected.append(dict(path=rel(p),sha256=sha(p)))
plan=dict(root=str(ROOT),archive=rel(archive),archive_sha256=sha(archive),
          archive_verified=True,retired_experiments=names,
          retired_scripts=[rel(p) for p in sorted(scripts)],
          targets=[rel(p) for p in targets],
          deleted_files=[dict(path=rel(p),bytes=p.stat().st_size) for p in deleted_files],
          archived_files=entries,protected_files=protected,
          bytes_to_remove=sum(p.stat().st_size for p in deleted_files),
          archive_bytes=archive.stat().st_size)
(OUT/'plan.json').write_text(json.dumps(plan,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:plan[k] for k in ['retired_experiments','retired_scripts','bytes_to_remove','archive_bytes']},indent=2))
print(f'Verified {len(entries)} archived source/report files; {len(targets)} deletion targets. Nothing deleted yet.')
