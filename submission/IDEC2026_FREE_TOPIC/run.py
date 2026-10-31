from pathlib import Path
import argparse,os,shutil,subprocess,sys
D=Path(__file__).resolve().parent
p=argparse.ArgumentParser(description='Winograd accelerator evaluation')
p.add_argument('task',choices=['check','controlled','vgg','examples','area','synth'])
a=p.parse_args();orfs=Path(os.environ.get('ORFS_ROOT','/home/junbeom/OpenROAD-flow-scripts'))
if a.task=='check':
    for f in ['01_project/rtl/sources.f','02_libraries/asap7_sram/generated/LIB/srambank_256x4x64_6t122.lib','02_libraries/asap7_sram/generated/LEF/srambank_256x4x64_6t122.lef','02_libraries/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v']:
        assert (D/f).is_file(),f
    for tool in ['iverilog','vvp']:assert shutil.which(tool),f'Missing executable: {tool}'
    for tool,path in [('OpenROAD',Path(os.environ.get('OPENROAD',orfs/'tools/install/OpenROAD/bin/openroad'))),('Yosys',Path(os.environ.get('YOSYS',orfs/'tools/install/yosys/bin/yosys')))]:
        assert path.is_file(),f'Missing {tool}: {path}'
    print('PASS: design/library files and Icarus/OpenROAD/Yosys executables')
elif a.task=='synth':
    subprocess.run(['bash','flow/full_cluster/run_reuse.sh'],cwd=D/'01_project',check=True)
else:
    folder,args={'controlled':('02_controlled',[]),'vgg':('01_vgg_layers',['--cases','10','11']),'examples':('03_vgg_examples',['--cases','12','13']),'area':('04_area',[])}[a.task]
    work=D/'03_evaluation'/folder
    subprocess.run([sys.executable,str(work/'reproduce.py'),*args],cwd=work,check=True)
