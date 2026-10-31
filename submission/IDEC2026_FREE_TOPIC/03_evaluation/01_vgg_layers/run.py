"""Sequential gate-level layer pairs with activity-annotated OpenROAD power."""
from pathlib import Path
import argparse,csv,gzip,hashlib,json,re,shutil,subprocess,time,os
R=Path(os.environ.get('PPA_PROJECT',Path(__file__).resolve().parents[2]))
W=Path(os.environ.get('PPA_WORK',R/'build/layer_ppa')); O=Path(os.environ.get('PPA_RESULTS',R/'evidence/layer_ppa'))
ORFS=Path(os.environ.get('ORFS_ROOT','/home/junbeom/OpenROAD-flow-scripts'))
OR=Path(os.environ.get('OPENROAD',ORFS/'tools/install/OpenROAD/bin/openroad'))
ap=argparse.ArgumentParser();ap.add_argument('--cases',nargs='+',type=int,default=[10,11]);a=ap.parse_args()
m=json.loads((O/'manifest.json').read_text())
libs=[str(ORFS/'flow/platforms/asap7/lib/NLDM'/Path(v['file']).name) for v in m['lib_files'].values()]
libs.append(str(R/'../02_libraries/asap7_sram/generated/LIB/srambank_256x4x64_6t122.lib'))
base='\n'.join('read_liberty {'+p+'}' for p in libs)
base+='\nread_lef {'+str(ORFS/'flow/platforms/asap7/lef/asap7_tech_1x_201209.lef')+'}\nread_lef {'+str(ORFS/'flow/platforms/asap7/lef/asap7sc7p5t_28_R_1x_220121a.lef')+'}\nread_lef {'+str(R/'../02_libraries/asap7_sram/generated/LEF/srambank_256x4x64_6t122.lef')+'}\n'
base+='\nread_verilog {'+str(W/'core.v')+'}\nlink_design ppa_core\n'
base+='create_clock -name clk -period 1430 [get_ports clk]\nset inputs [lsearch -inline -all -not -exact [all_inputs] [get_ports clk]]\nset_input_delay 200 -clock clk $inputs\nset_output_delay 200 -clock clk [all_outputs]\n'
cfg=[int(v,16) for v in (W/'vectors/config.hex').read_text().split()]
results=[]
for case in a.cases:
 for sparse in [0,1]:
    tag=f'case{case}_sparse{sparse}'; out=O/tag;out.mkdir(exist_ok=True)
    trace=W/(tag+'.vcd');log=out/'simulation.log'
    if (out/'measurement.json').exists():
        results.append(json.loads((out/'measurement.json').read_text())); print('REUSE',tag,flush=True);continue
    print('START',tag,flush=True); started=time.monotonic()
    if not(log.exists() and 'PASS U_LOADING' in log.read_text() and trace.exists()):
        with log.open('w') as f:
            subprocess.run(['vvp',str(W/'sim.vvp'),'+RESIDENT',f'+CASE={case}',f'+SPARSE={sparse}',f'+TRACE={trace}'],cwd=R,stdout=f,stderr=subprocess.STDOUT,check=True,timeout=3600)
    text=log.read_text();assert 'PASS U_LOADING' in text and 'FATAL' not in text,text[-2000:]
    window=re.search(r'PPA_WINDOW start_ps=(\d+) end_ps=(\d+) duration_ps=(\d+)',text);assert window
    start,end,duration=map(int,window.groups())
    # This OpenROAD build has no read_vcd -time option. Retain the dumpon
    # snapshot and measured execution only; normalize timestamps to zero.
    trimmed=trace.with_suffix('.window.vcd'); header=True; tick=-1
    if not (out/'power.tcl').exists():
        with trace.open() as src,trimmed.open('w') as dst:
            for line in src:
                if header:
                    dst.write(line)
                    if '$enddefinitions' in line:header=False
                elif line.startswith('#'):
                    tick=int(line[1:])
                    if tick>=end:break
                    if tick>=start:dst.write(f'#{tick-start}\n')
                elif start<=tick<end:dst.write(line)
            dst.write(f'#{duration}\n')
        trimmed.replace(trace)
    # OpenSTA accepts the initial snapshot as $dumpvars, not $dumpon.
    with trace.open() as src,trimmed.open('w') as dst:
        for line in src:dst.write(line.replace('$dumpon','$dumpvars'))
    trimmed.replace(trace)
    tcl=base+f'\nread_vcd -scope tb_v8_packed/dut {{{trace}}}\n'
    tcl+=f'report_activity_annotation -report_unannotated > {{{out}/activity.rpt}}\n'
    tcl+=f'report_power -digits 9 > {{{out}/power.rpt}}\n'
    tcl+=f'report_clock_min_period > {{{out}/timing.rpt}}\n'
    tcl+=f'report_design_area > {{{out}/area.rpt}}\nreport_checks -path_delay max -group_count 3 > {{{out}/paths.rpt}}\nexit\n'
    (out/'power.tcl').write_text(tcl)
    with (out/'openroad.log').open('w') as f:subprocess.run([str(OR),'-no_init','-exit',str(out/'power.tcl')],stdout=f,stderr=subprocess.STDOUT,check=True)
    annotation=(out/'activity.rpt').read_text()
    missing=re.search(r'unannotated\s+(\d+)',annotation);assert missing
    # The physical SRAM LEF exposes five sdel pins not present in the
    # supplied Liberty or behavioral model. No modeled digital pin may be missed.
    unmodeled=[l.strip() for l in annotation.splitlines() if '/sdel[' in l]
    assert int(missing[1])==len(unmodeled)==40,annotation[:4000]
    power=(out/'power.rpt').read_text(); match=re.search(r'^Total\s+\S+\s+\S+\s+\S+\s+(\S+)',power,re.M);assert match,power
    watts=float(match[1]); c=cfg[case]
    row=dict(case=case,sparse=sparse,input_NHWC=f'[1,{(c>>40)&63},{(c>>40)&63},{(c>>24)&1023}]',local_output_channels=(c>>16)&255,duration_ps=duration,clock_period_ps=1430,power_w=watts,energy_nj=watts*duration/1000,unannotated_lef_only_sdel_pins=40,analysis_elapsed_s=time.monotonic()-started,vcd_sha256=hashlib.sha256(trace.read_bytes()).hexdigest())
    (out/'measurement.json').write_text(json.dumps(row,indent=2));results.append(row)
    # Keep compressed measured activity for independent replay.
    with trace.open('rb') as src,gzip.open(out/'activity.vcd.gz','wb',compresslevel=1) as dest:shutil.copyfileobj(src,dest)
    trace.unlink()
    with (O/'measurements.csv').open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(row));writer.writeheader();writer.writerows(results)
    print('DONE',tag,row,flush=True)
print('PASS all requested layer-mode pairs',flush=True)
