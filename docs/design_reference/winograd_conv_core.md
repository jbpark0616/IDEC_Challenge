# Integrated Winograd convolution core

## 데이터 경로

`winograd_conv_core`는 한 공간 타일에 대한 convolution부터 pooled UINT8
activation 생성까지 연결한 통합 코어다.

```text
4x4 UINT8 activation tile/channel
  -> input transform
  -> V replay CB
  -> 16-lane INT4 x INT11 MAC + channel reduction
  -> M FIFO
  -> output transform
  -> bias + ReLU + 2x2 max-pool + requantization
  -> UINT8 activation/output channel
```

외부 controller는 같은 공간 타일의 입력 채널을 `c=0..C-1` 순서로 연속
공급한다. 코어는 출력 채널 `k=0..K-1`의 pooled activation을 순서대로 반환한다.

## 외부와 내부의 경계

코어에 포함:

- 두 Winograd transform
- 16-lane MAC/reduction
- V replay CB와 M FIFO
- fused post-process
- output-channel metadata pipeline

코어 밖에 유지:

- activation ping-pong bank와 4x4 tile loader
- U weight storage
- bias storage
- layer/tile/address controller

현재 `u_weight_bank`, `bias_bank`는 외부 저장소의 조합 read 결과를 모델링하는
입력 port다. 최종 top에서는 ROM 또는 weight register file의 출력에 연결한다.

## 채널 metadata

M FIFO는 M 타일과 output channel을 같은 entry에 저장한다. output transform과
post-process도 작은 `user` field를 각 pipeline stage에서 함께 전달한다.
따라서 여러 출력 채널이 동시에 서로 다른 stage에 있어도 bias 선택과 최종
activation channel이 어긋나지 않는다.

## 정수 연산 정합 수정

통합 전 Python 골든과 재대조하면서 MAC 누산 규칙을 다음처럼 확정했다.

- Conv/FC의 매 INT18 누산에서 saturation
- FC는 75개 product를 순서대로 saturation accumulate
- FC bias는 누산이 끝난 뒤 마지막에 saturation add

기존 MAC 단위 테스트는 overflow가 발생하지 않는 값만 사용해 wrap과 saturation의
차이를 검출하지 못했다. 양/음 INT18 rail에 도달하는 FC 테스트와 bias 순서를
구분하는 테스트를 추가했으며 수정 RTL이 통과했다.

## 검증

`make sim-core`는 독립적인 Verilog golden 계산으로 다음 경로 전체를 비교한다.

- Conv1 형식: `C=1`, `K=3`
- Conv2 형식: `C=3`, `K=3`
- V channel replay와 output-channel 순서
- transform의 모든 add/sub
- INT4 x INT11 product와 INT18 saturating reduction
- output transform 단계별 saturation
- bias/ReLU/max-pool/requantization
- 최종 output backpressure의 전 경로 전파

모든 검증을 통과했다.

## 통합 합성 결과

ASAP7 OpenROAD post-synthesis:

- area: `3863.714580 um^2`
- sequential area: `1014.330600 um^2` (`26.25%`)
- minimum period: `925.10 ps`
- estimated Fmax: `1080.96 MHz`
- vectorless total power: `341 mW`

전력은 400 ps 목표와 vectorless activity를 사용한 독립 합성 추정치이므로 최종
동작 workload 전력으로 해석하지 않는다.

현재 critical path는 M FIFO의 FF-array head selection에서 output transform의
첫 번째 saturating arithmetic stage까지다. 다음 timing 최적화에서는 M FIFO
출력을 한 번 register하거나 output transform 첫 단계를 더 나누는 방안을 실제
통합 경로 기준으로 비교한다.
