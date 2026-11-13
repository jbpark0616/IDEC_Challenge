"""Keep a visible status file and finalize the package only after paired PASS."""
from pathlib import Path
import csv,json,hashlib,subprocess,sys,time
R=Path(__file__).resolve().parents[2];ROOT=R.parent;O=R/'evidence/layer_ppa';D=ROOT/'submission/IDEC2026_FREE_TOPIC'
while True:
    log=(O/'resume.log').read_text() if (O/'resume.log').exists() else ''
    complete=[]
    for case in [10,11]:
        for sparse in [0,1]:
            p=O/f'case{case}_sparse{sparse}'/'measurement.json'
            if p.exists():complete.append(f'case{case}/sparse{sparse}')
    active=[l for l in log.splitlines() if l.startswith('START ')]
    status=f'Completed PPA conditions: {len(complete)}/4\nCompleted: {", ".join(complete)}\nLast started: {active[-1] if active else "none"}\n'
    (O/'PROGRESS.txt').write_text(status)
    if 'Traceback (most recent call last)' in log:
        (O/'PROGRESS.txt').write_text(status+'FAILED: inspect resume.log; package not complete.\n');sys.exit(1)
    if 'PASS all requested layer-mode pairs' in log:break
    time.sleep(10)
assert len(complete)==4
for script in ['summarize.py','package.py']:
    subprocess.run([sys.executable,str(Path(__file__).parent/script)],check=True)
(D/'03_technique_ppa_comparison/STATUS.txt').write_text('COMPLETE: Conv9/Conv13, sparse OFF/ON, all four conditions passed output checks and activity annotation audit.\nSee results/REPORT_KO.md and comparison.csv for scope and measurements.\n')
(D/'README_KO.txt').write_text('최신 설명: README.md\n레이어별 비교: 03_technique_ppa_comparison/results/REPORT_KO.md\n실행 방법: 03_technique_ppa_comparison/RUN.md\n전체 모델 전력 측정이 아닌 동일 계산 코어의 실제 레이어 부분 작업 비교입니다.\n')
(O/'PROGRESS.txt').write_text(status+'COMPLETE: comparison and submission package refreshed.\n')
# Include nested manifests but do not hash the root manifest into itself.
files=[p for p in D.rglob('*') if p.is_file() and p!=D/'SHA256.json']
records=[{'path':str(p.relative_to(D)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in files]
(D/'SHA256.json').write_text(json.dumps(records,indent=2))
print('PASS final layer PPA package',D,flush=True)
