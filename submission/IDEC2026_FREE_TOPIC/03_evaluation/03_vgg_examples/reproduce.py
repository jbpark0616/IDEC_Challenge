from pathlib import Path
import os,shutil,subprocess,sys
D=Path(__file__).resolve().parent;A=D.parent/'01_vgg_layers/assets';W=D/'work';O=D/'reproduced_results'
W.mkdir(exist_ok=True);O.mkdir(exist_ok=True)
for name in ['core.v','extra.v','asap7_functional_cells.v','asap7_final_extra_cells.v','sram.v']:shutil.copyfile(A/name,W/name)
shutil.copytree(D/'vectors',W/'vectors',dirs_exist_ok=True)
(W/'tb.sv').write_text((D/'tb_template.sv').read_text().replace('@VECTORS@',(W/'vectors').as_posix()))
shutil.copyfile(D/'results/manifest.json',O/'manifest.json')
cmd=['iverilog','-g2012','-s','tb_v8_packed','-o',str(W/'sim.vvp')]+[str(W/n) for n in ['core.v','asap7_functional_cells.v','asap7_final_extra_cells.v','extra.v','sram.v','tb.sv']]
subprocess.run(cmd,check=True)
env=dict(os.environ,PPA_PROJECT=str(D.parents[1]/'01_project'),PPA_WORK=str(W),PPA_RESULTS=str(O))
subprocess.run([sys.executable,str(D/'run.py'),*sys.argv[1:]],env=env,check=True)
