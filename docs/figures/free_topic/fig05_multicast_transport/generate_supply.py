from pathlib import Path
import csv,json,hashlib
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
import xml.etree.ElementTree as ET
H=Path(__file__).resolve().parent;R=H.parents[3];D=R/'free_topic_vgg/evidence/multicast_profile'
a=[r for r in csv.DictReader((D/'effects.csv').open()) if r['source_period']=='1']
b=[r for r in csv.DictReader((D/'supply_effects.csv').open()) if r['period']=='1']
assert len(a)==len(b)==3
plt.rcParams.update({'font.family':'Arial','font.size':9,'axes.linewidth':.6,'svg.fonttype':'none','pdf.fonttype':42})
fig,axes=plt.subplots(1,2,figsize=(7.2,3.5),sharey=True)
fig.subplots_adjust(left=.10,right=.98,bottom=.28,top=.81,wspace=.20)
for ax,rows,caption in zip(axes,[a,b],['(a) Fanout + receive FIFOs','(b) SRAM load + tile feed + delivery']):
    ratios=[1/float(r['speedup']) for r in rows];x=np.arange(3)
    ax.bar(x-.15,np.ones(3),.25,color='#0072BD',label='Repeated per-core transfer',zorder=3)
    ax.bar(x+.15,ratios,.25,color='#ED7D31',label='Single transfer + multicast',zorder=3)
    for i,r in enumerate(rows):
        ax.text(i,1.07,f"{float(r['speedup']):.2f}×",ha='center',va='bottom')
        ax.text(i+.15,ratios[i]+.025,f'{ratios[i]:.3f}',ha='center',va='bottom',fontsize=8)
    ax.set_ylim(0,1.22);ax.set_yticks(np.arange(0,1.01,.2));ax.set_xticks(x,['512 B','4 KiB','16 KiB'])
    ax.set_xlabel('Source payload size');ax.set_axisbelow(True);ax.grid(axis='y',color='#DDDDDD',lw=.55)
    for s in ['top','right']:ax.spines[s].set_visible(False)
    for s in ['left','bottom']:ax.spines[s].set_color('#999999')
    ax.tick_params(length=2.5,width=.6,color='#999999')
    ax.text(.5,-.31,caption,transform=ax.transAxes,ha='center',va='top',fontsize=8.5)
axes[0].set_ylabel('Normalized completion cycles')
leg=fig.legend(*axes[0].get_legend_handles_labels(),loc='upper center',bbox_to_anchor=(.54,.98),ncol=2,frameon=True,fancybox=False,edgecolor='#555555',fontsize=8.5)
leg.get_frame().set_linewidth(.6)
for ext in ['svg','png','pdf']:fig.savefig(H/f'figure_supply.{ext}',dpi=320,facecolor='white')
ET.parse(H/'figure_supply.svg')
(H/'SUPPLY_CAPTION.txt').write_text((D/'SUPPLY_REPORT_KO.txt').read_text(encoding='utf-8')+'\n그림은매사이클1word 조건만 표시. 각payload/패널에서 반복전송을1로정규화. 상단숫자는speedup. 4사이클공급 결과는CSV에보존.',encoding='utf-8')
(H/'supply_figure_provenance.json').write_text(json.dumps({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [D/'effects.csv',D/'supply_effects.csv']},indent=2))
