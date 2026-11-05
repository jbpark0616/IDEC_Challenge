# Winograd Output Transform RTL

작성일: 2026-08-25

상태: **RTL 구현, 단위 시뮬레이션, Vivado/OpenROAD 합성 완료**

## 기능

`winograd_output_transform`은 channel reduction이 끝난 INT18 M 4x4 tile에
`F(2x2,3x3)`의 output transform을 적용해 INT18 Y 2x2 tile을 만든다.

```text
Y = A^T M A
A^T = [1  1  1  0]
      [0  1 -1 -1]
```

## Python golden과 saturation 계약

`training/integer_inference.py`와 동일하게 모든 add/sub 직후 INT18 saturation을
적용한다. 마지막 결과만 clamp하는 방식과는 극값에서 결과가 다르다.

```text
top    = sat18(sat18(m0 + m1) + m2)
bottom = sat18(sat18(m1 - m2) - m3)
```

왼쪽 `A^T*M`과 오른쪽 `*A`에서 같은 순서를 사용한다.

## 파이프라인

```text
M 4x4, 16 x INT18
    |
O0: A^T*M, 2x4       8 x INT18 register
    |
O1: temporary*A, 2x2 4 x INT18 register
    |
Y 2x2
```

- latency: stall이 없을 때 2 cycles
- throughput: pipeline 충전 후 1 tile/cycle
- handshake: `in_valid/in_ready`, `out_valid/out_ready`
- packing: row-major LSB-first
- datapath register는 reset하지 않고 valid register만 reset

## Post-process 경계

이 블록은 bias, ReLU, max-pooling, requantization을 포함하지 않는다.

```text
Output Transform
  -> bias add + INT18 saturation
  -> ReLU
  -> max-pooling
  -> UINT8 requantization
  -> activation bank
```

Conv2의 홀수 출력 경계에서 생기는 무효 위치의 crop도 tile metadata를 가진
상위 controller/post-process가 담당한다.

## 파일과 실행

- RTL: `verilog/winograd_output_transform.v`
- testbench: `verification/winograd_output_transform_tb.v`
- simulation: `make sim-output-transform`
- Vivado: `make synth SYNTH_TOP=winograd_output_transform`
- OpenROAD: `make synth-asic ASIC_TOP=winograd_output_transform`

테스트는 zero, INT18 극값 saturation, 비대칭 packing, random 100 tiles,
연속 3-tile burst, output backpressure를 검사한다.

## ASAP7 post-synthesis

| 항목 | 결과 |
|---|---:|
| Cell area | 741.335 um^2 |
| Sequential area | 63.744 um^2 (8.60%) |
| 400 ps 목표 WNS | -370.28 ps |
| 추정 최소 period | 770.28 ps |
| 추정 Fmax | 1,298.23 MHz |
| Vectorless total power | 32.4 mW |

두 saturating adder가 한 stage에 직렬로 연결되어 input transform보다 critical
path가 길다. 전체 core 합성에서 이 경로가 실제 병목이 될 때만 각 saturation
단계를 분리한 4-stage pipeline을 검토한다.
