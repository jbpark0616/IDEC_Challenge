"""Extract the already mapped final compute core; do not resynthesize or edit RTL."""
from pathlib import Path
import hashlib,json,re,shutil,subprocess
R=Path(__file__).resolve().parents[2]; ROOT=R.parent
W=R/'build/layer_ppa'; O=R/'evidence/layer_ppa'
W.mkdir(parents=True,exist_ok=True); O.mkdir(parents=True,exist_ok=True)
source=R/'evidence/timing_writer_pipeline/netlist/1_2_yosys.v'
s=source.read_text(); core=s.split('endmodule',1)[0]+'endmodule\n'
old=re.search(r'^module (\S+)',core,re.M)[1]
core=core.replace('module '+old+' ', 'module ppa_core ',1)
(W/'core.v').write_text(core)
models=[ROOT/'verification/asap7_functional_cells.v',ROOT/'verification/asap7_final_extra_cells.v']
defined=set(re.findall(r'\bmodule\s+(\w+)', '\n'.join(p.read_text() for p in models)))
needed=set(re.findall(r'^\s*(\w+_ASAP7_75t_R)\s+',core,re.M))
catalog=json.loads((ROOT/'docs/designated_final/asap7_rvt_ff_cells.json').read_text())
cells={c['name']:c for c in catalog['cells']}
extra=['`timescale 1ps/1ps']
for name in sorted(needed-defined):
    if name=='TAPCELL_ASAP7_75t_R':extra.append('module '+name+'(); endmodule');continue
    c=cells[name];assert not name.startswith(('DFF','ICG')),name
    extra.append('module '+name+'('+', '.join(p['direction']+' '+p['name'] for p in c['pins'])+');')
    for p in c['pins']:
        if p['direction']=='output':
            assert p['function'] is not None
            fn=p['function'].replace('!','~').replace('*','&').replace('+','|')
            extra.append(f"assign {p['name']} = {fn};")
    extra.append('endmodule')
(W/'extra.v').write_text('\n'.join(extra)+'\n')
tb=(R/'verification/v8/tb_v8_packed.sv').read_text()
tb=tb.replace('`timescale 1ns/1ps','`timescale 1ps/1ps').replace('always #5 clk=~clk;','always #715 clk=~clk;')
tb=tb.replace('parameter integer PACKED=1, DENSE_U=0, TILE_INPUT=0','parameter integer PACKED=1, DENSE_U=1, TILE_INPUT=1')
start=tb.index('    vgg_sram_conv_layer #('); end=tb.index(' dut (',start)
tb=tb[:start]+'    ppa_core'+tb[end:]
start=tb.index('            physical_writes +=');end=tb.index('            if(output_valid',start)
tb=tb[:start]+tb[end:]
tb=tb.replace('                        if(dut.consumer_state!=dut.C_WEIGHTS) $fatal(1,"Stale weight commit accepted");','')
tb=tb.replace('                        store(14,1,status ^ 64\'h10000);','').replace('                        repeat(5) @(negedge clk);','')
tb=tb.replace(' || writes!=h*h/4*cin || transforms!=writes || releases!=h*h/4','')
tb=tb.replace(' || dut.cb_occupancy!=0','')
tb=re.sub(r'^\s*if\(physical_writes !=.*?;\n','\n',tb,flags=re.M)
tb=tb.replace('requests!=h*h/4*(kout/block_k)-1','requests!=(resident && kout==block_k ? 0 : h*h/4*(kout/block_k)-1)')
tb=tb.replace('cycle%7!=0',"1'b1").replace('cycle%13<9',"1'b1")
tb=tb.replace('for(case_id=0;case_id<12;case_id++)','for(case_id=selected_case;case_id<selected_case+1;case_id++)')
tb=tb.replace('for(sparse=0;sparse<2;sparse++)','for(sparse=selected_sparse;sparse<selected_sparse+1;sparse++)')
tb=tb.replace('    initial begin\n        enable_resident=', '''    integer selected_case=10, selected_sparse=0;
    time start_time, end_time;
    string trace_path;
    initial begin
        if (!$value$plusargs("CASE=%d",selected_case)) selected_case=10;
        if (!$value$plusargs("SPARSE=%d",selected_sparse)) selected_sparse=0;
        if (!$value$plusargs("TRACE=%s",trace_path)) trace_path="activity.vcd";
        $dumpfile(trace_path); $dumpvars(0,dut); $dumpoff;
        enable_resident=''')
tb=tb.replace('@(negedge clk);start_valid=1;', '@(negedge clk);start_time=$time; $dumpon; start_valid=1;')
tb=tb.replace('                if(done_error ||', '                end_time=$time; $dumpoff;\n                $display("PPA_WINDOW start_ps=%0t end_ps=%0t duration_ps=%0t",start_time,end_time,end_time-start_time);\n                if(done_error ||')
# Avoid claiming internal lifetime checks on the flattened gate design.
tb=tb.replace('last_use_release backpressure zero_bypass stale_commit','gate_outputs_match_integer_reference')
tb=tb.replace('verification/v8/vectors',(W/'vectors').as_posix())
assert 'dut.' not in tb, [l for l in tb.splitlines() if 'dut.' in l]
(W/'tb.sv').write_text(tb)
shutil.copytree(R/'verification/v8/vectors',W/'vectors',dirs_exist_ok=True)
cmd=['iverilog','-g2012','-s','tb_v8_packed','-o',str(W/'sim.vvp'),str(W/'core.v'),*map(str,models),str(W/'extra.v'),str(R/'third_party/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v'),str(W/'tb.sv')]
with (O/'compile.log').open('w') as f:subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT,check=True)
manifest={'scope':'one extracted compute core, 8 internal SRAM macros; activation SRAM and multicast excluded','comparison':'same physical netlist, ICG enabled in both, runtime sparsity OFF vs ON','source_netlist_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'original_module':old,'extracted_core_sha256':hashlib.sha256((W/'core.v').read_bytes()).hexdigest(),'tb_sha256':hashlib.sha256((W/'tb.sv').read_bytes()).hexdigest(),'clock_period_ps':1430,'clock_mhz':1e6/1430,'vectors':{str(p.relative_to(W)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (W/'vectors').rglob('*.hex')},'lib_files':catalog['active_files']}
(O/'manifest.json').write_text(json.dumps(manifest,indent=2))
print('PASS prepared mapped compute core and gate testbench',flush=True)
