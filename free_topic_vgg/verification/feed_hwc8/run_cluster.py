"""Isolated eight-channel feed experiment, identical immediate-host Conv5 TB."""
from pathlib import Path
import hashlib,json,subprocess,re,time
R=Path(__file__).resolve().parents[2];D=Path(__file__).resolve().parent
W=R/'build/feed_hwc8';O=R/'evidence/feed_hwc8'
W.mkdir(parents=True,exist_ok=True);O.mkdir(parents=True,exist_ok=True)
manifest=json.loads((R/'evidence/report_baseline_700mhz/manifest.json').read_text(encoding='utf-8-sig'))
def check():
    hashes={f['path']:hashlib.sha256((R/f['path']).read_bytes()).hexdigest() for f in manifest['files']}
    assert all(hashes[f['path']].lower()==f['sha256'].lower() for f in manifest['files'])
    return hashes
baseline=check();start=time.monotonic()
subprocess.run(['python3',str(D/'prepare.py')],check=True)
with (O/'unit_build.log').open('w') as log:
    subprocess.run(['iverilog','-g2012','-s','tb_feed','-o',str(W/'unit'),'-f',str(D/'sources.f'),
        'third_party/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v',str(D/'tb_feed.sv')],cwd=R,stdout=log,stderr=subprocess.STDOUT,check=True)
with (O/'unit.log').open('w') as log:
    subprocess.run(['vvp',str(W/'unit')],cwd=R,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
assert 'PASS ALL_FEED' in (O/'unit.log').read_text()
print('UNIT PASS',flush=True)
tb=R/'build/cluster_immediate/tb.sv'
with (O/'build.log').open('w') as log:
    subprocess.run(['verilator','--binary','--timing','-Wno-fatal','-j','2','--top-module','tb_report_layer',
        '--Mdir',str(W/'obj'),'-f',str(D/'sources.f'),
        'third_party/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v',str(tb)],cwd=R,stdout=log,stderr=subprocess.STDOUT,check=True)
print('BUILD COMPLETE',flush=True)
def parse(p):
    t=p.read_text();assert 'PASS ISOLATED_LAYER' in t
    out={}
    for l in t.splitlines():
        if l.startswith(('PROFILE ','LAYER_PASS ')):out.update({k:int(v) for k,v in re.findall(r'(\w+)=(\d+)(?=\s|$)',l)})
    return out
results=[]
for sparse in (0,1):
    p=O/f'conv5_sparse{sparse}.log'
    with p.open('w') as log:
        subprocess.run([str(W/'obj/Vtb_report_layer'),'+LAYER=4','+STREAM_HOST','+RESIDENT_U']+(['+SPARSE'] if sparse else []),cwd=R,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=1800)
    old=parse(R/f'evidence/cluster_immediate/conv5_sparse{sparse}.log');new=parse(p)
    for k in ('mac_lanes','U_words','compared_words','replacements'):assert old[k]==new[k],(k,old[k],new[k])
    assert new['source_reads']==3136
    results.append(dict(sparse=sparse,original=old,hwc8=new))
    (O/'results.json').write_text(json.dumps(results,indent=2))
    assert check()==baseline
    print(f'PASS sparse={sparse} cycles {old["cycles"]} -> {new["cycles"]}',flush=True)
(O/'provenance.json').write_text(json.dumps(dict(original_rtl_sha256=baseline,variant_sha256={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in D.glob('*.v')},tb_sha256=hashlib.sha256(tb.read_bytes()).hexdigest(),elapsed_seconds=time.monotonic()-start,scope='Separate HWC C%8==0 feed variant; original fallback for other modes. Conv5 16-core golden OFF/ON. No main RTL changes.'),indent=2))
