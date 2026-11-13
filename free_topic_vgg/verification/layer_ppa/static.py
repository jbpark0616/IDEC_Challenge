"""Report area/timing of the exact mapped submodule used for mode comparison."""
from pathlib import Path
import json,subprocess,re
R=Path(__file__).resolve().parents[2];W=R/'build/layer_ppa';O=R/'evidence/layer_ppa'
m=json.loads((O/'manifest.json').read_text())
libs=[v['file'] for v in m['lib_files'].values()]+[str(R/'third_party/asap7_sram/generated/LIB/srambank_256x4x64_6t122.lib')]
tcl='\n'.join('read_liberty {'+p+'}' for p in libs)
tcl+='\nread_lef /home/junbeom/OpenROAD-flow-scripts/flow/platforms/asap7/lef/asap7_tech_1x_201209.lef\nread_lef /home/junbeom/OpenROAD-flow-scripts/flow/platforms/asap7/lef/asap7sc7p5t_28_R_1x_220121a.lef\nread_lef {'+str(R/'third_party/asap7_sram/generated/LEF/srambank_256x4x64_6t122.lef')+'}\n'
tcl+='\nread_verilog {'+str(W/'core.v')+'}\nlink_design ppa_core\n'
tcl+='create_clock -name clk -period 1430 [get_ports clk]\nset inputs [lsearch -inline -all -not -exact [all_inputs] [get_ports clk]]\nset_input_delay 200 -clock clk $inputs\nset_output_delay 200 -clock clk [all_outputs]\n'
tcl+=f'report_clock_min_period > {{{O}/core_timing.rpt}}\nreport_design_area > {{{O}/core_area.rpt}}\nreport_checks -path_delay max -group_count 3 > {{{O}/core_paths.rpt}}\nexit\n'
(O/'static.tcl').write_text(tcl)
with (O/'static.log').open('w') as f:subprocess.run(['/home/junbeom/OpenROAD-flow-scripts/tools/install/OpenROAD/bin/openroad','-no_init','-exit',str(O/'static.tcl')],stdout=f,stderr=subprocess.STDOUT,check=True)
catalog=json.loads((R.parent/'docs/designated_final/asap7_rvt_ff_cells.json').read_text())
areas={c['name']:float(c['area_lib']) for c in catalog['cells']}
lib=(R/'third_party/asap7_sram/generated/LIB/srambank_256x4x64_6t122.lib').read_text()
areas['srambank_256x4x64_6t122']=float(re.search(r'\barea\s*:\s*([\d.]+)',lib)[1])
core=(W/'core.v').read_text(); instances=re.findall(r'^\s*(\w+_ASAP7_75t_R|srambank_256x4x64_6t122)\s+',core,re.M)
assert all(n in areas for n in instances)
area=sum(areas[n] for n in instances)
(O/'core_area.rpt').write_text(f'Liberty cell area sum, including eight SRAM macros: {area:.8f} um^2\nMapped instances: {len(instances)}\n')
print((O/'core_area.rpt').read_text(),(O/'core_timing.rpt').read_text())
