# Conv1 Tile FIFO Depth 최적화 자료

그래프 작성 형식은 상위 폴더의 `PUBLICATION_FIGURE_STYLE.md`를 따른다.

## 결론

Conv1 window generator와 Winograd core 사이의 128-bit tile FIFO는 **Depth 2가 최소 안전 깊이**다.

- Depth 1: core stall을 흡수하지 못해 입력 `image_ready`가 영상당 36 cycle 내려간다. 대회 입력은 ready를 보지 않고 계속 전송하므로 픽셀 정렬이 깨지고, 1000장 정확도가 9%까지 붕괴한다.
- Depth 2: 측정된 최대 occupancy 2를 수용하며 입력 backpressure가 발생하지 않는다. 1000장 정확도 97%를 유지한다.
- Depth 4/8: 기능 결과는 Depth 2와 같지만 실제 최대 occupancy는 계속 2이므로 여분 entry가 사용되지 않는다.

기존 Depth 8에서 Depth 2로 줄이면 FIFO data storage가 1024 bit에서 256 bit로 감소한다. 즉, 768 bit와 저장 용량의 75%를 제거하면서 기능 정확도를 유지한다.

## 보고서용 그림

1. `fifo_depth_sweep.svg`
   - Depth 1/2/4/8의 용량, 최대 occupancy, backpressure, 정확도를 한 장에서 비교한다.
   - FIFO 깊이 선정 근거를 설명하는 본문 그림으로 사용한다.
2. `fifo_depth_waveform.svg`
   - 첫 stall이 발생하는 cycle 103~119의 실제 RTL trace를 시각화한다.
   - Depth 1에서는 cycle 109에 `image_ready=0`이 되지만, Depth 2에서는 occupancy가 2까지 증가하면서 입력을 계속 받는 차이를 보여준다.
3. `fifo_depth_ppa.svg`
   - OpenROAD 합성 결과의 면적, FF 수, vectorless power, Fmax를 비교한다.
   - PPA 수치는 서로 동일한 RTL과 flow에서 FIFO depth만 바꾸어 측정했다.

SVG는 벡터 형식이므로 PowerPoint에 직접 삽입해도 확대 시 깨지지 않는다.

## 정량 결과

| 항목 | Depth 8 | Depth 2 | 변화 |
|---|---:|---:|---:|
| FIFO data storage | 1,024 bit | 256 bit | -75.00% |
| Total cell area | 10,091.37 µm² | 9,488.42 µm² | -5.97% |
| Sequential area | 3,488.61 µm² | 3,264.14 µm² | -6.44% |
| Flip-flop count | 11,520 | 10,752 | -768 (-6.67%) |
| Estimated Fmax | 1,098.70 MHz | 1,074.84 MHz | -2.17% |
| Vectorless power | 46.8 mW | 43.7 mW | -6.62% |
| 1000-image accuracy | 97% | 97% | 동일 |

전력은 실제 workload switching activity가 반영되지 않은 post-synthesis vectorless 추정값이다. 합성은 400 ps target constraint로 수행했으며 두 설계 모두 해당 목표에는 timing violation이 있다. 따라서 이 표는 절대 전력이나 sign-off 성능이 아니라 **동일 조건에서의 상대 비교**로 사용해야 한다.

## 보고서에 바로 사용할 수 있는 서술

> Conv1의 tile 생성은 연속적이지 않고 Winograd core 역시 내부 처리 중 일시적으로 입력을 수용하지 못하므로, 두 블록 사이에 elastic FIFO를 배치하였다. FIFO depth sweep 결과 Depth 1에서는 영상당 36 cycle의 backpressure가 외부 입력까지 전파되어 1000장 정확도가 9%로 저하되었다. 반면 Depth 2 이상에서는 최대 occupancy가 2로 제한되었으며 입력 stall 없이 기준 정확도 97%를 유지하였다. 이에 따라 사용되지 않는 여유 공간을 제거하고 FIFO depth를 8에서 2로 축소하였다. 이 최적화는 FIFO 저장 용량을 75% 줄였으며, 동일 합성 조건에서 전체 cell area 5.97%, flip-flop 수 6.67%, vectorless power 6.62%를 감소시켰다. 추정 Fmax는 2.17% 감소했지만 약 1.07 GHz 수준을 유지하였다.

## 재현 자료

- `data/fifo_depth_sweep.csv`: depth sweep 요약
- `data/fifo_depth1_trace.csv`, `data/fifo_depth2_trace.csv`: cycle trace
- `data/fifo_depth_ppa.csv`: PPA 요약
- `data/chip_fifo_depth*_post_synthesis.rpt`: OpenROAD 합성 보고서 원본
- `data/chip_fifo_depth*_synth_stat.txt`: OpenROAD 통계 원본
- `logs/`: XSIM trace 및 regression 로그
- `generate_fifo_depth_figures.js`: SVG 재생성 스크립트

그림 재생성 명령:

```powershell
node docs/figures/fifo_depth_optimization/generate_fifo_depth_figures.js
```
