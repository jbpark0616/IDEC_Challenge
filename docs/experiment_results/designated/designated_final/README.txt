지정주제 최종본: b1_g1 — sparse bypass + ICG
확정일: 2026-10-29

유일한 지정주제 RTL 경로는 루트 verilog/이다.
기존 matched_ablation/cases/b1_g1/rtl의 14개 파일을 바이트 그대로 승격했다.
rtl_sha256.json으로 동일성을 검증한다. boundary 후속 generator는 채택하지 않았다.
free_topic_vgg/는 별도 자유주제이며 그 안의 파생 RTL은 이 지정주제의 빌드 입력이 아니다.

기존 측정 결과 (이번 정리는 재측정이 아님)
평균 995.83 cycles/image, 최대 1009 cycles/image
cell area 7769.02590 um^2, power 7.868472 mW
energy 7.88755304 nJ/image, ICG 16개
최소 주기 추정 860.07 ps, Fmax 추정 1162.696 MHz
ASAP7 RVT FF corner, 0.77 V, 0 C, 1 GHz
배치배선/CTS 이전 합성 결과와 zero-delay gate VCD 기반 전력이다.
전력 구간은 20개 이미지의 reset/start를 포함한다.
46.51475 TOPS/W는 183 MAC x 2 x 1 GHz를 분자로 사용한 가상 dense 기준이다.
실제 추론 처리량 또는 실측 칩 전력으로 해석하지 않는다.

기존 검증: RTL 1000회 mismatch 0, 970/1000 정답.
입력은 고유 이미지 100개를 10회 반복한 데이터이다.
gate 전력 검증은 별도의 20개 이미지, mismatch 0, 20/20 정답이다.
4조건 비교 원본은 RESULTS.txt와 summary.json에 보존했다.
원본 보고서의 experiments 경로/보존 문구는 측정 당시 기록이다.

재현 (WSL, 저장소 루트에서)
python3 scripts/verify_designated_final.py
bash flow/openroad/run_designated_final.sh
python3 scripts/power_designated_final.py

RTL simulation은 latch 기반 ICG 모델을 사용한다.
ASIC 합성은 OPENROAD_CLKGATE를 정의하고 ORFS ASAP7의 ICG mapping을 사용한다.
Vivado FPGA sanity 합성만 CLOCK_GATING_BYPASS를 사용한다. ASIC PPA용이 아니다.
새 실행 결과는 build/designated_final/에 저장한다.

정리 전 복구본: archive/designated_before_final_20261029.zip (Git 제외)
전체 파일 SHA-256 검증 후 이전 experiments/ 설계를 작업 트리에서 제거한다.
원본 RTL, 과거 netlist/VCD, 실험 스크립트는 압축본에서 복구할 수 있다.
commit/push는 별도 요청 전까지 하지 않는다.

정리 후 확인 (2026-10-29)
루트 verilog/의 14개 파일이 최종 SHA-256과 모두 일치했다.
새 경로에서 1000회 RTL regression PASS, mismatch 0, 970/1000 정답,
input backpressure 0을 재확인했다. MAC/ICG 단위검증도 PASS했다.
이번에는 OpenROAD PPA를 재실행하지 않았다.
