"""Current 16-core RTL, isolated real VGG layers, identical OFF/ON input bytes."""
from pathlib import Path
import csv,hashlib,json,re,subprocess,time,argparse
ap=argparse.ArgumentParser()
ap.add_argument('--all',action='store_true',help='Measure all thirteen convolution layers in a separate evidence folder')
args=ap.parse_args()
R=Path(__file__).resolve().parents[2]; W=R/'build/report700/cluster'; O=R/'evidence/report700/cluster'
if args.all:
    W=R/'build/report700/cluster_all'; O=R/'evidence/report700/cluster_all'
stages=list(range(13)) if args.all else [0,4,8,12]
for d in (W,O):d.mkdir(parents=True,exist_ok=True)
manifest=json.loads((R/'evidence/report_baseline_700mhz/manifest.json').read_text(encoding='utf-8-sig'))
def hashes():
    result={f['path']:hashlib.sha256((R/f['path']).read_bytes()).hexdigest() for f in manifest['files']}
    assert all(result[f['path']].lower()==f['sha256'].lower() for f in manifest['files'])
    return result
source_hashes=hashes()
source=(R/'verification/full_model/tb_full_vgg_v8.sv').read_text()
source=source.replace('tb_full_vgg_v8','tb_report_layer').replace('inputs[0:383]','inputs[0:2047]')
source=source.replace('if(stage!=0) $fatal(1,"Intermediate activation came from TB");','// This experiment explicitly loads each layer input independently.')
source=source.replace('    initial begin\n        stream_host=', '''
    integer chosen_stage=0,activation_preload=0,activation_begin=0;
    integer measured_beats[0:15],measured_lanes[0:15],weight_waits[0:15],writer_stalls[0:15];
    integer sum_beats,sum_lanes,sum_waits,sum_writer;
    genvar m;
    generate for(m=0;m<16;m++) begin : monitor
        always @(posedge clk) begin
            if(!rst_n) begin measured_beats[m]<=0;measured_lanes[m]<=0;weight_waits[m]<=0;writer_stalls[m]<=0;end
            else if(dut.u_cluster.state==2) begin
                if(dut.u_cluster.g_core[m].u_compute.u_core.u_engine.response_valid && dut.u_cluster.g_core[m].u_compute.u_core.u_engine.mac_ready) begin
                    measured_beats[m]<=measured_beats[m]+1;
                    measured_lanes[m]<=measured_lanes[m]+4*$countones(dut.u_cluster.g_core[m].u_compute.u_core.u_engine.response_rows);
                end
                if(dut.u_cluster.g_core[m].u_compute.weights_waiting) weight_waits[m]<=weight_waits[m]+1;
                if(dut.u_cluster.g_core[m].output_valid && !dut.u_cluster.g_core[m].output_ready) writer_stalls[m]<=writer_stalls[m]+1;
            end
        end
    end endgenerate
    initial begin
        if(!$value$plusargs("LAYER=%d",chosen_stage)) $fatal(1,"missing LAYER");
        cmd_sparse=$test$plusargs("SPARSE");
        stream_host=''')
source=source.replace('        $readmemh("verification/full_model/vectors_v8/input.hex",inputs);','')
source=source.replace('        for(i=0;i<384;i++) store(0,8,i,inputs[i]);','')
source=source.replace('for(stage=0;stage<16;stage++)','for(stage=chosen_stage;stage<=chosen_stage;stage++)')
source=source.replace("cmd_phase=1'(stage);cmd_sharded=stage!=0;",'cmd_phase=0;cmd_sharded=0;')
source=source.replace('            weight_words=0;requests=0;load_begin=cycle;', '''
            if(h*h*cin>16384) $fatal(1,"input exceeds single HWC source region");
            path=$sformatf("verification/full_model/vectors_v8/layer%0d/input.hex",stage);
            $readmemh(path,inputs,0,(h*h*cin+7)/8-1);
            activation_begin=cycle;
            for(i=0;i<(h*h*cin+7)/8;i++) store(0,8+i/1024,i%1024,inputs[i]);
            activation_preload=cycle-activation_begin;
            weight_words=0;requests=0;load_begin=cycle;''')
marker='            total_commands+=int\'(total_cycles);check_begin=cycle;'
assert marker in source
source=source.replace(marker,'''            sum_beats=0;sum_lanes=0;sum_waits=0;sum_writer=0;
            for(i=0;i<16;i++) begin
                sum_beats+=measured_beats[i];sum_lanes+=measured_lanes[i];sum_waits+=weight_waits[i];sum_writer+=writer_stalls[i];
            end
            $display("PROFILE layer=%0d sparse=%0d activation_preload=%0d weight_preload=%0d cycles=%0d mac_beats=%0d mac_lanes=%0d weight_wait_corecycles=%0d writer_stall_corecycles=%0d",stage,cmd_sparse,activation_preload,load_cycles,total_cycles,sum_beats,sum_lanes,sum_waits,sum_writer);$fflush();
'''+marker)
start=source.index('        if(activation_writes!=384')
end=source.index('        $finish;',start)
source=source[:start]+'''        $display("PASS ISOLATED_LAYER stage=%0d sparse=%0d checked_words=%0d",chosen_stage,cmd_sparse,checked);$fflush();
'''+source[end:]
if args.all:
    # Large inputs use the existing channel-sharded layout produced by the
    # preceding layer. Do not enlarge SRAM or change the RTL feed path.
    source=source.replace('for(stage=chosen_stage;stage<=chosen_stage;stage++)',
        'for(stage=((chosen_stage==1 || chosen_stage==3) ? chosen_stage-1 : chosen_stage);stage<=chosen_stage;stage++)')
    source=source.replace('cmd_phase=0;cmd_sharded=0;', 'cmd_phase=(h*h*cin>16384);cmd_sharded=(h*h*cin>16384);')
    source=source.replace('if(h*h*cin>16384) $fatal(1,"input exceeds single HWC source region");','')
    begin=source.index('            path=$sformatf("verification/full_model/vectors_v8/layer%0d/input.hex",stage);')
    end=source.index('            activation_preload=cycle-activation_begin;',begin)
    source=source[:begin]+'''            activation_begin=cycle;
            if(cmd_sharded) begin
                // The preceding layer produced and committed region B.
                // No hierarchical descriptor injection or intermediate reload.
                if(!committed_regions[1]) $fatal(1,"Missing preceding layer commit");
            end else begin
                path=$sformatf("verification/full_model/vectors_v8/layer%0d/input.hex",stage);
                $readmemh(path,inputs,0,(h*h*cin+7)/8-1);
                for(i=0;i<(h*h*cin+7)/8;i++) store(0,8+i/1024,i%1024,inputs[i]);
            end
'''+source[end:]
    source=source.replace('            @(negedge clk);cmd_valid=1;', '''            @(negedge clk);
            for(i=0;i<16;i++) begin
                measured_beats[i]=0;measured_lanes[i]=0;weight_waits[i]=0;writer_stalls[i]=0;
            end
            cmd_valid=1;''')
(W/'tb.sv').write_text(source)
with (O/'build.log').open('w') as log:
    subprocess.run(['verilator','--binary','--timing','-Wno-fatal','-j','2','--top-module','tb_report_layer','--Mdir',str(W/'obj'),'-f','rtl/sources.f','third_party/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v',str(W/'tb.sv')],cwd=R,stdout=log,stderr=subprocess.STDOUT,check=True)
vector_root=R/'verification/full_model/vectors_v8'
model=json.loads((vector_root/'manifest.json').read_text())
rows=[];effects=[]
def save(name,values):
    with (O/name).open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(values[0]));writer.writeheader();writer.writerows(values)
for stage in stages:
    info=model['layers'][stage]
    for sparse in [0,1]:
        begin=time.monotonic();file=O/f'conv{stage+1}_sparse{sparse}.log'
        # Resume completed logs; retain the original four layer measurements.
        if args.all and stage in [0,4,8,12] and not file.exists():
            previous=R/'evidence/report700/cluster'
            old=json.loads((previous/'provenance.json').read_text())
            assert old['rtl_sha256']==source_hashes
            file.write_bytes((previous/file.name).read_bytes())
        if not file.exists() or 'PASS ISOLATED_LAYER' not in file.read_text():
            with file.open('w') as log:
                subprocess.run([str(W/'obj/Vtb_report_layer'),f'+LAYER={stage}','+STREAM_HOST','+RESIDENT_U']+(['+SPARSE'] if sparse else []),cwd=R,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=7200)
        text=file.read_text();assert 'PASS ISOLATED_LAYER' in text
        row={}
        for line in text.splitlines():
            if line.startswith(('PROFILE ','LAYER_PASS ')):
                parsed={k:int(v) for k,v in re.findall(r'(\w+)=([0-9]+)(?=\s|$)',line)}
                if parsed['layer']==stage: row.update(parsed)
        row.update(input_NHWC=f"[1,{info['input_h']},{info['input_h']},{info['cin']}]",output_channels=info['cout'],u_bytes_per_core=16*info['cin']*info['local_k'],image_index=model['image_index'],clock_mhz=700,
            inclusive_cycles=row['activation_preload']+row['weight_preload']+row['cycles'],simulation_seconds=None,
            input_layout='preceding-layer committed shards' if info['input_h']**2*info['cin']>16384 else 'core0 HWC')
        row['inclusive_latency_us_at_700mhz']=row['inclusive_cycles']/700
        rows.append(row);save('measurements.csv',rows)
        assert hashes()==source_hashes
        print(f"PASS Conv{stage+1} sparse={sparse} cycles={row['cycles']} lanes={row['mac_lanes']}",flush=True)
    a,b=rows[-2:];assert a['U_words']==b['U_words'] and a['source_reads']==b['source_reads']
    effects.append(dict(layer=stage+1,input_NHWC=a['input_NHWC'],output_channels=info['cout'],resident_u=a['resident_u'],u_bytes_per_core=a['u_bytes_per_core'],cycles_off=a['cycles'],cycles_on=b['cycles'],cycle_reduction_percent=100*(1-b['cycles']/a['cycles']),inclusive_off=a['inclusive_cycles'],inclusive_on=b['inclusive_cycles'],inclusive_reduction_percent=100*(1-b['inclusive_cycles']/a['inclusive_cycles']),mac_lane_reduction_percent=100*(1-b['mac_lanes']/a['mac_lanes'])))
    save('effects.csv',effects)
    (O/'provenance.json').write_text(json.dumps(dict(rtl_sha256=source_hashes,tb_sha256=hashlib.sha256(source.encode()).hexdigest(),completed_runs=len(rows),image_index=model['image_index'],scope='16-core isolated layers; core0 HWC input, or existing channel-sharded input for tensors exceeding 16KiB. Not whole-network latency or multi-image mean.',reused_original_layers=[0,4,8,12] if args.all else [],vectors={str(p.relative_to(vector_root)):hashlib.sha256(p.read_bytes()).hexdigest() for s in stages for p in (vector_root/f'layer{s}').glob('*.hex')}),indent=2))
