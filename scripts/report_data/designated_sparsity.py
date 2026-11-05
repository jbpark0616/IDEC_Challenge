"""Observe frozen RTL; classify exact Winograd row-zero causes, without RTL edits."""
from pathlib import Path
import csv, hashlib, json, re, subprocess
from collections import defaultdict

R=Path(__file__).resolve().parents[2]
O=R/'docs/experiment_results/designated/designated_sparsity'; O.mkdir(parents=True,exist_ok=True)
W=R/'build/report_designated_sparsity'; W.mkdir(parents=True,exist_ok=True)
frozen=json.loads((R/'docs/experiment_results/designated/designated_final/rtl_sha256.json').read_text())
def check():
    assert {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (R/'verilog').glob('*.v')}==frozen
check()
mon='''
always @(posedge clk) if(rst_n) begin
 if (`IT.in_valid && `IT.in_ready)
   $display("SPIN,%0d,%0d,%h",image_index,dut.u_accelerator.state,`IT.activation_tile);
 if (`IT.out_valid && `IT.out_ready)
   $display("SPOUT,%0d,%0d,%h,%h",image_index,dut.u_accelerator.state,`IT.v_tile,`IT.zero_rows);
end
'''.replace('`IT','dut.u_accelerator.u_core.u_input_transform')
tb=(R/'verification/winograd_chip_1000_tb.v').read_text().replace('../../../',R.as_posix()+'/')
tb=re.sub(r'localparam integer TEST_IMAGE_COUNT = \d+;', 'localparam integer TEST_IMAGE_COUNT = 100;',tb)
tb=tb.replace('(correct == 970)','(correct == 97)').replace('module winograd_chip_1000_tb;','module winograd_chip_1000_tb;\n'+mon)
(W/'tb.v').write_text(tb)
with (W/'compile.log').open('w') as f:
    subprocess.run(['iverilog','-g2012','-DTEST_M_FIFO_DEPTH_1','-s','winograd_chip_1000_tb','-o',str(W/'sim.vvp'),*map(str,sorted((R/'verilog').glob('*.v'))),str(W/'tb.v')],check=True,stdout=f,stderr=subprocess.STDOUT)
with (O/'simulation.log').open('w') as f:
    subprocess.run(['vvp','-n',str(W/'sim.vvp')],cwd=W,check=True,stdout=f,stderr=subprocess.STDOUT,timeout=1200)
log=(O/'simulation.log').read_text(); assert 'PASS' in log and 'FAIL' not in log and 'ERROR' not in log
ins=defaultdict(list); outs=defaultdict(list)
for line in log.splitlines():
    p=line.split(',')
    if p[0]=='SPIN': ins[tuple(map(int,p[1:3]))].append(int(p[3],16))
    if p[0]=='SPOUT': outs[tuple(map(int,p[1:3]))].append((int(p[3],16),int(p[4],16)))
rows=[]; tiles=[]; per=[]
for (im,state),inputs in sorted(ins.items()):
    assert state in (2,4)
    layer='Conv1' if state==2 else 'Conv2'
    outputs=outs[im,state]; assert len(inputs)==len(outputs)
    counts=defaultdict(int)
    for idx,(raw,(packed,mask)) in enumerate(zip(inputs,outputs)):
        d=[[raw>>((r*4+c)*8)&255 for c in range(4)] for r in range(4)]
        t=[[d[0][c]-d[2][c],d[1][c]+d[2][c],d[2][c]-d[1][c],d[1][c]-d[3][c]] for c in range(4)]
        t=[list(x) for x in zip(*t)]
        v=[[a-c,b+c,c-b,b-e] for a,b,c,e in t]
        expected=sum((v[r][c]&2047)<<((r*4+c)*11) for r in range(4) for c in range(4))
        assert expected==packed,(im,layer,idx)
        z=[all(x==0 for x in row) for row in v]
        assert mask==sum(int(x)<<r for r,x in enumerate(z))
        counts['tiles']+=1; counts['input_zero_elements']+=sum(x==0 for row in d for x in row)
        counts['v_zero_elements']+=sum(x==0 for row in v for x in row)
        counts['zero_rows']+=sum(z)
        counts['fully_zero_tiles']+=int(all(z)); counts['partial_zero_tiles']+=int(0<sum(z)<4)
        counts['no_zero_row_tiles']+=int(not any(z))
        for r,(a,b) in enumerate([(0,2),(1,2),(2,1),(1,3)]):
            cause='active'
            if z[r]:
                cause='zero_input_pair' if not any(d[a]+d[b]) else 'nonzero_cancellation'
            assert not(r==1 and cause=='nonzero_cancellation')
            counts[cause]+=1
            rows.append(dict(image=im,layer=layer,tile=idx,row=r,cause=cause))
        assert all(z)==(raw==0)
        tiles.append(dict(image=im,layer=layer,tile=idx,zero_rows=sum(z)))
    per.append(dict(image=im,layer=layer,**{k:counts[k] for k in ['tiles','input_zero_elements','v_zero_elements','zero_rows','fully_zero_tiles','partial_zero_tiles','no_zero_row_tiles','zero_input_pair','nonzero_cancellation','active']}))
summary=[]
for layer in ['Conv1','Conv2']:
    subset=[p for p in per if p['layer']==layer]; assert len(subset)==100
    s={k:sum(p[k] for p in subset) for k in subset[0] if k not in ('image','layer')}
    summary.append(dict(layer=layer,images=100,**s,**{k+'_percent':100*s[k]/(4*s['tiles']) for k in ['zero_input_pair','nonzero_cancellation','active','zero_rows']},input_zero_percent=100*s['input_zero_elements']/(16*s['tiles']),v_zero_percent=100*s['v_zero_elements']/(16*s['tiles'])))
def save(name,data):
    with (O/name).open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(data[0])); w.writeheader(); w.writerows(data)
save('row_causes.csv',rows);save('tile_histogram_source.csv',tiles);save('per_image.csv',per);save('summary.csv',summary)
# Verify the supplied dataset's repetition rather than treating repetitions as independent samples.
pixels=(R/'data/input_1000.txt').read_text().split(); assert len(pixels)==784000
hashes=[hashlib.sha256(' '.join(pixels[i:i+784]).encode()).hexdigest() for i in range(0,len(pixels),784)]
assert len(set(hashes))==100 and all(hashes[i]==hashes[i%100] for i in range(1000))
check()
(O/'provenance.json').write_text(json.dumps(dict(rtl_sha256=frozen,input_sha256=hashlib.sha256((R/'data/input_1000.txt').read_bytes()).hexdigest(),simulated_images=100,dataset_images=1000,unique_images=100,exact_transform_and_mask_matches=len(tiles),summary=summary),indent=2))
print(json.dumps(summary,indent=2),flush=True)
