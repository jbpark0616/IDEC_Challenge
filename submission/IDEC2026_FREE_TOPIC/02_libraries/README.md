# 사용 SRAM 모델

`asap7_sram/generated/`에 srambank_256x4x64_6t122(1,024 × 64 bit, 8 KiB)의 모델을 포함한다.

- verilog: 시뮬레이션 동작 모델
- LIB: 면적·타이밍·전력 모델
- LEF: 물리 크기·핀 정보

게이트 시뮬레이션에 사용하는 표준셀 기능 모델은 03_evaluation/01_vgg_layers/assets에 있다. 표준셀 Liberty는 설치한 ORFS ASAP7 라이브러리를 사용한다. SRAM의 라이선스와 출처는 asap7_sram 폴더를 참조한다.
