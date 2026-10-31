# 자유주제 제출 산출물

| 경로 | 내용 |
|---|---|
| 01_project/rtl | 최종 RTL 및 sources.f |
| 01_project/flow | 전체 합성 스크립트와 SDC |
| 01_project/evidence/timing_writer_pipeline | 합성 넷리스트·면적·STA·검증 로그 |
| 02_libraries/asap7_sram/generated | 사용 SRAM의 Verilog·Liberty·LEF |
| 03_evaluation | PPA 비교 결과와 재현에 필요한 코어·모델·벡터·스크립트 |


## 재현

Linux/WSL에 Icarus Verilog, Yosys 및 OpenROAD/ORFS를 설치하고 제출 폴더에서 실행한다. 버전은 TOOL_VERSIONS.txt를 따른다.

```sh
export ORFS_ROOT=/path/to/OpenROAD-flow-scripts
python3 run.py check
python3 run.py controlled    # 30조건 통제 실험
python3 run.py vgg           # Conv9·Conv13
python3 run.py examples      # Conv8·Conv12
python3 run.py area          # sparsity 면적 비교
```

레이어 PPA는 Icarus 게이트 시뮬레이션으로 VCD를 생성한 뒤 OpenROAD로 분석한다. 이 재현에는 Verilator가 필요하지 않다. `python3 run.py synth`는 Yosys/ORFS를 이용한 전체 재합성이며 결과 열람에는 필요하지 않다. 실행 결과는 각 실험의 reproduced_results에 저장된다.

전력 비교의 범위는 계산 코어와 U/V SRAM 8개이며, ICG를 유지한 sparsity OFF/ON 비교이다. 1,430 ps 클록으로 초기 적재 이후 명령 시작부터 완료까지 측정했다. 외부 activation SRAM·multicast는 제외하며, 에너지는 해당 레이어 슬라이스 기준이다. 상세 측정 조건은 각 평가 폴더에 기재하였다.

SHA256.json은 제출 파일 무결성 목록이다. 라이선스와 출처는 라이브러리 및 reference 폴더에 포함하였다.

소스 저장소: https://github.com/jbpark0616/IDEC_Challenge
