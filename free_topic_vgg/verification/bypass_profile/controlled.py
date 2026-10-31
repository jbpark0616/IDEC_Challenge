"""Fixed-shape factorial experiment; legal spatial activations, independent oracle."""
from pathlib import Path
import ast,csv,hashlib,json,re,subprocess,time,argparse
ap=argparse.ArgumentParser();ap.add_argument('--baseline',default='evidence/design_freeze_20261030/manifest.json');ap.add_argument('--output',default='evidence/bypass_controlled');ap.add_argument('--work',default='build/bypass_controlled');ap.add_argument('--channels',type=int,choices=[32,128,512],default=128);args=ap.parse_args()
C=args.channels
R=Path(__file__).resolve().parents[2];O=R/args.output;W=R/args.work;V=W/'vectors'
for p in [O,W,V]:p.mkdir(parents=True,exist_ok=True)
manifest=json.loads((R/args.baseline).read_text(encoding='utf-8-sig'))
def check():
    hashes={}
    for f in manifest['files']:
        p=f['path'];p=p if isinstance(p,str) else p['value'];h=hashlib.sha256((R/p).read_bytes()).hexdigest()
        assert h.lower()==f['sha256'].lower(),p;hashes[p]=h
    return hashes
hashes=check()
def dump(p,vals,bits=64):p.write_text(''.join(f'{int(n)&((1<<bits)-1):0{bits//4}x}\n' for n in vals))
def pack(vals):return [sum((int(n)&255)<<(8*j) for j,n in enumerate(vals[i:i+8])) for i in range(0,len(vals),8)]
def matmul(a,b):return [[sum(x*y for x,y in zip(row,col)) for col in zip(*b)] for row in a]
def tr(a):return list(map(list,zip(*a)))
bt=[[1,0,-1,0],[0,1,1,0],[0,-1,1,0],[0,1,0,-1]];at=[[1,1,1,0],[0,1,-1,-1]];g=[[2,0,0],[1,1,1],[1,-1,1],[0,0,2]]
patterns=['dense','balanced25','balanced50','balanced75','allzero','unbalanced50','frontzero50','tailzero50']
configs=[];stats=[];gold_words=0
for block,kout in enumerate([8,32]):
 for pi,name in enumerate(patterns):
    case=block*8+pi;dst=V/f'case{case}';dst.mkdir(exist_ok=True)
    def row_values(ch):
        zero=(name=='allzero' or name=='balanced25' and ch%4==0 or name=='balanced50' and ch%2==0 or name=='balanced75' and ch%4!=3 or name=='frontzero50' and ch<C//2 or name=='tailzero50' and ch>=C//2)
        return [0]*4 if zero else [1]*4 if name=='unbalanced50' else [1,2,3,4]
    x=[[[row_values(ch)[y] for ch in range(C)] for xx in range(4)] for y in range(4)]
    u=[]
    for k in range(kout):
        channels=[]
        for ch in range(C):
            kernel=[[(k*3+ch*5+r*2+c)%5-2 for c in range(3)] for r in range(3)]
            channels.append(matmul(matmul(g,kernel),tr(g)))
        u.append(channels)
    dump(dst/'input.hex',pack([n for row in x for pixel in row for n in pixel]))
    dump(dst/'u8.hex',[sum((u[k][ch+half][r][col]&255)<<((half*4+col)*8) for half in range(2) for col in range(4)) for r in range(4) for k in range(kout) for ch in range(0,C,2)])
    dump(dst/'shift.hex',[0]*kout,4);dump(dst/'bias.hex',[2000]*kout,32);dump(dst/'mult.hex',[65536]*kout,24)
    gold=[];zero_counts=[0]*4;ideal=0;tiles=0
    for yy in [0,2]:
      for xx in [0,2]:
        vs=[];active=[0]*4
        for ch in range(C):
            d=[[x[yy+r-1][xx+c-1][ch] if 0<=yy+r-1<4 and 0<=xx+c-1<4 else 0 for c in range(4)] for r in range(4)]
            v=matmul(matmul(bt,d),tr(bt));assert max(abs(n) for row in v for n in row)<=127
            vs.append(v);tiles+=1
            for r in range(4):zero_counts[r]+=int(not any(v[r]));active[r]+=int(any(v[r]))
        ideal+=max(active)*kout
        for k in range(kout):
            m=[[sum(u[k][ch][r][c]*vs[ch][r][c] for ch in range(C)) for c in range(4)] for r in range(4)]
            result=matmul(matmul(at,m),tr(at))
            gold.extend(min(255,(max(0,n+2000)*65536+(1<<23))>>24) for row in result for n in row)
    dump(dst/'gold.hex',pack(gold));gold_words+=len(pack(gold))*2
    configs.append((4<<40)|(C<<24)|(kout<<16)|(min(8,2048//C)<<8))
    stats.append(dict(case=case,pattern=name,input_NHWC=f'1,4,4,{C}',local_K=kout,u_bytes=16*C*kout,zero_row_percent=100*sum(zero_counts)/(4*tiles),ideal_dense_beats=tiles*kout,ideal_sparse_beats=ideal,**{f'row{r}_zero_percent':100*zero_counts[r]/tiles for r in range(4)}))
dump(V/'config.hex',configs);dump(V/'vshift.hex',[0]*16,4)
tb=(R/'verification/v8/tb_v8_packed.sv').read_text()
monitor=next(ast.literal_eval(n.value) for n in ast.parse((Path(__file__).parent/'run.py').read_text()).body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='monitor' for t in n.targets))
tb=tb.replace('    initial begin\n        enable_resident=',monitor+'\n    initial begin\n        enable_resident=',1)
tb=tb.replace('weight_writes=0;load_block(0,0);','''elapsed=0;preload_cycles=0;mac_beats=0;mac_lanes=0;
                v_read_blocked=0;v_write_blocked=0;no_ready_channel=0;mac_backpressure=0;
                busy_cycles=0;result_blocked=0;weight_mac_overlap=0;
                weight_writes=0;profile_loading=1;load_block(0,0);profile_loading=0;''')
tb=tb.replace('                @(negedge clk);running=0;done_ready=1;','''                $display("DETAIL case=%0d sparse=%0d resident=%0d preload=%0d elapsed=%0d mac_beats=%0d mac_lanes=%0d v_read_blocked=%0d v_write_blocked=%0d no_ready_channel=%0d mac_backpressure=%0d busy=%0d result_blocked=%0d",case_id,sparse,resident,preload_cycles,elapsed,mac_beats,mac_lanes,v_read_blocked,v_write_blocked,no_ready_channel,mac_backpressure,busy_cycles,result_blocked);
                @(negedge clk);running=0;done_ready=1;''')
tb=tb.replace('verification/v8/vectors',V.relative_to(R).as_posix()).replace('config_words[0:11]','config_words[0:15]').replace('vshifts[0:11]','vshifts[0:15]').replace('case_id<12','case_id<16')
tb=tb.replace('if(case_id==5 && sparse && mac_row_issues!=0)','if((case_id==4 || case_id==12) && sparse && mac_row_issues!=0)')
tb=tb.replace('cycle%7!=0','(!$test$plusargs("SLOW") || cycle%4==0)').replace('cycle%13<9',"1'b1")
# Generated U vectors are densely packed for the requested channel count.
tb=tb.replace('stride=cin>256 ? 512 : cin>128 ? 256 : 128;', 'stride=cin;')
tb=tb.replace('requests!=h*h/4*(kout/block_k)-1','requests!=(resident && kout==block_k ? 0 : h*h/4*(kout/block_k)-1)')
same_tb=(W/'tb.sv').exists() and (W/'tb.sv').read_text()==tb
(W/'tb.sv').write_text(tb)
start=time.monotonic()
if not same_tb or not (W/'obj/Vtb_v8_packed').exists():
 with (O/'build.log').open('w') as f:
    subprocess.run(['verilator','--binary','--timing','-Wno-fatal','-j','2','--top-module','tb_v8_packed','-GDENSE_U=1','-GTILE_INPUT=1','--Mdir',str(W/'obj'),'-f','rtl/sources.f','third_party/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v',str(W/'tb.sv')],cwd=R,stdout=f,stderr=subprocess.STDOUT,check=True)
print('Build complete',flush=True)
measure=[]
for rate,args in [('fast',[]),('slow',['+SLOW'])]:
 with (O/f'{rate}.log').open('w') as f:
    subprocess.run([str(W/'obj/Vtb_v8_packed'),'+RESIDENT',*args],cwd=R,stdout=f,stderr=subprocess.STDOUT,check=True,timeout=600)
 log=(O/f'{rate}.log').read_text();assert f'PASS U_LOADING compared_words={gold_words}' in log
 parsed={}
 for line in log.splitlines():
    if line.startswith(('U_LOADING ','DETAIL ')):
        p=dict(re.findall(r'(\w+)=([\d,]+)',line));p={k:(v if ',' in v else int(v)) for k,v in p.items()};parsed.setdefault((p['case'],p['sparse']),{}).update(p)
 assert len(parsed)==32
 for p in parsed.values():
    st=stats[p['case']];expected=st['ideal_dense_beats']*16*(1-st['zero_row_percent']/100 if p['sparse'] else 1)
    assert abs(p['mac_lanes']-expected)<1e-6,(p,st)
    assert p['mac_beats']>=st['ideal_sparse_beats'] if p['sparse'] else p['mac_beats']==st['ideal_dense_beats']
    measure.append({'rate':rate,**p,**st})
 print(rate,f'PASS 32 runs; {gold_words} output words; MAC work matches oracle',flush=True)
def save(name,rows):
 with (O/name).open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
effects=[]
for rate in ['fast','slow']:
 for case in range(16):
    a,b=[p for p in measure if p['rate']==rate and p['case']==case]
    assert a['U_words']==b['U_words']
    effects.append(dict(rate=rate,**stats[case],cycles_off=a['cycles'],cycles_on=b['cycles'],cycle_reduction=100*(1-b['cycles']/a['cycles']),mac_beats_off=a['mac_beats'],mac_beats_on=b['mac_beats'],ideal_beat_reduction=100*(1-b['ideal_sparse_beats']/b['ideal_dense_beats']),actual_beat_reduction=100*(1-b['mac_beats']/a['mac_beats']),wait_off=a['no_ready_channel'],wait_on=b['no_ready_channel'],weight_wait_off=a['weight_wait'],weight_wait_on=b['weight_wait'],v_block_off=a['v_read_blocked'],v_block_on=b['v_read_blocked'],inclusive_off=a['preload']+a['elapsed'],inclusive_on=b['preload']+b['elapsed']))
save('measurements.csv',measure);save('effects.csv',effects);save('patterns.csv',stats)
assert check()==hashes
(O/'provenance.json').write_text(json.dumps(dict(rtl_sha256=hashes,tb_sha256=hashlib.sha256(tb.encode()).hexdigest(),vector_sha256={str(p.relative_to(W)):hashlib.sha256(p.read_bytes()).hexdigest() for p in V.rglob('*.hex')},elapsed_seconds=time.monotonic()-start,tests=64,matched_words_per_supply_rate=gold_words),indent=2))
for p in effects:print(p['rate'],p['local_K'],p['pattern'],p['zero_row_percent'],p['cycles_off'],p['cycles_on'],round(p['cycle_reduction'],2),p['mac_beats_on'],p['ideal_sparse_beats'],flush=True)
