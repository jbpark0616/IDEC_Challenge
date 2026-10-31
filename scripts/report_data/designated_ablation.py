"""Audit archived PPA; rerun 100 unique-image RTL cases without modifying final RTL."""
from pathlib import Path
import csv, hashlib, json, re, subprocess, zipfile

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/report_data/designated_ablation'
WORK=ROOT/'build/report_designated_ablation'
OUT.mkdir(parents=True,exist_ok=True)
summary=json.loads((ROOT/'docs/designated_final/summary.json').read_text())
frozen=json.loads((ROOT/'docs/designated_final/rtl_sha256.json').read_text())
def verify():
    assert {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/'verilog').glob('*.v')}==frozen
verify()
z=zipfile.ZipFile(ROOT/'verification/designated_ablation_reference.zip')
prefix='experiments/row_sparse_fixed/iterations/matched_ablation/'
rows=[]; images=[]
for case,cfg in summary['cases'].items():
    work=WORK/case; rtl=work/'rtl'; rtl.mkdir(parents=True,exist_ok=True)
    for name in frozen:
        data=z.read(prefix+f'cases/{case}/rtl/{name}')
        (rtl/name).write_bytes(data)
        if case=='b1_g1': assert hashlib.sha256(data).hexdigest()==frozen[name]
    tb=(ROOT/'verification/winograd_chip_1000_tb.v').read_text().replace('../../../',ROOT.as_posix()+'/')
    tb=re.sub(r'localparam integer TEST_IMAGE_COUNT = \d+;', 'localparam integer TEST_IMAGE_COUNT = 100;',tb)
    tb=tb.replace('(correct == 970)', '(correct == 97)')
    tb=tb.replace('module winograd_chip_1000_tb;', '''module winograd_chip_1000_tb;
    integer probe_cycle=0, probe_first=-1;
    always @(posedge clk) begin
        probe_cycle=probe_cycle+1;
        if (!rst_n) probe_first=-1;
        else if (dut.image_valid && dut.image_ready && probe_first<0)
            probe_first=probe_cycle;
    end
    always @(posedge valid_out_6)
        $display("REPORT_LATENCY,%0d,%0d",image_index,probe_cycle-probe_first);
''')
    tb=tb.replace('total_tail_cycles = total_tail_cycles + cycle_in_image;',
        '$display("REPORT_IMAGE,%0d,%0d,%0d,%0d", image_index, cycle_in_image, decision, prediction_memory[image_index]);\n            total_tail_cycles = total_tail_cycles + cycle_in_image;')
    (work/'tb.v').write_text(tb)
    with (work/'compile.log').open('w') as f:
        subprocess.run(['iverilog','-g2012','-DTEST_M_FIFO_DEPTH_1','-s','winograd_chip_1000_tb','-o',str(work/'sim.vvp'),*map(str,sorted(rtl.glob('*.v'))),str(work/'tb.v')],stdout=f,stderr=subprocess.STDOUT,check=True)
    logpath=OUT/(case+'_rtl100.log')
    with logpath.open('w') as f:
        subprocess.run(['vvp','-n',str(work/'sim.vvp')],cwd=work,stdout=f,stderr=subprocess.STDOUT,check=True,timeout=1200)
    log=logpath.read_text()
    assert 'PASS' in log and 'ERROR:' not in log and 'FAIL' not in log
    measured=[]
    latencies={int(i):int(c) for i,c in re.findall(r'REPORT_LATENCY,(\d+),(\d+)',log)}
    for m in re.finditer(r'REPORT_IMAGE,(\d+),(\d+),(\d+),(\d+)',log):
        index,tail,decision,gold=map(int,m.groups()); assert decision==gold
        latency=latencies[index]
        assert latency-tail==781 # independently observed historical harness offset
        measured.append(latency)
        images.append(dict(case=case,image_index=index,post_input_cycles=tail,total_cycles=latency,decision=decision,reference=gold))
    assert len(measured)==100
    mean=sum(measured)/100
    assert abs(mean-cfg['cycles_mean'])<1e-9,(case,mean,cfg['cycles_mean'])
    rpt=z.read(prefix+f'power/synth/{case}/activity_power.rpt').decode()
    gate=z.read(prefix+f'power/synth/{case}/simulation.log').decode()
    ann=z.read(prefix+f'power/synth/{case}/activity_annotation.rpt').decode()
    assert 'RTL mismatches: 0' in gate and 'Correct: 20/20' in gate
    assert re.search(r'unannotated\s+0\b',ann)
    power=float(re.search(r'^Total\s+\S+\s+\S+\s+\S+\s+(\S+)',rpt,re.M)[1])*1000
    assert abs(power-cfg['power_mw']['Total'])<1e-8
    end_ps=int(re.search(r'\$finish called at (\d+) \(1ps\)',gate)[1])
    assert abs(end_ps/1000-cfg['window_ns'])<1e-9
    energy=power*(end_ps/1000)/20/1000
    assert abs(energy-cfg['energy_nj_per_image_including_reset'])<1e-8
    for name,data in [('power.rpt',rpt),('gate.log',gate),('annotation.rpt',ann)]:
        (OUT/(case+'_historical_'+name)).write_text(data)
    rows.append(dict(case=case,label={'b0_g0':'Baseline','b1_g0':'Bypass','b0_g1':'ICG','b1_g1':'Bypass + ICG'}[case],cycles_mean=mean,cycles_min=min(measured),cycles_max=max(measured),power_mw=power,energy_nj_per_image=energy,area_um2=cfg['area_um2'],cycle_sample_unique_images=100,power_sample_images=20,power_source='historical_audited_gate_vcd',cycle_source='fresh_rtl100'))
    print(case,mean,power,energy,flush=True)
for name,data in [('ablation.csv',rows),('cycles_per_image.csv',images)]:
    with (OUT/name).open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(data[0]));writer.writeheader();writer.writerows(data)
verify()
(OUT/'provenance.json').write_text(json.dumps(dict(conditions=summary['conditions'],final_rtl_sha256=frozen,source_archive_sha256=hashlib.sha256((ROOT/'verification/designated_ablation_reference.zip').read_bytes()).hexdigest(),fresh_rtl_images_per_case=100,ppa_remeasured=False),indent=2))
print('PASS: four RTL cases; historical power audited; final RTL unchanged',flush=True)
