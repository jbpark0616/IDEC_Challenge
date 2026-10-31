from pathlib import Path
import sys
sys.path.insert(0, '/tmp/idec_mac_plot_runtime')
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
import json

out=Path(__file__).parent/'figures'
labels=['Clock frequency','Cycles / image','Inference latency','Cell area','Power']
base=np.array([476.,1335.,2.80,.024848,335.])
final=np.array([1000.,995.83,.99583,.0077690259,7.868472])
ratio=final/base
plt.rcParams.update({'font.family':'DejaVu Sans','font.size':11,'svg.fonttype':'none','axes.spines.top':False,'axes.spines.right':False})
fig,ax=plt.subplots(figsize=(10.2,3.8))
x=np.arange(5);w=.30
ax.bar(x-w/2,np.ones(5),w,color='#0072BD',label='Competition reference (reported)',zorder=3)
bars=ax.bar(x+w/2,ratio,w,color='#F47C26',label='Proposed',zorder=3)
for i,(bar,val) in enumerate(zip(bars,ratio)):
    change=(val-1)*100
    ax.text(x[i],max(1.,val)+.10,f'{change:+.2f}%',ha='center',va='bottom',weight='bold',fontsize=11,clip_on=False)
ax.set_xticks(x,labels);ax.set_ylabel('Normalized value');ax.set_ylim(0,2.5)
ax.set_yticks([0,.5,1,1.5,2,2.5]);ax.grid(axis='y',color='#d5d5d5',linewidth=.7,zorder=0)
ax.legend(loc='upper center',bbox_to_anchor=(.5,1.20),ncol=2,frameon=True,fancybox=False,edgecolor='#777')
fig.subplots_adjust(left=.08,right=.99,bottom=.15,top=.81)
for ext in ['svg','png']:
    fig.savefig(out/f'competition_reported_comparison.{ext}',dpi=220,facecolor='white')
(out.parent/'competition_reported_comparison.json').write_text(json.dumps({'metrics':labels,'reported_reference':base.tolist(),'proposed':final.tolist(),'change_percent':((ratio-1)*100).tolist(),'scope':'Reported implementation comparison; model/kernel and power activity conditions differ. Accuracy: 97% for both. No direct-convolution speedup or matched-power claim.'},indent=2))
