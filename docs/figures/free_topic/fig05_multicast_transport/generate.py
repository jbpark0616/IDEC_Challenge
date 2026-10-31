from pathlib import Path
import csv,hashlib,json,shutil
import xml.etree.ElementTree as ET
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
H=Path(__file__).resolve().parent;R=H.parents[3]
S=R/'free_topic_vgg/evidence/multicast_profile/effects.csv'
rows=list(csv.DictReader(S.open()))
plt.rcParams.update({'font.family':'Arial','font.size':9,'axes.linewidth':.6,'svg.fonttype':'none','pdf.fonttype':42})
fig,axes=plt.subplots(1,2,figsize=(7.2,3.4))
fig.subplots_adjust(left=.09,right=.98,bottom=.26,top=.80,wspace=.28)
for ax,period,letter in zip(axes,[1,4],['a','b']):
    rs=[r for r in rows if int(r['source_period'])==period];x=np.arange(3)
    for offset,key,color,label in [(-.15,'unicast_cycles','#0072BD','Repeated unicast'),(.15,'multicast_cycles','#ED7D31','Multicast')]:
        vals=[int(r[key])/1000 for r in rs]
        ax.bar(x+offset,vals,.25,color=color,label=label,zorder=3)
        for xx,v in zip(x+offset,vals):ax.text(xx,v+max(vals)*.025,f'{v:.2f}',ha='center',va='bottom',fontsize=8)
    ax.set_ylim(0,max(int(r['unicast_cycles'])/1000 for r in rs)*1.18)
    ax.set_xticks(x,['512 B','4 KiB','16 KiB']);ax.set_xlabel('Payload per destination')
    ax.set_ylabel('Transfer cycles (×10³)');ax.set_axisbelow(True);ax.grid(axis='y',color='#DDDDDD',lw=.55)
    for s in ['top','right']:ax.spines[s].set_visible(False)
    for s in ['left','bottom']:ax.spines[s].set_color('#999999')
    ax.tick_params(length=2.5,width=.6,color='#999999')
    ax.text(.5,-.31,f'({letter}) Input: 1 word/{"cycle" if period==1 else "4 cycles"}',transform=ax.transAxes,ha='center',va='top')
legend=fig.legend(*axes[0].get_legend_handles_labels(),loc='upper center',bbox_to_anchor=(.54,.98),ncol=2,frameon=True,fancybox=False,edgecolor='#555555')
legend.get_frame().set_linewidth(.6)
for ext in ['svg','pdf','png']:fig.savefig(H/f'figure.{ext}',dpi=320,facecolor='white')
ET.parse(H/'figure.svg');shutil.copyfile(S,H/'source_data.csv')
(H/'CAPTION.txt').write_text('''16개 목적지에 동일 데이터를 전달하는 통신 블록 실험.
현재 RTL의 fanout(depth4)과 각 코어 수신FIFO(depth4)를 사용했다.
같은 입력 경로에서 한 코어씩16회 보내는 repeated unicast와16개 목적지 mask로1회 보내는 multicast 비교.
입력word는64bit, 수신 소비자는 항상ready. 첫word 제공부터 마지막 수신 소비와queue drain까지 측정.
모든 수신 데이터의 값·순서·중복을 검사했고12회 통과했다.
SRAM read/activation_feed/타일생성/DRAM 지연/계산 중첩은 제외한 통신 블록 측정이다.
외부 DRAM 대 실제 SRAM 복사 또는 전체 가속기 속도 비교가 아니다.
동일payload를16회 보내는 조건 대비 입력 전송량은1/16(93.75% 감소)이다.
각 패널 y축 범위는 다르며 단위는모두1000cycles다.
''',encoding='utf-8')
(H/'figure_provenance.json').write_text(json.dumps({'source':str(S.relative_to(R)),'sha256':hashlib.sha256(S.read_bytes()).hexdigest(),'rows':rows},indent=2))
