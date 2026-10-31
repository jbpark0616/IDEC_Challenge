"""Profile the frozen U8/V8 TILE_INPUT core, changing only sparse_enable."""
from pathlib import Path
import csv,hashlib,json,re,subprocess,time,argparse
R=Path(__file__).resolve().parents[2]
ap=argparse.ArgumentParser();ap.add_argument('--baseline',default='evidence/design_freeze_20261030/manifest.json');ap.add_argument('--output',default='evidence/bypass_current');ap.add_argument('--work',default='build/bypass_current');args=ap.parse_args()
O=R/args.output;O.mkdir(parents=True,exist_ok=True)
W=R/args.work;W.mkdir(parents=True,exist_ok=True)
manifest=json.loads((R/args.baseline).read_text(encoding='utf-8-sig'))
def check():
    out={}
    for f in manifest['files']:
        p=f['path'];p=p if isinstance(p,str) else p['value']
        h=hashlib.sha256((R/p).read_bytes()).hexdigest();assert h.lower()==f['sha256'].lower(),p
        out[p]=h
    return out
hashes=check()
tb=(R/'verification/v8/tb_v8_packed.sv').read_text()
monitor='''
 integer elapsed=0,preload_cycles=0,mac_beats=0,mac_lanes=0;
 integer v_read_blocked=0,v_write_blocked=0,no_ready_channel=0,mac_backpressure=0;
 integer busy_cycles=0,result_blocked=0,weight_mac_overlap=0;
 bit profile_loading=0;
 always @(posedge clk) begin
   if(profile_loading) preload_cycles++;
   if(running) begin
     elapsed++;
     if(dut.u_core.u_engine.busy) busy_cycles++;
     if(dut.u_core.u_engine.response_valid && dut.u_core.u_engine.mac_ready) begin
       mac_beats++;mac_lanes+=4*$countones(dut.u_core.u_engine.response_rows);
       if(dut.weights_waiting) weight_mac_overlap++;
     end
     if((|dut.u_core.row_read) && !dut.u_core.row_accept) v_read_blocked++;
     if(|(dut.u_core.u_scratchpad.p_valid & ~dut.u_core.u_scratchpad.p_ready)) v_write_blocked++;
     if(dut.u_core.u_engine.busy && !dut.u_core.u_engine.last_requested
       && !(|dut.u_core.u_engine.remaining_valid) && !(&dut.u_core.u_engine.last_in_row)) no_ready_channel++;
     if(dut.u_core.u_engine.response_valid && !dut.u_core.u_engine.mac_ready) mac_backpressure++;
     if(dut.u_core.u_engine.result_valid && !dut.u_core.u_engine.result_ready) result_blocked++;
   end
 end
'''
tb=tb.replace('    initial begin\n        enable_resident=',monitor+'\n    initial begin\n        enable_resident=',1)
tb=tb.replace('weight_writes=0;load_block(0,0);','''elapsed=0;preload_cycles=0;mac_beats=0;mac_lanes=0;
                v_read_blocked=0;v_write_blocked=0;no_ready_channel=0;mac_backpressure=0;
                busy_cycles=0;result_blocked=0;weight_mac_overlap=0;
                weight_writes=0;profile_loading=1;load_block(0,0);profile_loading=0;''')
tb=tb.replace('                @(negedge clk);running=0;done_ready=1;','''                $display("DETAIL case=%0d sparse=%0d resident=%0d preload=%0d elapsed=%0d mac_beats=%0d mac_lanes=%0d v_read_blocked=%0d v_write_blocked=%0d no_ready_channel=%0d mac_backpressure=%0d busy=%0d result_blocked=%0d weight_mac_overlap=%0d",case_id,sparse,resident,preload_cycles,elapsed,mac_beats,mac_lanes,v_read_blocked,v_write_blocked,no_ready_channel,mac_backpressure,busy_cycles,result_blocked,weight_mac_overlap);
                @(negedge clk);running=0;done_ready=1;''')
(W/'tb.sv').write_text(tb)
start=time.monotonic()
with (O/'build.log').open('w') as f:
    subprocess.run(['verilator','--binary','--timing','-Wno-fatal','-j','2','--top-module','tb_v8_packed','-GDENSE_U=1','-GTILE_INPUT=1','--Mdir',str(W/'obj'),'-f','rtl/sources.f','third_party/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v',str(W/'tb.sv')],cwd=R,stdout=f,stderr=subprocess.STDOUT,check=True)
print('Build complete',flush=True)
allrows=[]
for mode,args in [('capacity_policy',['+RESIDENT']),('forced_reload',[])]:
    with (O/f'{mode}.log').open('w') as f:
        subprocess.run([str(W/'obj/Vtb_v8_packed'),*args],cwd=R,stdout=f,stderr=subprocess.STDOUT,check=True,timeout=600)
    log=(O/f'{mode}.log').read_text();assert 'PASS U_LOADING compared_words=694' in log
    result={}
    for line in log.splitlines():
        if line.startswith(('U_LOADING ','DETAIL ')):
            p=dict(re.findall(r'(\w+)=([\d,]+)',line));p={k:(v if ',' in v else int(v)) for k,v in p.items()}
            key=p['case'],p['sparse'];result.setdefault(key,{}).update(p)
    assert len(result)==24
    for p in result.values():
        _,h,w,c=map(int,p['input'].split(','));p.update(mode=mode,u_bytes=16*c*p['local_K'],u_capacity_bytes=32768,
            capacity_fits=int(p['local_K']*((c+1)//2)<=1024),preload_plus_run=p['preload']+p['elapsed'],data_kind='VGG activation' if p['case']>=10 else 'synthetic')
        allrows.append(p)
    print(mode,'PASS: 24 runs, 694 output words matched',flush=True)
with (O/'measurements.csv').open('w',newline='') as f:
    writer=csv.DictWriter(f,fieldnames=list(allrows[0]));writer.writeheader();writer.writerows(allrows)
effects=[]
for mode in ['capacity_policy','forced_reload']:
    for case in range(12):
        a,b=[p for p in allrows if p['mode']==mode and p['case']==case]
        assert a['sparse']==0 and b['sparse']==1
        assert a['U_words']==b['U_words'] and a['transforms']==b['transforms']
        effects.append(dict(mode=mode,case=case,input=a['input'],local_K=a['local_K'],data_kind=a['data_kind'],capacity_fits=a['capacity_fits'],resident=a['resident'],u_bytes=a['u_bytes'],cycles_off=a['cycles'],cycles_on=b['cycles'],cycle_reduction_percent=100*(1-b['cycles']/a['cycles']),inclusive_off=a['preload_plus_run'],inclusive_on=b['preload_plus_run'],inclusive_reduction_percent=100*(1-b['preload_plus_run']/a['preload_plus_run']),lane_reduction_percent=100*(1-b['mac_lanes']/a['mac_lanes']),weight_wait_off=a['weight_wait'],weight_wait_on=b['weight_wait'],v_read_blocked_off=a['v_read_blocked'],v_read_blocked_on=b['v_read_blocked'],no_ready_channel_off=a['no_ready_channel'],no_ready_channel_on=b['no_ready_channel']))
with (O/'effects.csv').open('w',newline='') as f:
    writer=csv.DictWriter(f,fieldnames=list(effects[0]));writer.writeheader();writer.writerows(effects)
assert check()==hashes
(O/'provenance.json').write_text(json.dumps(dict(rtl_sha256=hashes,testbench_sha256=hashlib.sha256(tb.encode()).hexdigest(),elapsed_seconds=time.monotonic()-start,scope='Single frozen core; U8/V8; TILE_INPUT=1; artificial tile stream stalls, NOT full cluster/DRAM latency',parameters=dict(DENSE_U=1,TILE_INPUT=1),vector_sha256={str(p.relative_to(R)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((R/'verification/v8/vectors').rglob('*.hex'))}),indent=2))
print(json.dumps([p for p in effects if p['mode']=='capacity_policy'],indent=2))
