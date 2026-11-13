"""Output regression on matched remapped implementations; not formal equivalence."""
from pathlib import Path
import subprocess,re,json,sys,os
R=Path(__file__).resolve().parents[2];ROOT=R.parent;O=R/'evidence/area_ablation_v2';W=R/'build/area_ablation_v2'
O=Path(os.environ.get('AREA_RESULTS',O))
cat=json.loads((ROOT/'docs/designated_final/asap7_rvt_ff_cells.json').read_text());cells={c['name']:c for c in cat['cells']}
models=[ROOT/'verification/asap7_functional_cells.v',ROOT/'verification/asap7_final_extra_cells.v']
defined=set(re.findall(r'\bmodule\s+(\w+)','\n'.join(p.read_text() for p in models)))
for mode,sparse in [('runtime',1),('disabled',0)]:
    if len(sys.argv)>1 and mode not in sys.argv[1:]:continue
    out=O/mode;net=out/'mapped.v';needed=set(re.findall(r'^\s*(\w+_ASAP7_75t_R)\s+',net.read_text(),re.M));extra=[]
    for name in sorted(needed-defined):
        if name.startswith('TAPCELL'):extra.append(f'module {name}();endmodule');continue
        c=cells[name];extra.append('module '+name+'('+','.join(p['direction']+' '+p['name'] for p in c['pins'])+');')
        for p in c['pins']:
            if p['direction']=='output':
                assert p['function'] is not None
                extra.append('assign '+p['name']+'='+p['function'].replace('!','~').replace('*','&').replace('+','|')+';')
        extra.append('endmodule')
    (out/'extra.v').write_text('\n'.join(extra))
    tb=(R/'build/controlled_power/fast/tb.sv').read_text()
    tb=tb.replace('$dumpfile(trace_path); $dumpvars(0,dut); $dumpoff;','').replace('$dumpon;','').replace('$dumpoff;','')
    (out/'tb.sv').write_text(tb)
    with (out/'compile.log').open('w') as f:
        subprocess.run(['iverilog','-g2012','-s','tb_v8_packed','-o',str(out/'sim.vvp'),str(net),*map(str,models),str(out/'extra.v'),str(R/'third_party/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v'),str(out/'tb.sv')],stdout=f,stderr=subprocess.STDOUT,check=True)
    with (out/'simulation.log').open('w') as f:subprocess.run(['vvp',str(out/'sim.vvp'),'+RESIDENT','+CASE=2',f'+SPARSE={sparse}'],stdout=f,stderr=subprocess.STDOUT,check=True,timeout=600)
    assert 'PASS U_LOADING' in (out/'simulation.log').read_text()
    print(mode,'PASS integer output comparison',flush=True)
if all((O/m/'simulation.log').exists() and 'PASS U_LOADING' in (O/m/'simulation.log').read_text() for m in ['runtime','disabled']):
    (O/'VALIDATION.txt').write_text('PASS both remapped implementations match independent integer outputs on controlled 50% zero-row input. This is a sampled functional regression, not formal equivalence.\n')
