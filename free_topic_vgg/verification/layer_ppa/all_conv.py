from pathlib import Path
import json,shutil,hashlib,subprocess,os,sys,argparse
ap=argparse.ArgumentParser(description="One VGG layer OFF/ON pair using the report measurement boundary")
ap.add_argument("--layer",type=int,choices=range(1,14),default=1)
args=ap.parse_args()
R=Path(__file__).resolve().parents[2];ROOT=R.parent
W=R/'build/all_conv_ppa';O=R/'evidence/all_conv_ppa';W.mkdir(parents=True,exist_ok=True);O.mkdir(parents=True,exist_ok=True)
V=W/'vectors';shutil.copytree(R/'verification/v8/vectors',V,dirs_exist_ok=True)
def read(p):return [int(x,16) for x in p.read_text().split()]
def dump(p,vals,bits=64):p.write_text(''.join(f'{v&((1<<bits)-1):0{bits//4}x}\n' for v in vals))
def pack(vals):return [sum(v<<(j*8) for j,v in enumerate(vals[i:i+8])) for i in range(0,len(vals),8)]
F=R/'verification/full_model/vectors_v8';fm=json.loads((F/'manifest.json').read_text());cfg=read(V/'config.hex');shifts=read(V/'vshift.hex');vs=read(F/'vshift.hex')
for stage in range(13):
    case=12+stage
    m=fm['layers'][stage];src=F/f'layer{stage}';dst=V/f'case{case}';dst.mkdir(exist_ok=True)
    h=m['input_h'];c=m['cin'];k=4;pairs=(c+1)//2
    cfg.append((h<<40)|(c<<24)|(k<<16)|(2<<8)|m['pool']);shifts.append(vs[stage])
    shutil.copyfile(src/'input.hex',dst/'input.hex');raw=read(src/'u.hex')
    # TB file indexing uses padded row/output-channel strides; SRAM writes
    # still use only ceil(Cin/2) words and DENSE_U, exactly as in the report.
    file_pairs=max(128,256 if c>128 else 128,512 if c>256 else 128)//2
    payload=[]
    for r in range(4):
        for ko in range(k):
            words=raw[(r*m['cout']+ko)*pairs:(r*m['cout']+ko+1)*pairs]
            assert len(words)==pairs
            payload.extend(words+[0]*(file_pairs-pairs))
    assert len(payload)==4*k*file_pairs
    dump(dst/'u8.hex',payload)
    for n,b in [('shift',4),('bias',32),('mult',24)]:dump(dst/f'{n}.hex',read(src/f'{n}.hex')[:k],b)
    a=[(w>>(8*j))&255 for w in read(src/'gold0.hex') for j in range(8)]
    n=1 if m['pool'] else 4
    values=[v for t in range(h*h//4) for v in a[t*m['local_k']*n:t*m['local_k']*n+k*n]]
    dump(dst/'gold.hex',pack(values))
dump(V/'config.hex',cfg);dump(V/'vshift.hex',shifts,4)
for n in ['core.v','extra.v']:shutil.copyfile(R/'build/layer_ppa'/n,W/n)
tb=(R/'build/layer_ppa/tb.sv').read_text().replace(str(R/'build/layer_ppa/vectors'),str(V)).replace('[0:11]','[0:24]').replace('inputs[0:1023]','inputs[0:8191]').replace('gold[0:255]','gold[0:4095]')
# Match the full-model command: normalized Conv1 input is signed; ReLU outputs are unsigned.
tb=tb.replace("pooling=config_words[case_id][0];", "input_signed=(case_id==12);pooling=config_words[case_id][0];")
# Watchdog and diagnostic output only; no stimulus or measurement changes.
tb=tb.replace('#100000000;', '#2000000000;')
tb=tb.replace('received++; compared++;', 'received++; compared++; if(received%32==0 || received==expected_words) $display("PROGRESS case=%0d sparse=%0d outputs=%0d/%0d time_ps=%0t",case_id,sparse,received,expected_words,$time);')
(W/'tb.sv').write_text(tb)
manifest=json.loads((R/'evidence/layer_ppa/manifest.json').read_text())
manifest.update(cases={str(12+i):f'Conv{i+1}' for i in range(13)},tb_sha256=hashlib.sha256(tb.encode()).hexdigest(),vectors={str(p.relative_to(W)):hashlib.sha256(p.read_bytes()).hexdigest() for p in V.rglob('*.hex')},source_model_manifest=fm)
(O/'manifest.json').write_text(json.dumps(manifest,indent=2))
with (O/'compile.log').open('w') as f:
 subprocess.run(['iverilog','-g2012','-s','tb_v8_packed','-o',str(W/'sim.vvp'),str(W/'core.v'),str(ROOT/'verification/asap7_functional_cells.v'),str(ROOT/'verification/asap7_final_extra_cells.v'),str(W/'extra.v'),str(R/'third_party/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v'),str(W/'tb.sv')],stdout=f,stderr=subprocess.STDOUT,check=True)
subprocess.run([sys.executable,str(Path(__file__).with_name('run.py')),'--cases',str(11+args.layer)],env=dict(os.environ,PPA_PROJECT=str(R),PPA_WORK=str(W),PPA_RESULTS=str(O)),check=True)
