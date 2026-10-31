# Temporal-Sparse Multicore Winograd Accelerator

## 1. 문서 목적

이 문서는 IDEC 창의회로설계 경진대회 자유주제의 설계 방향을 정리한 작업 기준 문서이다. 지정주제에서 구현한 single-core Winograd CNN accelerator를 기반으로, 비디오의 frame 간 temporal sparsity를 활용하는 multicore 구조로 확장하는 방안을 다룬다.

현재 내용은 최종 사양이 아니라 설계 가설이다. 선행 연구 조사, workload 분석, RTL 구현 및 PPA 평가 결과에 따라 세부 구조와 core 수를 확정한다.

## 2. 제안 주제

### 가제

**Scratchpad-Centric Multicore Winograd Accelerator for Temporally Sparse Video CNNs**

### 핵심 주장

> Frame 간 변화로 불규칙하게 발생하는 active Winograd tile을 여러 core에 배치하고, active-tile 수와 layer의 output-channel 수에 따라 spatial-tile 병렬성과 output-channel 병렬성 사이의 sharding 축을 전환한다. Banked shared scratchpad와 선택적 U/V multicast를 이용하여 core utilization과 data reuse를 함께 확보한다.

이 설계의 기여는 Winograd 또는 temporal difference 자체를 새로 제안하는 것이 아니다. 제안의 중심은 **temporally sparse workload에 따라 병렬화 축을 바꾸는 sharding controller와 scratchpad 기반 multicore dataflow**이다.

## 3. 설계 배경과 문제 정의

비디오의 연속 frame은 대부분의 영역이 유지되고 객체나 배경의 일부만 변한다. 따라서 현재 frame과 reference frame의 차이를 계산하면 변화가 없는 영역의 convolution을 생략할 수 있다.

그러나 active 영역은 frame마다 위치와 개수가 달라진다. Tile을 core에 고정적으로 배정하거나 여러 lane을 lockstep으로 구동하면 특정 core에만 작업이 집중되고 나머지 core가 유휴 상태가 될 수 있다. 단순한 zero skipping만으로는 이러한 **불규칙한 작업 분포에 따른 utilization 저하**를 해결하지 못한다.

Winograd F(2×2, 3×3)는 4×4 input tile에서 2×2 output tile을 생성하므로, 4×4 tile을 독립적인 scheduling 단위로 사용할 수 있다. 이를 active-tile descriptor로 변환하여 실행 가능한 core에 동적으로 배정하는 것이 본 설계의 출발점이다.

## 4. 기존 연구와의 구분

Inter-frame reuse와 Winograd를 함께 사용하는 선행 연구가 이미 존재하므로 다음 항목 자체를 novelty로 주장하지 않는다.

- Frame difference 계산
- 변화가 작은 4×4 tile의 생략
- Winograd convolution과 temporal reuse의 결합
- PE 또는 PU array를 이용한 output-channel 병렬화
- Reference-result buffer 또는 ping-pong buffer 사용

대표적인 2022년 TVLSI 설계는 16개의 PU group을 사용하며, 동일한 activation에 서로 다른 output-channel weight를 적용하는 병렬 PU array 구조이다. 이는 높은 병렬성을 제공하지만, 각 Winograd core가 독립적인 tile 작업을 받아 실행하는 multicore 구조와는 구분된다.

본 설계에서는 다음 조합을 차별화 후보로 삼는다.

- 독립적인 ready/valid interface를 갖는 복수의 Winograd execution core
- Active-tile queue와 tile-compacting batch scheduler
- Spatial-tile parallel mode와 output-channel parallel mode의 전환
- Spatial mode의 transformed-weight multicast와 channel mode의 transformed-activation multicast
- 주소 지정이 가능한 banked shared scratchpad
- Scratchpad bank conflict를 고려한 tile dispatch
- Frame sparsity에 따른 adaptive active-core count와 clock gating

Novelty의 최종 범위는 추가 선행 연구 조사 후 확정한다.

## 5. 제안 아키텍처

```text
Current / Reference Frame
           │
  Temporal Difference Unit
           │
   Dirty-Tile Map Generator
           │
     Active-Tile Queue
           │
 Adaptive Sharding Controller
  (P_s spatial × P_k channel)
       ┌───┼───┐
       ▼   ▼   ▼
     Core0 Core1 ... CoreN-1
       └───┼───┘
     Banked Shared Scratchpad
           │
 Reference-State Update / Output
```

### 5.1 Temporal Difference Unit

현재 frame과 reference frame 또는 layer activation의 차이를 계산한다. 1차 구현은 quantized activation delta가 정확히 0이 아닌 tile을 active로 표시하고, 이후 threshold mode로 확장한다. Key frame에서는 모든 tile을 active로 처리한다.

### 5.2 Dirty-Tile Map Generator

변화한 spatial 위치가 영향을 주는 convolution receptive field와 Winograd tile 경계를 고려하여 dirty map을 생성한다. 단순히 변화 pixel이 포함된 tile만 선택하면 인접 output에 대한 영향을 누락할 수 있으므로 halo 확장이 필요하다.

### 5.3 Active-Tile Queue

Active tile을 descriptor 형태로 저장한다. 1차 구현은 모든 core가 같은 layer를 처리하는 layer-synchronous 방식이므로 descriptor에는 spatial 위치만 저장한다.

```text
{tile_row, tile_col}
```

Layer, channel group 및 memory base address는 global configuration과 controller counter에서 생성한다. 향후 서로 다른 layer의 작업을 동시에 실행할 경우에만 layer ID와 address field를 descriptor에 추가한다.

### 5.4 Tile-Compacting Scheduler

Queue에 존재하는 active tile ID를 연속적인 core batch로 압축하여 배정한다. Raster 공간을 core별로 고정 분할하지 않으므로, 변화 영역이 특정 위치에 집중되더라도 빈 partition 때문에 core가 유휴 상태가 되는 것을 피한다.

같은 layer의 spatial tile은 기본적으로 실행 시간이 동일하므로, 1차 구현에서는 복잡한 out-of-order work stealing을 사용하지 않는다. Scheduler는 다음 정보를 바탕으로 batch의 spatial 병렬도와 channel 병렬도를 선택한다.

- Active tile 수
- Output-channel group 수
- Scratchpad bank 충돌
- U 또는 V의 multicast 가능성
- 현재 active core 수

### 5.5 Multicore Winograd Engine

각 core는 지정주제에서 검증한 Winograd pipeline을 기본 실행 단위로 사용한다.

- Input transform
- Transform-domain MAC 및 channel reduction
- Output transform
- Fused nonlinear/post-processing operation

Core마다 전체 weight와 activation storage를 복제하지 않는다. 계산 pipeline과 최소 local V replay buffer만 복제하고, 큰 activation state와 transformed weight는 shared memory 계층에서 공급한다.

현재 single-core RTL에서 자연스러운 작업 단위는 다음과 같다.

```text
input  : 한 spatial tile의 4×4 activation, channel c=0..C-1
compute: 16 Winograd coordinates를 병렬 처리하고 C축을 시간 누적
output : 선택된 output-channel group의 2×2 output tile
```

자유주제에서는 현재 core에 내장된 전체 output-channel 순회 범위를 `k_base`와 `k_count`로 제한할 수 있도록 일반화한다. 또한 현재 postprocess가 항상 수행하는 2×2 max pooling은 core 외부의 선택 가능한 fused-output stage로 분리하여, pooling이 없는 일반 convolution layer에서도 네 output을 보존한다.

### 5.6 Banked Shared Scratchpad

Scratchpad는 current/reference activation, partial state 및 갱신 결과를 주소 기반으로 저장한다. FIFO와 달리 active tile의 불규칙한 순서를 지원할 수 있다는 점이 중요하다.

검토 항목은 다음과 같다.

- Bank 수와 core 수의 관계
- Tile-to-bank address mapping
- 동시 read/write 충돌 처리
- Reference와 current state의 배치
- Double buffering 필요 여부
- External memory traffic과 scratchpad capacity의 trade-off

### 5.7 Adaptive Core Activation

Frame별 active tile 수에 따라 사용하는 core 수를 조절한다.

- Dense key frame: 모든 core 활성화
- 중간 sparsity: 일부 core 활성화
- 높은 sparsity: 최소 core만 활성화하고 나머지는 clock gating

이 기능은 throughput뿐 아니라 temporal sparsity가 높은 frame에서의 switching power 감소를 목표로 한다.

### 5.8 Adaptive Sharding Mode

N개의 물리 core를 `P_s × P_k = N`으로 논리적으로 배치한다. `P_s`는 동시에 처리하는 spatial tile 수이고 `P_k`는 한 tile에서 동시에 처리하는 output-channel group 수이다.

4-core의 후보 mode는 다음과 같다.

| Mode | P_s × P_k | 동작 | 주요 재사용 |
|---|---:|---|---|
| Spatial mode | 4 × 1 | 네 active tile을 병렬 처리 | 동일 U를 네 core에 multicast |
| Hybrid mode | 2 × 2 | 두 tile과 두 channel group을 병렬 처리 | U와 V를 부분 multicast |
| Channel mode | 1 × 4 | 한 tile의 네 channel group을 병렬 처리 | 동일 V를 네 core에 multicast |

초기 layer처럼 active spatial tile이 많고 channel 수가 작을 때는 spatial mode가 유리하다. 반대로 temporal sparsity가 높아 active tile이 core 수보다 적거나, 후기 layer처럼 spatial 크기는 작고 output channel이 많을 때는 channel mode가 core utilization을 유지하기 유리하다.

Layer 또는 frame에 active tile이 `A`개이고 output-channel group이 `G`개일 때, compute 중심의 1차 cycle model은 다음과 같이 둘 수 있다.

```text
batch_count(P_s, P_k)
  = ceil(A / P_s) × ceil(G / P_k)

P_s × P_k = N_core
```

실제 mode 선택에서는 batch 수뿐 아니라 activation read, weight read, bank conflict 비용을 함께 고려한다. 1차 RTL은 configuration register로 mode를 지정하고, 이후 hardware counter가 `A`를 측정하여 mode를 선택하는 구조로 확장한다.

### 5.9 U/V Multicast Network

Sharding mode에 따라 재사용할 operand가 달라진다.

```text
Spatial mode: 같은 (k,c)의 U를 여러 spatial core에 broadcast
Channel mode: 같은 spatial tile과 c의 V를 여러 channel core에 broadcast
```

완전한 NoC 대신 두 개의 제한된 multicast 경로와 core별 input register를 사용한다. Spatial mode에서는 각 core의 input transform이 서로 다른 tile을 처리한다. Channel mode에서는 leader core 또는 shared transform unit이 생성한 V를 follower core의 replay buffer에도 기록하여 중복 transform을 피하는 방안을 비교한다.

### 5.10 Exact Delta-State Update

1차 구현은 threshold approximation보다 **정확히 0인 activation delta만 생략**하는 방식을 우선한다. 이 방식은 threshold 오차와 refresh 정책을 분리하여 hardware dataflow 자체를 먼저 검증할 수 있다.

Pointwise nonlinear layer의 상태 갱신은 다음과 같다.

```text
Δz_t = W × Δa_t
z_t  = z_ref + Δz_t
a_t  = Q(f(z_t))
Δa_next = a_t - Q(f(z_ref))
z_ref ← z_t
```

여기서 scratchpad는 layer별 pre-activation reference `z_ref`를 보존한다. Delta frame에서는 bias가 `z_ref`에 이미 포함되어 있으므로 bias를 다시 더하지 않는다. 따라서 fused-output stage에는 다음 동작이 필요하다.

- Key-frame mode: convolution output에 bias를 더한 뒤 `z_ref`에 저장
- Delta mode: convolution delta를 기존 `z_ref`에 더하고 bias path는 bypass
- 이전/현재 `z`에 nonlinear function을 적용하여 다음 layer의 activation delta 생성
- 생성된 delta가 정확히 0이면 다음 layer의 active map에서 제외

Threshold 기반 근사 생략은 exact-zero 구조가 검증된 이후 추가한다. 작은 delta를 단순 폐기하면 layer state가 불일치할 수 있으므로, threshold mode에서는 residual 누적 또는 last-emitted activation reference가 별도로 필요하다.

### 5.11 Scratchpad의 2×2 Tile-Word 구성

F(2×2, 3×3)의 output transform은 channel마다 2×2 output을 생성한다. 이를 하나의 scratchpad word로 저장하면 다음 layer의 4×4 input tile은 인접한 네 개의 2×2 tile word로 조립할 수 있다.

```text
previous-layer tile words          next-layer 4×4 input

  [T(r,c)] [T(r,c+1)]              ┌───────────────┐
  [T(r+1,c)] [T(r+1,c+1)]    →     │ four 2×2 words│
                                    └───────────────┘
```

Tile row와 column의 하위 비트로 bank를 선택한다.

```text
bank_id = {tile_row[0], tile_col[0]}
```

그러면 서로 인접한 2×2 tile word 네 개가 bank 0..3에 하나씩 배치되어, single-port 4-bank scratchpad에서도 한 core의 4×4 input tile을 충돌 없이 읽을 수 있다. Border padding은 tile loader에서 zero insertion으로 처리한다.

1차 memory organization은 다음과 같이 분리한다.

| 저장 영역 | Word 구성 | 용도 |
|---|---|---|
| State scratchpad | 4 × INT18 `z_ref` | Frame 간 유지되는 pre-activation state |
| Delta scratchpad | 4 × INT9 `Δa` | 현재 frame에서 다음 layer로 전달되는 signed activation delta |
| Weight banks | 16 × INT4 `U` | `(k,c)`별 transformed weight |

UINT8 activation의 frame 차이는 -255..255이므로 signed INT9가 필요하다. Dense key-frame activation은 앞에 0을 붙여 같은 signed INT9 input datapath로 공급할 수 있다. Input transform의 중간 차분을 포함해 V는 기존 INT11 범위를 우선 유지하되 bit-accurate sweep으로 다시 확인한다.

4-bank scratchpad가 한 cycle에 공급하는 네 word는 한 spatial input tile과 한 input channel에 해당한다. 여러 spatial core에 동시에 tile을 공급하려면 다음 선택지가 있다.

- Shared loader가 core local buffer를 순차적으로 prefetch
- Bank 수를 8개 또는 16개로 증가
- Multi-cycle read와 compute를 double buffering으로 중첩

1차 RTL은 4-bank shared loader와 core별 local V buffer를 사용한다. Channel 수와 output-channel group 수가 충분하면 MAC 시간이 tile load 시간을 가리므로, 처음부터 16-bank crossbar를 두지 않는다.

### 5.12 Layer-Synchronous Descriptor와 Scheduler

모든 core가 같은 layer를 처리하도록 제한하면 layer configuration과 channel loop를 descriptor마다 저장할 필요가 없다. Layer 정보는 global configuration register에 두고 active-tile queue에는 spatial 위치만 저장한다.

```text
Global layer configuration:
  H, W, C, K, tile_rows, tile_cols,
  weight_base, state_base, delta_base,
  activation_mode, sharding_mode

Active-tile descriptor:
  {tile_row, tile_col}
```

Output-channel group은 scheduler의 global `k_group` counter로 생성한다. 이 구조는 descriptor 폭, queue storage 및 제어 비교기를 줄이고 모든 core의 weight/activation multicast를 쉽게 만든다.

4-core mode 선택은 가능한 `(P_s,P_k) = (4,1), (2,2), (1,4)`를 비교하여 다음 batch 수가 가장 작은 구성을 고르는 방식으로 시작한다.

```text
cost(P_s,P_k) = ceil(active_tiles/P_s)
              × ceil(output_channel_groups/P_k)
```

동일한 cost가 나오면 scratchpad와 weight bandwidth를 기준으로 선택한다. 초기 구현에서는 software/configuration register가 mode를 지정하고, 검증 후 dirty-tile counter와 작은 비교 회로로 자동 선택을 추가한다.

## 6. 지정주제 설계의 재사용

지정주제에서 activation storage를 FIFO가 아닌 lifetime-aware scratchpad에 가깝게 구성한 것은 본 확장에 유리하다. 기존 설계에서 확보한 자산은 다음과 같다.

- 합성 가능한 single-core Winograd datapath
- Input/output transform 및 MAC pipeline
- Ready/valid 기반 block 연결
- Activation lifetime 분석과 주소 재사용
- Conv/FC operation fusion
- Bit-accurate verification 환경
- Post-synthesis timing, area 및 activity-based power 평가 flow

현재 구조는 single-core와 고정 모델을 전제로 하므로 다음 항목은 새로 설계해야 한다.

- Model-specific 104-word storage의 일반화
- Multi-bank memory organization
- 복수 core의 동시 접근과 arbitration
- Active-tile metadata 및 queue
- Previous/current frame state 관리
- Tile-compacting scheduler 및 adaptive sharding controller
- Core별 clock enable 및 완료 추적

따라서 자유주제는 별개의 가속기를 처음부터 만드는 것이 아니라 다음의 연속적인 발전으로 설명할 수 있다.

```text
Lifetime-aware single-core storage
        → Banked multicore scratchpad
        → Temporal-sparsity-aware tile scheduling
```

## 7. 동작 모드

### 7.1 Dense Mode

Key frame 또는 변화량이 큰 frame을 모든 tile이 active인 일반 CNN inference로 처리한다. Multicore scaling의 기준 동작이며 temporal approximation을 사용하지 않는다.

### 7.2 Temporal-Sparse Mode

Dirty map에 포함된 tile만 queue에 삽입한다. Core는 differential convolution 또는 필요한 갱신 연산을 수행하고 reference state를 갱신한다.

### 7.3 Refresh Mode

Threshold에 의해 누적될 수 있는 오차를 제한하기 위해 일정 주기 또는 error criterion에 따라 dense key frame을 수행한다. Refresh 정책은 accuracy와 연산 절감률을 함께 평가하여 결정한다.

## 8. 평가 계획

### 8.1 비교 구성

| 구성 | 검증 목적 |
|---|---|
| Single-core dense | 지정주제 baseline |
| Multicore dense | Core 복제에 따른 순수 scaling 확인 |
| Delta multicore + fixed spatial partition | Temporal skipping과 spatial load imbalance 확인 |
| Delta multicore + compacted spatial batches | Active-tile compaction 효과 확인 |
| Fixed sharding vs. adaptive sharding | P_s/P_k mode 전환 효과 확인 |
| Adaptive sharding + adaptive cores | Power 최적화 효과 확인 |

### 8.2 측정 지표

- Accuracy 또는 object-detection mAP
- Cycle/frame 및 frame/s
- Core별 utilization과 idle cycle
- Active tile 비율
- Scratchpad read/write 횟수
- External memory traffic
- Scratchpad bank-conflict rate
- U/V multicast에 따른 operand read 감소
- Sharding mode별 tail utilization
- Area와 최대 동작 주파수
- Activity-based power
- Dense-equivalent throughput 및 energy efficiency
- Scheduler와 metadata의 area/power overhead

### 8.3 Core 수 탐색

처음부터 큰 array를 구현하지 않고 1/2/4-core를 우선 비교한다. Active tile 수가 작으면 core를 늘려도 queue가 충분한 병렬 작업을 공급하지 못하므로, workload별 throughput 향상과 하드웨어 비용이 균형을 이루는 core 수를 선정한다. 필요할 경우 이후 8-core를 분석 모델 또는 확장 실험으로 추가한다.

## 9. 필수 검증 문제

다음 문제가 해결되지 않으면 temporal sparse inference의 정확성과 성능을 주장할 수 없다.

1. **Dirty-region propagation**  
   한 pixel 또는 tile의 변화가 kernel receptive field와 Winograd tile overlap을 통해 영향을 주는 범위를 정확히 추적해야 한다.

2. **Nonlinear operation 처리**  
   Difference만으로 ReLU, pooling 등의 비선형 연산 결과를 직접 갱신할 수 없으므로 reference 결과 복원과 갱신 순서를 정의해야 한다.

3. **Approximation error 관리**  
   Threshold에 의해 생기는 오차의 누적을 측정하고 key-frame 주기 또는 adaptive refresh 조건을 결정해야 한다.

4. **Scratchpad consistency**  
   여러 core가 서로 다른 tile을 완료하는 상황에서 reference/current state와 output address가 충돌하지 않도록 보장해야 한다.

5. **Memory bandwidth와 load balance**  
   Core 수 증가가 scratchpad port와 external bandwidth에 의해 제한되지 않는지 확인해야 한다.

6. **제어 overhead**  
   Scheduler, queue, dirty map 및 bank arbitration의 면적과 전력이 절감한 연산량보다 과도하지 않아야 한다.

## 10. 경진대회용 설계 범위

완성도를 위해 자유주제의 최소 목표를 다음과 같이 제한한다.

- 2-core 및 4-core synthesizable RTL
- Dense mode와 temporal-sparse mode 지원
- Active-tile queue와 tile-compacting scheduler 구현
- Spatial/channel sharding mode 및 최소 한 개의 U/V multicast 경로 구현
- Banked scratchpad 및 conflict 처리 구현
- 실제 또는 학습 모델에서 추출한 video activation trace 기반 검증
- Static mapping 대비 utilization, latency 및 power 비교
- Accuracy/연산 절감률과 key-frame 주기 분석

VGG 또는 ResNet 전체를 지원하는 완전한 범용 NPU를 일차 목표로 삼지 않는다. 우선 대표적인 video CNN workload에서 제안 회로의 효과를 명확히 증명하고, 대형 CNN 지원은 memory capacity와 layer mapping을 포함한 확장 가능성으로 제시한다.

## 11. 단계별 진행안

1. 선행 연구와 novelty 경계 확정
2. Video workload에서 frame/tile sparsity 측정
3. Dirty-region propagation의 golden model 구현
4. P_s/P_k sharding mode별 cycle 및 bandwidth model 비교
5. Scratchpad banking과 descriptor 형식 결정
6. Exact delta-state update golden model 구현
7. 2-core RTL 통합 및 검증
8. 4-core 확장과 core-count/sharding-mode sweep
9. Clock gating 및 adaptive active-core control 추가
10. Post-synthesis PPA와 activity-based power 평가
11. Ablation 결과와 architecture figure 정리

## 12. 성공 판단 기준

본 설계는 단순히 동작하는 multicore를 만드는 것으로 완료되지 않는다. 다음 질문에 정량적으로 답할 수 있어야 한다.

- Tile compaction이 고정 spatial partition보다 core utilization을 높이는가?
- Active tile 수와 layer shape에 따른 sharding 전환이 fixed mode보다 유리한가?
- Scheduler와 scratchpad overhead를 포함해 latency 또는 energy가 개선되는가?
- Temporal skipping에 따른 accuracy 저하를 제한할 수 있는가?
- Dense key frame에서도 multicore 구조가 정상적인 scaling을 보이는가?
- 어떤 active-tile 비율과 core 수에서 제안 구조가 가장 유리한가?

이 질문에 RTL, waveform, synthesis report 및 workload 결과로 답할 수 있을 때 경진대회용 논리와 회로 완성도가 확보된다.

## 참고할 선행 연구

1. S. Li et al., “An Efficient CNN Accelerator Using Inter-Frame Data Reuse of Videos on FPGAs,” *IEEE Transactions on Very Large Scale Integration Systems*, vol. 30, no. 11, pp. 1587–1600, 2022. https://doi.org/10.1109/TVLSI.2022.3151788
2. Q. Hong and Q. Wang, “Design of Sparse CNN Accelerator Based on Inter-Frame Data Reuse,” *Computer Engineering*, vol. 49, no. 12, pp. 55–62, 2023. https://doi.org/10.19678/j.issn.1000-3428.0066172
3. A. Parger et al., “DeltaCNN: End-to-End CNN Inference of Sparse Frame Differences in Videos,” *Proceedings of the IEEE/CVF Conference on Computer Vision and Pattern Recognition*, 2022. https://openaccess.thecvf.com/content/CVPR2022/html/Parger_DeltaCNN_End-to-End_CNN_Inference_of_Sparse_Frame_Differences_in_Videos_CVPR_2022_paper.html
4. M. Riera, J.-M. Arnau, and A. González, “Computation Reuse in DNNs by Exploiting Input Similarity,” *Proceedings of the 45th Annual International Symposium on Computer Architecture*, 2018. https://doi.org/10.1109/ISCA.2018.00016
5. L. Lu, Y. Liang, Q. Xiao, and S. Yan, “Evaluating Fast Algorithms for Convolutional Neural Networks on FPGAs,” *IEEE International Symposium on Field-Programmable Custom Computing Machines*, 2017. https://ceca.pku.edu.cn/media/lw/6940b5b0e09259131ff19334f3efeecd.pdf
6. X. Liu, Y. Chen, C. Hao, A. Dhar, and D. Chen, “WinoCNN: Kernel Sharing Winograd Systolic Array for Efficient Convolutional Neural Network Acceleration on FPGAs,” *IEEE International Conference on Application-specific Systems, Architectures and Processors*, 2021. https://arxiv.org/abs/2107.04244
7. F. Shi, H. Li, Y. Gao, B. Kuschner, and S.-C. Zhu, “Sparse Winograd Convolutional Neural Networks on Small-Scale Systolic Arrays,” *ACM/SIGDA International Symposium on Field-Programmable Gate Arrays*, 2019. https://arxiv.org/abs/1810.01973
8. L. Lu and Y. Liang, “SpWA: An Efficient Sparse Winograd Convolutional Neural Networks Accelerator on FPGAs,” *ACM/ESDA/IEEE Design Automation Conference*, 2018. https://ceca.pku.edu.cn/docs/20181119154841593887.pdf
9. H. Ye, X. Zhang, Z. Huang, G. Chen, and D. Chen, “HybridDNN: A Framework for High-Performance Hybrid DNN Accelerator Design and Implementation,” *ACM/IEEE Design Automation Conference*, 2020. https://arxiv.org/abs/2004.03804
10. M. Hattink, G. Di Guglielmo, L. P. Carloni, and K. Bergman, “A Scalable Architecture for CNN Accelerators Leveraging High-Performance Memories,” *IEEE High Performance Extreme Computing Conference*, 2020. https://sld.cs.columbia.edu/pubs/hattink_hpec20.pdf

### 멀티코어·dataflow 관점의 우선 읽기 순서

1. **WinoCNN**  
   `M × N` WinoPE systolic array에서 output-channel 축과 spatial-tile 축을 동시에 unroll한다. 같은 row 또는 column의 PE가 weight 또는 input tile을 공유하며, 인접 tile overlap과 planar memory access를 처리하는 전용 memory subsystem을 제안한다. 본 설계의 multicore 배치 및 U/V 공유 구조와 가장 직접적으로 비교해야 한다.

2. **Evaluating Fast Algorithms for CNNs on FPGAs**  
   Input/output channel loop를 `P_m × P_n` Winograd PE로 병렬화하고 line buffer로 인접 tile overlap을 재사용한다. Spatial-column 병렬화가 memory bank conflict를 유발할 수 있다는 분석과 DSP/BRAM/bandwidth 모델이 core 수 결정에 유용하다.

3. **A Scalable Architecture for CNN Accelerators**  
   Input-feature unrolling `U_i`, output-feature unrolling `U_o`, parallel output row 수 `N_r`로 확장하며, row buffer와 ping-pong serialization을 통해 memory bandwidth와 compute throughput을 맞춘다. 단순 core 복제보다 어느 loop를 unroll할지 결정하는 참고 구조다.

4. **Sparse Winograd on Small-Scale Systolic Arrays / SpWA**  
   Sparse Winograd 연산을 여러 PE 또는 작은 systolic-array cluster에 매핑하고 load imbalance와 memory layout을 다룬다. Temporal sparsity가 아니라 weight sparsity가 중심이지만, sparse work distribution과 PE utilization 비교에 필요하다.

5. **HybridDNN**  
   Spatial/Winograd mode, input-stationary/weight-stationary dataflow, `P_I`, `P_O`, `P_T` 병렬 인자를 함께 탐색한다. 범용 reconfigurable accelerator와 본 설계의 전용 temporal-sparse controller 사이의 범위 차이를 정하는 비교 대상이다.
