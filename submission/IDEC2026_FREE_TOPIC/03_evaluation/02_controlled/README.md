# 통제 실험: 주 평가

results/REPORT_KO.md와 comparison.csv가 주 결과이며, 01_vgg_layers은 실제 VGG 적용 사례이다.

Linux/WSL에서 Icarus Verilog 12, Python3, OpenROAD/ORFS를 설치하고 ORFS_ROOT를 설정한 뒤 `python3 reproduce.py`를 실행한다. 공통 코어/셀 모델은 03 폴더의 assets를 사용한다. 각 조건의 power.tcl에 Liberty, LEF, 클록, 활동 파형 경로가 기록되어 있다. 원시 VCD는 용량상 제외했으며 재현 실행으로 생성한다.

30조건 모두 독립 정수 출력과 일치해야 하며, 각 OFF/ON의 MAC 행 투입 수도 생성기의 기대값과 검증했다. 기존 공급속도 곡선과 새 결과는 측정 코어/구간이 다를 수 있으므로 새 그래프의 사이클과 에너지는 같은 게이트 실행에서 함께 계산했다.
