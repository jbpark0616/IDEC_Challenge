from pathlib import Path
import json
R=Path(__file__).resolve().parents[2]; O=R/'evidence/feed8_bypass_audit'
rows=json.loads((O/'results.json').read_text()); assert len(rows)==6
lines=['8채널 공급기 bypass / 병목 계측','================================',
 '16코어 U8/V8, 동일 이미지 HWC 독립 레이어, 초기 적재 제외 / 실행 중 U 공급 포함.',
 '원본 RTL 수정 없음. 계측 전후 cycles/MAC lanes/weight waits 정확히 일치.',
 '모든 출력 golden 검증. 전력 및 합성 주파수는 이번 시험의 측정 대상이 아님.','']
for layer,shape in [(3,'[1,16,16,64] -> Cout128'),(5,'[1,8,8,128] -> Cout256'),(11,'[1,2,2,512] -> Cout512')]:
    a,b=[next(r for r in rows if r['layer']==layer and r['sparse']==s) for s in (0,1)]
    p,q=a['profile'],b['profile']
    lines += [f'Conv{layer} {shape}',f' cycles {p["cycles"]:,} -> {q["cycles"]:,}: {100*(1-q["cycles"]/p["cycles"]):.4f}% 감소',
              f' MAC lanes {p["mac_lanes"]:,} -> {q["mac_lanes"]:,}: {100*(1-q["mac_lanes"]/p["mac_lanes"]):.4f}% 감소',
              f' MAC beats (16코어 합) {p["mac_beats"]:,} -> {q["mac_beats"]:,}: {100*(1-q["mac_beats"]/p["mac_beats"]):.4f}% 감소',
              f' 코어당 평균 beat 절감={(p["mac_beats"]-q["mac_beats"])/16:.2f}, 전체 wall-cycle 절감={p["cycles"]-q["cycles"]:,}']
    for label,row in [('OFF',a),('ON',b)]:
        f=row['feed']; cores=row['cores']
        lines += [f' {label} feed: '+', '.join(f'{k}={v:,}' for k,v in f.items()),
                  f' {label} core0: '+', '.join(f'{k}={v:,}' for k,v in cores[0].items())]
        for key in ('v_missing','row_blocked','mac_blocked','weights','producer_no_tile','finish'):
            v=[c[key] for c in cores];lines += [f' {label} {key}: min={min(v):,} max={max(v):,} mean={sum(v)/16:.2f} core-cycles']
    lines+=['']
lines += ['해석',
 'Conv3/5: OFF에서 코어당 32,768 MAC beat가 실행되며 V 미도착 대기는 각각317/621이다.',
 'Conv5: 코어당 beat 감소1,615회에 대해 wall-cycle 감소1,611이다. 생략된 beat의 시간 이득이 거의 보존된다.',
 'lane 수 감소는 같은 beat 안의 일부 lane 비활성화도 포함하므로 beat/사이클 감소와 동일하지 않다.',
 'Conv11 OFF: activation 공급은2,560에 끝난다. 최종 코어15의 C_WEIGHTS 체류는447,839이다.',
 '이 경우 activation/V 포트보다 U 가중치 전환 및 공급 대기가 주된 실행시간을 차지한다.',
 '공급기 출력 역압은 downstream이 받아줄 수 없다는 뜻이며 SRAM read 자체가 느리다는 뜻이 아니다.',
 '다음 최적화 후보는 비상주 U의 전송/전환과 연산 중첩이다. 이 실험에서는 구조를 바꾸지 않았다.',
 '', '계측 정의',
 'feed: emit=출력 handshake, pad=padding 준비, prepare=유효 위치 주소 준비,',
 'request/response=상태 체류시간. *_stall은 해당 상태 안에서 handshake가 없던 부분집합.',
 'blocked=출력 역압, finished=공급 완료 뒤 cluster 실행이 끝날 때까지의 시간.',
 'feed 상태 항목 합계는 audit_cycles와 일치하도록 TB에서 검사한다.',
 'core: weights=C_WEIGHTS 체류, wait_v_slot=C_WAIT 체류, job=C_JOB, mac_state=C_MAC.',
 'v_missing=engine busy 중 남은 유효 채널이 없고 reduction 완료도 아닌 시간.',
 'MAC acceptance > MAC blocked > V missing > row blocked > busy other 우선순위로 분류.',
 '따라서 row_blocked는 이전 MAC beat 수락과 겹치지 않는 read 거절만 센다.',
 'producer_no_tile/rx_missing은 다른 카운터와 중첩하므로 총 사이클에 더하지 않는다.',
 '16코어 대기 합계는 wall-clock 사이클과 다르다. min/max/mean은 코어별 통계다.',
 'V missing은 데이터 미도착 상태의 지표이며 SRAM 포트 충돌이라는 뜻이 아니다.',
 '실행 중 weight 대기와 다른 코어 연산은 겹칠 수 있어 개별 시간을 단순 합산하지 않는다.']
(O/'REPORT_KO.txt').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('\n'.join(lines))
