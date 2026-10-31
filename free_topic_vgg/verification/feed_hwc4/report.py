from pathlib import Path
import json
R=Path(__file__).resolve().parents[2];O=R/'evidence/feed_group_sweep'
rows=json.loads((O/'results.json').read_text());assert len(rows)==18
shapes={2:'[1,16,16,64] -> Cout128',4:'[1,8,8,128] -> Cout256',10:'[1,2,2,512] -> Cout512'}
lines=['4채널/8채널 공급기 비교 — 원본 보존','================================',
       '동일 원본16코어, U8/V8, 같은 이미지, 같은 즉시응답 shared host TB.',
       '전체 출력 golden 일치, 원본 RTL 해시 일치. 초기 적재 제외 실행시간.',
       '4채널: 64byte staging, 같은64bit word의 나머지4채널은 다음 묶음에서 재독.',
       '8채널: 128byte staging, 한64bit word의8채널 모두 재사용.',
       '두 변형 모두 HWC에 한정, 기존 sharded/FC fallback 유지. 합성/PPA 미측정.',
       '비교하는 채널 묶음은 memory transport 단위이며 MAC lane 수 변경 아님.', '']
summary=[]
for stage,shape in shapes.items():
    lines += [f'Conv{stage+1}: {shape}']
    baseline=next(r for r in rows if r['layer']==stage and r['variant']=='original' and r['sparse']==0)
    for variant in ('original','group4','group8'):
        a,b=[next(r for r in rows if r['layer']==stage and r['variant']==variant and r['sparse']==s) for s in (0,1)]
        assert a['source_reads']==b['source_reads']
        reduction=100*(1-b['cycles']/a['cycles'])
        speedup=baseline['cycles']/a['cycles']
        lines += [f" {variant}: OFF={a['cycles']:,} ON={b['cycles']:,} bypass={reduction:.4f}% source_reads={a['source_reads']:,} OFFspeedup={speedup:.4f}x U_words={a['U_words']:,} resident={a['resident_u']}"]
        summary.append(dict(layer=stage+1,shape=shape,variant=variant,cycles_off=a['cycles'],cycles_on=b['cycles'],bypass_percent=reduction,reads=a['source_reads'],off_speedup=speedup))
    lines+=['']
lines += ['해석 및 범위',
          '- Conv3/5는 U 상주, Conv11은 U 비상주 조건이다.',
          '- 실제 입력 C=4 및 C=12도 별도 공급기 단위시험에서 정상/역압 조건으로 검증했다.',
          '- 레이어 비교의 group4는 입력 C를 줄인 것이 아니라 전송 묶음을 4채널로 한 것이다.',
          '- 4채널 변형은 저장소를 절반으로 줄이는 대신 C가 8의 배수일 때 읽기가 8채널의 두 배다.',
          '- 초기 activation/weight 적재는 사이클에서 제외하되 실행 중 weight 공급은 포함한다.',
          '- 한 이미지의 독립 레이어 시험이다. 전체 모델 시간/정확도 및 sharded 경로 개선 주장이 아니다.',
          '- MAC 투입 횟수 감소는 실측 전력/에너지 감소율과 같지 않다.',
          '- 원본 RTL 수정 없음. 면적, 최대 주파수, 전력은 이 변형에 대해 아직 측정하지 않았다.']
(O/'summary.json').write_text(json.dumps(summary,indent=2))
(O/'REPORT_KO.txt').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('\n'.join(lines))
