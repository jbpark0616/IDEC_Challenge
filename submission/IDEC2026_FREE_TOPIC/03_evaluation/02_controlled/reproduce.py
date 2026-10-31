from pathlib import Path
import os,sys,shutil,subprocess
D=Path(__file__).resolve().parent;A=D.parent/'01_vgg_layers/assets'
for rate in ['fast','slow','supply8']:
 W=D/'work'/rate;O=D/'reproduced_results'/rate;W.mkdir(parents=True,exist_ok=True);O.mkdir(parents=True,exist_ok=True)
 for n in ['core.v','extra.v','asap7_functional_cells.v','asap7_final_extra_cells.v','sram.v']:shutil.copyfile(A/n,W/n)
 shutil.copytree(D/'vectors',W/'vectors',dirs_exist_ok=True)
 (W/'tb.sv').write_text((D/f'tb_{rate}.sv').read_text().replace('@VECTORS@',str(W/'vectors')))
 shutil.copyfile(D/'results'/rate/'manifest.json',O/'manifest.json')
 subprocess.run(['iverilog','-g2012','-s','tb_v8_packed','-o',str(W/'sim.vvp')]+[str(W/n) for n in ['core.v','extra.v','asap7_functional_cells.v','asap7_final_extra_cells.v','sram.v','tb.sv']],check=True)
 subprocess.run([sys.executable,str(D/'run.py'),'--cases','0','1','2','3','4'],env=dict(os.environ,PPA_PROJECT=str(D.parents[1]/'01_project'),PPA_WORK=str(W),PPA_RESULTS=str(O)),check=True)
