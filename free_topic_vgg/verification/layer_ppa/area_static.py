"""Conservative constant propagation of mapped core with sparse_enable tied off.
No ABC remapping or RTL change. Retains all remaining physical cells.
"""
from pathlib import Path
import json,re,subprocess,itertools
R=Path(__file__).resolve().parents[2];O=R/'evidence/area_static';O.mkdir(exist_ok=True)
W=R/'build/area_ablation_v2';Y='/home/junbeom/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys'
cat=json.loads((R.parent/'docs/designated_final/asap7_rvt_ff_cells.json').read_text())
catalog={c['name']:c for c in cat['cells']}
ys=(R/'evidence/area_ablation_v2/runtime/run.ys').read_text().split('select -module')[0]
ys+=f'write_json {O}/original.json\n'
if not (O/'original.json').exists():subprocess.run([Y,'-Q','-T','-p',ys],stdout=(O/'read.log').open('w'),check=True)
net=json.loads((O/'original.json').read_text());m=net['modules']['ppa_core'];cells=m['cells']
const={m['ports']['sparse_enable']['bits'][0]:'0'}
# The command sparse latch samples the tied-low mode on command acceptance.
# Prove below that this is an inductive constant before removing that latch.
mode_ff=cells['sparse$_DFFE_PP_'];assert mode_ff['type'].startswith('DFFHQN')
const[mode_ff['connections']['QN'][0]]='1'
comb={}
for n,c in catalog.items():
    if n.startswith(('DFF','SDF','ICG','DHL','DLL','LATCH')):continue
    ins=[p['name'] for p in c['pins'] if p['direction']=='input']
    outs=[p for p in c['pins'] if p['direction']=='output']
    if not outs or any(not p['function'] for p in outs):continue
    if any(set(re.findall(r'[A-Za-z_]\w*',p['function']))-set(ins) for p in outs):continue
    comb[n]=(ins,outs)
cache={}
def outputs(n,pattern):
    key=(n,pattern)
    if key in cache:return cache[key]
    ins,outs=comb[n];unknown=[i for i,v in enumerate(pattern) if v not in ('0','1')];res=[set() for _ in outs]
    for values in itertools.product((0,1),repeat=len(unknown)):
        env={p:int(v) if v in ('0','1') else 0 for p,v in zip(ins,pattern)}
        for i,v in zip(unknown,values):env[ins[i]]=v
        for s,p in zip(res,outs):s.add(eval(p['function'].replace('!','~').replace('*','&').replace('+','|'),{'__builtins__':{}},env)&1)
    cache[key]=[str(next(iter(s))) if len(s)==1 else None for s in res];return cache[key]
def value(b):return const.get(b,b)
removed=set();iterations=0
while True:
    changed=False;iterations+=1
    for name,c in cells.items():
        if name in removed:continue
        typ=c['type'];pins=c['connections']
        if typ in comb:
            ins,outs=comb[typ];vals=outputs(typ,tuple(str(value(pins[p][0])) if value(pins[p][0]) in ('0','1') else '?' for p in ins))
            if all(v is not None for v in vals):
                for p,v in zip(outs,vals):
                    for bit in pins[p['name']]:const[bit]=v
                removed.add(name);changed=True
        elif typ.startswith('DFFHQ') and value(pins['D'][0]) in ('0','1'):
            # Constant D settles on the first active edge; regression includes reset clocks.
            if 'Q' in pins:const[pins['Q'][0]]=value(pins['D'][0])
            else:const[pins['QN'][0]]=str(1-int(value(pins['D'][0])))
            removed.add(name);changed=True
    if not changed:break
    print('constant iteration',iterations,'removed',len(removed),flush=True)
assert value(mode_ff['connections']['D'][0])=='0', 'Mode latch constant must be inductively proven'
# All side effects are in SRAM state whose output remains in the observable cone.
drivers={b:n for n,c in cells.items() if n not in removed for p,bs in c['connections'].items() if c['port_directions'][p]=='output' for b in bs if isinstance(b,int)}
pending=[value(b) for p in m['ports'].values() if p['direction']=='output' for b in p['bits']];needed=set()
while pending:
    n=drivers.get(pending.pop())
    if n is None or n in needed:continue
    needed.add(n);c=cells[n]
    pending.extend(value(b) for p,bs in c['connections'].items() if c['port_directions'][p]=='input' for b in bs)
counts={}
for n in needed:counts[cells[n]['type']]=counts.get(cells[n]['type'],0)+1
assert counts.get('srambank_256x4x64_6t122')==8
def area(cs):
    # Catalog is Liberty-derived; SRAM area is read from its supplied Liberty.
    sram=(R/'third_party/asap7_sram/generated/LIB/srambank_256x4x64_6t122.lib').read_text()
    sa=float(re.search(r'\barea\s*:\s*([\d.eE+-]+)',sram)[1])
    lib=(W/'std.lib').read_text()
    areas={n:float(re.search(r'\barea\s*:\s*([\d.eE+-]+)',body)[1]) for n,body in re.findall(r'\bcell\s*\(\s*"?([^\s"()]+)"?\s*\)(.*?)(?=\bcell\s*\(|\Z)',lib,re.S)}
    return sum((sa if c['type']=='srambank_256x4x64_6t122' else areas[c['type']]) for c in cs if c['type']!='$scopeinfo'),sa*8
a,sram=area(cells.values());b,_=area(cells[n] for n in needed)
m['cells']={n:c for n,c in cells.items() if n in needed}
for c in m['cells'].values():
    for p,bs in c['connections'].items():c['connections'][p]=[value(b) for b in bs]
for p in m['ports'].values():
    if p['direction']=='output':p['bits']=[value(b) for b in p['bits']]
for p in m['netnames'].values():p['bits']=[value(b) for b in p['bits']]
# Keep the external sparse_enable input distinct from its internal tied-off value.
(O/'disabled').mkdir(exist_ok=True);(O/'runtime').mkdir(exist_ok=True)
(O/'disabled/net.json').write_text(json.dumps(net))
subprocess.run([Y,'-Q','-T','-p',f'read_json {O}/disabled/net.json; check; write_verilog -noattr {O}/disabled/mapped.v'],stdout=(O/'write.log').open('w'),check=True)
import shutil
shutil.copyfile(R/'build/layer_ppa/core.v',O/'runtime/mapped.v')
(O/'comparison.json').write_text(json.dumps(dict(runtime_area_um2=a,disabled_area_um2=b,overhead_pct=100*(a-b)/b,logic_overhead_pct=100*(a-b)/(b-sram),sram_area_um2=sram,removed_cells=len(cells)-len(needed),method='Mapped-cell constant propagation and unused-cone removal; sparse_enable tied 0; all remaining cell types unchanged; common ICG and SRAM.'),indent=2))
print((O/'comparison.json').read_text(),flush=True)
