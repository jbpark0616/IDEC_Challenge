"""Map real 16-core periphery; compute cores are explicit area-excluded blackboxes."""
from pathlib import Path
import fnmatch,gzip,hashlib,json,re,subprocess,time,sys
R=Path(__file__).resolve().parents[2];W=R/'build/periphery16_synth';O=R/'evidence/periphery16_synth'
for p in [W,O]:p.mkdir(parents=True,exist_ok=True)
frozen=json.loads((R/'evidence/design_freeze_20261030/manifest.json').read_text(encoding='utf-8-sig'))
def check():
    hs={}
    for f in frozen['files']:
        p=f['path'];p=p if isinstance(p,str) else p['value'];h=hashlib.sha256((R/p).read_bytes()).hexdigest();assert h.lower()==f['sha256'].lower();hs[p]=h
    return hs
hashes=check()
effects=list(__import__('csv').DictReader((R/'evidence/bypass_controlled/effects.csv').open()))
assert len(effects)==32
assert all(float(p['cycle_reduction'])>=-1 for p in effects)
libdir=Path('/home/junbeom/OpenROAD-flow-scripts/flow/platforms/asap7/lib/NLDM')
files=[libdir/f'asap7sc7p5t_{n}_RVT_FF_nldm_{date}.lib{ext}' for n,date,ext in [('AO','211120','.gz'),('INVBUF','220122','.gz'),('OA','211120','.gz'),('SEQ','220123',''),('SIMPLE','211120','.gz')]]
cells={};header=None;templates={}
def extract(text):
    for m in re.finditer(r'\bcell\s*\(\s*"?([^\s"()]+)"?\s*\)\s*\{',text):
        level=1;i=m.end()
        while level:
            level+=(text[i]=='{')-(text[i]=='}');i+=1
        yield m.group(1),text[m.start():i]
for p in files:
    s=gzip.open(p,'rt').read() if p.suffix=='.gz' else p.read_text()
    if header is None:header=s[:re.search(r'\bcell\s*\(',s).start()]
    for m in re.finditer(r'\b(?:lu_table_template|power_lut_template)\s*\(\s*([^()]+)\)\s*\{',s):
        level=1;i=m.end()
        while level:
            level+=(s[i]=='{')-(s[i]=='}');i+=1
        templates[m.group(1).strip()]=s[m.start():i]
    for name,body in extract(s):assert name not in cells;cells[name]=body
extra='\n'.join(body for name,body in templates.items() if not re.search(r'\b(?:lu_table_template|power_lut_template)\s*\(\s*'+re.escape(name)+r'\s*\)',header))
merged=W/'std.lib';merged.write_text(header+extra+'\n'+'\n'.join(cells.values())+'\n}\n')
sr=R/'third_party/asap7_sram/generated/LIB/srambank_256x4x64_6t122.lib'
for name,body in extract(sr.read_text()):cells[name]=body
core=(R/'rtl/core/vgg_sram_conv_layer.v').read_text();stub=core[:core.index(');')+2]+'\nendmodule\n'
(W/'compute_blackbox.v').write_text(stub)
sources=['rtl/designated/elastic_fifo.v','rtl/interconnect/vgg_mcast_fanout.v','rtl/interconnect/vgg_activation_feed.v','rtl/memory/vgg_sram_8k.v','rtl/memory/vgg_activation_sram.v','rtl/vgg_ab_layer_cluster.v','rtl/vgg_sixteen_core_cluster.v']
excluded=[n for n in cells if any(fnmatch.fnmatch(n,p) for p in ['*x1p*_ASAP7*','*xp*_ASAP7*','SDF*'])]
script=f'''read_liberty -lib {merged}
read_liberty -lib {sr}
read_verilog -lib {W/'compute_blackbox.v'}
read_verilog {' '.join(str(R/p) for p in sources)}
hierarchy -check -top vgg_sixteen_core_cluster
synth -top vgg_sixteen_core_cluster -flatten
dfflibmap -liberty {merged}
abc -liberty {merged} -D 1000 {' '.join('-dont_use '+n for n in excluded)}
clean
check
stat -liberty {merged}
write_verilog -noattr {W/'mapped.v'}
write_json {W/'mapped.json'}
'''
(W/'run.ys').write_text(script)
start=time.monotonic();(O/'STATUS.txt').write_text('RUNNING: periphery only; 16 compute cores blackboxed\n')
if '--analyze-only' not in sys.argv:
    with (O/'synthesis.log').open('w') as f:
        subprocess.run(['/home/junbeom/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys','-s',str(W/'run.ys')],stdout=f,stderr=subprocess.STDOUT,check=True)
net=json.loads((W/'mapped.json').read_text());top=net['modules']['vgg_sixteen_core_cluster'];counts={}
for c in top['cells'].values():counts[c['type']]=counts.get(c['type'],0)+1
counts.pop('$scopeinfo',None)  # Yosys hierarchy metadata, not a physical cell.
core_count=sum(v for k,v in counts.items() if 'vgg_sram_conv_layer' in k);assert core_count==16,core_count
sram_count=counts.get('srambank_256x4x64_6t122',0);assert sram_count==64,sram_count
area=0;macro_area=0;ff=0;unmapped=[]
for n,count in counts.items():
    if 'vgg_sram_conv_layer' in n:continue
    if n not in cells:unmapped.append(n);continue
    body=cells[n];a=float(re.search(r'\barea\s*:\s*([\d.eE+-]+)',body).group(1))*count
    if n.startswith('srambank'):macro_area+=a
    else:area+=a
    if re.search(r'\bff\s*\(',body):ff+=count
assert not unmapped,unmapped
assert check()==hashes
result=dict(scope='Actual 16-core peripheral RTL; 16 compute core blackboxes excluded. No STA/P&R.',standard_cell_liberty_area=area,sram_liberty_area=macro_area,ff_cells=ff,sram_macros=sram_count,excluded_compute_cores=core_count,cell_counts=counts,rtl_sha256=hashes,library_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files+[sr]},elapsed_seconds=None if '--analyze-only' in sys.argv else time.monotonic()-start)
(O/'results.json').write_text(json.dumps(result,indent=2));(O/'STATUS.txt').write_text('PASS: mapped periphery; 16 compute core blackboxes + 64 A/B SRAM macros verified\n')
print(json.dumps({k:v for k,v in result.items() if k not in ['cell_counts','rtl_sha256','library_sha256']},indent=2),flush=True)
