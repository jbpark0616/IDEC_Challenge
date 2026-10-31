IDEC2026 지정주제 Verilog 산출물

실행 환경: AMD Vivado 2024.1
ZIP 전체를 압축 해제하고 폴더 간 상대 경로를 유지하십시오.

1. RTL 시뮬레이션
   03_rtl_project/winograd_cnn_rtl.xpr 열기
   Run Simulation → Run Behavioral Simulation → Run All

2. 합성 netlist 기능 시뮬레이션
   05_gate_project/winograd_cnn_gate.xpr 열기
   Run Simulation → Run Behavioral Simulation → Run All
   ASAP7 셀 모델과 합성 netlist를 사용한 기능 시뮬레이션입니다.

두 프로젝트의 simulation top은 winograd_chip_1000_tb이며 기본 1000장을 실행합니다.
완료 시 Tcl Console의 Correct, Accuracy, RTL mismatches 및 PASS/FAIL을 확인하십시오.
정수 기준 모델과의 일치 목표: RTL mismatches: 0
데이터셋의 정답 기준: Correct: 970/1000, Accuracy: 97.0%

짧은 게이트 점검이 필요한 경우에만 Simulation Settings의 Verilog define에
SUBMISSION_GATE_20을 추가하면 20장으로 실행됩니다. 기본 제출 설정에는 없습니다.

02_sources: RTL, testbench, 입력·정답 데이터, 표준셀 시뮬레이션 모델
04_synthesis: 합성 netlist, SDC 및 결과 리포트
면적: 04_synthesis/reports/synth_stat.txt (7769.025900 um^2)
결과보고서는 별도로 제출합니다.