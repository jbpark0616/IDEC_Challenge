# Winograd MAC/Reduction Engine 설계

작성일: 2026-08-25

상태: **지정주제 1차 RTL 구현 및 단위 검증 완료**

## 1. 블록의 역할

아키텍처 그림의 파란색 블록은 단순 element-wise multiplier가 아니다. 이 블록은 다음 두 연산 모드를 제공하는 공유 연산 엔진이다.

```text
WINO 모드: F(2x2,3x3)의 16개 좌표별 곱셈 + 입력 채널 reduction
FC 모드:   10개 class별 MAC + 75개 입력 feature의 시간 누적
```

권장 명칭은 다음과 같다.

> **Winograd-domain MAC and Channel-Reduction Engine**

이 엔진의 앞에는 input transform과 transformed-activation CB가, 뒤에는 result CB와 output transform이 위치한다.

```text
V CB ----+
         +--> 16-lane MAC/Reduction Engine --> M CB
U CB ----+
```

## 2. 지정주제 기본 구성

`F(2x2,3x3)`에서 transformed activation `V`, transformed weight `U`, reduction 결과 `M`은 모두 4x4이다. 따라서 좌표 수는 16개다.

지정주제의 기본 연산 폭은 **16 lanes**로 정한다.

```text
lane  0: U[0]  x V[0]  -> M[k][0]
lane  1: U[1]  x V[1]  -> M[k][1]
...
lane 15: U[15] x V[15] -> M[k][15]
```

한 cycle에 입력 채널 하나와 출력 채널 하나의 4x4 Hadamard product를 모두 계산한다.

### 선택 이유

- Winograd의 4x4 transformed tile과 datapath가 일대일로 대응하여 제어가 단순하다.
- Conv1과 Conv2가 같은 물리 multiplier 16개를 재사용한다.
- 기존 레이어별 전용 multiplier 구조보다 전체 multiplier 수를 제한할 수 있다.
- 자유주제에서는 동일한 16-lane 엔진을 Winograd Core의 기본 연산 단위로 복제할 수 있다.
- lane 수를 4 또는 8로 folding하는 최적화는 합성 결과를 본 뒤 적용할 수 있다.

## 3. WINO 모드 수식

출력 채널 `k`, 타일 `b`, Winograd 좌표 `p`에 대해 중앙 연산은 다음과 같다.

```text
M[k,b,p] = sum(c=0..C-1) U[k,c,p] * V[c,b,p]
```

여기서:

- `p = 0..15`: 4x4 Winograd 좌표
- `c = 0..C-1`: 입력 채널
- `k = 0..K-1`: 출력 채널
- `b`: 공간 출력 타일 번호

16개 lane은 `p` 축을 병렬 처리하고, `c` 축은 accumulator에 시간 누적한다.

## 4. WINO 모드 내부 구조

```text
                16 x V registers
                        |
                16 x U registers
                        |
               16 signed multipliers
                        |
                        |
                16 wide M ACC bank
                        |
                  16-value M output
```

지정주제에서는 출력 채널마다 M bank를 따로 두지 않고 **16-entry accumulator bank 하나**를 모든 출력 채널이 시간 공유한다.

한 출력 채널 `k`를 선택한 뒤 모든 입력 채널 `c`를 연속해서 reduction하고, 완성된 `M[k,b]`를 result CB에 push한 후 같은 accumulator bank를 다음 출력 채널에 재사용한다.

```text
cycle 0: V[c=0,b] x U[k,c=0] -> M ACC load
cycle 1: V[c=1,b] x U[k,c=1] -> M ACC accumulate
cycle 2: V[c=2,b] x U[k,c=2] -> M ACC accumulate and complete
```

그 후 M을 출력하고 accumulator bank를 다음 `k`에 재사용한다. 이 구조는 V CB를 출력 채널마다 replay해야 하지만, accumulator register 수를 `3 x 16`에서 `1 x 16`으로 줄인다.

### accumulator 초기화

별도의 48-register clear cycle을 두지 않는다. 각 `(tile, input-channel group)`의 첫 입력 채널에서는 accumulator에 곱셈 결과를 직접 load한다.

```text
first_c = 1: M[k][p] <= product[p]
first_c = 0: M[k][p] <= M[k][p] + product[p]
```

마지막 입력 채널까지 누적되면 공유 `M ACC bank`를 출력 transform으로 전달한다.

## 5. 지정 모델 실행 스케줄

### Conv1: C=1, K=3

타일 하나에 대한 중앙 연산은 최소 3 MAC cycle이다. 입력 채널이 하나이므로 각 출력 채널마다 product를 M ACC에 직접 load하고 바로 출력한다.

```text
cycle 0: k0, c0 -> M[k0] complete
cycle 1: k1, c0 -> M[k1] complete
cycle 2: k2, c0 -> M[k2] complete
```

각 cycle에 완성되는 공유 M ACC의 결과는 해당 출력 채널의 4x4 `M` 타일이다.

### Conv2: C=3, K=3

타일 하나에 대한 중앙 연산은 최소 9 MAC cycle이다.

```text
k0: c0 -> c1 -> c2    cycles 0..2, M[k0] complete
k1: c0 -> c1 -> c2    cycles 3..5, M[k1] complete
k2: c0 -> c1 -> c2    cycles 6..8, M[k2] complete
```

각 출력 채널의 마지막 `c2` 누적 후 해당 `M[k]`를 output transform으로 전달한다. 다음 출력 채널 계산을 위해 V CB의 동일한 세 transformed activation tile을 다시 읽는다.

위 cycle 수에는 U/V 공급, multiplier pipeline latency, M 출력 handshaking은 포함하지 않는다. 정확한 latency는 RTL pipeline stage 결정 후 확정한다.

## 6. V CB의 소비 규칙

일반 FIFO처럼 `V`를 한 번 읽고 즉시 제거하면 안 된다. 동일한 타일의 `V[0..C-1,b]`를 모든 출력 채널 `k`가 반복해서 사용하기 때문이다.

지정주제에서는 다음 규칙을 사용한다.

```text
1. 한 공간 타일의 `C`개 transformed activation을 V CB에 저장한다.
2. k=0 계산에서 V[0]부터 V[C-1]까지 순차적으로 읽는다.
3. read pointer를 해당 공간 타일의 첫 V로 되돌려 k=1, k=2에서 replay한다.
4. 모든 K 출력 채널이 사용한 후에만 해당 공간 타일을 pop한다.
```

즉, `V CB pop`은 MAC 한 번이 아니라 해당 공간 타일의 reference count가 `K`에 도달한 후 발생한다. 구현은 destructive pop 대신 `tile_base`, `channel_offset`, `output_channel` counter를 이용한다.

## 7. U 공급 방식

Weight transform `U = GgG^T`는 소프트웨어에서 미리 수행한다. 연산 엔진에는 이미 변환·양자화된 16개 weight가 공급된다.

```text
U address = layer_base + ((k * C + c) * 16)
```

확정한 INT4 transformed weight 한 묶음은 다음과 같다.

```text
16 values x 4 bits = 64 bits
```
Conv1은 `3 x 64-bit`, Conv2는 `9 x 64-bit` 외부 weight 묶음으로 구성한다.

## 8. FC bypass 모드

FC에서는 16개 중 10개 MAC을 MNIST class에 일대일로 배정한다. 한 cycle에
activation feature 하나를 10개 lane에 broadcast하고, 각 class weight를 곱해
class별 accumulator에 누적한다.

```text
activation[f] --broadcast--> MAC 0 + ACC 0  (class 0)
                         +--> MAC 1 + ACC 1  (class 1)
                         ...
                         +--> MAC 9 + ACC 9  (class 9)
```

현재 모델의 FC 입력은 75개이므로 75 MAC beat 뒤에 10개 class score가 동시에
완성된다. 첫 beat에서는 `fc_bias_vec`의 INT16 bias를 INT18로 sign-extension해
불러오고 첫 product를 더한다. lane 10..15는 FC 모드에서 operand isolation으로
정지한다. 별도의 16-input adder tree는 필요하지 않는다.

## 9. 두 모드의 공유 자원

```text
16 multipliers --> shared 16-entry accumulator bank
                    |                 |
                    | WINO: p=0..15   | FC: class=0..9
                    v                 v
                 M[4x4]          10 class scores
```

공유하는 자원:

- 16 signed multipliers
- activation/weight input registers
- multiplier input/output pipeline registers
- valid pipeline 일부

모드별 전용 자원:

- WINO/FC: 공유 16-entry lane accumulator register
- FC: class 10개만 활성화하는 lane gating
- 주소 및 loop controller

## 10. 1차 비트폭 계획

Python 정수 golden model과 10,000장 검증으로 확정한 1차 RTL 비트폭은 다음과 같다.

```text
Activation = UINT8
U weight   = INT4
V          = INT11
FC weight  = INT4
Product    = INT15
Compute    = INT18
Bias store = INT16
```

INT4×INT11의 signed product는 INT15에 담고, Conv 채널 reduction과 FC의 75회
누산은 INT18에서 수행한다. bias는 저장 시 INT16이고 MAC 진입 시 INT18로
sign-extension한다.

INT18 누산은 overflow wrap이 아니라 매 beat saturation을 사용한다. FC bias는
첫 beat의 초기값으로 사용하지 않고 75개 feature 누산이 끝난 뒤 마지막에
saturation add하여 Python integer golden과 연산 순서를 일치시킨다.

## 11. 제어 인터페이스 초안

상위 controller가 제공해야 하는 정보:

```text
mode             : WINO / FC
layer_id         : CONV1 / CONV2 / FC
tile_id
input_channel c
output_channel k
first_c
last_c
first_chunk
last_chunk
```

데이터 handshaking:

```text
u_valid / u_ready
v_valid / v_ready
m_valid / m_ready
fc_out_valid / fc_out_ready
```

첫 RTL에서는 메타데이터 전부를 데이터와 함께 전달하기보다, 고정 모델용 FSM counter에서 생성한다. 자유주제에서 configuration register 기반으로 일반화한다.

## 12. 파이프라인 경계

권장 1차 구조:

```text
Stage M0: U/V 또는 activation/FC weight 선택, operand isolation, signed multiply
Stage M1: INT18 accumulator update 및 마지막 beat 결과 register
```

정확한 파이프라인 분할은 합성 timing report를 보고 조정한다. 지정주제의 첫 목표는 고주파수보다 수치적 정합성과 제어 완성이다.

## 13. result CB와의 계약

WINO 모드 출력 한 항목은 다음 데이터로 구성한다.

```text
M tile: 16 x WINO_ACC_W
metadata: tile_id, output_channel k, last_tile
```

`M`은 입력 채널 reduction이 완전히 끝난 뒤에만 push한다. 따라서 output transform은 channel reduction을 알 필요가 없으며, 완성된 4x4 `M`만 소비한다.

FC 모드는 result CB와 output transform을 우회하여 FC score를 comparator 또는 작은 score FIFO로 보낸다.

## 14. 이번 결정과 보류 항목

### 결정

- 지정주제는 `F(2x2,3x3)`을 사용한다.
- 중앙 엔진은 16-lane signed multiplier 구조를 사용한다.
- WINO 모드에서는 좌표별 accumulator로 입력 채널을 reduction한다.
- M accumulator는 16-entry bank 하나만 두고 출력 채널별로 시간 재사용한다.
- FC 모드에서는 lane 0..9를 class별 accumulator로 사용하고 75 feature를 시간 누적한다.
- Conv1, Conv2, FC가 동일한 multiplier 16개를 공유한다.
- zero weight와 FC의 미사용 lane 10..15에는 operand isolation을 적용한다.

### 다음에 확정

- layer별 binary point와 requantization 제어
- 합성 결과에 따른 multiplier pipeline 추가 여부
- U의 port packing과 load 방식
- result CB 깊이와 output-transform 처리율
- 4/8-lane folded 구조와 16-lane 구조의 합성 비교

## 15. 구현 상태

- RTL: `verilog/winograd_mac_array.v`
- 단위 테스트: `verification/winograd_mac_array_tb.v`
- 실행: `make sim-mac`
- Vivado 독립 합성: `make synth SYNTH_TOP=winograd_mac_array`
- OpenROAD 독립 합성: `make synth-asic ASIC_TOP=winograd_mac_array`

단위 테스트는 Conv1 1채널 product, Conv2 3채널 reduction, FC 75-feature
bias 누산, zero-weight gating의 수치 결과와 output backpressure를 검사한다.
Vivado 독립 합성은 100 MHz 제약에서 통과했다. OpenROAD ASAP7 post-synthesis
결과는 다음과 같다.

| 항목 | 결과 |
|---|---:|
| Cell area | 1,580.749 um^2 |
| Sequential area | 378.701 um^2 (23.96%) |
| 400 ps 목표 WNS | -159.70 ps |
| 추정 최소 period | 559.70 ps |
| 추정 Fmax | 1,786.66 MHz |
| Vectorless total power | 28.5 mW |

이는 MAC 배열만의 post-synthesis 수치이며 전체 코어의 배치·배선 후 결과는
아니다. 최종 성능 평가는 transform, CB, activation bank와 controller를 통합한
top에서 다시 수행한다.
- free-running valid 방식과 ready/valid 방식 중 최종 선택

## 16. 핵심 결론

> 파란색 블록은 Winograd 좌표 16개를 병렬 처리하고 입력 채널을 누적하는 공유 MAC 엔진이다. FC에서는 같은 배열의 lane 0..9를 class별 MAC으로 바꾸어 75개 feature를 누적하며, 별도의 adder tree 없이 10개 score를 동시에 완성한다.
