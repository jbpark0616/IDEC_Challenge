# Conv1 dead-tile pruning

> **결정: 미채택.** 25 cycle 단축보다 면적 증가와 Fmax 저하, 제어 복잡도
> 증가의 손해가 크다고 판단하여 최종 RTL에서는 원복했다. 아래 결과는 설계
> 탐색 과정과 미채택 근거로 보존한다.

원복 후 1,000장 재검증은 mismatch 0, 정확도 97.0%, 입력 backpressure 0,
post-input latency 433 cycle로 기존 동작을 복원했다. 적용 당시의 Codex 세션에
보존된 원본 patch를 역적용하여 소스 구조까지 복원했다. 재합성 결과는 7,939.82
um^2, 1,056.86 MHz, 34.0 mW이며 1 GHz 목표를 유지한다. 이전에 보관한 동일
RTL 구조의 best mapping 결과(7,880.81 um^2, 1,072.98 MHz)와는 0.75%의 area
mapping 차이가 남으므로 비교 기준 자료로 별도 보존한다.

## 목적

Conv1 sliding-window generator는 28x28 입력으로부터 13x13개의 Winograd
타일을 생성한다. 그러나 현재 네트워크의 Conv2 입력은 Conv1 결과 중 좌상단
12x12 feature map만 사용한다. 따라서 마지막 tile row 또는 마지막 tile column에
속하는 25개 타일은 계산해도 이후 계층에서 읽히지 않는다.

이번 최적화는 입력 스트림과 window generator는 그대로 유지하면서, 다음 조건의
타일만 FIFO와 공유 Winograd core로 전달한다.

```text
tile_row != 12 && tile_col != 12
```

제외된 경계 타일은 즉시 acknowledge하므로 대회 인터페이스의 고정 속도 28x28
pixel stream은 멈추지 않는다. Conv1 계산 완료와 전체 입력 stream 완료를 별도로
기록하여, 유효 타일 계산이 먼저 끝나더라도 Conv2가 조기에 시작하지 않게 했다.

## 기능 검증

동일한 1,000장 회귀 시험에서 결과가 보존되었다.

| 항목 | 최적화 전 | dead-tile pruning | 변화 |
|---|---:|---:|---:|
| 생성 타일 | 169 | 169 | 0 |
| 코어 실행 타일 | 169 | 144 | -25 (-14.79%) |
| RTL/golden mismatch | 0 | 0 | 0 |
| 정확도 | 97.0% | 97.0% | 0.0%p |
| 입력 backpressure | 0 cycle | 0 cycle | 0 |
| V-replay backpressure | 286 cycle/image | 245 cycle/image | -14.34% |
| 입력 종료 후 latency | 433 cycle | 408 cycle | -25 (-5.77%) |
| 전체 latency | 약 1,220 cycle | 약 1,195 cycle | -25 (-2.05%) |

제거된 연산량은 Conv1의 25 tiles x 3 output channels x 16 Winograd-domain
products, 즉 1,200개의 element-wise product에 해당한다. 또한 쓰이지 않는
75개의 channel output에 대한 output transform과 postprocess도 제거된다.

## 합성 결과

OpenSTA/OpenROAD의 동일한 ASAP7 합성 흐름으로 비교했다.

| 항목 | 최적화 전 | dead-tile pruning | 변화 |
|---|---:|---:|---:|
| Flip-flop | 8,255 | 8,259 | +4 (+0.05%) |
| Cell area | 7,880.81 um^2 | 7,938.49 um^2 | +0.73% |
| Sequential area | 2,538.73 um^2 | 2,540.24 um^2 | +0.06% |
| Fmax | 1,072.98 MHz | 1,045.66 MHz | -2.55% |
| Vectorless power | 34.1 mW | 34.0 mW | -0.1 mW |

추가된 stream-completion 상태와 tile filter 때문에 cell area가 소폭 증가했지만,
목표인 1 GHz는 유지한다. Vectorless power는 실제 타일 활동 감소를 충분히
반영하지 않으므로, 25개 타일의 switching 및 에너지 절감은 추후 SAIF/VCD 기반
power analysis로 확인해야 한다.

## 결론

이 최적화는 공유 코어의 Conv1 작업량을 14.79% 줄였지만 전체 inference 개선은
2.05%에 그쳤다. 반면 면적은 0.73% 증가하고 Fmax는 2.55% 감소했으며 제어 상태도
추가됐다. Vectorless power에서도 유의미한 개선이 확인되지 않았으므로 최종
설계에는 채택하지 않는다. 이는 국소 연산량 감소가 반드시 전체 PPA 개선으로
이어지지 않는다는 negative design-space exploration 결과로 사용한다.

원시 결과는 다음 파일에 보관한다.

- `dead_tile_pruning_comparison.csv`
- `logs/dead_tile_pruning_xsim.log`
- `data/chip_dead_tile_pruning_post_synthesis.rpt`
- `data/chip_dead_tile_pruning_synth_stat.txt`
- `rollback/rollback_xsim.log`
- `rollback/chip_rollback_post_synthesis.rpt`
- `rollback/chip_rollback_synth_stat.txt`
