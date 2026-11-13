from pathlib import Path
import shutil,json,hashlib,subprocess,sys
R=Path(__file__).resolve().parents[2];ROOT=R.parent;D=ROOT/'submission/IDEC2026_FREE_TOPIC'
E=R/'evidence/extra_vgg_ppa';W=R/'build/extra_vgg_ppa';P=D/'05_vgg_additional_examples';P.mkdir(exist_ok=True)
assert all((E/f'case{c}_sparse{s}/measurement.json').exists() for c in [12,13] for s in [0,1])
shutil.copytree(E,P/'results',dirs_exist_ok=True,ignore=shutil.ignore_patterns('*.vcd.gz','*.lock'))
shutil.copytree(W/'vectors',P/'vectors',dirs_exist_ok=True)
(P/'tb_template.sv').write_text((W/'tb.sv').read_text().replace(str(W/'vectors'),'@VECTORS@'))
shutil.copyfile(Path(__file__).with_name('run.py'),P/'run.py')
s=(D/'03_technique_ppa_comparison/reproduce.py').read_text()
s=s.replace("A=D/'assets'","A=D.parent/'03_technique_ppa_comparison/assets'").replace("A/'vectors'","D/'vectors'").replace("A/'tb_template.sv'","D/'tb_template.sv'")
(P/'reproduce.py').write_text(s)
(P/'README.md').write_text('# 실제 VGG 추가 사례\n\nConv8(case12): 입력 [1,4,4,256], Conv12(case13): 입력 [1,2,2,512]. 같은 CIFAR-10 test image 0의 저장된 중간 activation과 학습된 가중치를 사용하며 각 코어 출력 4채널만 측정한다. 초기 U 적재 제외, 가중치 상주, ICG 공통 유지, sparse OFF/ON 비교이다.\n\nLinux/WSL, Icarus Verilog 12 및 OpenROAD/ORFS 환경에서 ORFS_ROOT를 설정하고 `python3 reproduce.py --cases 12 13`을 실행한다. 공통 코어와 셀 모델은 03 폴더에서 재사용한다.\n')
A=R/'evidence/area_static';P=D/'06_area_ablation';P.mkdir(exist_ok=True)
assert (A/'VALIDATION.txt').exists()
shutil.copytree(A,P/'results',dirs_exist_ok=True,ignore=shutil.ignore_patterns('original.json','net.json','sim.vvp','tb.sv','extra.v'))
(P/'assets').mkdir(exist_ok=True)
shutil.copyfile(R/'build/area_ablation_v2/std.lib',P/'assets/std.lib')
src=Path(__file__).with_name('area_static.py').read_text()
src=src.replace("R=Path(__file__).resolve().parents[2];O=R/'evidence/area_static'", "D=Path(__file__).resolve().parent;R=D.parent/'01_project';O=D/'reproduced_results'")
src=src.replace("W=R/'build/area_ablation_v2'", "W=D/'assets'")
src=src.replace("R.parent/'docs/designated_final/asap7_rvt_ff_cells.json'", "D.parent/'03_technique_ppa_comparison/assets/cell_catalog.json'")
src=src.replace("R/'build/layer_ppa/core.v'", "D.parent/'03_technique_ppa_comparison/assets/core.v'")
src=src.replace("ys=(R/'evidence/area_ablation_v2/runtime/run.ys').read_text().split('select -module')[0]", "ys=f\"read_liberty -lib {W/'std.lib'}\\nread_liberty -lib {R/'third_party/asap7_sram/generated/LIB/srambank_256x4x64_6t122.lib'}\\nread_verilog {D.parent/'03_technique_ppa_comparison/assets/core.v'}\\nhierarchy -check -top ppa_core\\n\"")
(P/'reproduce.py').write_text(src)
(P/'README.md').write_text('# Sparsity 제어 면적 비교\n\n최종 계산 코어의 셀 매핑을 유지하고 sparse_enable을 0으로 고정한 비교본을 생성했다. 상수 전파 및 사용되지 않는 논리만 제거하며 ABC 재매핑은 하지 않는다. 커맨드 sparse 래치는 명령 수락 시 0을 샘플하며, QN=1 상태에서 D=0이 유지되는 불변성을 스크립트에서 확인한다. 두 구현의 통제 50% zero-row 입력 출력이 독립 정수 기준과 일치했다. 표본 회귀 검증이며 formal equivalence는 아니다.\n\nSRAM 8개 포함: 35,958.28950 vs 35,752.34700 µm². 추가 면적 205.94250 µm², 비교본 대비 0.5760%. SRAM 제외 기준 1.2205%. ICG는 양쪽에 유지하므로 ICG 자체의 면적 비용을 나타내지 않는다. 고정 셀 매핑의 기능 제거 비교이며 서로 독립적인 전체 RTL 재합성 결과가 아니다. 전력 비교(03/04/05)는 원래 동일 코어의 OFF/ON을 사용한다.\n\nWSL/Linux에서 `python3 reproduce.py`로 재현한다. Yosys 설치 위치가 다르면 스크립트의 Y 경로를 조정한다. 사용 Liberty, 비교 넷리스트, 검사 로그와 면적 JSON을 포함했다.\n')
F=ROOT/'docs/report_assets/free_topic/figures'
for ext in ['svg','pdf','png','csv']:shutil.copyfile(F/f'vgg_controlled_cycle_energy_extended.{ext}',D/'04_controlled_ppa/results'/f'vgg_controlled_cycle_energy_extended.{ext}')
readme=D/'README.md';s=readme.read_text();note='\n## 추가 평가\n04_controlled_ppa에 1/4/8 cycles per word의 30조건을 포함했다. 05_vgg_additional_examples에는 Conv8/Conv12 실제 데이터 사례, 06_area_ablation에는 기존 셀 매핑을 유지한 sparsity 제어 면적 비교를 포함했다. 기존 VGG Conv9/Conv13 사례는 03 폴더에 있다.\n'
if '## 추가 평가' not in s:readme.write_text(s+note)
files=[dict(path=p.relative_to(D).as_posix(),sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in sorted(D.rglob('*')) if p.is_file() and p!=D/'SHA256.json']
(D/'SHA256.json').write_text(json.dumps(files,indent=2))
subprocess.run([sys.executable,str(ROOT/'scripts/validate_free_topic_package.py')],check=True)
print('PASS packaged extended measurements and area ablation')
