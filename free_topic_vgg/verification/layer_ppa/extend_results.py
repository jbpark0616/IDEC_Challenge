from pathlib import Path
import csv,json,re,subprocess,sys,hashlib,shutil
R=Path(__file__).resolve().parents[2];ROOT=R.parent;O=R/'evidence/controlled_power';W=R/'build/controlled_power'
s=Path(__file__).with_name('controlled_power.py').read_text().split('\nrows=[]',1)[1].split("subprocess.run([sys.executable",1)[0]
s='rows=[]'+s;s=s.replace("['fast','slow']","['fast','slow','supply8']")
exec(compile(s,'controlled_summary','exec'),dict(R=R,O=O,W=W,json=json,csv=csv,re=re,progress=print))
subprocess.run([sys.executable,str(Path(__file__).with_name('controlled_publish.py'))],check=True)
extra=R/'evidence/extra_vgg_ppa';original=list(csv.DictReader((R/'evidence/layer_ppa/comparison.csv').open()));fields=list(original[0]);new=[]
for case,layer in [(12,'Conv8'),(13,'Conv12')]:
    pair=[json.loads((extra/f'case{case}_sparse{s}/measurement.json').read_text()) for s in [0,1]]
    counts=[]
    for sp in [0,1]:
        log=(extra/f'case{case}_sparse{sp}/simulation.log').read_text();assert 'PASS U_LOADING' in log
        counts.append({k:int(v) for k,v in re.findall(r'\b(cycles|rows)=(\d+)',log)})
    a,b=pair;r=dict(original[0]);r.update(layer=layer,input_NHWC=a['input_NHWC'],local_output_channels=a['local_output_channels'],active_cycles_off=counts[0]['cycles'],active_cycles_on=counts[1]['cycles'],row_issues_off=counts[0]['rows'],row_issues_on=counts[1]['rows'],power_off_mw=a['power_w']*1000,power_on_mw=b['power_w']*1000,power_reduction_pct=100*(1-b['power_w']/a['power_w']),latency_off_us=a['duration_ps']/1e6,latency_on_us=b['duration_ps']/1e6,latency_reduction_pct=100*(1-b['duration_ps']/a['duration_ps']),energy_off_nj=a['energy_nj'],energy_on_nj=b['energy_nj'],energy_reduction_pct=100*(1-b['energy_nj']/a['energy_nj']))
    new.append(r)
with (extra/'comparison.csv').open('w',newline='') as f:
    wr=csv.DictWriter(f,fieldnames=fields);wr.writeheader();wr.writerows(new)
# Create a new figure by reusing the verified input-derived sparsity calculation.
p=Path(__file__).with_name('plot_controlled_vgg_examples.py');s=p.read_text()
s=s.replace("prefix=source.read_text().split", "prefix=source.read_text().replace(\"V=R/'verification/v8/vectors'\",\"V=R/'build/extra_vgg_ppa/vectors'\").split")
s=s.replace("for case,name in [(10,'Conv9'),(11,'Conv13')]:", "measured += list(csv.DictReader((R/'evidence/extra_vgg_ppa/comparison.csv').open()))\nfor case,name in [(10,'Conv9'),(11,'Conv13'),(12,'Conv8'),(13,'Conv12')]:")
s=s.replace('with_examples','extended')
s=s.replace("('slow','#F47B20','D','Controlled: 1 word/4 cycles')]", "('slow','#F47B20','D','Controlled: 1 word/4 cycles'),('supply8','#888888','^','Controlled: 1 word/8 cycles')]")
s=s.replace("for p,color in zip(points,['#7030A0','#222222']):", "axes[0].plot([0,100],[0,100],'--',color='#222222',linewidth=1.3,label='MAC-row reduction reference')\nfor p,color in zip(points,['#7030A0','#222222','#009E73','#B34A70']):")
s=s.replace('figsize=(10,4)','figsize=(11,4.8)').replace('top=.76','top=.72').replace('ncol=2,fontsize=10','ncol=3,fontsize=9')
s=s.replace('512 input / 4 output channels','256 or 512 input / 4 output channels')
s=s.replace("xytext=(8,-16 if p['layer']=='Conv9' else 10)", "xytext={'Conv9':(8,-20),'Conv13':(-34,18),'Conv8':(-34,28),'Conv12':(12,28)}[p['layer']]")
s=s.replace("color=color,fontsize=10)", "color=color,fontsize=10,bbox=dict(facecolor='white',edgecolor='none',alpha=.85,pad=1.2),arrowprops=dict(arrowstyle='-',color=color,lw=.65))")
exec(compile(s,str(p),'exec'),{'__file__':str(p)})
print('PASS extension summaries and new extended SVG')
