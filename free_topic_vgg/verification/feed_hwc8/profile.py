"""Read-only bottleneck audit of the isolated eight-channel feed variant."""
from pathlib import Path
import sys, subprocess, json, hashlib, re, time
R=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(R/'verification/bypass_profile'))
from cluster_probe import instrument
O=R/'evidence/feed8_bypass_audit'; W=R/'build/feed8_bypass_audit'
O.mkdir(parents=True,exist_ok=True); W.mkdir(parents=True,exist_ok=True)
manifest=json.loads((R/'evidence/report_baseline_700mhz/manifest.json').read_text(encoding='utf-8-sig'))
def hashes():
    h={f['path']:hashlib.sha256((R/f['path']).read_bytes()).hexdigest() for f in manifest['files']}
    assert all(h[f['path']].lower()==f['sha256'].lower() for f in manifest['files'])
    return h
initial=hashes(); started=time.monotonic()
tb=instrument((R/'build/cluster_immediate/tb.sv').read_text())
a=tb.index('        case(dut.u_cluster.u_feed.state)')
b=tb.index('        if(dut.u_cluster.feed_valid',a)
tb=tb[:a]+'''        if(!dut.u_cluster.u_feed.use_fast) $fatal(1,"Expected HWC8 feed");
        case(dut.u_cluster.u_feed.fast_path.state)
            1: if(dut.u_cluster.u_feed.fast_path.padding) build_pad++; else build_miss++;
            2: begin
                req_cycles++;
                if(!dut.u_cluster.u_feed.read_ready[0]) req_stall++;
                else if(!seen_words[dut.u_cluster.u_feed.fast_path.request_word]) begin
                    seen_words[dut.u_cluster.u_feed.fast_path.request_word]=1;unique_reads++;
                end
            end
            3: begin rsp_cycles++; if(!dut.u_cluster.u_feed.response_valid[0]) rsp_stall++;end
            4: if(dut.u_cluster.feed_ready) build_hit++; else build_block++;
            5: drain_cycles++;
            default: other_cycles++;
        endcase
'''+tb[b:]
tb=tb.replace('hit=%0d pad=%0d miss=%0d blocked=%0d','emit=%0d pad=%0d prepare=%0d blocked=%0d')
tb=tb.replace('drain=%0d other=%0d','finished=%0d other=%0d')
(W/'tb.sv').write_text(tb)
def run(cmd,path):
    with path.open('w') as f: subprocess.run(cmd,cwd=R,stdout=f,stderr=subprocess.STDOUT,check=True,timeout=1800)
run(['verilator','--binary','--timing','-Wno-fatal','-j','2','--top-module','tb_report_layer','--Mdir',str(W/'obj'),
     '-f','verification/feed_hwc8/sources.f','third_party/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v',str(W/'tb.sv')],O/'build.log')
print('BUILD PASS',flush=True)
rows=[]
previous=json.loads((R/'evidence/feed_group_sweep/results.json').read_text())
for stage in (2,4,10):
    for sparse in (0,1):
        log=O/f'conv{stage+1}_sparse{sparse}.log'
        run([str(W/'obj/Vtb_report_layer'),f'+LAYER={stage}','+STREAM_HOST','+RESIDENT_U']+(['+SPARSE'] if sparse else []),log)
        raw=log.read_text(); assert 'PASS ISOLATED_LAYER' in raw
        row={'layer':stage+1,'sparse':sparse,'cores':[]}
        for line in raw.splitlines():
            d={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)(?=\s|$)',line)}
            if line.startswith('PROFILE '):row['profile']=d
            if line.startswith('FEED_AUDIT '):row['feed']=d
            if line.startswith('CORE_AUDIT '):row['cores'].append(d)
            if line.startswith('LAYER_PASS '):row['result']=d
        ref=next(r for r in previous if r['layer']==stage and r['sparse']==sparse and r['variant']=='group8')
        for key in ('cycles','mac_lanes','weight_wait_corecycles'):
            assert row['profile'][key]==ref[key],(key,row['profile'][key],ref[key])
        assert len(row['cores'])==16 and hashes()==initial
        rows.append(row); (O/'results.json').write_text(json.dumps(rows,indent=2))
        print(f'PASS {len(rows)}/6 Conv{stage+1} sparse={sparse} cycles={row["profile"]["cycles"]}',flush=True)
(O/'provenance.json').write_text(json.dumps({'rtl_sha256':initial,'tb_sha256':hashlib.sha256(tb.encode()).hexdigest(),
 'variant_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (R/'verification/feed_hwc8').glob('*.v')},
 'elapsed_seconds':time.monotonic()-started,'scope':'Same one-image HWC isolated Conv3/5/11; initial preload excluded, runtime U transfers included; read-only counters; cycles identical to prior uninstrumented runs.'},indent=2))
