# Winograd CNN 논문 읽기 목록

이 문서는 2026 KNU IDEC CCDC 준비를 위한 Winograd convolution 학습 순서와 논문별 핵심 확인 사항을 정리한다.

## 먼저 읽을 3편

### 1. Fast Algorithms for Convolutional Neural Networks

- 저자: Andrew Lavin, Scott Gray
- 학회: CVPR 2016
- 역할: Winograd 최소 필터링을 CNN convolution에 적용한 대표 논문
- [논문 페이지](https://openaccess.thecvf.com/content_cvpr_2016/html/Lavin_Fast_Algorithms_for_CVPR_2016_paper.html)
- [PDF](https://openaccess.thecvf.com/content_cvpr_2016/papers/Lavin_Fast_Algorithms_for_CVPR_2016_paper.pdf)

읽으면서 확인할 것:

1. `F(m, r)`에서 `m`과 `r`이 각각 무엇인지
2. 입력 타일 크기가 `m + r - 1`이 되는 이유
3. `F(2, 3)`이 직접 convolution보다 곱셈을 얼마나 줄이는지
4. 아래 식의 세 변환이 각각 무엇을 하는지

   ```text
   Y = A^T [(GgG^T) ⊙ (B^T d B)] A
   ```

5. 1차원 알고리즘이 2차원 convolution으로 확장되는 방식
6. 여러 입력 채널의 결과를 어느 단계에서 누적하는지
7. 인접 출력 타일을 계산할 때 입력 타일이 겹치는 방식
8. 곱셈 감소 대신 추가되는 변환, 덧셈, 메모리 비용

> 첫 번째 목표는 이 논문의 `F(2, 3)`을 Python으로 구현하고 일반 convolution 결과와 비교하는 것이다.

### 2. Efficient Winograd Convolution via Integer Arithmetic

- 저자: Lingchuan Meng, John Brothers
- 연도: 2019
- 역할: Winograd를 정수 연산 및 하드웨어 관점에서 이해하기 위한 핵심 논문
- [arXiv](https://arxiv.org/abs/1901.01965)

읽으면서 확인할 것:

- 변환 행렬의 분수 계수를 정수 연산으로 바꾸는 방법
- 입력, 가중치, 변환 결과, element-wise product, accumulator의 비트 폭
- 스케일 인자를 어느 단계에서 적용하거나 제거하는지
- 직접 convolution과 비교했을 때 정수 Winograd의 추가 하드웨어 비용
- overflow, rounding, truncation이 정확도에 미치는 영향

### 3. Searching for Winograd-aware Quantized Networks

- 저자: Javier Fernandez-Marques 외
- 학회: MLSys 2020
- 역할: Winograd 변환과 quantization을 함께 고려하는 학습 방법을 이해하기 위한 대표 논문
- [공식 PDF](https://proceedings.mlsys.org/paper_files/paper/2020/file/678e209691cd37f145a5502695378bac-Paper.pdf)

읽으면서 확인할 것:

- 일반적인 INT8 quantization을 Winograd에 그대로 적용하기 어려운 이유
- spatial-domain weight와 Winograd-domain weight의 분포 차이
- fake quantization을 연산 그래프의 어느 지점에 넣는지
- Winograd-aware training 또는 QAT가 보상하는 오차
- bit width, tile size, 정확도 사이의 trade-off

## 다음으로 읽을 논문

### 4. Error Analysis and Improving the Accuracy of Winograd Convolution for DNNs

- 저자: B. Barabasz 외
- 연도: 2018
- 역할: Winograd의 수치 오차와 tile 크기에 따른 안정성 분석
- [arXiv](https://arxiv.org/abs/1803.10986)

현재 프로젝트에서 볼 부분:

- tile이 커질수록 수치 오차가 증가하는 이유
- transform coefficient와 중간값의 동적 범위
- 제한된 비트 폭에서 정확도를 유지하기 위한 방법

### 5. Evaluating Fast Algorithms for Convolutional Neural Networks on FPGAs

- 저자: Liqiang Lu, Yun Liang, Qingcheng Xiao, Shengen Yan
- 역할: FPGA에서 Winograd 계열 알고리즘의 실제 구조와 자원 trade-off를 살펴보기 위한 논문
- [PDF](https://ceca.pku.edu.cn/docs/20200915215234099363.pdf)

현재 프로젝트에서 볼 부분:

- processing element와 데이터 경로 구성
- transform, element-wise multiplication, channel accumulation의 파이프라이닝
- DSP, BRAM, bandwidth 사용량
- 타일과 채널 병렬화 방식

### 6. Winograd Convolution for Deep Neural Networks: Efficient Point Selection

- 저자: B. Barabasz, D. Gregg
- 연도: 2019
- 역할: Winograd/Toom-Cook 용어와 변환 행렬 생성 원리를 더 정확히 이해하기 위한 논문
- [arXiv](https://arxiv.org/abs/1905.05233)

현재 프로젝트에서 볼 부분:

- interpolation point 선택이 변환 행렬과 수치 안정성에 미치는 영향
- 일반적인 DNN 문헌에서 Winograd와 Toom-Cook이라는 이름이 사용되는 방식
- 5x5 kernel용 알고리즘을 검토할 때 변환 행렬을 어떻게 구성할지

## 이론의 출발점

### Arithmetic Complexity of Computations

- 저자: Shmuel Winograd
- 출판: SIAM, 1980
- 역할: 최소 곱셈 알고리즘의 이론적 원전
- [Google Books](https://books.google.com/books?id=ymwZAQAAIAAJ)

처음부터 완독할 필요는 없다. CNN 적용을 먼저 이해한 뒤 최소 필터링의 이론적 근거가 필요할 때 참고한다.

## 권장 학습 순서

```text
Lavin & Gray
    ↓
Python F(2, 3) 구현 및 직접 convolution과 비교
    ↓
Meng & Brothers
    ↓
정수형 비트 폭 및 중간값 범위 실험
    ↓
Fernandez-Marques et al.
    ↓
Winograd-aware quantization/QAT 실험
    ↓
수치 오차 논문 + FPGA 구조 논문
    ↓
현재 베이스라인의 5x5 convolution에 적용할 구조 결정
```

## 대회 프로젝트에 적용할 때 주의할 점

- 현재 베이스라인의 convolution kernel은 5x5이므로, 논문에서 흔히 다루는 `F(2, 3)` 결과를 그대로 적용할 수 없다.
- 먼저 `F(2, 3)`으로 수식과 구현을 검증한 뒤 `F(2, 5)` 후보를 검토한다.
- `F(2, 5)`는 6x6 입력 타일에서 2x2 출력을 만들며, 직접 계산의 타일당 100회 곱셈을 element-wise 곱셈 36회로 줄일 가능성이 있다. 단, 변환 비용과 채널 누적 비용은 별도로 계산해야 한다.
- 하드웨어 설계 전 입력, 가중치, 변환 결과, 곱셈 결과, accumulator, 최종 출력 각각의 비트 폭을 독립적으로 정해야 한다.
- 정확도 비교 기준은 최종 분류 정확도만이 아니라 layer별 출력 오차와 overflow 발생 횟수까지 포함하는 것이 좋다.

## 당장 할 일

1. Lavin & Gray 논문의 `F(2, 3)` 부분을 읽는다.
2. 위의 여덟 가지 질문에 답을 적는다.
3. PyTorch 또는 NumPy로 한 타일의 `F(2, 3)`을 구현한다.
4. 일반 `conv2d`와 부동소수점 결과가 일치하는지 확인한다.
5. 그 다음에만 정수화와 5x5 확장을 시작한다.
