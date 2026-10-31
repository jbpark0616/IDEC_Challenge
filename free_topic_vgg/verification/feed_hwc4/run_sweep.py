"""Three layers, identical original/4/8-channel feed conditions. Main RTL untouched."""
from pathlib import Path
import subprocess,json,hashlib,re,time
R=Path(__file__).resolve().parents[2];D=Path(__file__).resolve().parent
O=R/'evidence/feed_group_sweep';W=R/'build/feed_hwc4'
O.mkdir(parents=True,exist_ok=True);W.mkdir(parents=True,exist_ok=True)
m=json.loads((R/'evidence/report_baseline_700mhz/manifest.json').read_text(encoding='utf-8-sig'))
def check():
    h={f['path']:hashlib.sha256((R/f['path']).read_bytes()).hexdigest() for f in m['files']}
    assert all(h[f['path']].lower()==f['sha256'].lower() for f in m['files'])
    return h
rtl=check();start=time.monotonic();tb=R/'build/cluster_immediate/tb.sv'
def run(cmd,log,timeout=1800):
    with log.open('w') as f:subprocess.run(cmd,cwd=R,stdout=f,stderr=subprocess.STDOUT,check=True,timeout=timeout)
subprocess.run(['python3',str(D/'prepare.py')],check=True)
run(['iverilog','-g2012','-s','tb_feed','-o',str(W/'unit'),'-f',str(D/'sources.f'),
     'third_party/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v',str(D/'tb_feed.sv')],O/'unit_build.log')
run(['vvp',str(W/'unit')],O/'unit4.log')
assert 'PASS ALL_FEED' in (O/'unit4.log').read_text()
print('4-channel UNIT PASS',flush=True)
run(['verilator','--binary','--timing','-Wno-fatal','-j','2','--top-module','tb_report_layer','--Mdir',str(W/'obj'),
     '-f',str(D/'sources.f'),'third_party/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v',str(tb)],O/'build4.log')
print('BUILD COMPLETE',flush=True)
executables={'original':R/'build/cluster_immediate/obj/Vtb_report_layer',
             'group4':W/'obj/Vtb_report_layer','group8':R/'build/feed_hwc8/obj/Vtb_report_layer'}
def parse(p,stage):
    t=p.read_text();assert 'PASS ISOLATED_LAYER' in t
    out={}
    for line in t.splitlines():
        if line.startswith(('PROFILE ','LAYER_PASS ')):
            v={k:int(n) for k,n in re.findall(r'(\w+)=(\d+)(?=\s|$)',line)}
            if v['layer']==stage:out.update(v)
    assert out['layer']==stage
    return out
rows=[]
for stage in (4,2,10):
    for variant,exe in executables.items():
        for sparse in (0,1):
            p=O/f'conv{stage+1}_{variant}_sparse{sparse}.log'
            if stage==4 and variant in ('original','group8') and not p.exists():
                previous='cluster_immediate' if variant=='original' else 'feed_hwc8'
                p.write_bytes((R/f'evidence/{previous}/conv5_sparse{sparse}.log').read_bytes())
            if not p.exists() or 'PASS ISOLATED_LAYER' not in p.read_text():
                run([str(exe),f'+LAYER={stage}','+STREAM_HOST','+RESIDENT_U']+(['+SPARSE'] if sparse else []),p)
            v=parse(p,stage);v.update(variant=variant)
            if variant!='original':
                a=next(r for r in rows if r['layer']==stage and r['sparse']==sparse and r['variant']=='original')
                for k in ('mac_lanes','U_words','compared_words','replacements'):assert a[k]==v[k],(k,a[k],v[k])
            rows.append(v);assert check()==rtl
            (O/'results.json').write_text(json.dumps(rows,indent=2))
            (O/'progress.txt').write_text(f'{len(rows)}/18 completed\nConv{stage+1} {variant} sparse={sparse}\n')
            print(f'PASS {len(rows)}/18 Conv{stage+1} {variant} sparse={sparse}: cycles={v["cycles"]} reads={v["source_reads"]}',flush=True)
(O/'provenance.json').write_text(json.dumps({'rtl_sha256':rtl,'tb_sha256':hashlib.sha256(tb.read_bytes()).hexdigest(),
    'variant_sha256':{str(p.relative_to(R)):hashlib.sha256(p.read_bytes()).hexdigest() for folder in ('feed_hwc4','feed_hwc8') for p in (R/'verification'/folder).glob('*.v')},
    'scope':'Conv3/5/11 HWC inputs, all16 cores, same immediate shared host. OFF/ON. One image. Initial preload excluded.',
    'elapsed_seconds':time.monotonic()-start},indent=2))
