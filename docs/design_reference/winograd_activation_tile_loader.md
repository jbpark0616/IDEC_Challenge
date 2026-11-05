# Winograd streaming activation tile loader

> 현재 controller는 아래의 초기 full-bank loader 대신
> `winograd_sliding_window_generator`를 사용한다.
> 구형 `winograd_activation_tile_loader`와
> `winograd_activation_tile_loader_reference` RTL은 최종 streaming 구조에서
> 사용되지 않아 삭제했다. 아래 수치는 설계 변경 근거를 남기기 위한 역사적
> 비교 결과다.

## 현재 구조

Conv1 입력은 외부에서 raster order로 들어오는 즉시 3개의 고정 길이 line delay와
수평 shift register를 통과한다. 4x4 window가 완성되는 위치에서만 타일을 캡처해
Winograd core로 보낸다. 따라서 784-byte Bank A와 임의주소 read MUX가 없다.

```text
external UINT8 stream
  -> 3 line delays + horizontal shifts
  -> 4x4 pending-window register
  -> input transform
```

Conv1 출력은 Conv2가 바로 소비할 수 없다. 하나의 Winograd core를 두 레이어가
시간 공유하기 때문이다. 그래서 B에는 Conv1 전체 결과를 보존하되, 공간 위치마다
세 채널을 `{ch2,ch1,ch0}` 24-bit word 하나로 묶어 순서대로 저장한다.

```text
Conv1 output -> 169 x 24-bit sequential FF frame buffer
             -> 3-channel sliding-window generator -> Conv2
```

B는 frame buffer이지만 주소를 자유롭게 선택하는 scratchpad가 아니다. write/read
pointer로 순차 접근하며, 4x4 재사용과 채널 replay는 뒤의 window generator가 맡는다.
Conv2 결과 75개는 FC가 순서대로 읽는 `75 x 8-bit` linear feature buffer에 저장한다.

## 선택 근거와 결과

ASAP7 OpenROAD post-synthesis 기준:

| 구현 | 면적 | 최소 주기 | 추정 Fmax |
|---|---:|---:|---:|
| 16-read reference loader | 21,434.73 um^2 | 877.96 ps | 1.139 GHz |
| registered 16-bank loader | 7,190.70 um^2 | 1,528.09 ps | 654.41 MHz |
| Conv1 sliding-window generator | 505.02 um^2 | 252.60 ps | 3.959 GHz |
| packed B sequential frame buffer | 2,937.94 um^2 | 397.43 ps | 2.516 GHz |

전체 controller는 9,275.08 um^2, 최소 주기 923.31 ps(1.083 GHz), 실제
export-model RTL simulation 1,359 cycles를 기록했다. 이전 banked controller의
15,257.96 um^2, 446.61 MHz, 1,741 cycles보다 면적과 지연이 모두 감소했다.
다만 1.083 GHz는 배치배선 전 post-synthesis 수치이며 최종 sign-off 수치는 아니다.

전체 임계경로는 loader가 아니라 MAC의 `pipe_weight_zero`에서 INT18 accumulator로
가는 경로다. 그러므로 1 GHz 목표를 위해 loader에 추가 파이프라인을 넣을 이유는
현재 없다.

## 이전 full-bank 기준 구조

삭제된 `winograd_activation_tile_loader`는 UINT8 activation을 FF 기반 NCHW
scratchpad에 저장하고, `F(2x2,3x3)` 코어가 요구하는 4x4 입력 타일을 만들던
초기 비교 구조였다.

## 저장 순서

```text
address = channel * feature_plane_size + row * feature_width + column
```

Conv 코어 출력은 한 공간 위치에 대해 output channel 0, 1, 2 순서로
발생한다. Controller가 위 주소로 저장하면 다음 레이어에서 채널별 4x4 타일을
바로 읽을 수 있다.

## 출력 순서

```text
for tile_row
  for tile_col
    for input_channel
      emit 4x4 tile
```

같은 공간 타일의 모든 입력 채널이 연속하므로 `winograd_v_replay_buffer`의
채널 reduction 계약과 일치한다. 공간 타일 origin은 행과 열 방향으로 2씩
이동한다.

- Conv1: width 28, plane 784, C=1, tile grid 13x13
- Conv2: width 13, plane 169, C=3, tile grid 5x5

Conv2의 valid convolution 결과는 11x11이지만 마지막 행과 열은 stride-2
floor pooling에서 버려진다. 따라서 loader는 5x5 타일만 생성하고 불필요한
경계 타일을 계산하지 않는다.

## 하드웨어 선택

현재 지정주제 구현은 16개 pixel을 한 사이클에 읽는 FF scratchpad를 모델링한다.
출력에 register를 두어 downstream stall 동안 tile과 metadata가 안정적으로
유지된다. 주소 계산은 일반 곱셈기 대신 다음 누적 offset으로 구성한다.

- channel offset: `+ feature_plane_size`
- tile column offset: `+ 2`
- tile row offset: `+ 2 * feature_width`

최종 top에서는 이 모듈을 두 bank로 구성해 input/Conv2 output bank와 Conv1
output/Conv2 input bank를 번갈아 사용한다.

이 16-read 구조는 기능 기준 버전이다. FF array의 임의 주소 read가 합성에서
큰 MUX tree가 되므로, 전체 CNN 검증 후 2-cycle 또는 row-banked loader로
교체할 예정이다. 저장 용량 최적화와 read-port 최적화는 별개의 단계로 다룬다.

## 검증

`make sim-window-generator`는 Conv1 28x28x1과 Conv2 13x13x3의 타일 값,
채널 순서, metadata, backpressure를 확인한다.

`make sim-tile-loader`는 다음을 확인한다.

- 28x28x1 Conv1 타일 주소와 stride 2 이동
- 13x13x3 NCHW Conv2 채널 순서
- 16개 pixel lane의 정확한 packing
- 마지막 transaction 표시
- output backpressure 동안 tile/metadata 안정성

`make sim-two-conv-real`은 실제 INT4 export를 사용하여 A/B bank를 통과한
Conv2 feature 75개와 FC decision까지 Python 정수 golden과 비교한다.
