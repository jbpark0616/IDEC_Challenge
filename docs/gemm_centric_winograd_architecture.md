# GEMM 중심 Winograd CNN 가속기 구상

작성일: 2026-08-24

상태: **초기 아키텍처 가설 — 확정 설계가 아님**

이 문서는 Winograd 전용 가속기를 별도로 만드는 대신, 범용 GEMM 엔진을 가속기의 중심에 두고 Winograd를 선택적 전처리·후처리 경로로 사용하는 아이디어를 정리한다. 앞으로 관련 논문과 실제 수치 실험을 통해 타당성을 검증하고 수정한다.

## 1. 핵심 관점

```text
가속기의 본체: GEMM/MAC engine

Winograd의 역할:
convolution을 더 적은 GEMM 연산으로 바꾸는
선택적 transform front-end/back-end
```

Winograd를 하나의 완결된 전용 코어로 보는 대신 다음처럼 해석한다.

```text
                    +----------------------+
입력 ----+--------->| Winograd input       |
         |          | transform: B^T d B   |
         |          +----------+-----------+
         |                     |
         |                     v
         +-- direct path --> shared GEMM engine
                               |
                    +----------v-----------+
                    | Winograd output      |
                    | transform: A^T M A   |
                    +----------+-----------+
                               |
                        bias / ReLU / pool
```

이 구조에서는 일반 multiplier와 accumulator를 GEMM 엔진에 집중하고, Winograd 변환기는 고정계수 add/sub/shift 위주로 구성한다.

## 2. Direct convolution의 GEMM 표현

5x5 convolution에서 출력 하나에 필요한 reduction dimension은 다음과 같다.

```text
입력 채널 C x 필터 5x5 = 25C
```

입력의 sliding window를 행렬로 펼치면 convolution을 다음 GEMM으로 표현할 수 있다.

```text
W: K x 25C
X: 25C x HW
Y: K x HW

Y = W X
```

- `C`: 입력 채널 수
- `K`: 출력 채널 수
- `HW`: 출력 공간 위치 수

2x2 출력 타일 하나를 직접 convolution으로 계산할 때 출력 채널당 필요한 곱셈은 다음과 같다.

```text
4 outputs x 25C = 100C multiplications
```

## 3. Winograd convolution의 GEMM 표현

`F(2x2,5x5)`에서는 입력과 필터를 6x6 Winograd domain으로 변환한다. 변환 좌표 `p` 하나를 고정하면 채널 누적은 다음과 같다.

```text
U_p: K x C
V_p: C x T
M_p: K x T

M_p = U_p V_p
```

- `p`: 6x6 transform coordinate, 총 36개
- `T`: 동시에 묶어 계산하는 출력 타일 수

따라서 Winograd 중앙 연산은 36개의 작은 GEMM으로 볼 수 있다.

```text
p = 0  : U_0  x V_0
p = 1  : U_1  x V_1
...
p = 35 : U_35 x V_35
```

출력 타일 하나와 출력 채널 하나당 총 곱셈은 다음과 같다.

```text
36 coordinates x C = 36C multiplications
```

```text
Direct:   100C
Winograd:  36C
감소:      64%
```

Winograd는 GEMM을 제거하는 것이 아니라 GEMM 엔진이 수행할 총 곱셈을 줄인다.

## 4. 레이어별 실행 경로

### 3x3 또는 5x5 stride-1 convolution

```text
line/tile buffer
-> Winograd input transform
-> GEMM
-> Winograd output transform
-> post-processing
```

### 1x1 convolution

```text
input feature
-> GEMM direct path
-> post-processing
```

1x1 convolution에는 Winograd 변환을 사용할 필요가 거의 없다.

### Fully connected layer

```text
input vector
-> GEMM/MVM direct path
-> output
```

### Winograd가 불리하거나 지원하지 않는 convolution

```text
im2col 또는 direct-convolution data preparation
-> GEMM
-> post-processing
```

큰 stride, dilation, 지원하지 않는 커널 크기, 매우 작은 feature map 등에는 bypass 경로를 사용한다.

## 5. 제안하는 하드웨어 블록

```text
Input stream / scratchpad
          |
          v
Circular line buffer + tile generator
          |
          v
Configurable transform unit
  - INPUT_TRANSFORM mode
  - OUTPUT_TRANSFORM mode
          |
          v
Transformed-tile circular buffer
          |
          v
Shared GEMM/MAC array
  - Winograd GEMM mode
  - direct/1x1 convolution mode
  - FC mode
          |
          v
Accumulator / result circular buffer
          |
          v
Output transform when required
          |
          v
Bias / maxpool / ReLU / requantization
```

### 공유할 가능성이 높은 자원

- 일반 multiplier와 MAC lane
- wide accumulator
- weight/activation scratchpad
- transformed-tile/result circular buffer
- GEMM address generator와 reduction controller
- requantization의 일부 datapath

### 전용으로 둘 가능성이 높은 자원

- circular line buffer와 tile generator
- Winograd 고정계수 add/sub/shift transform unit
- maxpool, ReLU, residual add 등의 후처리 unit

필터 transform `GgG^T`는 소프트웨어에서 미리 수행하여 변환된 weight를 저장하는 방안을 우선 고려한다.

## 6. 이상적인 producer-consumer 파이프라인

```text
Stage 1              Stage 2          Stage 3
Input transform  ->  GEMM/reduction -> Output transform/post

tile n+1             tile n           tile n-1
```

각 stage 사이에 circular buffer를 두면 다음 세 작업을 겹쳐 실행할 수 있다.

```text
Transform producer
    -> transformed-tile CB
        -> GEMM consumer/producer
            -> result CB
                -> output-transform consumer
```

이 구조가 성립하려면 각 stage의 처리율이 균형을 이루고, CB가 일시적인 속도 차이를 흡수할 수 있어야 한다.

## 7. 현재 베이스라인에 대한 매핑

### Conv1

```text
C = 1
K = 3
T = 12 x 12 = 144 tiles

각 transform 좌표:
(3x1) x (1x144) -> (3x144)
```

### Conv2

```text
C = 3
K = 3
T = 4 x 4 = 16 tiles

각 transform 좌표:
(3x3) x (3x16) -> (3x16)
```

### FC

```text
(10x48) x (48x1) -> (10x1)
```

세 레이어 모두 같은 MAC array에서 계산할 수 있지만, 현재 모델의 `C`와 `K`가 매우 작아 큰 systolic array의 utilization은 낮을 가능성이 높다. 지정주제에서는 작은 lane 수의 GEMM/MAC 엔진이 더 적합할 수 있다.

## 8. 2x2 maxpool과의 결합

`F(2x2,5x5)`의 출력 타일은 현재 모델의 2x2 maxpool window와 정확히 일치한다.

```text
Winograd output transform
-> 2x2 raw convolution outputs
-> max of four values
-> bias once
-> ReLU
-> pooled output one value
```

동일한 출력 채널의 네 값에는 같은 bias가 더해지므로 다음 관계를 이용할 수 있다.

```text
max(y0+b, y1+b, y2+b, y3+b)
= max(y0, y1, y2, y3) + b
```

이렇게 하면 convolution 출력 feature map 전체를 저장하지 않고 pooled 값만 다음 레이어로 전달할 수 있다.

## 9. 이 구조가 이상적으로 나오지 않을 수 있는 이유

현재 그림은 데이터 이동, 비트 폭, 처리율이 이상적으로 맞는다고 가정한 개념 구조다. 실제로는 다음 문제가 생길 수 있다.

### 작은 GEMM의 낮은 utilization

현재 베이스라인은 `C=1` 또는 `C=3`, `K=3`이므로 범용 GEMM array의 많은 lane이 놀 수 있다.

### transform 병목

input/output transform의 wide add/sub 처리율이 GEMM보다 낮으면 multiplier 감소가 전체 latency 감소로 이어지지 않는다.

### transform data 재배열

타일별로 만들어지는 6x6 데이터를 좌표별 GEMM으로 공급하려면 tile-major와 coordinate-major layout 사이의 재배열 또는 blocking이 필요하다.

### transformed-tile 저장량

모든 타일을 한 번에 좌표별로 모으면 저장량이 커진다. 작은 tile block 단위로 transform과 GEMM을 반복해야 할 가능성이 높다.

### 비트 폭 증가

transform 결과, transformed weight, Hadamard product 및 channel accumulator가 원래 INT8보다 크게 증가한다. 넓은 GEMM datapath를 그대로 사용하면 multiplier 절감이 면적·전력 이득으로 이어지지 않을 수 있다.

### 파이프라인 stage 불균형

한 transform unit을 input과 output에 시간 공유하면 면적은 줄지만 두 작업을 동시에 수행하지 못해 initiation interval이 증가할 수 있다.

### 범용성에 따른 mux/control 비용

Winograd, direct convolution, 1x1 convolution, FC를 모두 지원하면 data routing과 address generation이 복잡해진다.

### 지정주제와 자유주제의 목표 차이

- 지정주제: 고정된 작은 CNN에서 PPA를 최대한 줄이는 특수화가 유리할 수 있음
- 자유주제: ResNet 계열까지 지원하는 범용 GEMM 중심 구조가 더 설득력 있음

두 주제에서 완전히 동일한 RTL을 사용하는 것보다, 공통 GEMM 중심 개념을 유지하면서 array 크기와 transform 구성을 다르게 할 가능성이 있다.

## 10. 앞으로 검증할 질문

1. 현재 `C`, `K`, `T`에서 적합한 MAC lane 수는 몇 개인가?
2. Winograd 좌표 36개를 tile-major와 coordinate-major 중 어떤 순서로 처리할 것인가?
3. 한 번에 몇 개 타일을 CB에 묶어 GEMM할 것인가?
4. input transform, GEMM, output transform의 예상 cycle 수는 각각 얼마인가?
5. transform unit 하나를 입력과 출력에 공유해도 pipeline 병목이 생기지 않는가?
6. transformed input과 weight의 실제 필요 비트 폭은 얼마인가?
7. GEMM array를 FC와 공유했을 때 추가 mux/control 면적보다 제거되는 FC 전용 회로가 큰가?
8. direct/1x1 bypass 경로를 넣었을 때 자유주제의 일반성이 실제로 충분한가?
9. 모든 타일을 저장하지 않는 blocked/streaming schedule은 어떻게 구성할 것인가?
10. 최종 합성에서 transform의 wide adder 비용이 제거한 multiplier 비용보다 작은가?

## 11. 현재 가설

```text
지정주제 후보:
작은 shared MAC/GEMM engine
+ F(2x2,5x5) 전용 transform
+ maxpool/bias/ReLU fusion

자유주제 후보:
확장 가능한 GEMM core 또는 multi-core array
+ 선택 가능한 Winograd transform front/back-end
+ direct/1x1/FC bypass
+ scratchpad/CB 기반 producer-consumer pipeline
```

현재 단계의 결론은 다음과 같다.

> 일반 AI 가속기의 본체는 GEMM 엔진이며, Winograd는 일부 convolution을 더 적은 GEMM 작업으로 바꾸는 선택적 전처리·후처리 기능으로 보는 것이 가장 자연스럽다. 다만 현재 베이스라인처럼 채널 수가 작은 모델에서도 이 추상화가 실제 PPA 이득으로 이어지는지는 별도로 검증해야 한다.

## 관련 문서

- [Winograd CNN 논문 읽기 목록](winograd_paper_reading_list.md)
- [F(2x2,5x5) Winograd 변환 오버헤드 1차 계산](winograd_f2x5_overhead.md)
- [F(2x2,3x3) Winograd MAC/Reduction Engine 설계](winograd_mac_reduction_engine.md)
- [Lavin and Gray, Fast Algorithms for Convolutional Neural Networks](https://openaccess.thecvf.com/content_cvpr_2016/html/Lavin_Fast_Algorithms_for_CVPR_2016_paper.html)
