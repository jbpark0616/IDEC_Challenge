"""Describe measured cycles and actual post-quantization zero distribution."""
from pathlib import Path
import csv,json
R=Path(__file__).resolve().parents[2];O=R/'evidence/bypass_current';V=R/'verification/v8/vectors'
def read(p):return [int(x,16) for x in p.read_text().split()]
configs=read(V/'config.hex');shifts=read(V/'vshift.hex');stats=[]
for case,conf in enumerate(configs):
    h=(conf>>40)&63;c=(conf>>24)&1023;k=(conf>>16)&255
    words=read(V/f'case{case}/input.hex');x=[(w>>(8*i))&255 for w in words for i in range(8)][:h*h*c]
    zero_rows=[0]*4; zero_tiles=0; total=0; ideal_max=0
    for y in range(0,h,2):
        for z in range(0,h,2):
            active=[0]*4
            for ch in range(c):
                d=[[x[((y+r-1)*h+z+q-1)*c+ch] if 0<=y+r-1<h and 0<=z+q-1<h else 0 for q in range(4)] for r in range(4)]
                t=[[d[0][q]-d[2][q],d[1][q]+d[2][q],d[2][q]-d[1][q],d[1][q]-d[3][q]] for q in range(4)]
                t=list(zip(*t));vv=[[a-cc,b+cc,cc-b,b-e] for a,b,cc,e in t];s=shifts[case]
                vv=[[max(-127,min(127,(n+(1<<(s-1) if s else 0))>>s)) for n in row] for row in vv]
                zeros=[not any(row) for row in vv]
                for r in range(4):zero_rows[r]+=int(zeros[r]);active[r]+=int(not zeros[r])
                total+=1;zero_tiles+=int(all(zeros))
            ideal_max+=max(active)*k
    st=dict(case=case,input_NHWC=f'1,{h},{h},{c}',local_K=k,tiles=total,zero_tiles=zero_tiles,zero_row_percent=100*sum(zero_rows)/(4*total),**{f'row{r}_zero_percent':100*zero_rows[r]/total for r in range(4)},ideal_dense_beats=total*k,ideal_sparse_beats=ideal_max)
    stats.append(st)
with (O/'activation_distribution.csv').open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(stats[0]));w.writeheader();w.writerows(stats)
effects=list(csv.DictReader((O/'effects.csv').open()));measure=list(csv.DictReader((O/'measurements.csv').open()))
for p in measure:
    st=stats[int(p['case'])]
    expected=st['tiles']*4*st['local_K']*(1-st['zero_row_percent']/100 if int(p['sparse']) else 1)
    assert abs(float(p['mac_lanes'])/4-expected)<1e-6,(p['case'],expected,p['mac_lanes'])
lines=['자유주제 현재 고정 코어 — U8/V8 sparsity-aware 부분 평가',
'======================================================',
'결론: 기능/출력 일치와 사이클 감소를 확인. 전체 VGG/16코어 성능 및 전력 측정은 아님.',
'최종 고정 RTL SHA256 29항목(소스 목록 포함) 일치. RTL 수정 없음.',
'12개 사례 × sparse OFF/ON × 용량 기반 상주/강제 재적재 = 48회 PASS.',
'모드별 694 출력 워드가 정수 reference와 일치; ON/OFF 동일 정답.',
'고정 TILE_INPUT=1, U8/V8, DENSE_U=1, 코어당 16 MAC lane. 메모리 기본 구조 유지.',
'전체 16코어 중 한 코어를 측정. local_K는 이 코어가 담당한 출력 채널 수.',
'입력 표기는 [N,H,W,Cin]. conv 출력은 같은 H,W에서 local_K, pooling이면 H,W 절반.',
'U 용량은 4bank × 8KiB =32KiB. 필요량은 16*Cin*local_K bytes (짝수 Cin).',
'홀수 Cin은 행당 두 채널/워드 packing의 끝 패딩 포함 용량으로 상주 판정.',
'',
'용량 정책을 사용하는 결과 (실행 사이클: 초기 U 적재 제외):',
'입력[N,H,W,C] | local_K | U | 상주 | OFF -> ON | 절감 | MAC lane 투입 절감']
for p in effects:
    if p['mode']!='capacity_policy':continue
    lines.append(f"{p['input']} | {p['local_K']} | {int(p['u_bytes'])/1024:g} KiB | {p['resident']} | {p['cycles_off']} -> {p['cycles_on']} | {float(p['cycle_reduction_percent']):.2f}% | {float(p['lane_reduction_percent']):.2f}% ({p['data_kind']}, case{p['case']})")
lines+=['','실제 VGG 입력 상세: 동일 이미지의 U8/V8 Python reference에서 추출한 두 레이어의 첫 출력 4개.',
'Conv9: 입력[1,4,4,512], 코어 출력4개, 초기 U 적재 작업+run 20715 ->18083 (12.71%).',
'Conv13: 입력[1,2,2,512], 코어 출력4개+pool, 초기 U 적재 작업+run11329 ->11257 (0.64%).',
'전체 VGG의 원래 출력 채널 전체를 실행한 레이어 latency가 아님.',
'용량 초과 사례는 합성 데이터다. 실제 VGG의 용량 초과 레이어 효과로 단정하지 않는다.',
'',
'원인 분석 / 계측 한계:',
'- SRAM U/V는 DUT 경로를 통과한다. activation 타일은 TB가 직접 공급한다.',
'  전체 외부 DRAM -> A/B SRAM -> shared feed -> multicast 비용은 포함하지 않는다.',
'- TB는 입력 7cycle마다 1cycle, 출력13cycle중4cycle stall을 넣는다.',
'  U 쓰기는 64bit store task의 2cycle/word. 실물 DRAM 대역폭 모델이 아니다.',
'- U 재요청 때 상태 polling, 의도적 stale commit 및5cycle 대기를 포함한다.',
'  weight_wait에는 데이터 재적재뿐 아니라 metadata/commit 대기도 포함된다.',
'  따라서 상주 케이스의 weight_wait가0이 아니어도 U를 다시 썼다는 뜻은 아니다.',
'- capacity_policy는 용량이 맞으면 상주. forced_reload는 진단용 비상주 비교다.',
'  forced_reload 결과를 현재 권장 메모리 정책의 성능으로 제시하지 않는다.',
'- 실측 Conv9의 V read blocked OFF/ON=6/5, Conv13=0/0cycle.',
'  이 사례에서 V 읽기/쓰기 중재는 지배적 병목이 아니다.',
'- no_ready_channel은 엔진 busy, 미완료, 다음 알려진 채널 없음 조건이다.',
'  Conv9 4006 ->4701, Conv13 1027 ->1050. 연산을 더 생략하면서 공급을',
'  따라잡아 대기가 늘 수 있다. 이 증가 자체를 성능 퇴보로 해석하지 않는다.',
'- 모든 stall 카운터는 관측 조건별 값이며 상호 배타적이지 않다. 합산 금지.',
'- MAC lane 투입은 accepted response의 활성 row 수 ×4. 실제 비영 곱셈',
'  또는 스위칭/에너지 측정이 아니다. row mask와 투입 수의 수학적 일치도 확인했다.',
'- ideal_sparse_beats는 채널이 모두 준비됐다고 가정한 타일별 max(행별 비영 채널 수)',
'  ×local_K. 제어/공급 대기/빈 종료 beat/결과처리 제외하므로 실제 latency가 아니다.',
'',
'권장 판단:',
'현재 코어의 bypass가 실제 데이터에서 동작하고 일부 레이어에서 유의미한 사이클',
'절감을 만든다는 근거는 확보했다. 모든 레이어의 큰 절감 또는 전력절감을 보장하지 않는다.',
'코어 구조 변경보다 실제 A/B SRAM+feed+mcast를 포함한 대표 레이어 부분 검증이',
'다음 단계다. 그 결과 확인 후 cluster/controller/interconnect 합성 범위를 확정한다.',
'이번 요청은 측정으로 수행했으며 새로운 코어 freeze나 전체 합성은 실행하지 않았다.',
'',
'재현: WSL python3 free_topic_vgg/verification/bypass_profile/run.py',
'리포트: python free_topic_vgg/verification/bypass_profile/report.py',
'측정 runtime: '+str(round(json.loads((O/'provenance.json').read_text())['elapsed_seconds'],1))+' seconds (build+48 tests).',
'raw: capacity_policy.log, forced_reload.log, measurements.csv, effects.csv, activation_distribution.csv']
(O/'REPORT_KO.txt').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('\n'.join(lines[:26]));print('PASS: measured MAC rows equal independently calculated post-V8 zero distribution')
