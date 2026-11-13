"""Publish controlled measurements separately from real VGG examples."""
from pathlib import Path
import csv,hashlib,json,shutil,subprocess,sys
R=Path(__file__).resolve().parents[2];ROOT=R.parent;O=R/'evidence/controlled_power';W=R/'build/controlled_power'
rows=list(csv.DictReader((O/'comparison.csv').open()));assert len(rows) in [10,15]
rates=['fast','slow']+(['supply8'] if len(rows)==15 else [])
lines=['# 공급 조건과 변환 영역 희소성에 따른 코어 에너지 평가','',
'주 실험은 통제 입력이며 실제 VGG Conv9/Conv13 결과는 별도 적용 사례이다.',
'동일 최종 합성 코어, ICG ON 공통, runtime sparsity OFF/ON 비교. 면적 35,958.28950 um²와 정적 Fmax 725.89 MHz는 공통이다.',
'입력 [1,4,4,32], 출력 8채널, U8/V8. 가중치 4096 bytes 상주. 초기 U 적재 제외, 명령부터 완료까지 측정.',
'공급기는 64-bit 타일 데이터 word를 매 cycle 또는 4 cycles마다 제공한다. 이는 최대 제공 빈도이며 실제 수락률은 ready에 영향을 받는다.',
'공간 입력에서 채널을 규칙적으로 0으로 설정해 변환 후 zero-row 0/25/50/75/100%를 생성했다. 비영 입력과 가중치 생성 규칙은 고정되어 있다. mask를 강제로 주입하지 않았다.',
'전체가 0인 채널 타일이 주기적으로 분포하는 통제 패턴이다. 같은 zero-row 비율의 모든 공간적/행별 분포를 대표하지 않는다. 실제 SRAM/제어 회로가 포함된 한 코어의 평가이며 외부 공급 회로 전력은 제외된다.',
'주기 1430ps(699.30MHz), zero-delay gate VCD 및 OpenROAD Liberty 전력 추정. SRAM/표준셀 라이브러리 조건과 활동 주석 범위는 VGG 예시 평가와 동일하다.',
'에너지=Pavg×측정 구간 시간. 이미지당 에너지 또는 전체 16코어 에너지가 아니다. 본 결과는 회로 제거 전후의 면적 비교가 아니다.','',
'| 공급 | zero row | 사이클 OFF→ON | 사이클 감소 | 전력 OFF→ON (mW) | 에너지 OFF→ON (nJ) | 에너지 감소 |',
'|---|---:|---:|---:|---:|---:|---:|']
for r in rows:
    lines.append(f"| {r['rate']} | {r['zero_row_pct']}% | {r['cycles_off']} → {r['cycles_on']} | {float(r['cycle_reduction_pct']):.2f}% | {float(r['power_off_mw']):.3f} → {float(r['power_on_mw']):.3f} | {float(r['energy_off_nj']):.2f} → {float(r['energy_on_nj']):.2f} | {float(r['energy_reduction_pct']):.2f}% |")
(O/'REPORT_KO.md').write_text('\n'.join(lines)+'\n')
if len(rows)==15:
    q=O/'REPORT_KO.md';q.write_text(q.read_text().replace('매 cycle 또는 4 cycles마다','매 cycle, 4 cycles 또는 8 cycles마다'))
sys.path.insert(0,'/tmp/idec_mac_plot_runtime')
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
plt.rcParams.update({'font.size':11,'svg.fonttype':'none','pdf.fonttype':42})
fig,axes=plt.subplots(1,2,figsize=(10,3.5),layout='constrained')
for rate,color,marker,label in [('fast','#0072BD','s','Resident U, 1 word/cycle'),('slow','#F47B20','D','Resident U, 1 word/4 cycles')]+([('supply8','#888888','^','Resident U, 1 word/8 cycles')] if len(rows)==15 else []):
    rr=[r for r in rows if r['rate']==rate]
    for ax,key in zip(axes,['cycle_reduction_pct','energy_reduction_pct']):
        ax.plot([float(r['zero_row_pct']) for r in rr],[float(r[key]) for r in rr],color=color,marker=marker,label=label,linewidth=2)
for ax,title in zip(axes,['(a) Cycle reduction','(b) Energy reduction']):
    ax.set(xlabel='Zero rows after input transform (%)',ylabel='Reduction (%)',title=title,xticks=[0,25,50,75,100],ylim=(-3,103));ax.grid(axis='y',color='#dddddd');ax.spines[['top','right']].set_visible(False)
axes[0].legend(fontsize=9,loc='upper left')
stem='controlled_cycle_energy_3rates' if len(rows)==15 else 'controlled_cycle_energy'
for ext in ['svg','pdf','png']:fig.savefig(O/f'{stem}.{ext}',dpi=180,bbox_inches='tight')
plt.close(fig)
D=ROOT/'submission/IDEC2026_FREE_TOPIC';P=D/'04_controlled_ppa';P.mkdir(exist_ok=True)
shutil.copytree(O,P/'results',dirs_exist_ok=True,ignore=shutil.ignore_patterns('*.vcd.gz','PROGRESS.txt','run.log','*.lock','measurements.csv'))
shutil.copytree(W/'vectors',P/'vectors',dirs_exist_ok=True)
shutil.copyfile(R/'verification/bypass_profile/controlled.py',P/'vector_generator_reference.py')
for rate in rates:
    (P/f'tb_{rate}.sv').write_text((W/rate/'tb.sv').read_text().replace(str(W/rate/'vectors'),'@VECTORS@'))
shutil.copyfile(Path(__file__).with_name('run.py'),P/'run.py')
(P/'reproduce.py').write_text('''from pathlib import Path
import os,sys,shutil,subprocess
D=Path(__file__).resolve().parent;A=D.parent/'03_technique_ppa_comparison/assets'
for rate in ['fast','slow']:
 W=D/'work'/rate;O=D/'reproduced_results'/rate;W.mkdir(parents=True,exist_ok=True);O.mkdir(parents=True,exist_ok=True)
 for n in ['core.v','extra.v','asap7_functional_cells.v','asap7_final_extra_cells.v','sram.v']:shutil.copyfile(A/n,W/n)
 shutil.copytree(D/'vectors',W/'vectors',dirs_exist_ok=True)
 (W/'tb.sv').write_text((D/f'tb_{rate}.sv').read_text().replace('@VECTORS@',str(W/'vectors')))
 shutil.copyfile(D/'results'/rate/'manifest.json',O/'manifest.json')
 subprocess.run(['iverilog','-g2012','-s','tb_v8_packed','-o',str(W/'sim.vvp')]+[str(W/n) for n in ['core.v','extra.v','asap7_functional_cells.v','asap7_final_extra_cells.v','sram.v','tb.sv']],check=True)
 subprocess.run([sys.executable,str(D/'run.py'),'--cases','0','1','2','3','4'],env=dict(os.environ,PPA_PROJECT=str(D.parent/'01_project'),PPA_WORK=str(W),PPA_RESULTS=str(O)),check=True)
''')
(P/'README.md').write_text('# 통제 실험: 주 평가\n\nresults/REPORT_KO.md와 comparison.csv가 주 결과이며, 03_technique_ppa_comparison은 실제 VGG 적용 사례이다.\n\nLinux/WSL에서 Icarus Verilog 12, Python3, OpenROAD/ORFS를 설치하고 ORFS_ROOT를 설정한 뒤 `python3 reproduce.py`를 실행한다. 공통 코어/셀 모델은 03 폴더의 assets를 사용한다. 각 조건의 power.tcl에 Liberty, LEF, 클록, 활동 파형 경로가 기록되어 있다. 원시 VCD는 용량상 제외했으며 재현 실행으로 생성한다.\n\n20조건 모두 독립 정수 출력과 일치해야 하며, 각 OFF/ON의 MAC 행 투입 수도 생성기의 기대값과 검증했다. 기존 공급속도 곡선과 새 결과는 측정 코어/구간이 다를 수 있으므로 새 그래프의 사이클과 에너지는 같은 게이트 실행에서 함께 계산했다.\n')
(P/'STATUS.txt').write_text(f'COMPLETE {len(rows)*2}/{len(rows)*2} gate runs; output gold and MAC row count checks PASS\n')
if len(rows)==15:
    q=P/'reproduce.py';q.write_text(q.read_text().replace("['fast','slow']","['fast','slow','supply8']"))
    q=P/'README.md';q.write_text(q.read_text().replace('20조건','30조건'))
readme=D/'README.md'
text=readme.read_text();note='\n## 통제 실험과 실제 적용 사례\n04_controlled_ppa는 공급속도와 zero-row 비율을 통제한 주 평가이다. 03_technique_ppa_comparison은 실제 VGG 두 레이어의 적용 사례이며 데이터셋 평균이 아니다. 두 평가 모두 동일 코어의 runtime sparsity OFF/ON 비교이다.\n'
if '## 통제 실험과 실제 적용 사례' not in text:readme.write_text(text+note)
files=[dict(path=p.relative_to(D).as_posix(),sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in sorted(D.rglob('*')) if p.is_file() and p!=D/'SHA256.json']
(D/'SHA256.json').write_text(json.dumps(files,indent=2))
subprocess.run([sys.executable,str(ROOT/'scripts/validate_free_topic_package.py')],check=True)
print('PASS controlled experiment published and submission ZIP refreshed',flush=True)
