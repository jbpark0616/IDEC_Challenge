from pathlib import Path
from collections import Counter
import json,re,shutil,sys
root=Path(__file__).resolve().parents[2]
build=root/'build'/(sys.argv[1] if len(sys.argv)>1 else 'single_core_sram_fixed_window')
base='asap7/vgg_single_core_sram/base'
net=build/'results'/base/'1_2_yosys.v'
groups=Counter(); macros=[]; gates=[]
for line in net.open():
    m=re.match(r'\s+(DFF\S+|ICG\S+|srambank_256x4x64_6t122)\s+(\S+)\s+\(',line)
    if not m: continue
    cell,name=m.groups()
    if cell.startswith('DFF'):
        group=name.rsplit('.',1)[0]
        groups[group]+=1
    elif cell.startswith('ICG'): gates.append(name)
    else: macros.append(name)
out=root/'evidence'/(sys.argv[2] if len(sys.argv)>2 else 'single_core_fixed_window')
out.mkdir(parents=True,exist_ok=True)
for f in ['synth_stat.txt','synth_check.txt','1_Post_synthesis.rpt']:
    shutil.copy2(build/'reports'/base/f,out/f)
for f in ['source_sha256.json','STATUS.txt']:
    shutil.copy2(build/f,out/f)
data={'ff_total':sum(groups.values()),'ff_groups':dict(groups.most_common()),'sram_count':len(macros),'sram_instances':macros,'icg_count':len(gates),'icg_instances':gates}
(out/'structure.json').write_text(json.dumps(data,indent=2))
print(json.dumps({'ff_total':sum(groups.values()),'ff_groups_top':groups.most_common(12),'sram_count':len(macros),'icg_count':len(gates)},indent=2))
