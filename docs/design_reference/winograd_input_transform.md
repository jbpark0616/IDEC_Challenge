# Winograd Input Transform RTL

작성일: 2026-08-25

상태: **RTL 구현, 단위 시뮬레이션, Vivado/OpenROAD 합성 완료**

## 기능

`winograd_input_transform`은 UINT8 activation 4x4 tile에 대해
`F(2x2,3x3)`의 다음 변환을 수행한다.

```text
V = B^T d B

B^T = [ 1  0 -1  0 ]
      [ 0  1  1  0 ]
      [ 0 -1  1  0 ]
      [ 0  1  0 -1 ]
```

행렬 계수가 `0`, `1`, `-1`뿐이므로 multiplier 없이 add/sub만 사용한다.

## 파이프라인과 비트폭

```text
UINT8 4x4 tile
    |
T0: B^T*d          signed 10-bit x16
    |
T1: temporary*B    signed 11-bit x16
    |
V FIFO / MAC input 176-bit
```

- latency: stall이 없을 때 2 cycles
- throughput: pipeline 충전 후 1 tile/cycle
- backpressure: `in_valid/in_ready`, `out_valid/out_ready`
- packing: row-major LSB-first
- clipping/rounding: 없음

UINT8 입력의 이론적 transform 범위는 INT11에 들어가므로 Python golden의
`B^T d B` 결과와 bit-exact하다.

## 파일과 실행

- RTL: `verilog/winograd_input_transform.v`
- testbench: `verification/winograd_input_transform_tb.v`
- simulation: `make sim-transform`
- Vivado: `make synth SYNTH_TOP=winograd_input_transform`
- OpenROAD: `make synth-asic ASIC_TOP=winograd_input_transform`

테스트는 zero tile, UINT8 극값, row-major packing, random 100 tiles,
연속 3-tile burst, output backpressure를 검사한다.

## ASAP7 post-synthesis

| 항목 | 결과 |
|---|---:|
| Cell area | 387.988 um^2 |
| Sequential area | 120.168 um^2 (30.97%) |
| 400 ps 목표 WNS | 0.00 ps |
| 추정 최소 period | 249.34 ps |
| 추정 Fmax | 4,010.55 MHz |
| Vectorless total power | 5.29 mW |

이는 transform 단독 post-synthesis 수치다. 최종 평가는 activation loader,
V FIFO, MAC과 통합한 core top에서 다시 수행한다.
