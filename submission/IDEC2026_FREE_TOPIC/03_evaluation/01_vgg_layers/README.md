# 실제 VGG 레이어의 코어 PPA 비교

최종 16코어 넷리스트에서 계산 코어를 추출하고 모듈 이름을 `ppa_core`로 변경하여 시뮬레이션하였다. 셀 매핑은 동일하게 유지하고 `sparse_enable`만 OFF/ON으로 전환한다. ICG는 두 모드 모두 적용한다.

## 측정 조건

- 대상: 계산 코어와 U/V SRAM 8개. 외부 activation SRAM과 multicast는 제외.
- 입력: CIFAR-10 test image 0의 실제 VGG Conv9(case 10), Conv13(case 11) activation과 학습된 가중치. 각 레이어의 첫 출력 4채널.
- 공급: 가중치 사전 상주, 타일 데이터는 매 사이클 제공, 출력 sink는 항상 ready.
- 구간: 명령 시작부터 완료까지. Reset·초기 적재·완료 후 idle은 제외하고 실행 중 SRAM 및 제어 대기는 포함.
- 클록: 1,430 ps(699.30 MHz). SDF와 배선 기생 성분을 반영하지 않은 게이트 시뮬레이션.
- 전력: 게이트 VCD를 OpenROAD에 주석하고 합성과 동일한 Liberty 조합으로 계산.
- 에너지: 평균 전력 × 측정 시간. 해당 레이어 슬라이스의 에너지이며 전체 이미지나 16코어의 에너지가 아님.

출력 word는 독립 정수 기준값과 비교하였다. 면적과 정적 Fmax는 같은 회로의 실행 모드 비교이므로 동일하다. 주요 결과는 `results/comparison.csv`, 측정 조건과 해시는 `results/manifest.json`에 있다.

## 재현 및 리포트

실행 방법은 `RUN.md`를 따른다. `assets/`에 계산 코어, 게이트 모델 및 입력 벡터를 포함하였다. 각 조건의 `simulation.log`, `power.rpt`, `timing.rpt`, `area.rpt`, `activity.rpt`와 `power.tcl`을 제공한다.

SRAM LEF의 sdel 핀 5개는 Liberty와 기능 모델에 없으므로 매크로 8개에 대한 40핀은 활동 주석 대상에서 제외된다. 그 밖의 모델링된 핀에는 미주석 항목이 없다. SRAM과 표준셀의 nominal PVT는 다르며, 두 비교 모드에는 동일한 공급 라이브러리 조합을 적용하였다.

원시 로그의 `physical_bank_writes`, `transforms`, `V_writes`, `releases`, `weight_wait`, `early`는 이전 테스트벤치의 미사용 필드로 0이 출력된다. 분석에는 출력 검증, `active_cycles`, `mac_row_issues` 및 VCD 측정 구간만 사용하였다.
