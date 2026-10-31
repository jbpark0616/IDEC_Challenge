"""Additional U-resident real layers; explicitly retain sharded fallback."""
from pathlib import Path
import subprocess,json,hashlib,re,time
R=Path(__file__).resolve().parents[2];O=R/'evidence/feed8_resident_more'
O.mkdir(parents=True,exist_ok=True)
m=json.loads((R/'evidence/report_baseline_700mhz/manifest.json').read_text(encoding='utf-8-sig'))
def check():
 h={f['path']:hashlib.sha256((R/f['path']).read_bytes()).hexdigest() for f in m['files']}
 assert all(h[f['path']].lower()==f['sha256'].lower() for f in m['files']);return h
initial=check();start=time.monotonic();rows=[]
exe=R/'build/feed_hwc8/obj/Vtb_report_layer'
for stage in (1,3):
 for sparse in (0,1):
  p=O/f'conv{stage+1}_sparse{sparse}.log'
  with p.open('w') as f:
   subprocess.run([str(exe),f'+LAYER={stage}','+STREAM_HOST','+RESIDENT_U']+(['+SPARSE'] if sparse else []),cwd=R,stdout=f,stderr=subprocess.STDOUT,check=True,timeout=3600)
  raw=p.read_text();assert 'PASS ISOLATED_LAYER' in raw
  row={'layer':stage+1,'sparse':sparse,'feed_path':'original sharded fallback; HWC8 optimization not active'}
  for line in raw.splitlines():
   d={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)(?=\s|$)',line)}
   if d.get('layer')!=stage:continue
   if line.startswith('PROFILE '):row['profile']=d
   if line.startswith('LAYER_PASS '):row['result']=d
  assert row['result']['resident_u']==1 and check()==initial
  rows.append(row);(O/'results.json').write_text(json.dumps(rows,indent=2))
  print(f'PASS {len(rows)}/4 Conv{stage+1} sparse={sparse} cycles={row["profile"]["cycles"]}',flush=True)
(O/'provenance.json').write_text(json.dumps({'rtl_sha256':initial,'binary_sha256':hashlib.sha256(exe.read_bytes()).hexdigest(),'elapsed_seconds':time.monotonic()-start,'scope':'One real image; Conv2/4 with preceding layer to populate committed sharded activation. Target-layer cycles only. Initial preload excluded. U resident. Original sharded fallback is used by HWC8 wrapper.'},indent=2))
existing=json.loads((R/'evidence/feed8_bypass_audit/results.json').read_text())
allrows=rows+[dict(x,feed_path='HWC8') for x in existing if x['layer'] in (3,5)]
lines=['U 상주 레이어 추가 비교','======================','같은 이미지, 16코어, U8/V8, initial preload 제외, 실행 중 제어/공급 포함.',
'주의: Conv2/4는 분산 activation 저장이라 원본 공급기 fallback. HWC8 개선 효과를 측정한 레이어가 아니다.',
'Conv2/4는 앞 레이어를 먼저 실행해 분산 결과를 생성하며 아래 사이클은 대상 레이어만 포함한다.','']
for layer in (2,3,4,5):
 a,b=[next(r for r in allrows if r['layer']==layer and r['sparse']==s) for s in (0,1)]
 p,q=a['profile'],b['profile']
 lines += [f'Conv{layer}: {a["feed_path"]}',f' cycles {p["cycles"]} -> {q["cycles"]}; reduction={100*(1-q["cycles"]/p["cycles"]):.4f}%',
 f' MAC lanes {p["mac_lanes"]} -> {q["mac_lanes"]}; reduction={100*(1-q["mac_lanes"]/p["mac_lanes"]):.4f}%',
 f' MAC beats {p["mac_beats"]} -> {q["mac_beats"]}; reduction={100*(1-q["mac_beats"]/p["mac_beats"]):.4f}%',
 f' source_reads={a["result"]["source_reads"]} -> {b["result"]["source_reads"]}','']
(O/'REPORT_KO.txt').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('\n'.join(lines),flush=True)
