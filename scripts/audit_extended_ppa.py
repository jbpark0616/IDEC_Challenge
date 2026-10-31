from pathlib import Path
import ast,csv,json,hashlib,zipfile
R=Path(__file__).resolve().parents[1];D=R/'submission/IDEC2026_FREE_TOPIC'
for folder in ['03_evaluation/02_controlled','03_evaluation/03_vgg_examples','03_evaluation/04_area']:
    ast.parse((D/folder/'reproduce.py').read_text(encoding='utf-8'))
control=D/'03_evaluation/02_controlled'
rows=list(csv.DictReader((control/'results/comparison.csv').open()));assert len(rows)==15
for rate in ['fast','slow','supply8']:
    assert (control/f'tb_{rate}.sv').exists()
    for case in range(5):
        for sparse in [0,1]:
            out=control/f'results/{rate}/case{case}_sparse{sparse}'
            assert 'PASS U_LOADING' in (out/'simulation.log').read_text()
            m=json.loads((out/'measurement.json').read_text())
            assert abs(m['energy_nj']-m['power_w']*m['duration_ps']/1000)<1e-6
for case in [12,13]:
    for sparse in [0,1]:
        assert 'PASS U_LOADING' in (D/f'03_evaluation/03_vgg_examples/results/case{case}_sparse{sparse}/simulation.log').read_text()
A=D/'03_evaluation/04_area/results';m=json.loads((A/'comparison.json').read_text())
assert abs(m['overhead_pct']-100*(m['runtime_area_um2']-m['disabled_area_um2'])/m['disabled_area_um2'])<1e-10
assert (A/'runtime/mapped.v').read_bytes()==(D/'03_evaluation/01_vgg_layers/assets/core.v').read_bytes()
assert 'PASS' in (A/'VALIDATION.txt').read_text()
for row in json.loads((D/'SHA256.json').read_text()):
    assert hashlib.sha256((D/row['path']).read_bytes()).hexdigest()==row['sha256']
with zipfile.ZipFile(D.parent/'IDEC2026_FREE_TOPIC_OpenROAD.zip') as z:
    assert z.testzip() is None
    for row in json.loads((D/'SHA256.json').read_text()):
        assert hashlib.sha256(z.read(D.name+'/'+row['path'])).hexdigest()==row['sha256']
print('PASS: 30 controlled runs, 4 additional VGG runs, area arithmetic and validation, folder/ZIP byte consistency')
