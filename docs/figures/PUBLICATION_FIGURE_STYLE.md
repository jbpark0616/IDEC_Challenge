# Publication Figure Style Guide

이 프로젝트의 보고서·논문용 그래프는 아래 형식을 기본값으로 사용한다.

## 기본 원칙

- 최종 산출물은 PowerPoint와 문서에서 확대 가능한 SVG 벡터 형식으로 만든다.
- figure 내부에 전체 제목, 결론 문장, 설명 박스, 카드, 둥근 테두리 등 발표자료형 장식을 넣지 않는다.
- 보고서 본문에서 입력할 figure 제목과 caption은 그래프 내부에 중복해서 넣지 않는다.
- 흰 배경과 얇은 축·격자선을 사용하고 데이터 자체가 시각적 중심이 되게 한다.
- 데이터와 단위는 실제 시뮬레이션 및 합성 결과에서 직접 가져온다.

## Subfigure 표기

- `(a)`, `(b)`, `(c)` 표기는 각 그래프의 아래쪽 중앙에 배치한다.
- 표기 뒤에는 그래프가 나타내는 대상만 짧게 적는다.
- 예: `(a) FIFO storage`, `(b) Maximum occupancy`.
- 긴 해석이나 결론은 figure가 아니라 보고서 본문에 작성한다.

## 막대그래프

- 축 이름에는 수량과 단위를 함께 표기한다.
- 비교 기준은 중간 회색, 선택된 설계는 채도가 낮은 파란색 하나로 표시한다.
- 여러 항목을 불필요하게 서로 다른 색으로 칠하지 않는다.
- 값은 막대 바로 위에 직접 표기하며 범례가 없어도 해석 가능하게 한다.
- 0 기준선과 비교 가능한 동일 축 범위를 유지한다.

## Digital waveform

- 논리 신호는 검은색 또는 짙은 회색 step waveform으로 그린다.
- cycle 경계는 얇고 옅은 회색 세로선으로 표시한다.
- stall 등 필요한 구간만 매우 옅은 회색 배경으로 표시하며 강한 강조색은 사용하지 않는다.
- multi-bit bus는 cycle마다 상자를 반복하지 않는다.
- bus 값이 유지되는 구간을 하나로 묶고 값이 변하는 경계에 X형 transition을 표시한다.
- bus 값은 각 안정 구간 중앙에 한 번만 적는다.
- 각 waveform 비교의 `(a)`, `(b)` 설명은 파형 아래에 배치한다.

## 글꼴과 선

- 기본 글꼴은 Arial이며 한글 fallback으로 Noto Sans KR을 사용한다.
- 본문 label은 15 px, tick과 직접 표기 값은 13 px를 기준으로 한다.
- 축과 grid는 1 px, digital waveform은 약 1.8 px를 기준으로 한다.
- 굵은 글꼴은 subfigure caption처럼 구조를 구분할 때만 제한적으로 사용한다.

## 재현성

- figure와 함께 원본 CSV, 시뮬레이션 로그, 합성 보고서 및 생성 스크립트를 보존한다.
- figure의 수치를 수동으로 다시 입력하지 않고 가능한 한 CSV에서 읽어 생성한다.
- 생성 후 모든 SVG가 정상 XML인지 검증한다.

현재 기준 구현은 `fifo_depth_optimization/generate_fifo_depth_figures.js`에 있다.

## 아키텍처 다이어그램

- 발표자료형 장식보다 하드웨어 계층과 데이터 경계를 먼저 보여준다.
- 최상위 accelerator, 재사용 가능한 core, compute datapath, functional unit 순으로 경계를 중첩한다.
- 외부 모델 파라미터와 입출력 인터페이스는 accelerator 외곽에 배치하여 칩 경계를 명확히 한다.
- 재사용 단위는 하나의 닫힌 사각형으로 묶고, 향후 멀티코어 확장 시 그 사각형을 그대로 복제할 수 있게 표현한다.
- 데이터 흐름은 기본적으로 왼쪽에서 오른쪽, 로컬 저장소는 datapath 아래에 배치한다.
- 제어기는 상단에 배치하고 제어선은 옅은 점선으로 표현하여 주 데이터 경로보다 시각적 우선순위를 낮춘다.
- 블록 내부에는 이름과 핵심 구조만 남긴다. 비트폭, mode, 세부 동작 설명은 데이터선 옆의 짧은 label 또는 본문으로 이동한다.
- operation fusion은 긴 설명 대신 별도의 옅은 기능 영역과 짧은 이름으로 표시한다.
- 현재 전체 아키텍처의 기준 구성은 `winograd_cnn_architecture_publication.svg`를 따른다.

## RTL 마이크로아키텍처 회로도

- 블록 나열이 아니라 실제 RTL의 조합논리, 레지스터, feedback, enable 관계가 보이는 회로도로 그린다.
- MUX는 사다리꼴, multiplier와 adder는 원형 `×`, `+`, register는 clock 표식이 있는 사각형으로 표현한다.
- comparator는 `= 0`과 같이 조건을 직접 적고, AND/OR 등 논리 결합은 표준 논리 게이트 기호를 사용한다.
- 데이터선은 검은색 실선 약 1.8 px, 제어선은 짙은 회색 점선 약 1.2 px로 구분한다.
- 분기점에는 작은 node를 두며, 같은 값을 병렬 저장하는 레지스터를 직렬 연결처럼 그리지 않는다.
- saturation, sign extension 등 구현 정책은 회로 기호를 복잡하게 만들지 않는다. adder는 `+`로 표시하고 세부 정책은 본문이나 caption에서 설명한다.
- zero-weight 최적화는 실제 구현 의미에 맞춰 `operand isolation` 또는 `zero-weight gating`으로 표기한다. 사이클을 제거하지 않는 구조를 `zero-skip`이라고 부르지 않는다.
- 기능 영역은 매우 옅은 배경색으로만 구분한다. 현재 기준 색상은 다음과 같다.
  - MAC / channel reduction: fill `#F1F5F8`, stroke `#7F95A5`
  - Operation fusion: fill `#FBF6E8`, stroke `#B4A675`
  - Register: fill `#F0F1F2`, stroke `#111111`
  - 일반 symbol: fill `#FFFFFF`, stroke `#111111`
- fusion 영역은 기본 연산 영역 안에 중첩하여, 별도 후처리 블록이 아니라 datapath에 결합된 연산임을 보여준다.
- 파이프라인은 register 자체로 경계를 나타내며, 강조가 필요할 때만 register 출력 직후에 옅은 세로 점선 하나를 추가한다.
- pipeline stage 이름은 그림 상단에 작게 배치하고, `Stage 1 · Multiply`, `Stage 2 · Reduction and fusion`처럼 짧게 쓴다.
- 세로 stage boundary 기준은 stroke `#999999`, width 1 px, dash `4 4`를 사용한다.
- 회로 아래 타임라인이 필요하면 회로의 register와 동일한 stage 이름을 사용한 cycle table로 정렬한다. 별도의 장식형 waveform이나 설명 박스를 만들지 않는다.
- 현재 RTL 회로도의 기준 구성은 `winograd_mac_array_microarchitecture.svg`를 따른다.

## 피겨 작성 순서

1. RTL에서 조합논리 경로, register 경계, feedback, 병렬 분기를 먼저 확인한다.
2. 전체 아키텍처에서는 재사용 단위와 외부 인터페이스 경계를 먼저 고정한다.
3. 회로도에서는 표준 symbol만 배치하고 데이터선과 제어선을 분리한다.
4. architecture idea가 있는 부분만 옅은 배경으로 그룹화한다.
5. 그림 안의 설명을 최소화하고 saturation, bit policy, 조건식은 본문으로 이동한다.
6. SVG XML 검증 후 실제 RTL과 신호별로 다시 대조한다.
