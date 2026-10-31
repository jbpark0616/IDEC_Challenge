from pathlib import Path
import re,json
R=Path(__file__).resolve().parents[2]; O=R/'evidence/cluster_bottleneck'
all_rows=[]
for sparse in (0,1):
    text=(O/f'conv5_sparse{sparse}.log').read_text()
    assert 'PASS ISOLATED_LAYER' in text
    def values(line): return {k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)}
    feed=values(next(l for l in text.splitlines() if l.startswith('FEED_AUDIT')))
    cores=[values(l) for l in text.splitlines() if l.startswith('CORE_AUDIT')]
    profile=values(next(l for l in text.splitlines() if l.startswith('PROFILE')))
    assert len(cores)==16
    assert sum(feed[k] for k in ('hit','pad','miss','blocked','request','response','drain','other'))==feed['cycles']
    assert all(sum(c[k] for k in ('wait_v_slot','job','mac_state','weights','done'))==feed['cycles'] for c in cores)
    all_rows.append(dict(sparse=sparse,feed=feed,cores=cores,profile=profile))
(O/'bottleneck.json').write_text(json.dumps(all_rows,indent=2))
lines=['Conv5 병목 실측 — 원본 RTL, 즉시 요청 응답 TB',
       '입력 [1,8,8,128], 출력256, 16코어, U 전체상주. 이미지1장.',
       'RTL 계측은 read-only. 측정 전후 해시 일치. 기존 즉시TB와 사이클 동일.',
       '모든 최종 출력 2048word/실행 golden 일치. OFF/ON 2회 PASS.', '',
       '1. 공급기 사이클 분해 (서로 배타적인 상태 카운터)',
       'BUILD hit는 새로 읽은 워드의 재시도도 포함하므로 cache reuse hit rate가 아니다.']
for r in all_rows:
    f=r['feed']; p=r['profile']
    lines += [f"sparse={r['sparse']}, total={p['cycles']}, sampled_RUN={f['cycles']}, last_feed={f['last_feed']}",
              f"픽셀 조립(hit+pad)={f['hit']+f['pad']}; 미스 판정={f['miss']}; 요청상태={f['request']}; 응답상태={f['response']}; drain={f['drain']}; 기타(주로feed완료후)={f['other']}",
              f"downstream 정지={f['blocked']}, 요청 추가대기={f['request_stall']}, 응답 추가대기={f['response_stall']}",
              f"전송={f['words']}word, 고유 source word={f['unique_reads']}"]
lines += ['', '2. 코어별 계측 (서로 다른 그룹의 카운터는 중첩 가능; 합산 금지)']
for r in all_rows:
    lines += [f"sparse={r['sparse']}"]
    for c in r['cores']:
        lines += [f"core{c['core']}: MACbeats={c['mac_beats']} V미도착={c['v_missing']} operand요청거절={c['row_blocked']} MACready대기={c['mac_blocked']} weight상태={c['weights']} RX미도착={c['rx_missing']} RX막힘={c['rx_blocked']} 완료위치={c['finish']}"]
lines += ['', '3. 확정할 수 있는 원인',
          '독립 주소 재생 address_audit.json: 유효 픽셀25088회마다 cache miss. 재사용hit=0.',
          'HWC C128: spatial pixel 간 word address 간격16. cache index는 word[1:0].',
          '서로 다른 공간 픽셀이 같은 cache entry를 덮어써 다음 채널의 같은 word를 재사용하지 못함.',
          '8KiB 원본을 25088*8=200704byte(196KiB) 읽음. 고유word1024, 평균24.5회 재독.',
          '유효 픽셀마다 미스판정/요청/응답/픽셀조립 4사이클; padding7680개는 각1사이클.',
          '25088*4 + 7680 =108032, drain 포함 마지막 공급108033과 일치.',
          'SRAM 추가 wait나 multicast backpressure 없이도 공급기 FSM만으로 이 시간이 필요.',
          'bypass는 공급기 주소순서/전송량을 바꾸지 않아 OFF/ON 공급완료시점이 동일.',
          '코어의 작업 감소는 상당부분 V미도착 대기 증가로 바뀐다.',
          '이 결론은 이 HWC Conv5 측정에 해당. sharded/다른shape/비상주U에 자동 일반화하지 않음.',
          '이번에는 수정하지 않음. 개선 우선순위는 같은64bit워드의8채널 재사용과 요청/응답 파이프라인.',
          '처리순서/출력/재사용 수명을 유지하는 제한된 공급기 수정 후 동일시험으로 검증해야 함.']
(O/'REPORT_KO.txt').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('\n'.join(lines[:17]))
