"""Summarize completed paired runs only; never infer missing measurements."""
from pathlib import Path
import csv
import hashlib
import json

R = Path(__file__).resolve().parents[2]
O = R / 'evidence/report700'
manifest = json.loads((R / 'evidence/report_baseline_700mhz/manifest.json').read_text(encoding='utf-8-sig'))
for entry in manifest['files']:
    assert hashlib.sha256((R / entry['path']).read_bytes()).hexdigest().lower() == entry['sha256'].lower()

def rows(folder):
    file = O / folder / 'effects.csv'
    return list(csv.DictReader(file.open(newline=''))) if file.exists() else []

controlled = []
for folder in ['scale32', 'core_controlled', 'scale512']:
    for row in rows(folder):
        controlled.append({'source': folder, **row,
            'u_fits_32kib': int(int(row['u_bytes']) <= 32768),
            'inclusive_off_us_700mhz': int(row['inclusive_off']) / 700,
            'inclusive_on_us_700mhz': int(row['inclusive_on']) / 700})
if controlled:
    with (O / 'controlled_scaling.csv').open('w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=list(controlled[0]))
        writer.writeheader(); writer.writerows(controlled)

lines = [
    '자유주제 700MHz 기준 bypass 실험 — 완료된 쌍만 집계',
    '===================================================',
    '현재 RTL 해시는 evidence/report_baseline_700mhz/manifest.json으로 검사했다.',
    '16코어 x 16 MAC, U8/V8, SRAM 12 x 8KiB/core. 이번 측정에서 RTL 변경 없음.',
    '700MHz는 보고용 가정이다. 최신 배치배선 전 STA 추정 725.89MHz이며 signoff 결과가 아니다.',
    'latency(us) = cycles / 700. 시뮬레이터 실행 시간과 하드웨어 latency를 구분한다.',
    '',
    '1. 단일 코어 통제 실험 (전체 16코어 성능으로 해석하지 않는다)',
    '입력 [N,H,W,C]=[1,4,4,C], 출력 채널은 코어 로컬 K=8 또는32.',
    '공간 activation을 변환해 mask를 생성한다. mask를 강제로 주입하지 않는다.',
    '동일 입력/가중치에서 sparse OFF/ON을 비교하고 독립 정수 oracle로 출력을 확인한다.',
    'fast: 타일 입력 매 사이클 가능. slow: 4사이클 중1사이클 가능.',
    'U 용량32KiB의 실제 상주 정책 사용. initial preload는 run cycles에서 제외하고 inclusive에 별도 포함.',
    'inclusive는 initial preload + 실행이며, 실행 중 재적재는 이미 실행 시간에 포함된다.',
    '',
    '균등 50% zero-row 결과:',
    '입력 / 로컬K / U KiB / 공급 / OFF -> ON / 실행사이클 감소',
]
for row in controlled:
    if row['pattern'] == 'balanced50':
        lines.append(f"{row['input_NHWC']} / {row['local_K']} / {int(row['u_bytes'])/1024:g} / {row['rate']} / {row['cycles_off']} -> {row['cycles_on']} / {float(row['cycle_reduction']):.2f}%")
lines += [
    '',
    '해석: zero-row 비율만으로 사이클 절감률을 결정할 수 없다.',
    '행별 작업량 불균형, V 공급 및 SRAM 충돌, U 교체와 제어 시간도 포함된다.',
    'unbalanced50은 총 zero-row 비율이50%여도 일부 행의 최대 작업량이 유지되는 대조군이다.',
    'MAC lane 투입량과 MAC beat 수는 별도 지표다. 한 beat에서 일부 행만 활성일 수 있다.',
    '대기 카운터들은 겹칠 수 있으므로 더해서 전체 사이클로 만들지 않는다.',
    'weight_wait 카운터에는 제어/메타데이터 대기도 포함되어 순수 DRAM stall로 해석하지 않는다.',
    '',
    '2. 실제16코어 VGG 레이어 (기존 이미지1장의 중간 activation)',
    '각 레이어를 독립 실행: core0 A SRAM 입력 적재 -> 실제 공급/multicast ->16코어 연산.',
    'Conv1/5/9/13의 OFF/ON을 비교한다. 마지막까지 완료된 쌍만 아래에 표시한다.',
    '모든 출력 SRAM word를 golden과 대조. 전체모델 latency 또는 여러 이미지 평균이 아니다.',
]
cluster = rows('cluster')
for row in cluster:
    lines.append(f"Conv{row['layer']} 입력{row['input_NHWC']} Cout={row['output_channels']}, U/core={int(row['u_bytes_per_core'])/1024:g}KiB, resident={row['resident_u']}: {row['cycles_off']} -> {row['cycles_on']} cycles ({float(row['cycle_reduction_percent']):.2f}% 감소), MAC lane {float(row['mac_lane_reduction_percent']):.2f}% 감소; 적재 포함 {row['inclusive_off']} -> {row['inclusive_on']} cycles")
lines += [
    f'완료 레이어쌍: {len(cluster)}/4. 미완료 항목은 cluster_run.log에서 상태 확인.',
    '',
    '3. 파일',
    'controlled_scaling.csv: 완료된 통제실험 통합표 (그래프용)',
    'core_actual/: 기존48개 코어 경계 실험. 실제 VGG 데이터도 일부 출력채널만 측정.',
    'core_controlled/, scale32/, scale512/: 원시 로그, counters, effects, provenance',
    'cluster/: 실제16코어 레이어별 로그, measurements.csv, effects.csv, provenance',
    '',
    '전력/에너지 측정은 이번 실험에 포함하지 않는다. MAC 감소율을 전력 감소율로 대체하지 않는다.',
]
(O / 'REPORT_KO.txt').write_text('\n'.join(lines) + '\n', encoding='utf-8')
print(f'Updated report: {len(controlled)} controlled pairs; {len(cluster)} cluster pairs')
