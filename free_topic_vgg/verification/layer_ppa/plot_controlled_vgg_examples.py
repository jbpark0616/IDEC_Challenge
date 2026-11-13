"""New overlay figure; preserve the original controlled figure unchanged."""
from pathlib import Path
import csv,hashlib,json,sys
R=Path(__file__).resolve().parents[2];ROOT=R.parent
D=ROOT/'docs/report_assets/free_topic/figures'
original=D/'vgg_controlled_cycle_energy.svg'
before=hashlib.sha256(original.read_bytes()).hexdigest()
# Recompute post-transform/quantization zero rows directly from saved inputs.
source=R/'verification/bypass_profile/report.py'
prefix=source.read_text().split("with (O/'activation_distribution.csv').open",1)[0]
ns={'__file__':str(source)};exec(compile(prefix,str(source),'exec'),ns)
stats={s['case']:s for s in ns['stats']}
measured=list(csv.DictReader((R/'evidence/layer_ppa/comparison.csv').open()))
manifest=json.loads((R/'evidence/layer_ppa/manifest.json').read_text())
for rel,h in manifest['vectors'].items():
    assert hashlib.sha256((R/'verification/v8'/rel).read_bytes()).hexdigest()==h,rel
points=[]
for case,name in [(10,'Conv9'),(11,'Conv13')]:
    st=stats[case];m=next(r for r in measured if r['layer']==name)
    dense=st['tiles']*4*st['local_K']
    active=dense*(1-st['zero_row_percent']/100)
    assert int(m['row_issues_off'])==dense
    assert abs(int(m['row_issues_on'])-active)<1e-8
    points.append(dict(layer=name,zero_row_pct=st['zero_row_percent'],cycle_reduction_pct=100*(1-int(m['active_cycles_on'])/int(m['active_cycles_off'])),energy_reduction_pct=float(m['energy_reduction_pct']),input_NHWC=m['input_NHWC'],output_channels=m['local_output_channels']))
with (D/'vgg_controlled_cycle_energy_with_examples.csv').open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(points[0]));w.writeheader();w.writerows(points)
sys.path.insert(0,'/tmp/idec_mac_plot_runtime')
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
plt.rcParams.update({'font.size':11,'svg.fonttype':'none','pdf.fonttype':42})
rows=list(csv.DictReader((R/'evidence/controlled_power/comparison.csv').open()))
fig,axes=plt.subplots(1,2,figsize=(10,4))
fig.subplots_adjust(top=.76,bottom=.22,wspace=.24,left=.07,right=.99)
for rate,color,marker,label in [('fast','#0072BD','s','Controlled: 1 word/cycle'),('slow','#F47B20','D','Controlled: 1 word/4 cycles')]:
    rr=[r for r in rows if r['rate']==rate]
    for ax,key in zip(axes,['cycle_reduction_pct','energy_reduction_pct']):
        ax.plot([float(r['zero_row_pct']) for r in rr],[float(r[key]) for r in rr],color=color,marker=marker,label=label,linewidth=2)
for p,color in zip(points,['#7030A0','#222222']):
    for ax,key in zip(axes,['cycle_reduction_pct','energy_reduction_pct']):
        ax.scatter(p['zero_row_pct'],p[key],marker='*',s=160,color=color,edgecolors='white',linewidths=.6,zorder=5,label='VGG '+p['layer'])
        ax.annotate(p['layer'],(p['zero_row_pct'],p[key]),xytext=(8,-16 if p['layer']=='Conv9' else 10),textcoords='offset points',color=color,fontsize=10)
for ax,title in zip(axes,['(a) Cycle reduction','(b) Energy reduction']):
    ax.set(xlabel='Zero rows after input transform (%)',ylabel='Reduction (%)',title=title,xticks=[0,25,50,75,100],ylim=(-4,103),xlim=(-4,104))
    ax.grid(axis='y',color='#dddddd');ax.spines[['top','right']].set_visible(False)
fig.legend(*axes[0].get_legend_handles_labels(),loc='upper center',ncol=2,fontsize=10,bbox_to_anchor=(.52,1.01))
fig.text(.5,.035,'Controlled: 4×4×32 input, 8 output channels. VGG stars: one-image layer slices, 512 input / 4 output channels.\nAll weights resident; stars are application examples with different tensor shapes, not samples of the controlled curves.',ha='center',fontsize=8.5)
for ext in ['svg','pdf','png']:
    fig.savefig(D/f'vgg_controlled_cycle_energy_with_examples.{ext}',dpi=180,bbox_inches='tight')
plt.close(fig)
assert hashlib.sha256(original.read_bytes()).hexdigest()==before
print(json.dumps(points,indent=2));print('PASS original SVG unchanged; input-derived sparsity agrees with measured row issues')
