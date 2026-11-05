지정주제 레이어별 sparsity-aware 동작 프로파일
===========================================
고유 이미지 100장 x 두 조건. ICG는 모두 ON.
b0_g1 = Winograd + ICG, b1_g1 = Sparsity-Aware Winograd + ICG.
각 조건 정수 기준 모델 불일치 0, 정확도 97/100.
현재 최종본과 b1_g1의 소스 해시 일치; 최종 RTL 무수정.

파일
  per_image.csv: 이미지별 레이어 관측값 400행
  layer_summary.csv: 조건별/레이어별 평균 및 희소성 4행
  layer_reduction.csv: ICG 공통 기준 대비 감소율 2행
  b0_g1.log / b1_g1.log: 원본 시뮬레이션 로그
  rtl_sha256.json: 지정주제 최종본 해시
재현: WSL python3 scripts/report_data/designated_layers.py

지표 정의
  run_cycles: 상위 FSM이 RUN_CONV1(2)/RUN_CONV2(4)에 있는 상승 에지 수.
    해당 레이어 RUN 구간이며 초기 START/FC/argmax 등은 포함하지 않는다.
    Conv2 일부 입력 준비는 Conv1 구간과 겹친다. 순수 연산 latency와 구분한다.
  v_tiles: transform_valid && transform_ready로 V가 publish된 횟수.
  zero_rows/tiles/elements: 실제 transform_v의 44bit 행/176bit 타일/11bit 원소를
    검사한 개수. 매 행 mask와 실제 zero 판정의 일치도 assertion으로 검사한다.
    비율은 원소/행/타일 각각의 총 개수로 나눈다. 재사용 발행 횟수와 구분한다.
  mac_beats: MAC in_valid && in_ready 수락 횟수.
  active_lane_products: 수락 시 conv_row_enable에 켜진 행 수 x 4.
    정확한 표현은 활성 MAC lane 연산 슬롯이다. 실제 트랜지스터 switching 수가 아니다.
    활성 행 내부의 0 원소 및 weight zero도 포함한다.
  nonzero_operand_products: 활성 슬롯 중 V와 U가 모두 nonzero인 곱셈 수.
    두 조건에서 동일함을 검증했다. zero-skipping은 필요한 nonzero 곱셈을 없애지 않는다.
    따라서 active_lane_products 감소를 'nonzero 곱셈 감소'로 표기하면 안 된다.
  bypass_jobs: 전체 reduction 작업의 우회 수락 횟수.
    입력 채널 하나의 zero 타일 수와 다르다. Conv2에서는 다른 채널의 기여가 남을 수 있다.
  output_transforms: output transform 입력 수락 횟수.

서로 겹치지 않는 RUN 구간 분류 (우선순위 순서)
  issue_cycles: MAC 수락
  bypass_cycles: 전체 zero 작업 우회 수락
  no_v_cycles: V replay 출력 valid 없음
  order_blocked_cycles: V가 있으나 필요한 순서 FIFO 공간 없음
  mac_blocked_cycles: 위 항목에 해당하지 않고 MAC ready 없음
  other_cycles: 나머지
각 이미지에서 이 여섯 개 합계 == run_cycles를 검증했다.
no_v는 초기 fill/공급 공백/마무리 drain을 포함하며 외부 입력 stall로 단정할 수 없다.
분류는 MAC 입력 경계의 상태다. issue가 없는 동안에도 이전 연산/후처리는 진행할 수 있다.

결과 (이미지당 평균)
  Conv1: RUN 752.00 -> 751.44 (-0.0745%)
         MAC beats 432.00 -> 211.47 (-51.0486%)
         활성 lane 슬롯 6912.00 -> 2915.64 (-57.8177%)
         zero 행 57.8177%, 채널별 zero 타일 51.0486%
  Conv2: RUN 238.00 -> 162.39 (-31.7689%)
         MAC beats 225.00 -> 121.14 (-46.1600%)
         활성 lane 슬롯 3600.00 -> 1684.92 (-53.1967%)
         zero 행 53.1967%, 채널별 zero 타일 46.1200%
  두 RUN 구간 절감 합계 0.56+75.61=76.17cycles로 전체 지연 절감과 일치.

해석
  Conv1에서 MAC beats가 줄어든 만큼 전체 zero 작업의 우회 수락이 생겨
  issue+bypass는 두 조건 모두 432cycles다. RUN 길이 감소는 매우 작다.
  Conv2에서는 채널 reduction의 압축으로 issue+bypass가 225->128.04cycles로 줄어든다.
  Conv1 정체를 모두 '외부 인터페이스 때문'이라고 단정하지 말고,
  우회도 수락 슬롯을 소비한다는 현재 프로토콜 특성을 함께 설명한다.

피겨 제안
  (a) Conv1/Conv2별 활성 MAC lane 슬롯 감소율: 57.8%, 53.2%
  (b) Conv1/Conv2별 RUN 사이클 감소율: 0.07%, 31.8%
  (c) 필요 시 MAC issue / zero bypass / no-V의 RUN 사이클 누적 막대.
  색상/이름은 기존 피겨와 동일. 측정된 값을 수정하거나 error bar를 임의 생성하지 않는다.
