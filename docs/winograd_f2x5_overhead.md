# F(2x2, 5x5) Winograd 변환 오버헤드 1차 계산

작성일: 2026-08-24

이 문서는 현재 CNN 베이스라인의 5x5 convolution을 `F(2x2, 5x5)` Winograd로 바꿀 때의 연산량, 버퍼, 가중치 저장량 및 비트 폭 오버헤드를 1차 계산한 것이다.

## 1. 계산 가정

- 출력 타일: 2x2
- 필터: 5x5
- 입력 타일: `(2 + 5 - 1) x (2 + 5 - 1) = 6x6`
- stride: 1
- padding: 없음
- 보간점: `{0, 1, -1, 2, -2}`
- 필터는 추론 전에 변환하여 저장하며, 필터 변환 비용은 이미지별 실행 연산량에서 제외한다.
- shift는 일반 multiplier보다 훨씬 저렴한 배선 이동으로 구현한다고 가정한다.
- 아래 add/shift 수는 가능한 한 가지 공통부분 재사용 스케줄의 수이며, 합성 후 최소값을 보장하지 않는다.

Lavin의 `wincnn` 생성 방식은 보간점에 따라 변환 행렬이 달라질 수 있다. 따라서 아래 수치는 모든 `F(2,5)` 구현에 공통인 절대값이 아니라, 위 행렬 선택에 대한 기준값이다.

## 2. 사용한 1차원 변환 행렬

```text
A^T = [ 1  1  1  1  1  0 ]
      [ 0  1 -1  2 -2  1 ]

B^T = [ 4  0 -5  0  1  0 ]
      [ 0 -4 -4  1  1  0 ]
      [ 0  4 -4 -1  1  0 ]
      [ 0 -2 -1  2  1  0 ]
      [ 0  2 -1 -2  1  0 ]
      [ 0  4  0 -5  0  1 ]

G   = [ 1/4    0      0      0      0   ]
      [-1/6  -1/6   -1/6   -1/6   -1/6 ]
      [-1/6   1/6   -1/6    1/6   -1/6 ]
      [ 1/24  1/12   1/6    1/3    2/3 ]
      [ 1/24 -1/12   1/6   -1/3    2/3 ]
      [ 0      0      0      0      1   ]
```

1차원 식은 다음과 같다.

```text
y = A^T [(Gg) ⊙ (B^T d)]
```

임의의 정수 입력과 필터 1,000쌍으로 직접 5-tap convolution과 비교했으며, 부동소수점 최대 절대 오차는 약 `2.27e-13`이었다.

## 3. 출력 타일 하나의 핵심 곱셈

### Direct convolution

2x2 출력에는 출력값이 4개 있고, 각 출력마다 5x5 곱셈 25회가 필요하다.

```text
4 outputs x 25 multiplications = 100 multiplications
```

입력 채널이 `C`개면 출력 채널 하나의 타일당 `100C`회다.

### Winograd

6x6으로 변환된 입력과 필터를 같은 위치끼리 곱한다.

```text
6 x 6 = 36 multiplications
```

입력 채널이 `C`개면 출력 채널 하나의 타일당 `36C`회다.

```text
100C -> 36C
곱셈 64% 감소
이론적 곱셈 수 비율: 2.78x
```

## 4. 입력 변환 오버헤드

입력 변환은 다음 식이다.

```text
V = B^T d B
```

한 1차원 길이-6 벡터의 변환은 공통부분을 재사용하면 다음과 같이 구성할 수 있다.

```text
t42 = d4 - d2
t02 = d0 - d2
v0  = 4*t02 + t42

t13 = d1 - d3
t53 = d5 - d3
v5  = 4*t13 + t53

v3  = t42 - 2*t13
v4  = t42 + 2*t13

s12 = d1 + d2
s34 = d3 + d4
v1  = s34 - 4*s12

q12 = d1 - d2
q43 = d4 - d3
v2  = q43 + 4*q12
```

1차원 변환 한 번의 연산은 다음과 같다.

```text
14 add/sub
5 shifts
일반 multiplier 0
```

6x6 2차원 변환은 열 6개와 행 6개, 총 12개 벡터에 적용한다.

```text
입력 타일 하나:
168 add/sub
60 shifts
```

입력 변환 결과는 같은 입력 타일을 사용하는 모든 출력 채널에 재사용할 수 있다.

## 5. 채널 누적 오버헤드

입력 채널이 여러 개이면 6x6 Hadamard product를 채널 방향으로 누적한다.

```text
M = sum_c (U_c ⊙ V_c)
```

출력 채널 하나의 출력 타일당:

```text
36 x (C - 1) add
```

- Conv1, `C=1`: 0 add
- Conv2, `C=3`: 72 add

## 6. 출력 변환 오버헤드

출력 변환은 다음 식이다.

```text
Y = A^T M A
```

1차원에서는 다음처럼 계산할 수 있다.

```text
y0 = m0 + m1 + m2 + m3 + m4
y1 = (m1 - m2) + 2*(m3 - m4) + m5
```

1차원 변환 한 번은 `8 add/sub + 1 shift`다. 6개 열과 2개 행, 총 8개 벡터에 적용한다.

```text
출력 타일 하나:
64 add/sub
8 shifts
```

출력 변환은 입력 채널 누적이 끝난 후 출력 채널마다 한 번 수행한다. 마지막 2x2 출력에 bias를 더하면 타일당 4 add가 추가된다.

## 7. 레이어 전체 연산량

### Conv1

```text
입력: 28x28x1
출력: 24x24x3
출력 타일: 12x12 = 144
C=1, K=3
```

| 항목 | Direct | F(2x2,5x5) |
|---|---:|---:|
| 일반 곱셈 | 43,200 | 15,552 |
| 입력 변환 add/sub | 0 | 24,192 |
| 채널 누적 add | direct 합산에 포함 | 0 |
| 출력 변환 add/sub | 0 | 27,648 |
| bias add | direct 합산에 포함 | 1,728 |
| 총 add/sub | 43,200 | 53,568 |
| shift | 0 | 12,096 |

Direct add/sub는 각 출력의 25개 product 합산과 bias 덧셈을 포함한다.

### Conv2

```text
입력: 12x12x3
출력: 8x8x3
출력 타일: 4x4 = 16
C=3, K=3
```

| 항목 | Direct | F(2x2,5x5) |
|---|---:|---:|
| 일반 곱셈 | 14,400 | 5,184 |
| 입력 변환 add/sub | 0 | 8,064 |
| 채널 누적 add | direct 합산에 포함 | 3,456 |
| 출력 변환 add/sub | 0 | 3,072 |
| bias add | direct 합산에 포함 | 192 |
| 총 add/sub | 14,400 | 14,784 |
| shift | 0 | 3,264 |

### Conv1 + Conv2 합계

| 항목 | Direct | F(2x2,5x5) | 변화 |
|---|---:|---:|---:|
| 일반 곱셈 | 57,600 | 20,736 | -64.0% |
| add/sub | 57,600 | 68,352 | +18.7% |
| shift | 0 | 15,360 | 추가 |

핵심 결과는 일반 multiplier 36,864회를 없애는 대신 add/sub 10,752회와 shift 15,360회를 추가한다는 것이다. 하지만 Winograd add/sub는 direct accumulator보다 중간 비트 폭이 커질 수 있으므로 단순 연산 개수만으로 면적과 전력을 판단하면 안 된다.

## 8. 필터 변환과 저장 오버헤드

필터 변환은 다음 식이다.

```text
U = G g G^T
```

필터는 모든 이미지와 타일에서 재사용되므로 PyTorch/내보내기 단계에서 미리 변환하여 저장하는 것이 유리하다. 따라서 추론 중에는 필터 변환 연산이 필요 없다.

저장되는 원소 개수는 필터 하나당 다음과 같이 증가한다.

```text
원래 필터: 5x5 = 25 values
변환 필터: 6x6 = 36 values
증가: 44%
```

현재 convolution 필터는 Conv1 3개, Conv2 9개로 총 12개다.

```text
원래: 12 x 25 = 300 values
변환: 12 x 36 = 432 values
증가: 132 values
```

단, 변환된 필터의 비트 폭도 증가하므로 실제 bit 저장량 증가는 44%보다 훨씬 클 수 있다.

## 9. line buffer 오버헤드

Direct 5x5 convolution은 5개 입력 행을 보관한다. `F(2,5)`는 6x6 입력 타일이 필요하므로 최소 6개 행을 보관해야 한다.

### Conv1

```text
Direct: 28 x 5 x 8-bit = 1,120 bits
Winograd: 28 x 6 x 8-bit = 1,344 bits
증가: 224 bits, +20%
```

### Conv2

```text
Direct: 3 x 12 x 5 x 12-bit = 2,160 bits
Winograd: 3 x 12 x 6 x 12-bit = 2,592 bits
증가: 432 bits, +20%
```

별도로 한 코어에서 6x6 입력 타일 또는 변환 타일 36개를 보관할 레지스터/FIFO 공간이 필요할 수 있다.

## 10. 비트 폭 오버헤드

입력 변환 `B^T d B`에는 최대 절댓값 5의 정수 계수가 포함된다. 행렬의 절댓값 합을 이용한 보수적 bound를 적용하면 8-bit unsigned 입력의 2차원 변환 결과는 약 다음 범위까지 커질 수 있다.

```text
255 x 10 x 10 = 25,500
```

따라서 입력 변환 결과에는 보수적으로 signed 16-bit가 필요하다. 실제 데이터 분포와 zero-point를 사용하면 줄일 가능성이 있다.

필터 변환 행렬 `G`에는 `1/24`, `1/12`, `1/6` 등의 분수가 존재한다. 분수를 없애기 위해 `G' = 24G`로 정수화하면:

```text
G' = [ 6   0   0   0   0 ]
     [-4  -4  -4  -4  -4 ]
     [-4   4  -4   4  -4 ]
     [ 1   2   4   8  16 ]
     [ 1  -2   4  -8  16 ]
     [ 0   0   0   0  24 ]
```

이때 `G'gG'^T = 576(GgG^T)`이므로 출력 쪽에서 576의 scale을 제거해야 한다. signed INT8 필터에 절댓값 합 bound를 적용하면 변환 가중치는 약 signed 18-bit까지 필요할 수 있다.

```text
최대 보수 bound: 128 x 31 x 31 = 123,008
```

그러면 Hadamard product와 Conv2 채널 누적은 30비트 이상으로 크게 증가할 수 있다. 이 bound는 매우 보수적이고 스케일 배치에 따라 달라지지만, `INT8 input x INT8 weight` multiplier를 단순히 36개 배치하는 구조로 끝나지 않는다는 점은 확실하다.

## 11. 현재 결론

`F(2x2,5x5)`는 베이스라인 두 convolution에서 핵심 일반 곱셈을 정확히 64% 줄인다. 그러나 동시에 다음 비용이 생긴다.

- add/sub 약 18.7% 증가
- shift 15,360회 추가
- line buffer 행 수 5개에서 6개로 증가: +20%
- 변환 필터 원소 수 25개에서 36개로 증가: +44%
- 입력 변환 결과와 변환 가중치의 비트 폭 증가
- scale 576 처리 또는 다른 정수 스케일 설계 필요

따라서 다음 설계 판단의 핵심은 곱셈 개수가 아니라 다음 식으로 봐야 한다.

```text
제거되는 8-bit direct multiplier/adder tree 비용
vs.
추가되는 wide transform adder/shift/register/requantization 비용
```

중간보고서 전에는 적어도 실제 학습 가중치와 1,000개 입력에 대해 각 transform stage의 min/max 분포를 측정해야 현실적인 비트 폭과 PPA 이득을 판단할 수 있다.

## 참고

- [Lavin and Gray, Fast Algorithms for Convolutional Neural Networks, CVPR 2016](https://openaccess.thecvf.com/content_cvpr_2016/html/Lavin_Fast_Algorithms_for_CVPR_2016_paper.html)
- [Andrew Lavin, wincnn transform generator](https://github.com/andravin/wincnn)
- [Barabasz et al., Error Analysis and Improving the Accuracy of Winograd Convolution for DNNs](https://arxiv.org/abs/1803.10986)
