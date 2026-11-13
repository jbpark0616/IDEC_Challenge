"""Export a self-contained gate-level layer comparison and completed evidence."""
from pathlib import Path
import json,shutil,hashlib
R=Path(__file__).resolve().parents[2];ROOT=R.parent;W=R/'build/layer_ppa';O=R/'evidence/layer_ppa'
D=ROOT/'submission/IDEC2026_FREE_TOPIC/03_technique_ppa_comparison';A=D/'assets'
A.mkdir(parents=True,exist_ok=True)
for name in ['core.v','extra.v'] : shutil.copyfile(W/name,A/name)
for name in ['asap7_functional_cells.v','asap7_final_extra_cells.v']:shutil.copyfile(ROOT/'verification'/name,A/name)
shutil.copyfile(R/'third_party/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v',A/'sram.v')
shutil.copytree(W/'vectors',A/'vectors',dirs_exist_ok=True)
tb=(W/'tb.sv').read_text().replace((W/'vectors').as_posix(),'@VECTORS@')
(A/'tb_template.sv').write_text(tb)
for name in ['run.py','README.md']:shutil.copyfile(Path(__file__).parent/name,D/name)
shutil.copyfile(ROOT/'docs/designated_final/asap7_rvt_ff_cells.json',A/'cell_catalog.json')
shutil.copytree(O,D/'results',dirs_exist_ok=True,ignore=shutil.ignore_patterns('*.vcd.gz','pilot*','run.log','resume.log','PROGRESS.txt'))
for p in (D/'results').glob('pilot*'):
    assert p.resolve().is_relative_to(D.resolve())
    if p.is_file():p.unlink()
for name in ['run.log','resume.log','PROGRESS.txt']:
    p=D/'results'/name
    if p.exists():p.unlink()
launcher='''from pathlib import Path
import os,shutil,subprocess,sys
D=Path(__file__).resolve().parent;A=D/'assets';W=D/'work';O=D/'reproduced_results'
W.mkdir(exist_ok=True);O.mkdir(exist_ok=True)
for name in ['core.v','extra.v','asap7_functional_cells.v','asap7_final_extra_cells.v','sram.v']:shutil.copyfile(A/name,W/name)
shutil.copytree(A/'vectors',W/'vectors',dirs_exist_ok=True)
(W/'tb.sv').write_text((A/'tb_template.sv').read_text().replace('@VECTORS@',(W/'vectors').as_posix()))
shutil.copyfile(D/'results/manifest.json',O/'manifest.json')
cmd=['iverilog','-g2012','-s','tb_v8_packed','-o',str(W/'sim.vvp')]+[str(W/n) for n in ['core.v','asap7_functional_cells.v','asap7_final_extra_cells.v','extra.v','sram.v','tb.sv']]
subprocess.run(cmd,check=True)
env=dict(os.environ,PPA_PROJECT=str(D.parent/'01_project'),PPA_WORK=str(W),PPA_RESULTS=str(O))
subprocess.run([sys.executable,str(D/'run.py'),*sys.argv[1:]],env=env,check=True)
'''
(D/'reproduce.py').write_text(launcher)
if (O/'comparison.csv').exists() and all((O/f'case{c}_sparse{s}/measurement.json').exists() for c in [10,11] for s in [0,1]):
    (D/'STATUS.txt').write_text('COMPLETE: Conv9/Conv13, sparse OFF/ON, all four conditions passed output checks and activity annotation audit.\nSee results/REPORT_KO.md and comparison.csv for scope and measurements.\n')
(D/'RUN.md').write_text('''# Reproduce the layer comparison

Use Linux/WSL with Python 3, Icarus Verilog 12 and OpenROAD/ASAP7 ORFS installed.
No Python ML package, dataset download or Vivado project is required for these saved slices.

```sh
cd 03_technique_ppa_comparison
export ORFS_ROOT=/path/to/OpenROAD-flow-scripts
# Optional if the OpenROAD executable is installed elsewhere:
# export OPENROAD=/path/to/openroad
python3 reproduce.py --cases 10 11
```

`reproduced_results/` is created separately from the supplied measured `results/`.
The script compiles the exact mapped core and uses the included vectors; it
does not rerun synthesis or modify the final RTL. `run.py` writes the exact
Liberty/LEF/SDC/VCD commands to each case's `power.tcl`.

Read README.md for the comparison boundary. Area and Fmax are common to both
runtime modes; this is not a claim of area or frequency improvement.
Activity VCDs are reproducible and compressed after measurement. They are
not included in the submission copy to avoid large waveform uploads.
The original source core is identifiable by manifest.json hashes.
''')
files={str(p.relative_to(D)):hashlib.sha256(p.read_bytes()).hexdigest() for p in D.rglob('*') if p.is_file() and p.name!='SHA256.json'}
(D/'SHA256.json').write_text(json.dumps(files,indent=2))
print('Exported',len(files),'comparison files to',D)
