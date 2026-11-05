# Winograd core CB/FIFO structure

## 배치

현재 코어의 연산 경계는 다음처럼 구성한다.

```text
activation loader
  -> input transform
  -> V replay CB
  -> MAC + channel reduction
  -> M FIFO
  -> output transform
  -> fused post-process
  -> activation bank
```

입출력 블록 자체가 valid-ready pipeline register를 포함하므로 모든 stage 앞뒤에
FIFO를 반복해서 두지 않는다. 처리 시간이 크게 다른 두 경계만 명시적인 버퍼를
둔다.

## 일반 elastic FIFO

`elastic_fifo`는 폭과 깊이를 parameter로 받는 FF 기반 동기식 circular FIFO다.

- valid-ready handshake
- full/empty 표시
- full 상태에서도 같은 cycle에 pop하면 push 허용
- 임의의 depth에서 pointer wrap 지원
- storage payload는 reset하지 않고 pointer/count만 reset
- downstream stall 동안 head data 유지

M 경계에는 `winograd_m_fifo` wrapper가 이를 `288-bit x depth 2`로 사용한다.
M 한 항목은 채널 reduction이 끝난 완전한 `4x4 x INT18` 타일이다.

## V replay CB

V는 일반 FIFO처럼 한 번 읽고 제거할 수 없다. Conv2의 한 공간 타일에는 입력
채널별 V 세 개가 있고, 이것을 출력 채널 세 개에 각각 다시 사용한다.

```text
k0: V[c0], V[c1], V[c2]
k1: V[c0], V[c1], V[c2]
k2: V[c0], V[c1], V[c2] -> group release
```

`winograd_v_replay_buffer`는 다음 counter를 내부에서 관리한다.

- write group/channel
- read group/input channel
- read output channel
- complete group count

첫 번째 V만 들어온 partial group은 consumer에게 보이지 않는다. 마지막 출력
채널이 마지막 입력 채널을 소비했을 때만 group을 pop한다. 출력되는
`txn_first/txn_last`는 그대로 MAC reduction transaction 경계를 구동한다.

런타임 설정은 count-minus-one 형식이다.

```text
Conv1: input_channels_minus1=0, output_channels_minus1=2
Conv2: input_channels_minus1=2, output_channels_minus1=2
```

설정은 buffer가 empty이고 partial write가 없을 때만 바꾼다.

## 깊이 2를 선택한 이유

Conv2에서 타일 하나를 MAC이 소비하는 데 최소 9 beat가 필요하고, input
transform은 다음 타일의 채널 V 세 개를 3 beat에 만들 수 있다.

- depth 1: 현재 group을 9회 읽는 동안 다음 group을 저장할 곳이 없어 MAC 사이에
  입력 준비 지연이 생긴다.
- depth 2: 한 group을 읽는 동안 다른 group을 채우는 ping-pong이 가능하다.

따라서 V 저장량은 `2 groups x 3 channels x 176 bits = 1056 bits`다. 단순히
크기를 절반으로 줄이면 약 2 cycle의 tile 간 공백을 감수해야 하므로 첫 통합
설계에서는 depth 2를 유지한다.

## 검증

`make sim-fifo`:

- non-power-of-two depth pointer wrap
- full/empty
- full 상태의 동시 push/pop
- ordering
- backpressure

`make sim-v-replay`:

- partial group 차단
- Conv2 C=3, K=3 replay 순서
- Conv1 C=1, K=3 replay 순서
- 두 group ping-pong 및 pointer wrap
- full/empty와 backpressure

두 테스트 모두 통과했다.

## 합성 결과

ASAP7 OpenROAD 독립 post-synthesis 기준:

| 블록 | 저장량 | 면적 | 최소 주기 | 추정 Fmax |
|---|---:|---:|---:|---:|
| elastic FIFO 기본형 | 2 x 176 bit | 301.835 um^2 | 244.35 ps | 4092.50 MHz |
| M FIFO | 2 x 288 bit | 495.428 um^2 | 255.47 ps | 3914.42 MHz |
| V replay CB | 2 x 3 x 176 bit | 943.836 um^2 | 334.46 ps | 2989.94 MHz |

V CB 면적은 작지 않지만 MAC의 transform 재계산과 tile 간 공백을 없애는 데이터
재사용 자원이다. 최종 면적이 부족할 때만 depth 1 성능 저하와 비교해 재검토한다.
