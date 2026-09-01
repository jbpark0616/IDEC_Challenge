# Activation Storage Lifetime Optimization

## 최종 구조

Conv1과 Conv2 사이의 activation 저장을 모델의 고정된 데이터 lifetime에 맞춰 최적화했다. 최종 RTL은 별도의 범용 arbitration 없이 FSM 단계에 따라 scratchpad 접근 주체가 하나로 고정된다.

1. Conv2가 참조하지 않는 Conv1 결과의 마지막 행과 열을 제거한다.
2. 첫 4×4 Conv2 window를 구성하는 40개 vector를 window generator에 직접 선적재한다.
3. 나머지 104개 vector만 FF 기반 sequential frame buffer에 저장한다.
4. Conv2가 이미 소비한 frame buffer의 주소 0~24를 Conv2 출력 저장에 재사용한다.
5. 각 주소에는 세 채널을 하나의 24-bit word로 묶고, FC 단계에서 channel-major 순서로 byte를 선택한다.

결과적으로 별도의 75×8-bit linear feature buffer는 제거되었고, 하나의 104×24-bit storage가 Conv1→Conv2 activation과 Conv2→FC feature를 시간 다중화하여 보관한다.

## 최적화 근거

### 13×13에서 12×12 crop

Conv2는 13×13 Conv1 출력에 3×3 valid convolution을 적용한 후 2×2 max pooling을 수행한다. 최종 5×5 pooled output은 Conv1 activation의 행과 열 0~11만 참조한다. 따라서 마지막 행과 마지막 열에 해당하는 25개 위치는 Conv2 결과에 영향을 주지 않는다.

### 40-vector generator prefill

12-wide raster stream에서 첫 4×4 window는 `3×12+4=40`개 vector를 받으면 완성된다. 이 40개는 Conv1 실행 중 Conv2 window generator의 line/horizontal register에 직접 적재한다. 하나의 Winograd core를 공유하므로 완성된 첫 Conv2 tile은 generator 출력에서 대기하며, 나머지 `144-40=104`개만 frame buffer에 저장한다.

선적재 구간은 첫 타일이 완성되기 전이라 generator input이 항상 비어 있다. 이 고정 스케줄을 사용하여 generator ready를 core ready로 되돌리는 조합 경로를 만들지 않았다. 초기 구현에서 발견한 ready 조합 루프는 제거한 뒤 OpenROAD 합성을 다시 수행했다.

### consumed-region reuse

lifetime trace에서 첫 Conv2 결과를 frame 주소 0에 덮어쓸 때 sequential read pointer는 이미 6이었다. 이후 25개 결과에서도 결과 write address가 다음 read address보다 항상 작아, 아직 소비되지 않은 activation을 덮어쓰지 않는다.

Conv2 결과는 공간 위치마다 채널 0, 1, 2를 24-bit word로 묶어 주소 0~24에 기록한다. STREAM_FEATURES와 FC 단계에서는 word address와 byte lane counter만 사용하여 기존 channel-major 순서를 복원한다.

## RTL 및 정확도 검증

| 단계 | 중간 저장량 | RTL mismatch | 정확도 | 입력 backpressure | Post-input latency |
|---|---:|---:|---:|---:|---:|
| 169-entry 기준 | 4,656 bit | 0 | 97.0% | 0 cycle | 484 cycle |
| 12×12 crop | 4,056 bit | 0 | 97.0% | 0 cycle | 473 cycle |
| 40-vector prefill | 3,096 bit | 0 | 97.0% | 0 cycle | 433 cycle |
| consumed-region reuse | 2,496 bit | 0 | 97.0% | 0 cycle | 433 cycle |

각 채택 단계는 competition dataset 1,000장에 대해 Python integer model과 RTL decision을 비교했다. 최종 구조까지 mismatch 0, 정확도 97.0%, 입력 backpressure 0을 유지했다.

기준 대비 전용 inter-layer storage는 4,656 bit에서 2,496 bit로 46.39% 감소했고, post-input latency는 51 cycle(10.54%) 감소했다.

## Post-synthesis PPA

동일한 ASAP7 OpenROAD post-synthesis flow를 사용했다.

| 단계 | FF | Total cell area | Sequential area | Fmax | Vectorless power |
|---|---:|---:|---:|---:|---:|
| 169-entry 기준 | 10,453 | 9,366.15 µm² | 3,176.69 µm² | 1,092.26 MHz | 42.8 mW |
| 12×12 crop | 9,782 | 8,872.94 µm² | 2,981.64 µm² | 1,061.18 MHz | 40.3 mW |
| 40-vector prefill | 8,835 | 8,233.22 µm² | 2,706.11 µm² | 1,062.60 MHz | 36.5 mW |
| consumed-region reuse | 8,255 | 7,880.81 µm² | 2,538.73 µm² | 1,072.98 MHz | 34.1 mW |

최종 구조는 기준 대비 FF 21.03%, total cell area 15.86%, sequential area 20.08%, vectorless power 20.33%를 줄였다. Fmax는 1.77% 감소했지만 1 GHz 목표를 유지한다.

전력은 workload switching activity가 없는 vectorless 추정값이며, Fmax와 면적도 배선 전 post-synthesis 상대 비교값이다.

## 보고서용 핵심 서술

> 계층별 activation lifetime과 실제 소비 영역을 분석하여 FF 기반 scratchpad의 저장 공간을 시간 다중화하였다. Conv2에서 참조되지 않는 경계 activation을 제거하고, 첫 Winograd window를 line buffer에 선적재하여 중간 frame storage를 169 word에서 104 word로 축소하였다. 또한 Conv2가 이미 소비한 저장 영역을 Conv2 출력 및 FC 입력 공간으로 재사용하였다. 접근 주체는 실행 단계별로 정적으로 결정되므로 범용 memory arbitration을 사용하지 않는다.

## Evidence

- `optimization_results.csv`: RTL 및 PPA 단계별 원본 수치
- `activation_storage_optimization.svg`: 저장량·latency 비교
- `activation_storage_ppa.svg`: FF·area·power·Fmax 비교
- `activation_lifetime_trace.csv`: 104-entry 구조의 한 이미지 lifetime trace
- `logs/*_xsim.log`: 1,000장 RTL regression 로그
- `data/*_post_synthesis.rpt`: 단계별 OpenROAD STA/power 보고서
- `data/*_synth_stat.txt`: 단계별 cell/area 통계
- `generate_activation_storage_figures.js`: SVG 재생성 스크립트
