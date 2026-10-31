from pathlib import Path
import csv,json,re,hashlib
R=Path(__file__).resolve().parents[2];O=R/'evidence/multicast_profile'
t=(O/'supply_run.log').read_text();assert 'PASS SRAM_SUPPLY' in t
rows=[{k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)} for line in t.splitlines() if line.startswith('SUPPLY')]
assert len(rows)==12
effects=[]
for a,b in zip(rows[::2],rows[1::2]):
    assert a['multicast']==0 and b['multicast']==1 and a['bytes']==b['bytes']
    assert a['external_bytes']==16*b['external_bytes']
    assert a['received_words']==b['received_words']==16*a['h']**2//4*a['cin']*2
    effects.append(dict(input_NHWC=f"[1,{a['h']},{a['h']},{a['cin']}]",bytes=a['bytes'],period=a['period'],
        repeated_load_cycles=a['cycles'],single_load_mcast_cycles=b['cycles'],speedup=a['cycles']/b['cycles'],
        reduction_percent=100*(1-b['cycles']/a['cycles']),external_bytes_repeated=a['external_bytes'],external_bytes_mcast=b['external_bytes'],
        repeated_load_phase=a['load_cycles'],mcast_load_phase=b['load_cycles'],tile_words_per_receiver=a['received_words']//16))
for name,items in [('supply_measurements.csv',rows),('supply_effects.csv',effects)]:
    with (O/name).open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(items[0]));w.writeheader();w.writerows(items)
m=json.loads((R/'evidence/report_baseline_700mhz/manifest.json').read_text(encoding='utf-8-sig'))
for f in m['files']:assert hashlib.sha256((R/f['path']).read_bytes()).hexdigest().lower()==f['sha256'].lower()
(O/'supply_provenance.json').write_text(json.dumps(dict(rtl_manifest=m,tb_sha256=hashlib.sha256((R/'verification/multicast_profile/tb_sram_supply.sv').read_bytes()).hexdigest(),runs=12),indent=2))
lines=['SRAM 공급 경로 통제 비교 — RTL 변경 없음',
'반복 적재: 하나의64-bit 외부 포트로 각 코어 SRAM에 HWC 데이터를16회 적재. 각 코어 적재 직후 독립 activation_feed가 시작하며 이후 코어 적재와 중첩된다.',
'단일 적재+멀티캐스트: core0 SRAM에1회 적재 후 실제 activation_feed(TILE_STREAM=1) -> fanout ->16개 RX FIFO.',
'비교용 반복 적재 경로의16개 독립 feed는 테스트벤치 구성이다. 현재 메인 칩에16개 feed가 있다는 뜻이 아니다.',
'양쪽 실제 activation_sram, 제공된 SRAM behavioral macro, activation_feed, elastic_fifo를 사용했다.',
'첫 host write 제공부터 모든 코어가 마지막 tile word를 소비하고 FIFO가 비워질 때까지 측정.',
'padding/4x4 타일/입력채널 순서를 독립 HWC oracle와 모든 수신 word에 대해 비교했다. 12회 통과.',
'수신측 항상ready. 실제 MAC backpressure, DRAM command latency, weight traffic는 포함하지 않는다.',
'외부 공급률1word/cycle 또는1word/4cycles. 이는64-bit host 경계의 공급률이다.',
'이 결과는 SRAM 공급 subsystem 비교이며 full-model 가속비나 물리 DRAM 실측이 아니다.',
'(a) 통신블록은payload 자체를 전송, (b) 공급경로는HWC를타일로 확장하므로 패널간 절대cycles를 직접 비교하지 않는다.', '']
for e in effects:lines.append(str(e))
(O/'SUPPLY_REPORT_KO.txt').write_text('\n'.join(lines),encoding='utf-8')
print(effects)
