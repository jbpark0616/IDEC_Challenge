# VGG Conv1 / Conv2 추가 측정

최종 보고서 이후 동일한 CIFAR-10 이미지의 Conv1과 Conv2를 추가 측정한 기록이다.
기존 보고서의 Conv8·9·12·13 예시와 혼동하지 않도록 별도로 보존한다.
측정 범위는 계산 코어 하나와 U/V SRAM 8개이며, ICG를 유지한 같은 넷리스트에서 runtime sparsity OFF/ON을 비교했다.
클록 주기는 1,430 ps, 출력 채널은 각 레이어의 첫 4개이다.

- `results/summary.csv`: Conv1(case 12), Conv2(case 13)의 OFF/ON 4개 결과
- `results/case*/`: 정수 기준값 대조 PASS 로그, 전력·타이밍·활동도 리포트, 측정 조건
- `assets/`: 실제 측정 넷리스트, TB와 입력 벡터
- `SHA256.json`: 보존 파일의 해시

각 측정의 `energy_nj = power_w × duration_ps / 1000`이다.
Conv1은 두 모드의 측정 시간이 같았고, Conv2는 sparsity ON에서 측정 시간이 감소했다.
원본 로그의 일부 내부 카운터는 게이트 계측에서 제거된 신호의 0 placeholder이므로 측정값으로 해석하지 않는다.
대용량 VCD는 보존하지 않으며, 벡터로 다시 생성한다. 과거 `power.tcl`과 `tb_measured.sv`에는 당시 경로가 남아 있다.

파일 무결성 확인:

```sh
python3 docs/experiment_results/free_topic/vgg_conv1_conv2_ppa/reproduce.py --check
```

Linux/WSL에서 Icarus Verilog와 제출 패키지의 OpenROAD/ORFS 환경을 사용하여 재측정:

```sh
export ORFS_ROOT=/path/to/OpenROAD-flow-scripts
python3 docs/experiment_results/free_topic/vgg_conv1_conv2_ppa/reproduce.py --cases 12 13
```

`tb_template.sv`의 경로는 실행 폴더에 맞춰 치환된다. 새 결과는 `reproduced_results/`에 저장하며 원본 측정값은 덮어쓰지 않는다.
