# Winograd fused post-process

## 역할

`winograd_postprocess`는 output transform이 만든 한 출력 채널의 2x2
INT18 타일을 다음 activation bank에 저장할 UINT8 값 하나로 변환한다.

```text
Y[2x2] INT18
    -> signed max4
    -> bias add + INT18 saturation
    -> ReLU
    -> integer requantization
    -> UINT8 activation
```

Winograd `F(2x2, 3x3)`의 출력 타일 크기와 max-pool의 `2x2, stride 2`
윈도우가 일치하므로, 정상적인 출력 타일 하나가 pooled activation 하나를
만든다.

## 연산 융합이 정확한 이유

Python 골든 모델의 원래 순서는 각 원소에 대해 다음과 같다.

```text
max_i(ReLU(sat18(Y_i + bias)))
```

동일한 bias에 대한 포화 덧셈과 ReLU는 모두 단조 증가 함수이므로 다음과
같이 바꿀 수 있다.

```text
ReLU(sat18(max_i(Y_i) + bias))
```

따라서 4개의 bias 덧셈기 대신 signed comparator tree와 bias 덧셈기 하나만
사용해도 정수 결과가 완전히 같다. 테스트벤치는 의도적으로 최적화 전
순서로 골든 값을 계산하여 이 등가성을 검증한다.

## Requantization

학습/export 환경과 같은 정수식을 사용한다.

```text
rounded = (relu_value * multiplier + 2^23) >> 24
activation = clamp(rounded, 0, 255)
```

- Conv1 multiplier: `1616163`
- Conv2 multiplier: `1827841`
- multiplier 입력 폭: UINT24
- 출력: UINT8

multiplier를 데이터와 함께 파이프라인에 저장하므로 서로 다른 계층이나
출력 채널의 transaction이 연속으로 들어와도 정렬이 깨지지 않는다.

## 파이프라인

3-stage valid-ready elastic pipeline이며, stall이 없을 때 매 cycle 타일
하나를 받아 pooled activation 하나를 출력한다.

1. P0: signed max4, bias와 multiplier capture
2. P1: bias add, INT18 saturation, ReLU
3. P2: UINT24 multiply, round, shift, UINT8 clamp

각 stage는 downstream backpressure를 전달한다. Datapath register는 reset하지
않고 valid register만 reset하여 불필요한 reset tree를 줄였다.

## 공간 경계 처리

- Conv1: `26x26 -> max-pool -> 13x13`; 모든 2x2 Winograd 출력 타일을 사용한다.
- Conv2: `11x11 -> max-pool -> 5x5`; 마지막 출력 행/열은 PyTorch floor pooling에서
  사용되지 않는다.

따라서 Conv2에서는 controller가 tile row 5 또는 tile column 5인 연산을 처음부터
schedule하지 않아도 된다. post-process 내부에 부분 타일 마스크를 둘 필요가 없다.

## 검증 결과

`make sim-postprocess`에서 다음 항목을 통과했다.

- zero 및 전체 음수 입력
- 양/음 INT18 saturation 경계
- UINT8 clamp와 반올림
- 실제 Conv1/Conv2 multiplier
- random 100개 타일
- cycle마다 bias/multiplier가 바뀌는 연속 입력
- output backpressure 중 결과 유지

Vivado 합성은 오류/경고 없이 완료되었다. ASAP7 OpenROAD post-synthesis 결과는
다음과 같다.

- cell area: `320.351760 um^2`
- sequential area: `32.338440 um^2` (`10.09%`)
- minimum period: `633.36 ps`
- estimated Fmax: `1578.88 MHz`
- vectorless total power: `29.9 mW`

이 수치는 블록 단독 post-synthesis 추정값이며 최종 통합 배치배선 결과와는
구분해야 한다.
