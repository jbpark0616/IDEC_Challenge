"""Rebuild the report only from passing logs; keep full-model claims separate."""
from pathlib import Path
import hashlib
import json
import re

here=Path(__file__).resolve().parent
root=here.parents[1]
results={}
for mode,name in [('resident','run.log'),('streamed','streamed.log')]:
    text=(here/name).read_text()
    assert 'PASS U_LOADING compared_words=694' in text
    rows=[]
    for line in text.splitlines():
        if line.startswith('U_LOADING'):
            row=dict(re.findall(r'(\w+)=([\d,]+)',line))
            rows.append({k:v if ',' in v else int(v) for k,v in row.items()})
    assert len(rows)==24
    results[mode]=rows
assert 'PASS U_LOADING' in (here/'v16_regression.log').read_text()
assert 'cases=16328' in (here/'quantizer.log').read_text()
assert '%Error' not in (here/'cluster_lint.log').read_text()
baseline=(root/'evidence/bypass_u8_v16/resident.log').read_text().splitlines()
regression=(here/'v16_regression.log').read_text().splitlines()
assert [x for x in baseline if x.startswith('U_LOADING')]==[x for x in regression if x.startswith('U_LOADING')]
lines=['U8/V8 RTL 적용 및 메모리 공급 부분 검증',
       'U는 실제 Cin 기반 밀집 배치이며, 상주는 bank당 1024워드 용량으로 판정한다. 출력 16개 상한 없음.',
       '',
       '양자화: floor((V + 2^(s-1))/2^s), s=0이면 V; -127~127 포화.',
       'Colab과 동일한 레이어 시프트: Conv1=2, Conv2~13=1. 보정값을 테스트 데이터로 재조정하지 않았다.',
       'mask는 양자화된 V에서 판정하며 재사용 수명 동안 유지한다.',
       '64비트 SRAM 워드에 두 채널의 4원소 INT8 행을 밀집 저장한다.',
       '짝수 채널 수에서 V 저장량과 bank 쓰기 횟수 50% 감소. 홀수 마지막 채널은 상위 절반 0 패딩.',
       '한 채널의 첫 절반은 행별 32비트 FF에 보관하고 다음 절반과 합쳐 쓰며, 실제 쓰기 완료 뒤 watermark를 공개한다.',
       '기존 CB 슬롯 수, bank 수, 코어 수, MAC 수, tile generator, accumulator 폭은 유지한다.',
       'MAC 입력에서 V8 부호 확장과 레이어 시프트를 복원한다. 8x8 곱셈기 축소를 구현한 것은 아니다.',
       '독립 행별 주소/반워드 선택을 유지한다. 같은 packed 워드의 두 채널을 읽을 때 SRAM 재읽기를 제거하는 캐시는 아직 없다.',
       '따라서 쓰기 절반을 읽기 대역폭 2배 또는 전체 속도 2배로 해석하지 않는다.',
       '',
       '검증: 12사례 x sparse OFF/ON x U 상주/반복적재 = 48회. 각 모드 694 출력 워드 일치.',
       '양자화 단위 검증: V=-1020..1020, shift=0..7의 16328 조합 전부 일치.',
       'case0~9: 합성 입력, 홀수 C/shift0~4/2994개 V 포화/전체0/pooling/backpressure/stale commit.',
       'case10: 실제 VGG Conv9, 4x4x512 입력, 해당 레이어 첫 출력 채널 4개.',
       'case11: 실제 VGG Conv13, 2x2x512 입력, 첫 출력 채널 4개 및 pooling.',
       '실제 사례의 입력은 이전 레이어도 U8/V8로 계산한 Python reference에서 가져왔다.',
       'V16 회귀 20회: 기존 결과값과 사이클/행 투입/U 대기 수치까지 동일.',
       '16코어 V8 full-model TB lint 통과. U8/V8 full-model RTL 전체 실행은 아직 하지 않았다.',
       'Python U8/V8 전체 reference 이미지0의 최종 분류는 3. 이는 RTL 전체 실행 결과가 아니다.',
       '',
       '실행 중 계측(초기 U 적재 제외):']
for mode in results:
    for case in (9,10,11):
        a,b=[r for r in results[mode] if r['case']==case]
        lines.append(f"{mode} case{case} input={a['input']} local_K={a['local_K']}: {a['cycles']} -> {b['cycles']} cycles ({100*(1-b['cycles']/a['cycles']):.2f}% 감소), rows {a['rows']} -> {b['rows']}, weight_wait {a['weight_wait']} -> {b['weight_wait']}")
lines+=['', '다음 full-model 실행 진입점 run.sh는 V8을 기본 선택하며, 연속 host 전송과 U 상주를 켠다.',
        '기존 V16 run.log/results.json은 보존하고 V8 로그는 full_model/v8_run에 분리한다.']
fc=here/'fc_run.log'
if fc.exists():
    assert 'PASS HOST_STREAM' in fc.read_text()
    lines+=['','추가 16코어 Conv/FC 전환 회귀 로그:',fc.read_text().strip()]
(here/'REPORT_KO.txt').write_text('\n'.join(lines)+'\n',encoding='utf-8')
(here/'results.json').write_text(json.dumps(results,indent=2)+'\n')
hashes={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (root/'rtl').rglob('*.v')}
(here/'rtl_sha256.json').write_text(json.dumps(hashes,indent=2)+'\n')
print('\n'.join(lines[-13:]))
