"""Check gate VCD name annotation on a short snapshot; not reported as PPA."""
from pathlib import Path
import subprocess
R=Path(__file__).resolve().parents[2];W=R/'build/layer_ppa';O=R/'evidence/layer_ppa'
source=W/'case10_sparse0.vcd';dest=W/'annotation_pilot.vcd'
header=True; enabled=False; tick=0; start=None
with source.open() as src,dest.open('w') as out:
 for line in src:
    if header:
        out.write(line)
        if '$enddefinitions' in line:header=False
    elif line.startswith('#'):
        tick=int(line[1:])
        if enabled:
            out.write(f'#{tick-start}\n')
            if tick-start>=1430*20:break
    elif '$dumpon' in line:
        enabled=True;start=tick;out.write('#0\n$dumpvars\n')
    elif enabled:out.write(line)
assert enabled
base=(O/'static.tcl').read_text().split('report_clock_min_period')[0]
tcl=base+f'read_vcd -scope tb_v8_packed/dut {{{dest}}}\nreport_activity_annotation -report_unannotated > {{{O}/pilot_annotation.rpt}}\nreport_power -digits 9 > {{{O}/pilot_power_NOT_FOR_REPORT.rpt}}\nexit\n'
(W/'pilot.tcl').write_text(tcl)
with (O/'pilot.log').open('w') as f:subprocess.run(['/home/junbeom/OpenROAD-flow-scripts/tools/install/OpenROAD/bin/openroad','-no_init','-exit',str(W/'pilot.tcl')],stdout=f,stderr=subprocess.STDOUT,check=True)
print((O/'pilot_annotation.rpt').read_text()[:1600])
