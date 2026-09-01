# Full-bank Winograd CNN engine

## 기준 아키텍처

지정주제의 첫 완성 버전은 하나의 Winograd 코어와 두 activation bank를
계층 단위로 재사용한다.

```text
external UINT8 image
        |
        v
Bank A: 784 B -- Conv1 --> Bank B: 507 B -- Conv2 --> Bank A[0:74]
                                                        |
                                                        v
                                      shared 16-lane MAC (FC mode)
                                                        |
                                                        v
                                             INT18 argmax decision
```

- Bank A 초기 배치: `1x28x28`, NCHW, 784 byte
- Bank B 배치: `3x13x13`, NCHW, 507 byte
- Bank A 재사용 배치: `3x5x5`, NCHW, 75 byte
- Conv1/Conv2는 같은 transform, MAC, output-transform, postprocess를 재사용한다.
- FC는 별도 multiplier array를 만들지 않고 같은 16-lane MAC을 사용한다.
  lane 0~9가 class 0~9를 맡고 75개 feature를 시간 방향으로 누산한다.
- FC 마지막 beat에서 INT16 bias를 더하고, 10개의 signed INT18 logit을
  비교하여 가장 작은 index 우선의 argmax를 출력한다.

## 제어 순서

```text
LOAD_IMAGE
 -> CONV1
 -> CONV2
 -> STREAM_FEATURES       (검증/관측용)
 -> FC
 -> COMPLETE
```

Conv1과 Conv2를 동시에 실행하지 않으므로 Bank B에는 Conv1 결과 전체를
보관한다. 이것이 하나의 코어를 재사용하면서 controller를 단순하게 유지하는
기준 설계의 핵심 trade-off다.

## 실제 모델 검증

`training/export_rtl_conv_vectors.py`는 동결된 INT4 export와 첫 대회 이미지를
사용하여 다음 RTL golden vector를 생성한다.

- 입력 UINT8 784개
- Conv1 출력 UINT8 507개
- Conv2 출력 UINT8 75개
- FC signed INT18 logit 10개와 최종 decision

`make sim-two-conv-real`은 export된 U weight, bias, requant multiplier, FC
weight를 RTL에 직접 넣는다. 현재 결과는 다음과 같다.

```text
PASS: winograd_cnn_accelerator real exported model (1741 cycles)
```

따라서 실제 데이터에 대해 `Bank A -> Conv1 -> Bank B -> Conv2 -> Bank A ->
FC -> argmax`가 Python INT18 golden과 일치한다.

## 현재 loader 구조와 다음 최적화

초기 기준 loader의 16개 가변 read port는 큰 MUX network를 만들었다. 이를
logical address의 하위 4-bit로 선택하는 16개의 interleaved FF bank로 바꾸고,
한 타일을 두 번의 bank read로 조립한다. 주소 schedule과 bank read 사이에도
register를 두어 긴 조합 경로를 끊었다.

1. 완료: 16-read reference loader를 16-bank/2-read registered loader로 변경
2. 다음 후보: 초기 Bank A를 4-row line buffer로 축소
3. 필요할 때만 Conv1/Conv2 wavefront scheduling으로 Bank B도 line buffer화

풀 뱅크 버전은 이후 최적화의 정확성·면적·성능 비교 기준으로 유지한다.

## OpenROAD ASAP7 기준 결과

모든 결과는 동일한 400 ps constraint의 post-synthesis OpenSTA 결과다.

| 합성 top | Area (um^2) | Sequential (um^2) | Fmax | Vectorless power |
|---|---:|---:|---:|---:|
| `winograd_conv_core` | 4,167.87 | 1,077.87 | 1.093 GHz | 295 mW |
| reference 16-read loader (`DEPTH=784`) | 21,434.73 | 1,885.84 | 1.139 GHz | 394 mW |
| first 16-bank loader (`DEPTH=784`) | 6,221.93 | 1,886.21 | 570.33 MHz | 925 mW |
| registered 16-bank loader (`DEPTH=784`) | 7,190.70 | 1,989.62 | 654.41 MHz | 363 mW |
| reference full controller | 38,658.77 | 4,209.42 | 427.16 MHz | 60 mW |
| first banked controller + pipelined argmax | 15,257.96 | 4,281.45 | 446.61 MHz | 156 mW |

풀 컨트롤러 합성에는 24분 21초와 약 3.5 GB peak memory가 필요했다.
총 362,931 standard cell 중 13,997개만 FF 계열이고, 전체 면적의 89.1%가
조합논리다. 이는 full-bank의 16개 가변 read port가 만든 MUX network가 큰
면적을 차지한다는 증거다.

reference controller의 최장 경로였던 FC 결과의 조합식 10-class argmax는
4-stage balanced signed comparator tree로 교체했다. 동점일 때 작은 class
index를 선택하는 기존 동작도 유지한다.

```text
u_core.u_mac.result_vec -> pipelined_argmax10 -> decision register
```

첫 banked controller에서 새 최장 경로는 loader의 row/address 선택과 bank
read MUX를 지나 MAC product register로 들어가는 경로였다. registered loader
단독 합성은 면적을 6,221.93에서 7,190.70 um^2로 15.6% 늘리는 대신 Fmax를
570.33에서 654.41 MHz로 14.7% 개선했다. 전체 controller의 최종 Fmax는
registered loader를 포함한 재합성 후 확정한다.

Vectorless power는 block별 activity 가정이 일관되지 않아 직접 합산하거나
우열 지표로 사용하지 않는다. 최종 전력 비교에는 실제 inference VCD/SAIF가
필요하다.
