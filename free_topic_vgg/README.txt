자유주제: Sparsity-Aware Winograd CNN Accelerator
===============================================

현재 기준 설계
--------------
Top: rtl/vgg_sixteen_core_cluster.v
소스 목록: rtl/sources.f — 이 목록 하나로 빌드한다.
16코어 x 16 MAC, 코어당 12개 8-KiB SRAM, 출력 채널 샤딩.
U8/V8 저장, 행별 zero bypass, activation 공유, SRAM A/B 영역 교대.
MAC은 기존 16비트 입력과 48비트 누산기를 유지하고 U/V 스케일을 복원한다.
가중치는 필요한 묶음만 적재하며, 들어가는 레이어는 U 상주 정책을 사용한다.
U 주소 배치는 실제 Cin에 맞춰 밀집 저장하며 상주는 물리 용량으로 판정한다.
출력 16개 상한을 제거했다. 설정·남은 제약은 architecture/U_STORAGE.txt 참고.
기존 지정주제 디렉터리는 별개이며 이번 정리에서 수정하지 않았다.

구조
----
rtl/                     고정본 RTL 28개. 이전 4코어 설계는 제거.
architecture/            확정한 저장/공급 규칙
verification/v8/         V8 정확성, 밀집 저장, bypass, Conv/FC 회귀
verification/u_supply/   현재 코어의 U 공급 및 V16 수치 회귀 fixture
verification/fc/         FC 연결 fixture/벡터 생성기
verification/full_model/ 전체 VGG 기준값 및 16코어 실행 진입점
model_tools/quantization/ 고정 양자화 규칙, calibration, Colab 재현 도구
scripts/                 자산 준비, integer 기준 모델, SRAM 확인 도구
tests/                   소형 부품 테스트. reference/는 검증 oracle만 포함.
third_party/             고정 SRAM 매크로, 원본 라이선스/출처
reference/upstream/      모델 원본 라이선스/출처
evidence/                기존 측정 결과. 현재 V8 측정값과 구분.
data/, weights/          로컬 자산. Git 제외.

재현 (프로젝트 Python 환경 / WSL Verilator)
-----------------------------------------
작업 폴더는 free_topic_vgg/이다. requirements.txt와 tool_versions.txt 참고.
새 checkout에서 데이터와 checkpoint 준비:
  python scripts/prepare_assets.py
  python scripts/build_integer_vgg.py
고정 calibration: model_tools/quantization/artifacts/uv8/v_calibration.json.
검증 벡터 생성:
  python verification/u_supply/generate_vectors.py
  python verification/fc/generate.py
  python verification/full_model/generate.py --v8
  python verification/v8/generate.py
부분 테스트:
  bash verification/v8/run.sh
  bash verification/v8/run_regression.sh
전체 RTL 실행 (긴 실행이므로 부분 검증 후 수동 실행):
  bash verification/full_model/run.sh
U8/V8 + 연속 host 전송 + U 상주 정책. 결과는 verification/full_model/v8_run/.

검증 상태와 제한
---------------
U8/V8 부분 검증 48회, 양자화 16328조합, 실제 VGG Conv9/Conv13 부분 출력,
16코어 Conv->FC1->FC2->FC3->Conv 전환 통과.
U8/V8 full-model 전체 RTL 실행은 아직 미실시.
evidence/full_model_u8_v16/의 전체 통과 기록은 U8/V16 이미지 한 장이다.
Colab U8/V8 정확도 93.94%는 소프트웨어 10000장 결과이며 RTL 검증과 다르다.
최종 16코어 합성은 evidence/timing_writer_pipeline/REPORT_KO.txt 참고.
배치 전 STA 최소 주기 1,377.62ps, 환산 주파수 725.89MHz이며 보고 기준은 700MHz다.
단일 코어의 과거 고정 시점 결과는 evidence/single_core_fixed_window/에 별도 보존했다.
SRAM physical view 관련 제한은
evidence/sram_macro/REPORT_KO.txt 및 third_party/asap7_sram/README.md 참고.
레이어 명령은 테스트벤치가 공급한다. PCIe/DRAM PHY 구현을 포함하지 않는다.

Git
---
벡터, 모델 바이너리, 시뮬레이터 빌드 결과는 제외한다.
모델/SRAM 라이선스와 provenance는 함께 유지한다.
보고서 근거와 최종 합성 netlist는 evidence/에 보존한다. 폐기 실험의 복구 ZIP은 삭제했다.

현재 설계 고정: architecture/DESIGN_FREEZE_20261030.txt
메인 입력 경로: SRAM activation feed -> 고정 4x4 tile reader -> input transform -> V SRAM 재사용.
현재 공급 회귀: verification/fixed_window/ (기존 v8 회귀도 보존).
최종 자료 안내: ../docs/FINAL_DELIVERY.md
