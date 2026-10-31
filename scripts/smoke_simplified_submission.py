from pathlib import Path
import subprocess,json,os
R=Path(__file__).resolve().parents[1];D=R/'submission/IDEC2026_FREE_TOPIC';C=D/'03_evaluation/01_vgg_layers';A=C/'assets'
O=R/'.submission_review/simplified_smoke';O.mkdir(parents=True,exist_ok=True)
orfs=Path(os.environ.get('ORFS_ROOT','/home/junbeom/OpenROAD-flow-scripts'))
with (O/'iverilog.log').open('w') as log:
    subprocess.run(['iverilog','-g2012','-tnull','-s','tb_v8_packed',*[str(A/p) for p in ['core.v','asap7_functional_cells.v','asap7_final_extra_cells.v','extra.v','sram.v','tb_template.sv']]],stdout=log,stderr=subprocess.STDOUT,check=True)
m=json.loads((C/'results/manifest.json').read_text());S=D/'02_libraries/asap7_sram/generated'
t='\n'.join('read_liberty {'+str(orfs/'flow/platforms/asap7/lib/NLDM'/Path(v['file']).name)+'}' for v in m['lib_files'].values())
t+='\nread_liberty {'+str(S/'LIB/srambank_256x4x64_6t122.lib')+'}\n'
for p in [orfs/'flow/platforms/asap7/lef/asap7_tech_1x_201209.lef',orfs/'flow/platforms/asap7/lef/asap7sc7p5t_28_R_1x_220121a.lef',S/'LEF/srambank_256x4x64_6t122.lef']:t+='read_lef {'+str(p)+'}\n'
t+='read_verilog {'+str(A/'core.v')+'}\nlink_design ppa_core\nreport_design_area\nexit\n'
(O/'link.tcl').write_text(t)
with (O/'openroad.log').open('w') as log:subprocess.run([str(orfs/'tools/install/OpenROAD/bin/openroad'),'-no_init','-exit',str(O/'link.tcl')],stdout=log,stderr=subprocess.STDOUT,check=True)
print('PASS: gate testbench elaboration and OpenROAD SRAM/Liberty/netlist linking')
