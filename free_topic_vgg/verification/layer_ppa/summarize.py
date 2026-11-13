"""Publish completed matched layer pairs only."""
from pathlib import Path
import json,csv,re
R=Path(__file__).resolve().parents[2];O=R/'evidence/layer_ppa'
area=float(re.search(r': ([\d.]+) um', (O/'core_area.rpt').read_text())[1])
fmax=float(re.search(r'fmax = ([\d.]+)',(O/'core_timing.rpt').read_text())[1])
rows=[]; coverage=[]
for case,layer in [(10,'Conv9'),(11,'Conv13')]:
    paths=[O/f'case{case}_sparse{s}'/'measurement.json' for s in [0,1]]
    if not all(p.exists() for p in paths):continue
    a,b=[json.loads(p.read_text()) for p in paths]
    logs=[(O/f'case{case}_sparse{s}/simulation.log').read_text() for s in [0,1]]
    counts=[dict((k,int(v)) for k,v in re.findall(r'\b(cycles|rows)=(\d+)',log)) for log in logs]
    for s in [0,1]:
        out=O/f'case{case}_sparse{s}'
        assert 'PASS U_LOADING' in (out/'simulation.log').read_text()
        ann=(out/'activity.rpt').read_text()
        missing=int(re.search(r'unannotated\s+(\d+)',ann)[1])
        assert missing==len([l for l in ann.splitlines() if '/sdel[' in l])==40
        coverage.append(f'{layer} sparse={s}\n'+ann[:2000])
    rows.append(dict(layer=layer,input_NHWC=a['input_NHWC'],local_output_channels=a['local_output_channels'],area_off_um2=area,area_on_um2=area,fmax_off_mhz=fmax,fmax_on_mhz=fmax,clock_mhz=1e6/1430,active_cycles_off=counts[0]['cycles'],active_cycles_on=counts[1]['cycles'],row_issues_off=counts[0]['rows'],row_issues_on=counts[1]['rows'],power_off_mw=a['power_w']*1000,power_on_mw=b['power_w']*1000,power_reduction_pct=100*(1-b['power_w']/a['power_w']),latency_off_us=a['duration_ps']/1e6,latency_on_us=b['duration_ps']/1e6,latency_reduction_pct=100*(1-b['duration_ps']/a['duration_ps']),energy_off_nj=a['energy_nj'],energy_on_nj=b['energy_nj'],energy_reduction_pct=100*(1-b['energy_nj']/a['energy_nj'])))
assert rows,'No completed matched pairs'
with (O/'comparison.csv').open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
lines=['# 레이어별 코어 활동 기반 PPA 비교','',
'비교: Winograd + ICG (sparse OFF) / Winograd + ICG + sparsity-aware (sparse ON).',
'최종 합성 netlist에서 추출한 동일 계산 코어이며, 양쪽의 면적과 정적 Fmax는 같다.',
'U/V SRAM 8개 포함. 외부 activation SRAM 4개, 공급기, multicast, 나머지 코어 제외.',
'실제 VGG 이미지 한 장에서 추출한 레이어 입력/가중치, 로컬 출력 4채널만 평가.',
'전체 16코어 전력, 전체 VGG 처리시간 또는 이미지당 에너지로 해석하지 않는다.',
'초기 U 적재 제외; 명령 시작부터 완료 관측까지 측정. 실행 중 제어/대기 포함.',
'동일 1430ps 클록(699.300699MHz), 제로 지연 게이트 시뮬레이션. 배치·배선·SDF 미적용.',
'ASAP7 FF Liberty와 제공된 SRAM Liberty를 이용한 OpenROAD 전력 추정. 실측 전력이 아니다.',
'SRAM 모델의 전압/온도 조건은 표준셀과 다르며 기존 전체 합성과 같은 혼합 라이브러리 조건이다.',
'',f'공통 Liberty 면적: {area:.5f} um²; 배치 전 Fmax: {fmax:.2f} MHz.','',
'| 레이어 | 입력 NHWC | 전력 OFF→ON (mW) | 전력 감소 | 지연 OFF→ON (µs) | 구간 에너지 OFF→ON (nJ) | 에너지 감소 |',
'|---|---|---|---|---|---|---|']
for r in rows:
    lines.append(f"| {r['layer']} | {r['input_NHWC']} | {r['power_off_mw']:.5f} → {r['power_on_mw']:.5f} | {r['power_reduction_pct']:.2f}% | {r['latency_off_us']:.5f} → {r['latency_on_us']:.5f} | {r['energy_off_nj']:.5f} → {r['energy_on_nj']:.5f} | {r['energy_reduction_pct']:.2f}% |")
lines+=['','모든 완료된 OFF/ON 조건의 출력 word는 같은 독립 정수 기준값과 일치했다.',
'활동 주석 범위는 각 case의 activity.rpt, 원시 전력은 power.rpt, 파형 구간은 measurement.json 참조.',
'동적 모드 비교이므로 최적화 회로를 제거한 별도 구현 대비 면적 오버헤드를 측정한 실험이 아니다.',
'ICG는 양쪽에 유지하므로 이 결과로 ICG 자체의 절감률을 주장하지 않는다.']
(O/'REPORT_KO.md').write_text('\n'.join(lines)+'\n')
(O/'annotation_summary.txt').write_text('\n\n'.join(coverage))
print('\n'.join(lines))
