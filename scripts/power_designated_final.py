"""Matched VCD power for the integrated design; no delay/glitch simulation."""
import argparse
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
EXP = ROOT
p = argparse.ArgumentParser()
p.set_defaults(variant='b1_g1')
p.add_argument('--stage', choices=['synth'], default='synth')
p.add_argument('--count', type=int, default=20)
p.add_argument('--period-ps', type=int, default=1000)
a = p.parse_args()
work = ROOT/'build/designated_final'
stage_tag = a.stage if a.period_ps == 1000 else f'{a.stage}_{a.period_ps}ps'
out = work/'power'/stage_tag/a.variant
out.mkdir(parents=True, exist_ok=True)
result = work/'openroad/results/asap7/chip_row_sparse_fixed/matched_v1'
base = '4_cts_holdfix' if a.stage == 'cts_fixed' else '4_cts'
netlist = result/('1_2_yosys.v' if a.stage == 'synth' else base+'.v')
odb = result/('1_synth.odb' if a.stage == 'synth' else base+'.odb')
sdc = result/('1_synth.sdc' if a.stage == 'synth' else base+'.sdc')
if a.stage != 'synth' and not netlist.exists():
    assert odb.exists() and sdc.exists()
    libroot = '/home/junbeom/OpenROAD-flow-scripts/flow/platforms/asap7/lib/NLDM'
    libfiles = json.loads((ROOT/'docs/designated_final/asap7_rvt_ff_cells.json').read_text())['active_files']
    export = '\n'.join(f'read_liberty {x["file"]}' for x in libfiles.values())
    export += f'\nread_db {odb}\nread_sdc {sdc}\nwrite_verilog {netlist}\n'
    (out/'export.tcl').write_text(export)
    with (out/'export.log').open('w') as f:
        subprocess.run(['/home/junbeom/OpenROAD-flow-scripts/tools/install/OpenROAD/bin/openroad',
                        '-no_init', '-exit', str(out/'export.tcl')], stdout=f, stderr=subprocess.STDOUT, check=True)
assert netlist.exists(), netlist

tb = (ROOT/'verification/winograd_chip_1000_tb.v').read_text().replace('../../../', ROOT.as_posix()+'/')
tb = re.sub(r'localparam integer TEST_IMAGE_COUNT = \d+;', f'localparam integer TEST_IMAGE_COUNT = {a.count};', tb)
tb = tb.replace('one-image power activity regression', f'{a.count}-image power activity regression')
assert a.period_ps % 2 == 0
tb = tb.replace('always #500 clk = ~clk;', f'always #{a.period_ps//2} clk = ~clk;')
tb = tb.replace('module winograd_chip_1000_tb;', '''module winograd_chip_1000_tb;
    initial begin
        $dumpfile("activity.vcd");
        $dumpvars(0, dut);
    end
''')
tb = tb.replace('$finish;', '$display("Total post-input cycles: %0d", total_tail_cycles); $finish;')
(out/'tb.v').write_text(tb)

# Keep verified sequential models; derive only missing combinational cells
# from the exact Liberty functions catalogued from the synthesis libraries.
models = [ROOT/'verification/asap7_functional_cells.v', ROOT/'verification/asap7_final_extra_cells.v']
defined = set(re.findall(r'\bmodule\s+(\w+)', '\n'.join(x.read_text() for x in models)))
needed = set(re.findall(r'^\s*(\w+_ASAP7_75t_R)\s+', netlist.read_text(), re.M))
catalog = {c['name']: c for c in json.loads((ROOT/'docs/designated_final/asap7_rvt_ff_cells.json').read_text())['cells']}
extra = ['`timescale 1ps/1ps']
for name in sorted(needed-defined):
    if name == 'TAPCELL_ASAP7_75t_R':
        # Physical well tap; exported instances have no digital ports.
        extra.append('module TAPCELL_ASAP7_75t_R(); endmodule')
        continue
    if name == 'ICGx1_ASAP7_75t_R':
        extra.append('''module ICGx1_ASAP7_75t_R(input CLK, ENA, SE, output GCLK);
reg IQ; always @* if (!CLK) IQ = ENA | SE;
assign GCLK = CLK & IQ;
endmodule''')
        continue
    cell = catalog[name]
    ports = ', '.join(pin['direction']+' '+pin['name'] for pin in cell['pins'])
    extra.append(f'module {name}({ports});')
    for pin in cell['pins']:
        if pin['direction'] == 'output':
            fn = pin['function']
            assert fn is not None and not name.startswith(('DFF', 'ICG')), name
            fn = fn.replace('!', '~').replace('*', '&').replace('+', '|')
            extra.append(f"assign {pin['name']} = {fn};")
    extra.append('endmodule')
(out/'extra_models.v').write_text('\n'.join(extra)+'\n')
with (out/'compile.log').open('w') as f:
    subprocess.run(['iverilog', '-g2012', '-DGATE_LEVEL', '-DPOWER_TRACE', '-s', 'winograd_chip_1000_tb',
                    '-o', str(out/'gate.vvp'), str(netlist), *map(str, models), str(out/'extra_models.v'), str(out/'tb.v')],
                   stdout=f, stderr=subprocess.STDOUT, check=True)
with (out/'simulation.log').open('w') as f:
    subprocess.run(['vvp', str(out/'gate.vvp')], cwd=out, stdout=f, stderr=subprocess.STDOUT, check=True)
log = (out/'simulation.log').read_text()
print(log, flush=True)
assert 'PASS:' in log and 'FAIL:' not in log and 'ERROR:' not in log

tcl = (ROOT/'flow/openroad/report_activity_power.tcl').read_text()
# Summary plus unannotated pins is sufficient to check complete coverage;
# avoid serializing hundreds of thousands of already-annotated pin names.
tcl = tcl.replace('-report_annotated -report_unannotated', '-report_unannotated')
tcl = tcl.replace('read_sdc $::env(POWER_SDC)',
                  f'read_sdc $::env(POWER_SDC)\ncreate_clock -name clk -period {a.period_ps} [get_ports clk]')
if a.stage != 'synth':
    clock_command = f'create_clock -name clk -period {a.period_ps} [get_ports clk]'
    tcl = tcl.replace(clock_command, clock_command+'''
source /home/junbeom/OpenROAD-flow-scripts/flow/platforms/asap7/setRC.tcl
set_propagated_clock [all_clocks]
estimate_parasitics -placement''')
tcl += '''\nreport_design_area >> $::env(POWER_REPORT)
report_checks -path_delay min -group_count 3 >> $::env(POWER_REPORT)
report_check_types -max_slew -max_capacitance -violators >> $::env(POWER_REPORT)
report_clock_skew >> $::env(POWER_REPORT)
'''
tcl += f'''\nset bank_file [open "{out}/icg_loads.tsv" w]
puts $bank_file "icg\tnet\tsinks\tsink_types"
foreach inst [[ord::get_db_block] getInsts] {{
    if {{[[$inst getMaster] getName] != "ICGx1_ASAP7_75t_R"}} {{continue}}
    set net [[$inst findITerm GCLK] getNet]
    set count 0
    set kinds [dict create]
    foreach pin [$net getITerms] {{
        if {{[$pin getIoType] == "INPUT"}} {{
            incr count
            set cell [[[$pin getInst] getMaster] getName]
            dict incr kinds $cell
        }}
    }}
    puts $bank_file "[$inst getName]\t[$net getName]\t$count\t$kinds"
}}
close $bank_file
'''
(out/'report.tcl').write_text(tcl)
(out/'power.sh').write_text(f'''#!/usr/bin/env bash
set -euo pipefail
cd /home/junbeom/OpenROAD-flow-scripts
source ./env.sh
export POWER_LIBERTY_DIR="$PWD/flow/platforms/asap7/lib/NLDM"
export POWER_ODB="{odb}" POWER_SDC="{sdc}"
export POWER_VCD="{out}/activity.vcd" POWER_REPORT="{out}/activity_power.rpt"
export POWER_ACTIVITY_REPORT="{out}/activity_annotation.rpt"
openroad -no_init -exit "{out}/report.tcl"
''')
with (out/'openroad.log').open('w') as f:
    subprocess.run(['bash', str(out/'power.sh')], stdout=f, stderr=subprocess.STDOUT, check=True)
print((out/'activity_power.rpt').read_text()[-2500:])
