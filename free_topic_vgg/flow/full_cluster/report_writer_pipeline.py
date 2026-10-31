"""Compare the writer-boundary run with the preserved complete-cluster result."""
from pathlib import Path
import hashlib, json, re, shutil, time

r=Path(__file__).resolve().parents[2]
out=r/'evidence/timing_writer_pipeline'
baseline=r/'build/full_cluster_reuse'
variant=r/'build/full_cluster_writer_pipeline'

def read(work):
    p=work/'reports/asap7/vgg_sixteen_core_cluster/base'
    sta=(p/'1_Post_synthesis.rpt').read_text()
    stat=(p/'synth_stat.txt').read_text()
    check=(p/'synth_check.txt').read_text()
    assert 'Found and reported 0 problems' in check
    section=stat.split('=== design hierarchy ===')[1]
    counts={}
    for line in section.splitlines():
        columns=line.split()
        if len(columns)==5 and columns[0].isdigit() and columns[4].endswith('_R'):
            counts[columns[4]]=int(columns[0])
    macros=re.search(r'^\s+(\d+)\s+\S+\s+\d+\s+\S+\s+srambank_256x4x64_6t122\s*$',section,re.M)
    assert int(macros[1])==192
    assert re.search(r'^\s+16\s+\S+\s+16\s+-\s+\$paramod.*vgg_sram_conv_layer',section,re.M)
    period=float(re.search(r'period_min = ([\d.]+)',sta)[1])
    area=float(re.search(r"Chip area for top module.*: ([\d.]+)",stat)[1])
    return dict(period_ps=period,fmax_mhz=float(re.search(r'fmax = ([\d.]+)',sta)[1]),
        area_um2=area,sram_macros=192,compute_instances=16,
        ff_cells=sum(v for k,v in counts.items() if k.startswith('DFF')),
        icg_cells=sum(v for k,v in counts.items() if k.startswith('ICG')))

# The mapping process exits before OpenROAD STA. Wait for the complete flow,
# not merely for the mapper PID, and never parse a partially written report.
deadline=time.monotonic()+7200
while 'EXIT_CODE=' not in (variant/'STATUS.txt').read_text():
    if time.monotonic()>deadline:
        raise TimeoutError('Full flow did not finish; no result claimed')
    time.sleep(10)
assert 'EXIT_CODE=0' in (variant/'STATUS.txt').read_text()
old=read(baseline);new=read(variant)
before=json.loads((baseline/'source_sha256.json').read_text())
after=json.loads((variant/'source_sha256.json').read_text())
changed=[p for p in before if p.startswith('rtl/') and before[p]!=after[p]]
assert changed==['rtl/vgg_ab_layer_cluster.v'],changed
assert all(hashlib.sha256((r/p).read_bytes()).hexdigest()==v for p,v in after.items() if p.startswith('rtl/'))
data=dict(before=old,after=new,changed_rtl=changed,
    period_reduction_percent=100*(1-new['period_ps']/old['period_ps']),
    frequency_increase_percent=100*(new['fmax_mhz']/old['fmax_mhz']-1),
    scope='Pre-layout synthesis/STA only; identical mapping settings and constraints')
(out/'comparison.json').write_text(json.dumps(data,indent=2))
for name in ['1_Post_synthesis.rpt','synth_stat.txt','synth_check.txt']:
    shutil.copy2(variant/'reports/asap7/vgg_sixteen_core_cluster/base'/name,out/name)
shutil.copy2(variant/'source_sha256.json',out/'source_sha256.json')
print(json.dumps(data,indent=2))
