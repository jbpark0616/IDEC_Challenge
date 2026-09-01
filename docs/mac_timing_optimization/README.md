# MAC zero-skip timing optimization

## 병목 분석

기존 post-synthesis critical path는 `pipe_weight_zero` 레지스터에서 시작하여
zero-weight 선택 논리와 saturating accumulation을 통과했다. Zero-skip 여부를
Stage 2에서 `pipe_active && !pipe_weight_zero`로 다시 조합하면서 누산기 앞에
반전, AND, MUX가 추가된 것이 원인이었다.

## 채택한 변경

Stage 1에서 다음 조건을 한 번만 계산하여 `pipe_accumulate`로 레지스터링했다.

```text
pipe_accumulate = lane_active && !weight_zero
```

Stage 2는 이 신호로 accumulator update 여부를 직접 선택한다. 곱셈 입력의 operand
isolation과 zero-skip은 유지되며, 파이프라인 단계, handshake, 수치 연산 순서,
latency는 바뀌지 않는다.

변경 후 critical path의 startpoint는 zero-skip 제어 레지스터가 아니라 accumulator
레지스터로 이동했다.

## 결과

| 항목 | 기존 | pipe_accumulate | 변화 |
|---|---:|---:|---:|
| Fmax | 1,056.86 MHz | 1,180.21 MHz | +11.67% |
| Minimum period | 946.20 ps | 847.31 ps | -10.45% |
| 1 GHz timing margin | 53.80 ps | 152.69 ps | +98.89 ps |
| Cell area | 7,939.82 um^2 | 7,953.89 um^2 | +0.18% |
| Flip-flop | 8,255 | 8,261 | +6 |
| Sequential area | 2,538.73 um^2 | 2,540.48 um^2 | +0.07% |
| Vectorless power | 34.0 mW | 34.0 mW | 변화 없음 |
| Post-input latency | 433 cycle | 433 cycle | 변화 없음 |

RTL 1,000장 및 ASAP7 합성 netlist 1,000장 회귀에서 모두 mismatch 0,
정확도 97.0%를 확인했다.

Wide signed comparison을 sign-overflow 검출로 바꾸는 saturating-adder 표현도
검토했다. 면적은 7,744.81 um^2로 감소했지만 Fmax가 1,034.47 MHz로 하락하여
timing 목표와 맞지 않아 미채택했다.

## 결론

이 변경은 기존 zero-skip 의미를 유지하면서 조건 계산을 파이프라인 경계 앞으로
이동한 retiming 최적화다. 면적 증가 0.18%로 Fmax를 11.67% 개선하고 1 GHz
post-synthesis timing margin을 약 2.84배로 확대했으므로 최종 RTL에 채택한다.

## Evidence

- `timing_comparison.csv`
- `data/chip_pipe_accumulate_post_synthesis.rpt`
- `data/chip_pipe_accumulate_synth_stat.txt`
- `logs/pipe_accumulate_rtl_xsim.log`
- `logs/pipe_accumulate_gate_xsim.log`
