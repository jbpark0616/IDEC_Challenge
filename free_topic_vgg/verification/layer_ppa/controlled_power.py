"""Controlled gate experiment; no frozen RTL modifications. Run under WSL."""
from pathlib import Path
import csv,hashlib,json,os,re,shutil,subprocess,sys,time
R=Path(__file__).resolve().parents[2]; ROOT=R.parent
W=R/'build/controlled_power'; O=R/'evidence/controlled_power'
W.mkdir(parents=True,exist_ok=True);O.mkdir(parents=True,exist_ok=True)
source=R/'verification/bypass_profile/controlled.py'
# Reuse the independent spatial-input and integer-output generator, not its RTL runner.
prefix=source.read_text().split("tb=(R/'verification/v8/tb_v8_packed.sv').read_text()",1)[0]
# Its old RTL freeze check belongs to its RTL runner, not this vector-only use.
# This experiment uses the already audited final mapped core, never that old RTL.
prefix=prefix.replace('hashes=check()', 'hashes={} # vector generation only; mapped netlist provenance below')
sys.argv=[str(source),'--channels','32','--work','build/controlled_power','--output','evidence/controlled_power']
ns={'__file__':str(source),'__name__':'controlled_vectors'}
exec(compile(prefix,str(source),'exec'),ns)
stats=ns['stats']
(O/'patterns.json').write_text(json.dumps(stats,indent=2))
for n in ['core.v','extra.v']:shutil.copyfile(R/'build/layer_ppa'/n,W/n)
template=(R/'build/layer_ppa/tb.sv').read_text()
template=template.replace(str(R/'build/layer_ppa/vectors'),str(W/'vectors'))
template=template.replace('config_words[0:11]','config_words[0:15]').replace('vshifts[0:11]','vshifts[0:15]')
template=template.replace('stride=cin>256 ? 512 : cin>128 ? 256 : 128;','stride=cin;')
template=template.replace('if(case_id==5 && sparse && mac_row_issues!=0)','if(case_id==4 && sparse && mac_row_issues!=0)')
manifest=json.loads((R/'evidence/layer_ppa/manifest.json').read_text())
assert hashlib.sha256((W/'core.v').read_bytes()).hexdigest()==manifest['extracted_core_sha256']
manifest.update(controlled_shape='[1,4,4,32] -> 8 channels',generator_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),vectors={str(p.relative_to(W)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (W/'vectors').rglob('*.hex')})
def progress(message):
    done=len(list(O.glob('*/case*/measurement.json')))
    (O/'PROGRESS.txt').write_text(f'{done}/20 completed ({done*5}%)\n{message}\n')
    print(message,flush=True)
for rate,period in [('fast',1),('slow',4)]:
    work=W/rate;out=O/rate;work.mkdir(exist_ok=True);out.mkdir(exist_ok=True)
    for n in ['core.v','extra.v']:shutil.copyfile(W/n,work/n)
    shutil.copytree(W/'vectors',work/'vectors',dirs_exist_ok=True)
    tb=template.replace(str(W/'vectors'),str(work/'vectors'))
    tb=tb.replace("activation_valid=running && sent<input_words && 1'b1;",f'activation_valid=running && sent<input_words && cycle%{period}==0;')
    assert f'cycle%{period}==0' in tb
    (work/'tb.sv').write_text(tb)
    manifest['tb_sha256']=hashlib.sha256(tb.encode()).hexdigest();manifest['offer_period_cycles']=period
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2))
    progress('Compiling '+rate)
    with (out/'compile.log').open('w') as f:
        subprocess.run(['iverilog','-g2012','-s','tb_v8_packed','-o',str(work/'sim.vvp'),str(work/'core.v'),str(ROOT/'verification/asap7_functional_cells.v'),str(ROOT/'verification/asap7_final_extra_cells.v'),str(work/'extra.v'),str(R/'third_party/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v'),str(work/'tb.sv')],stdout=f,stderr=subprocess.STDOUT,check=True)
    env=dict(os.environ,PPA_PROJECT=str(R),PPA_WORK=str(work),PPA_RESULTS=str(out))
    for case in range(5):
        progress(f'Running {rate}, zero-row {case*25}% OFF/ON')
        with (out/f'case{case}_driver.log').open('w') as f:
            subprocess.run([sys.executable,str(Path(__file__).with_name('run.py')),'--cases',str(case)],env=env,stdout=f,stderr=subprocess.STDOUT,check=True)
        progress(f'PASS {rate} zero-row {case*25}%')
rows=[]
for rate in ['fast','slow']:
 for case in range(5):
    pair=[json.loads((O/rate/f'case{case}_sparse{s}/measurement.json').read_text()) for s in [0,1]]
    counters=[]
    for s in [0,1]:
        log=(O/rate/f'case{case}_sparse{s}/simulation.log').read_text();assert 'PASS U_LOADING' in log
        counters.append({k:int(v) for k,v in re.findall(r'\b(cycles|rows)=(\d+)',log)})
    expected=4*32*8*4
    assert counters[0]['rows']==expected
    assert counters[1]['rows']==expected*(1-case/4)
    a,b=pair
    rows.append(dict(rate=rate,zero_row_pct=case*25,input_NHWC='[1,4,4,32]',output_channels=8,cycles_off=counters[0]['cycles'],cycles_on=counters[1]['cycles'],cycle_reduction_pct=100*(1-counters[1]['cycles']/counters[0]['cycles']),power_off_mw=a['power_w']*1000,power_on_mw=b['power_w']*1000,energy_off_nj=a['energy_nj'],energy_on_nj=b['energy_nj'],energy_reduction_pct=100*(1-b['energy_nj']/a['energy_nj'])))
with (O/'comparison.csv').open('w',newline='') as f:
    writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
progress('COMPLETE: all outputs and row counts match independent oracle')
subprocess.run([sys.executable,str(Path(__file__).with_name('controlled_publish.py'))],check=True)
