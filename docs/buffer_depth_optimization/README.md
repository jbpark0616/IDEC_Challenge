# Pipeline Buffer Depth Optimization

## Final configuration

- Conv1 tile FIFO depth: 2
- V replay group depth: 2
- M FIFO depth: 1

M FIFO라는 모듈 이름은 유지한다. Depth 1에서도 하나의 결과를 보존하고 MAC과 output transform 사이의 valid/ready 경계를 형성하는 1-entry FIFO로 동작한다.

## RTL sweep

| Conv1 tile | V replay | M FIFO | RTL mismatch | Accuracy | Input backpressure | Post-input cycles | 결과 |
|---:|---:|---:|---:|---:|---:|---:|---|
| 2 | 2 | 2 | 0 | 97% | 0 | 484 | 기준 |
| 2 | 2 | 1 | 0 | 97% | 0 | 484 | 선택 |
| 2 | 1 | 2 | 36,910 | 9% | 36,000 | 588 | 실패 |

M FIFO는 기준 설계에서도 최대 occupancy가 1이고 backpressure가 0 cycle이었다. Depth 1 회귀에서도 기능, 정확도, 입력 흐름 및 latency가 모두 동일하므로 두 번째 290-bit entry는 불필요하다.

V replay buffer는 Depth 2에서 실제 최대 occupancy 2를 사용한다. Depth 1에서는 transform 결과를 대기시킬 공간이 부족하여 Conv1 tile FIFO를 거쳐 고정 속도 외부 입력까지 backpressure가 전파된다. 대회 입력 인터페이스는 ready를 관찰하지 않으므로 영상당 36 pixel이 유실되고 결과가 붕괴한다. 따라서 V replay depth는 2를 유지한다.

V replay Depth 1과 M FIFO Depth 1의 결합 조합은 실행하지 않았다. V replay Depth 1이 독립적으로 외부 입력 계약을 위반하므로 M FIFO 설정과 관계없이 채택할 수 없기 때문이다.

## Post-synthesis comparison

| 항목 | M FIFO Depth 2 | M FIFO Depth 1 | 변화 |
|---|---:|---:|---:|
| Total cell area | 9,488.42 µm² | 9,366.15 µm² | -1.29% |
| Sequential area | 3,264.14 µm² | 3,176.69 µm² | -2.68% |
| Flip-flop count | 10,752 | 10,453 | -299 (-2.78%) |
| Estimated Fmax | 1,074.84 MHz | 1,092.26 MHz | +1.62% |
| Vectorless power | 43.7 mW | 42.8 mW | -2.06% |

M FIFO payload에서는 290 bit가 제거되지만 합성 과정에서 pointer와 count 제어도 단순화되어 실제 sequential cell은 총 299개 감소했다.

전력은 workload switching activity가 반영되지 않은 post-synthesis vectorless 추정값이다. Fmax 역시 배선 전 단계의 논리 합성 추정치이므로 절대 성능이 아닌 동일 flow의 상대 비교로 사용한다.

## Evidence

- `buffer_depth_sweep.svg`: 조합별 저장량, backpressure, latency 및 정확도
- `m_fifo_ppa.svg`: M FIFO Depth 2/1의 post-synthesis PPA 비교
- `generate_buffer_depth_figures.js`: 논문형 SVG 재생성 스크립트
- `depth_sweep.csv`: RTL 조합별 결과
- `ppa_comparison.csv`: 합성 PPA 비교
- `logs/depth_t2_v2_m2_xsim.log`: 기준 1000장 회귀
- `logs/depth_t2_v2_m1_xsim.log`: 선택 조합 1000장 회귀
- `logs/depth_t2_v1_m2_xsim.log`: V replay Depth 1 실패 회귀
- `data/chip_mfifo_depth*_post_synthesis.rpt`: OpenROAD 원본 보고서
- `data/chip_mfifo_depth*_synth_stat.txt`: 합성 cell 통계
