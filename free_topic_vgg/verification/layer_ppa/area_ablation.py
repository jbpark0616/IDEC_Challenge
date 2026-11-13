"""Matched combinational remapping of final core, runtime sparse vs tied-off.
Sequential cells/ICG/SRAM remain mapped. This is an implementation ablation,
not the original physical-design area and not ICG overhead.
"""
from pathlib import Path
import gzip,json,re,subprocess,hashlib
R=Path(__file__).resolve().parents[2];W=R/'build/area_ablation_v2';O=R/'evidence/area_ablation_v2'
W.mkdir(parents=True,exist_ok=True);O.mkdir(parents=True,exist_ok=True)
cat=json.loads((R.parent/'docs/designated_final/asap7_rvt_ff_cells.json').read_text())
core=R/'build/layer_ppa/core.v';manifest=json.loads((R/'evidence/layer_ppa/manifest.json').read_text())
assert hashlib.sha256(core.read_bytes()).hexdigest()==manifest['extracted_core_sha256']
# Reuse the repository's Liberty merging code only, never its synthesis runner.
src=R/'flow/single_core/synth_periphery.py';s=src.read_text()
section=s[s.index('libdir=Path('):s.index("core=(R/'rtl/core/")]
ns=dict(Path=Path,gzip=gzip,json=json,re=re,R=R,W=W);exec(section,ns)
merged=ns['merged'];sr=ns['sr'];cells=ns['cells']
models=[]
for c in cat['cells']:
    n=c['name'];pins=c['pins'];outputs=[p for p in pins if p['direction']=='output']
    if re.search(r'\b(?:ff|latch)\s*\(',cells[n]) or n.startswith(('DFF','SDF','ICG','LATCH','DHL','DLL')) or not outputs or any(p['function'] is None for p in outputs):continue
    for p in outputs:
        assert set(re.findall(r'[A-Za-z_]\w*',p['function'])) <= {q['name'] for q in pins},(n,p['function'])
    models.append('module '+n+'('+','.join(p['direction']+' '+p['name'] for p in pins)+');')
    for p in outputs:models.append('assign '+p['name']+' = '+p['function'].replace('!','~').replace('*','&').replace('+','|')+';')
    models.append('endmodule')
(W/'comb.v').write_text('\n'.join(models))
for mode in ['runtime','disabled']:
    out=O/mode;out.mkdir(exist_ok=True)
    tie="connect -set sparse_enable 1'b0\n" if mode=='disabled' else ''
    ys=f'''read_liberty -lib {merged}
read_liberty -lib {sr}
read_verilog {core}
hierarchy -check -top ppa_core
select -module ppa_core
{tie}techmap -map {W/'comb.v'}
opt -full
techmap
opt -full
abc -liberty {merged} -D 1430
clean
check
stat -liberty {merged} -liberty {sr}
write_verilog -noattr {out/'mapped.v'}
write_json {out/'mapped.json'}
'''
    (out/'run.ys').write_text(ys)
    with (out/'synthesis.log').open('w') as f:subprocess.run(['/home/junbeom/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys','-s',str(out/'run.ys')],stdout=f,stderr=subprocess.STDOUT,check=True)
    net=json.loads((out/'mapped.json').read_text())['modules']['ppa_core'];counts={}
    for c in net['cells'].values():counts[c['type']]=counts.get(c['type'],0)+1
    counts.pop('$scopeinfo',None)
    assert all(n in cells for n in counts),[n for n in counts if n not in cells]
    area=sum(float(re.search(r'\barea\s*:\s*([\d.eE+-]+)',cells[n])[1])*count for n,count in counts.items())
    assert counts.get('srambank_256x4x64_6t122')==8
    (out/'area.json').write_text(json.dumps(dict(area_um2=area,counts=counts),indent=2))
    print(mode,area,flush=True)
a,b=[json.loads((O/m/'area.json').read_text())['area_um2'] for m in ['runtime','disabled']]
(O/'comparison.json').write_text(json.dumps(dict(runtime_area_um2=a,disabled_area_um2=b,overhead_pct=100*(a-b)/b,method='Same final mapped core; common combinational remapping, sparse_enable variable versus tied 0; ICG retained in both. Not an ICG-overhead measurement.'),indent=2))
print('COMPLETE matched area ablation',flush=True)
