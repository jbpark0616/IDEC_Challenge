"""Reproduce the report's arithmetic-work comparison from existing RTL counts.
Direct counts are analytical dense 3x3 counts, including padded positions.
No direct-convolution RTL timing or power measurement is implied.
"""
import csv, json, hashlib
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'docs/experiment_results/free_topic/figure_data'
SRC = ROOT / 'free_topic_vgg/evidence/report700/cluster_all/measurements.csv'
rows = list(csv.DictReader(SRC.open(encoding='utf-8-sig')))
data=[]
for i in range(13):
    a=next(r for r in rows if int(r['layer'])==i and int(r['sparse'])==0)
    b=next(r for r in rows if int(r['layer'])==i and int(r['sparse'])==1)
    n,h,w,ci=json.loads(a['input_NHWC']); co=int(a['output_channels'])
    direct=n*h*w*ci*co*9
    win=n*(h//2)*(w//2)*ci*co*16
    assert h%2==w%2==0 and win==int(a['mac_lanes'])
    sparse=int(b['mac_lanes'])
    data.append(dict(layer=f'Conv{i+1}',H=h,W=w,Cin=ci,Cout=co,
                     direct_analytical=direct,winograd_rtl=win,sparse_rtl=sparse,
                     sparse_reduction_vs_winograd_pct=100*(1-sparse/win),
                     combined_reduction_vs_direct_pct=100*(1-sparse/direct)))
with (OUT/'mac_three_way.csv').open('w',newline='',encoding='utf-8-sig') as f:
    writer=csv.DictWriter(f,fieldnames=data[0]);writer.writeheader();writer.writerows(data)
totals={key:sum(d[key] for d in data) for key in ('direct_analytical','winograd_rtl','sparse_rtl')}
conv_weights=sum(d['Cin']*d['Cout']*9 for d in data)
conv_bias=sum(d['Cout'] for d in data)
fc_weights=512*512*2+512*10
fc_bias=512*2+10
model=dict(designated=dict(conv_weights=108,fc_weights=750,weights=858,biases=16,folded_parameters=874,
                          direct_conv_mac=26*26*1*3*9+11*11*3*3*9,fc_mac=750),
           vgg=dict(conv_weights=conv_weights,fc_weights=fc_weights,weights=conv_weights+fc_weights,
                    biases=conv_bias+fc_bias,folded_parameters=conv_weights+fc_weights+conv_bias+fc_bias,
                    trainable_parameters_before_bn_folding=conv_weights+fc_weights+conv_bias+fc_bias+2*conv_bias,
                    direct_conv_mac=totals['direct_analytical'],fc_mac=fc_weights))
result=dict(totals=totals,model=model,source=str(SRC.relative_to(ROOT)),sha256=hashlib.sha256(SRC.read_bytes()).hexdigest(),
            image_index=0,cores=16,scope='13 independently executed convolution layers; FC and transforms excluded',
            direct_definition='Hout*Wout*Cin*Cout*9; dense padded arithmetic reference, not RTL measurement')
(OUT/'mac_model_comparison.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
plt.rcParams.update({'font.family':'DejaVu Sans','font.size':12,'axes.linewidth':.7,'svg.fonttype':'none','pdf.fonttype':42})
fig,ax=plt.subplots(figsize=(11.5,4.4))
fig.subplots_adjust(left=.075,right=.995,bottom=.16,top=.77)
x=np.arange(13);bw=.24
for offset,key,color,label in [(-bw,'direct_analytical','#A6A6A6','Direct 3×3 (analytical)'),
                              (0,'winograd_rtl','#0072BD','Winograd'),
                              (bw,'sparse_rtl','#ED7D31','Winograd + sparsity-aware')]:
    ax.bar(x+offset,[d[key]/1e6 for d in data],bw,color=color,label=label,zorder=3)
ax.set_xticks(x,[d['layer'] for d in data],fontsize=10)
ax.set_xlim(-.6,12.6);ax.set_ylim(0,42);ax.set_yticks([0,10,20,30,40])
ax.set_ylabel('MAC operations (million)')
ax.grid(axis='y',color='#DDDDDD',linewidth=.7);ax.set_axisbelow(True)
for s in ('top','right'):ax.spines[s].set_visible(False)
for s in ('left','bottom'):ax.spines[s].set_color('#999999')
ax.tick_params(length=3,color='#999999')
fig.legend(*ax.get_legend_handles_labels(),loc='upper center',bbox_to_anchor=(.53,.995),ncol=3,
           frameon=True,fancybox=False,edgecolor='#777777',fontsize=11)
fig.text(.53,.825,'Conv total: 313.20M → 139.20M → 96.38M MACs',ha='center',fontsize=12)
for ext in ('svg','png'):
    fig.savefig(ROOT/'docs/figures/graphs'/f'vgg_mac_three_way.{ext}',dpi=220,facecolor='white')
print(json.dumps(result,indent=2))
