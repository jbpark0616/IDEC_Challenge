# W4A8 3x3 Winograd CNN 학습 및 정수 검증 환경

이 디렉터리는 대회 지정주제용 MNIST CNN을 다음 순서로 개발하고 검증한
PyTorch 환경이다.

```text
공식 5x5 모델 분석
    -> 3x3 spatial CNN 사전학습
    -> Winograd F(2x2, 3x3) 수학 동치 검증
    -> Winograd-aware W4A8 QAT
    -> 정수 골든 모델
    -> 중간 연산 비트폭 sweep
    -> 정수 weight/bias/scale export
    -> export 파일 round-trip 검증
```

최종 W4A8 정수 모델은 대회 입력 1,000장에서 **97.00%**, MNIST test set
10,000장에서 **96.25%** 정확도를 기록한다. Export된 TXT/HEX 파일을 다시
읽은 결과는 checkpoint 기반 정수 추론과 prediction 및 모든 logit이 동일하다.

## 1. 실행 환경

WSL이 아닌 Windows 네이티브 Python 환경을 사용한다.

```text
Python       3.12
PyTorch      2.13.0+cpu
torchvision  0.28.0+cpu
Environment  C:\Users\jbpar\miniconda3\envs\idec-winograd
```

이 README의 명령은 저장소 루트 `C:\IDEC_challenge`에서 실행한다.

```powershell
$PYTHON = 'C:\Users\jbpar\miniconda3\envs\idec-winograd\python.exe'
```

## 2. 최종 CNN 구조

공식 모델의 두 convolution, 두 max-pooling, FC라는 큰 구조와 채널 수 3은
유지하고 convolution kernel만 5x5에서 3x3으로 변경했다.

```text
Input                  1 x 28 x 28
Conv1, valid 3x3       3 x 26 x 26
MaxPool 2x2 + ReLU     3 x 13 x 13
Conv2, valid 3x3       3 x 11 x 11
MaxPool 2x2 + ReLU     3 x  5 x  5
Flatten                75
Fully connected        10
Argmax                 digit 0..9
```

`Spatial3x3`과 `Winograd3x3`은 state-dict key가 같다. 따라서 spatial
convolution으로 학습한 checkpoint를 변환 없이 Winograd 모델에 로드할 수
있다.

## 3. Winograd 연산

두 convolution은 `F(2x2, 3x3)`을 사용한다.

```text
U = G g G^T       transformed weight, 4x4
V = B^T d B       transformed activation tile, 4x4
M = sum_c(U odot V)
Y = A^T M A       output tile, 2x2
```

- `g`: 학습되는 spatial 3x3 master weight
- `U`: forward와 정수 추론에서 사용하는 transformed 4x4 weight
- `V`: 4x4 activation tile의 입력 변환 결과
- `M`: element-wise product의 입력 채널 reduction 결과
- `Y`: 복원된 2x2 출력 tile

PyTorch `Conv2d`는 수학적인 convolution이 아니라 cross-correlation을
수행하며, 현재 Winograd 식도 같은 convention을 따른다. 출력 크기가
11x11처럼 홀수인 경우 마지막 tile만 오른쪽/아래쪽에 zero padding한 뒤
복원 결과를 crop한다.

`test_winograd.py`는 일반 `torch.nn.functional.conv2d`와 Winograd 결과가
float64 기준 `1e-12` 오차 안에서 일치하는지 검증한다. 전체 CNN logit 동치와
역전파는 `test_models.py`에서 검증한다.

## 4. 학습과 QAT 방식

### 4.1 FP32 사전학습

먼저 `Spatial3x3`을 FP32로 학습한다. 최종 채택 run은 다음 설정을 사용했다.

```text
optimizer       SGD
initial LR      0.02
momentum        0.9
epochs          25
LR milestones   12, 20
LR gamma        0.2
seed            1
best epoch      19
best accuracy   97.03%
```

### 4.2 Winograd-aware W4A8 QAT

FP32 checkpoint를 QAT 모델에 로드한 뒤 다음 forward를 사용해 fine-tuning했다.

```text
FP32 spatial master weight g
    -> U = G g G^T
    -> signed INT4 fake quantization of U
    -> Winograd convolution
    -> unsigned INT8 fake quantization of stored activation
```

FC weight도 signed INT4 fake quantization을 사용한다. `round()` 때문에 끊기는
gradient는 STE(straight-through estimator)로 FP32 master weight에 전달한다.
따라서 마지막에 weight를 한 번 잘라내는 단순 PTQ가 아니라, 학습 중 매
forward에서 양자화 오차를 경험하는 QAT다.

먼저 INT8 QAT checkpoint를 만든 뒤, INT4 fine-tuning과 observer scale 고정
학습을 적용했다. 최종 단계의 설정과 결과는 다음과 같다.

```text
initial checkpoint  runs/qat_winograd3x3_w4.pt
optimizer           Adam
initial LR          0.0001
epochs              10
LR milestones       5, 8
LR gamma            0.2
augmentation        enabled
observer freeze     epoch 0
seed                 42
best epoch          5
best accuracy       96.25%
```

Bias는 QAT 중 FP32 master 값으로 유지하고, 학습 후 해당 accumulator scale로
나눠 정수화했다.

## 5. 최종 동결 수치 형식

지정주제에 사용할 수치 형식은 다음과 같이 동결했다.

| 데이터 | 형식 | 선택 근거 |
|---|---:|---|
| 입력 및 저장 activation | unsigned 8-bit | 인터페이스 및 activation QAT |
| Winograd `U` | signed 4-bit | transformed-weight QAT |
| Winograd `V` | signed 11-bit | 관측 범위 `-510..1020`의 최소 signed 폭 |
| Product 및 compute | signed 18-bit | 10,000장 saturation 0회 |
| Bias 저장 | signed 16-bit | 실제 필요 폭 최대 14-bit + 구현 여유 |

16-bit bias는 compute 경로에 들어갈 때 signed 18-bit로 sign-extension한다.
Activation CB와 activation 저장소에는 requantization 이후 unsigned 8-bit
값만 저장한다. 11/18-bit 값은 Winograd 연산기의 중간 경로에만 존재한다.

### 5.1 관측된 정수 범위

| 구간 | 관측 범위 | 필요한 signed 폭 |
|---|---:|---:|
| Conv1 `V` | `-510..1020` | 11 |
| Conv1 product | `-3570..3570` | 13 |
| Conv1 output + bias | `-5128..2904` | 14 |
| Conv2 `V` | `-473..683` | 11 |
| Conv2 product | `-4781..2838` | 14 |
| Conv2 `M` | `-5418..3763` | 14 |
| Conv2 output + bias | `-5103..2347` | 14 |
| FC accumulator + bias | `-4859..4933` | 14 |

### 5.2 Compute 비트폭 sweep

각 채널 add, 출력변환 adder, bias add, FC의 75회 순차 누산 직후에 해당
비트폭의 signed saturation을 적용했다.

| Compute 폭 | 정확도 | Saturation | 판단 |
|---:|---:|---:|---|
| 18-bit | 96.25% | 0 | 최종 채택 |
| 14-bit | 96.25% | 0 | 관측 데이터 기준 최소 폭 |
| 13-bit | 96.25% | 60,645 | 데이터 의존적 clipping 발생 |
| 12-bit | 93.68% | 1,532,583 | 정확도 저하 |

14-bit까지는 평가 데이터에서 saturation이 없었지만 관측 데이터에 의존한
결과다. RTL은 추가 입력에 대한 여유를 확보하기 위해 18-bit를 채택했다.

근거 JSON은 다음과 같다.

- `runs/integer_inference_w4_int12.json` ~ `integer_inference_w4_int18.json`
- `../docs/numerical_precision/w4_compute_width_sweep.csv`

## 6. Requantization

Conv 출력은 18-bit 정수 영역에서 bias, max-pooling, ReLU를 처리한 뒤 다음
레이어용 unsigned INT8 activation으로 requantize한다.

```text
q_out = saturate_u8((q_acc * multiplier + 2^(shift-1)) >> shift)
```

현재 동결 상수는 다음과 같다.

```text
fractional shift  24
Conv1 multiplier  1616163
Conv2 multiplier  1827841
```

상세 scale과 rounding 규칙은 export 패키지의 `manifest.json`에 기록된다.

## 7. 재현된 정확도

모든 정확도는 MNIST test set 10,000장 기준이다.

| 단계 | 정확도 |
|---|---:|
| 공식 대회 baseline | 96.00% |
| FP32 spatial 3x3 | 97.03% |
| Winograd INT8 QAT | 97.03% |
| 최종 W4A8 QAT checkpoint | 96.25% |
| W4A8 INT18 bit-accurate profile | 96.25% |
| W4A8 export TXT/HEX round-trip | 96.25% |

보존할 핵심 checkpoint와 history는 다음과 같다.

- `runs/spatial3x3_97.pt`
- `runs/spatial3x3_97_history.json`
- `runs/qat_winograd3x3_w4_frozen_aug.pt`
- `runs/qat_winograd3x3_w4_frozen_aug_history.json`

## 8. 정수 모델 export

최종 export 위치는 `export/qat_winograd3x3_w4_frozen_aug/`이다.

주요 파일:

```text
manifest.json
conv1_u_signed.txt
conv1_u_twos_complement.hex
conv1_bias_signed.txt
conv1_bias_twos_complement.hex
conv2_u_signed.txt
conv2_u_twos_complement.hex
conv2_bias_signed.txt
conv2_bias_twos_complement.hex
fc_weight_signed.txt
fc_weight_twos_complement.hex
fc_bias_signed.txt
fc_bias_twos_complement.hex
conv1_g_fp32.txt
conv2_g_fp32.txt
predictions_10000.txt
labels_10000.txt
roundtrip_report.json
competition_predictions_1000.txt
competition_labels_1000.txt
competition_1000_report.json
```

- `U` 배열 순서: `[output_channel][input_channel][row][column]`
- FC weight 순서: `[output_class][input_feature]`
- Flatten 순서: `[channel][row][column]`
- Signed TXT: 사람이 읽고 Python에서 검증하기 위한 정수값
- HEX: 같은 값을 해당 비트폭의 2의 보수로 표현
- `g_fp32`: 학습 추적용이며 정수 추론에는 사용하지 않음

Round-trip 결과:

```text
export accuracy                    96.25% (9625/10000)
prediction mismatch vs checkpoint 0
integer logit mismatch             0
HEX vs signed TXT mismatch         0
```

### 8.1 공식 대회 1000장 입력 검증

`data/input_1000.txt`는 8-bit HEX 픽셀 784,000개로 구성되며, 이미지 한 장은
28x28 row-major 순서의 784픽셀이다. 대회 `top_tb_1000`과 동일하게 이미지
인덱스의 `mod 10`을 정답으로 사용했다.

Export된 정수 파라미터만 다시 읽어 추론한 결과는 다음과 같다.

```text
competition input accuracy  97.00% (970/1000)
input images                1000
pixels per image            784
HEX vs signed TXT mismatch  0
INT18 saturation            0
```

이 결과로 대회 입력의 픽셀 값, 28x28 row-major 순서, `index % 10` label 규칙과
현재 정수 골든 모델이 서로 맞는 것을 확인했다. 개별 `0_0.txt`~`9_0.txt`는
`input_1000.txt`의 첫 10장을 복제한 파일이 아니므로 순서 판정에 사용하지 않는다.

### 8.2 공격형 비트폭 탐색

`sweep_competition_bitwidths.py`로 공식 1000장과 전체 MNIST 10,000장을
교차 검증한다. 현재 가장 유력한 공격형 후보는 Activation 8-bit, Winograd U
6-bit, V 11-bit, compute 17-bit, bias 13-bit, FC weight 6-bit다.

| 형식 | 공식 1000장 | MNIST 10,000장 |
|---|---:|---:|
| 기존 8/11/18/16, FC W8 | 99.00% | 97.02% |
| 공격형 U6/V11/C17/B13, FC W6 | 99.00% | 96.89% |

V를 10-bit로 줄이면 공식 입력 정확도가 93%로 떨어졌으므로 V는 11-bit를
유지한다. 공격형 후보의 정수 코드는 scale을 다시 계산한 PTQ 결과이며, 최종
채택 시 해당 scale, bias, requant multiplier를 별도 export해야 한다.

### 8.3 최종 W4A8 Winograd QAT

하드웨어 효과가 명확한 4-bit weight를 위해 원래 3x3 FP32 master kernel은
유지하고, 학습 forward에서 변환된 `U=GgG^T`와 FC weight를 signed INT4로
fake quantization했다. Activation은 UINT8, V는 INT11, compute는 INT18,
bias 저장은 INT16을 유지했다.

| 실험 | 공식 1000장 | MNIST 10,000장 |
|---|---:|---:|
| W4A8 PTQ | 94.00% | 95.21% |
| 첫 W4A8 QAT | 94.00% | 96.19% |
| scale 고정 + augmentation W4A8 QAT | **97.00%** | **96.25%** |

최종 INT4 checkpoint는 `runs/qat_winograd3x3_w4_frozen_aug.pt`, export는
`export/qat_winograd3x3_w4_frozen_aug/`이다. Export TXT/HEX round-trip에서
prediction, integer logit, HEX 값 mismatch는 모두 0이다. 전체 10,000장의
INT18 정수 추론에서도 모든 단계의 saturation은 0회였다.

관측된 최대 필요 폭은 Conv1/Conv2/FC의 주요 compute 경로에서 14-bit였지만,
데이터 의존적인 관측값이므로 최종 RTL은 INT18 compute 경로를 유지했다.

## 9. 주요 소스 파일

| 파일 | 역할 |
|---|---|
| `models.py` | 5x5 baseline, spatial 3x3, Winograd, QAT 모델 정의 |
| `winograd.py` | 읽기 쉬운 FP32 Winograd 골든 연산 |
| `quantization.py` | EMA observer와 STE fake quantizer |
| `train.py` | FP32 및 QAT 학습, 최고 checkpoint 저장 |
| `evaluate.py` | checkpoint의 10,000장 평가 |
| `integer_inference.py` | 정수 골든 모델, range 측정, 비트폭 제한 |
| `export_model.py` | 정수 TXT/HEX 및 manifest 생성 |
| `evaluate_export.py` | export 파일 round-trip 및 logit 동치 검증 |
| `evaluate_competition_input.py` | 대회 `input_1000.txt`의 입력 순서 및 정수 정확도 검증 |
| `sweep_competition_bitwidths.py` | 공식 1000장 및 MNIST 전체의 공격형 비트폭 sweep |
| `plots/plot_bitwidth_selection.py` | 보고서용 비트폭 근거 피겨 생성 |
| `test_*.py` | 수학 동치, gradient, QAT, 정수 primitive 검증 |

## 10. 핵심 재현 명령

### 전체 테스트

```powershell
& $PYTHON training\test_winograd.py
& $PYTHON training\test_models.py
& $PYTHON training\test_quantization.py
& $PYTHON training\test_integer_inference.py
```

### 최종 FP32 모델 재학습

```powershell
& $PYTHON training\train.py --model spatial3x3 --epochs 25 --optimizer sgd --lr 0.02 --momentum 0.9 --lr-milestones 12,20 --lr-gamma 0.2 --run-name spatial3x3_97 --seed 1
```

### INT8 사전 QAT 모델 재학습

```powershell
& $PYTHON training\train.py --model qat_winograd3x3 --epochs 8 --optimizer sgd --lr 0.001 --momentum 0.9 --lr-milestones 4,7 --lr-gamma 0.2 --run-name qat_winograd3x3_97 --init-checkpoint training\runs\spatial3x3_97.pt --seed 1
```

### INT4 Winograd QAT fine-tuning

```powershell
& $PYTHON training\train.py --model qat_winograd3x3 --weight-bits 4 --epochs 8 --batch-size 128 --optimizer sgd --lr 0.0005 --momentum 0.9 --lr-milestones 4,7 --lr-gamma 0.2 --run-name qat_winograd3x3_w4 --init-checkpoint training\runs\qat_winograd3x3_97.pt --seed 1
& $PYTHON training\train.py --model qat_winograd3x3 --weight-bits 4 --epochs 10 --batch-size 128 --optimizer adam --lr 0.0001 --lr-milestones 5,8 --lr-gamma 0.2 --augment --freeze-observers-after 0 --run-name qat_winograd3x3_w4_frozen_aug --init-checkpoint training\runs\qat_winograd3x3_w4.pt --seed 42
& $PYTHON training\export_model.py --checkpoint training\runs\qat_winograd3x3_w4_frozen_aug.pt --output-dir training\export\qat_winograd3x3_w4_frozen_aug
& $PYTHON training\evaluate_export.py --export-dir training\export\qat_winograd3x3_w4_frozen_aug
& $PYTHON training\evaluate_competition_input.py --export-dir training\export\qat_winograd3x3_w4_frozen_aug --input-file data\input_1000.txt
```

### 최종 checkpoint와 정수 모델 평가

```powershell
& $PYTHON training\evaluate.py --model qat_winograd3x3 --checkpoint training\runs\qat_winograd3x3_w4_frozen_aug.pt
& $PYTHON training\integer_inference.py --checkpoint training\runs\qat_winograd3x3_w4_frozen_aug.pt --profile int18 --report training\runs\integer_inference_w4_int18.json
```

### Export 및 round-trip 검증

```powershell
& $PYTHON training\export_model.py --checkpoint training\runs\qat_winograd3x3_w4_frozen_aug.pt --output-dir training\export\qat_winograd3x3_w4_frozen_aug
& $PYTHON training\evaluate_export.py --export-dir training\export\qat_winograd3x3_w4_frozen_aug
& $PYTHON training\evaluate_competition_input.py --export-dir training\export\qat_winograd3x3_w4_frozen_aug --input-file data\input_1000.txt
```

### 보고서 피겨 재생성

```powershell
& $PYTHON training\plots\plot_bitwidth_selection.py
```

출력:

- `docs/figures/winograd_bitwidth_selection.png`
- `docs/figures/winograd_bitwidth_selection.pdf`

## 11. 현재 상태

PyTorch 측에서 다음 항목은 완료됐다.

- 일반 convolution과 Winograd의 수학적 동치
- 전체 CNN logit 동치 및 gradient 전달
- FP32 사전학습과 Winograd-aware W4A8 QAT
- Bias를 포함한 정수 골든 추론
- INT18 연산 순서별 saturation 검증
- 비트폭 sweep과 선택 근거
- Signed TXT/2의 보수 HEX export
- Export 패키지의 10,000장 round-trip 동치

현재 동결된 모델과 정수 규칙을 변경하면 checkpoint, range report, export,
round-trip 결과를 모두 다시 생성해야 한다.
