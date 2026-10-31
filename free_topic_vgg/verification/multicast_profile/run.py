from pathlib import Path
import subprocess,json,hashlib,csv,re
R=Path(__file__).resolve().parents[2]
O=R/'evidence/multicast_profile';W=R/'build/multicast_profile'
manifest=json.loads((R/'evidence/report_baseline_700mhz/manifest.json').read_text(encoding='utf-8-sig'))
for f in manifest['files']:
    assert hashlib.sha256((R/f['path']).read_bytes()).hexdigest().lower()==f['sha256'].lower()
sources=['rtl/designated/elastic_fifo.v','rtl/interconnect/vgg_mcast_fanout.v','verification/multicast_profile/tb_transport.sv']
with (O/'build.log').open('w') as log:
    subprocess.run(['iverilog','-g2012','-s','tb_transport','-o',str(W/'sim'),*sources],cwd=R,stdout=log,stderr=subprocess.STDOUT,check=True)
with (O/'run.log').open('w') as log:
    subprocess.run(['vvp',str(W/'sim')],cwd=R,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
text=(O/'run.log').read_text();assert 'PASS TRANSPORT' in text
rows=[{k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)} for line in text.splitlines() if line.startswith('RESULT')]
assert len(rows)==12
effects=[]
for a,b in zip(rows[::2],rows[1::2]):
    assert a['multicast']==0 and b['multicast']==1
    assert a['received_words']==b['received_words']==16*a['bytes']//8
    assert a['external_bytes']==16*b['external_bytes']
    effects.append(dict(bytes_per_core=a['bytes'],source_period=a['period'],unicast_cycles=a['cycles'],multicast_cycles=b['cycles'],speedup=a['cycles']/b['cycles'],external_bytes_unicast=a['external_bytes'],external_bytes_multicast=b['external_bytes']))
for name,data in [('measurements.csv',rows),('effects.csv',effects)]:
    with (O/name).open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(data[0]));writer.writeheader();writer.writerows(data)
(O/'provenance.json').write_text(json.dumps(dict(files={p:hashlib.sha256((R/p).read_bytes()).hexdigest() for p in sources},scope='Measured fanout and sixteen depth-4 RX FIFOs; testbench traffic source and always-ready consumers. Not SRAM copy, DRAM model, or whole accelerator latency.'),indent=2))
(O/'REPORT_KO.txt').write_text('''멀티캐스트 통신 블록 비교
현재 메인 RTL의 fanout(depth4)와16개 수신 FIFO(depth4)를 사용했다. RTL 변경 없음.
개별 전송은 목적지 mask를 한 코어씩 지정하여 같은 payload를16번 보낸다.
멀티캐스트는 mask=16개 전체로 같은 payload를 한 번 보낸다.
두 경우 모두 동일 fanout 경로를 사용하여 전달 방식만 비교한다.
입력64-bit word 제공 기회는1사이클당1회 또는4사이클당1회, 수신 소비자는 항상 ready.
512B/4KiB/16KiB를 각 코어가 받으며 모든 word의 내용/순서/중복 여부를 검증한다.
시작은 첫 전송 제공, 끝은 마지막 코어 수신 FIFO의 소비 완료 및 전체 drain이다.
전송 시뮬레이션12회 통과. 결과는effects.csv 참조.
이 실험은 외부 전송원의 데이터가 fanout 입력까지 도착했다고 가정한다.
SRAM 읽기, activation_feed 타일 생성, 실제 DRAM 지연, MAC과 통신 중첩은 포함하지 않는다.
따라서 SRAM간 복사 또는 가속기 전체의16배 가속 증거로 사용하면 안 된다.
실제 메인 경로는 source SRAM -> activation_feed -> fanout -> 수신 FIFO -> compute이다.
''',encoding='utf-8')
print(effects)
