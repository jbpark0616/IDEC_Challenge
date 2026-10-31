# CNN / Winograd 가속기 논문 모음

최종 갱신: 2026-10-27. 기존 정리본 14편 + 추가 4편 = **18편**.

SRAM CB의 재사용·반환·multicast 제어는 **Buffets → Eyeriss v2의 연결망** 순서로 참고한다.
현재 4코어에 적용할 범위와 Tenstorrent 공식 API 대조는
[SRAM/CB 설계안 V2](../../free_topic_vgg/architecture/SRAM_CB_MULTICAST_V2.txt)에 정리했다. RTL 구현 결과와는 구분한다.

추가한 **Cnvlutin / Eyeriss v2 / MAERI**의 원문 기반 요약과 읽을 페이지는
[한국어 읽기 노트](SPARSE_DATAFLOW_READING_NOTES_KO.txt)에 정리했다.
현재 자유주제의 행별 sparsity 처리, SRAM 공급, multicast/reduction 관점에서는
**Cnvlutin → Eyeriss v2 → MAERI** 순서로 읽는다. 아래 최초 연구 후보·목록은 역사적 맥락을 유지한다.

`docs/`에 있던 원본 사본은 유지하고, `docs/papers/` 내부 파일만 주제별로 이동했다. NVDLA HTML과 부속 파일도 기존 경로를 유지했다.

## 현재 주제와 읽는 순서

연구 후보: **Winograd 타일 내부의 정확한 수학적 관계를 검출해 변환과 MAC의 불필요한 활동을 줄이는 회로**. MNIST는 평가 데이터이며 정확성의 전제가 아니다. 독창성과 순 에너지 개선은 아직 검증되지 않았다.

1. **SCNN / ISCA 2017**: sparse CNN 하드웨어의 대표 사례. Winograd 전용은 아니다.
2. **Efficient Sparse-Winograd / ICLR 2018**: 변환과 sparsity의 관계, 모델 변경 여부 확인.
3. **SpWA / DAC 2018**: sparse Winograd 하드웨어 구현 비교.
4. **WRA-SS / IEEE TVLSI 2024**: 구조적 sparsity와의 중복 여부 확인. **PDF 미확보**.
5. **DREW / IEEE TKDE 2023**: 타일 간 근사 재사용과 타일 내부의 정확한 관계 검출을 구분.
6. **DeltaCNN / CVPR 2022**: 영상의 프레임 간 차분을 쓰는 별도 확장 후보.

DAC는 회로·설계자동화, TVLSI는 VLSI 설계, ICLR/CVPR은 머신러닝·컴퓨터비전, TKDE는 데이터·지식공학 분야의 발표처다. 발표처의 신뢰도와 회로에 대한 직접 관련성은 별도로 판단한다.

## 폴더 구성

| 폴더 | 내용 | PDF 수 |
|---|---|---:|
| `01_winograd_foundations/` | 알고리즘 기초 | 1 |
| `02_winograd_hardware/` | 연산기·메모리·병렬화 | 4 |
| `03_sparsity_patterns/` | sparsity·패턴·계산 재사용 | 5 |
| `04_temporal_reuse/` | 프레임 간 재사용·DeltaCNN | 2 |
| `05_memory_dataflow_fusion/` | 데이터 이동·연산 결합 | 5 |
| `06_circuit_reference/` | FIFO 등 기술 자료 | 1 |
| `nvdla/` | 공식 HTML 문서 | — |

## 01. Winograd 알고리즘 기초

- **Lavin & Gray, Fast Algorithms for Convolutional Neural Networks — CVPR 2016**: [PDF](01_winograd_foundations/Lavin_Fast_Algorithms_for_CVPR_2016_paper.pdf) · [CVF](https://openaccess.thecvf.com/content_cvpr_2016/html/Lavin_Fast_Algorithms_for_CVPR_2016_paper.html).

## 02. Winograd 하드웨어

- **Lu et al., Evaluating Fast Algorithms for Convolutional Neural Networks on FPGAs — FCCM 2017**: [PDF](02_winograd_hardware/Evaluating_Fast_Algorithms_for_Convolution_Neural_Networks_onFPGAs.pdf) · [기관 공개본](https://ceca.pku.edu.cn/media/lw/6940b5b0e09259131ff19334f3efeecd.pdf). 기존 목록의 FPGA 2017 표기를 수정했다. 보관본은 8페이지다.
- **Aydonat et al., An OpenCL Deep Learning Accelerator on Arria 10 — FPGA 2017**: [PDF](02_winograd_hardware/Aydonat_2017_An_OpenCL_Deep_Learning_Accelerator_on_Arria_10.pdf) · [arXiv](https://arxiv.org/abs/1701.03534).
- **Hattink et al., A Scalable Architecture for CNN Accelerators Leveraging High-Performance Memories — HPEC 2020**: [PDF](02_winograd_hardware/A_Scalable_Architecture_for_CNN_Accelerators.pdf) · [저자 공개본](https://www.cs.columbia.edu/~luca/research/hattink_HPEC20.pdf).
- **Liu et al., WinoCNN: Kernel Sharing Winograd Systolic Array for Efficient Convolutional Neural Network Acceleration on FPGAs — 2021 공개본**: [PDF](02_winograd_hardware/Liu_2021_WinoCNN.pdf) · [arXiv](https://arxiv.org/abs/2107.04244). 파일명 `2107.04244v1.pdf`를 알아보기 쉽게 변경했다.

## 03. Sparsity와 타일 패턴

- **Albericio et al., Cnvlutin: Ineffectual-Neuron-Free Deep Neural Network Computing — ISCA 2016**: [PDF](03_sparsity_patterns/Albericio_2016_Cnvlutin_ISCA.pdf) · [저자 공개본](https://www.eecg.toronto.edu/~enright/albericio-isca2016.pdf). 독립 lane 그룹, nonzero+offset, bank별 Brick Buffer/prefetch. 단순 압축 용량 절감 논문과 구분한다.

- **Parashar et al., SCNN: An Accelerator for Compressed-Sparse Convolutional Neural Networks — ISCA 2017**: [PDF](03_sparsity_patterns/Parashar_2017_SCNN_ISCA.pdf) · [arXiv 공개본](https://arxiv.org/abs/1708.04485). Activation·weight sparsity를 데이터 공급·곱셈·누적에 연결하는 대표 비교 자료.

| 자료 | 발표처 | 파일 / 출처 | 읽을 관점 |
|---|---|---|---|
| Lu & Liang, SpWA: An Efficient Sparse Winograd Convolutional Neural Networks Accelerator on FPGAs | DAC 2018 | [PDF](03_sparsity_patterns/Lu_2018_SpWA_DAC.pdf) · [저자 공개본](https://liqianglu-zju.github.io/files/conference/2018/DAC_2018_SpWA.pdf) | sparse Winograd 하드웨어와 제어 비용 |
| Liu et al., Efficient Sparse-Winograd Convolutional Neural Networks | ICLR 2018 | [PDF](03_sparsity_patterns/Liu_2018_Efficient_Sparse_Winograd_ICLR.pdf) · [학회](https://openreview.net/forum?id=HJzgZ3JCW) · [다운로드 판본](https://arxiv.org/abs/1802.06367) | ReLU 위치 변경·pruning과 정확한 패턴 검출의 차이 |
| Zhang et al., Expanding the Edge: Enabling Efficient Winograd CNN Inference With Deep Reuse on Edge Device (DREW) | IEEE TKDE 2023 | [PDF](03_sparsity_patterns/Zhang_2023_DREW_TKDE.pdf) · [저자 공개본](https://jamesthez.github.io/files/zhang-tkde23.pdf) | 유사 타일의 클러스터링과 근사 결과 재사용 |
| Yang et al., WRA-SS: A High-Performance Accelerator Integrating Winograd With Structured Sparsity for Convolutional Neural Networks | IEEE TVLSI 32(1), 164–177, 2024 | **PDF 미확보** · [출판사 DOI](https://doi.org/10.1109/TVLSI.2023.3330993) | 원문 확보 후 검출·변환 구조 확인 필요 |

WRA-SS는 다운로드 가능한 공개 원문을 확보하지 못했다. 링크 안내를 PDF로 가장해 저장하지 않았다. 온라인 공개 연도는 2023, 권호 기준 연도는 2024다. Sparse-Winograd는 OpenReview가 다운로드를 거절하여 arXiv 공개본을 확보했다.

### 우리 회로의 비교 기준

- 기존 dense Winograd.
- zero-tile bypass만 적용한 구조.
- 변환 후 V의 0을 검출해 MAC을 차단하는 구조.
- 변환 전 행·열 관계 검출을 추가한 제안 구조.

동일 수치 결과와 처리율에서 검출기·마스크·선택기·버퍼까지 포함한 면적과 에너지를 비교한다. 16-lane 병렬 MAC의 일부 좌표 차단이 곧 사이클 감소를 의미하지 않는다. MNIST 입력 통계만으로 다른 모델의 효과를 가정하지 않는다.

## 04. 시간적 재사용

- **Parger et al., DeltaCNN: End-to-End CNN Inference of Sparse Frame Differences in Videos — CVPR 2022**: [PDF](04_temporal_reuse/Parger_2022_DeltaCNN_CVPR.pdf) · [CVF](https://openaccess.thecvf.com/content/CVPR2022/html/Parger_DeltaCNN_End-to-End_CNN_Inference_of_Sparse_Frame_Differences_in_Videos_CVPR_2022_paper.html).
- **Li et al., An Efficient CNN Accelerator Using Inter-Frame Data Reuse of Videos on FPGAs — IEEE TVLSI 2022**: [기존 PDF](04_temporal_reuse/An_Efficient_CNN_Accelerator_Using_Inter-Frame_Data_Reuse_of_Videos_on_FPGAs.pdf).

프레임 간 연속성이 있는 영상의 비교 자료다. 독립된 MNIST 이미지 순서를 영상의 시간적 연속성으로 간주하지 않는다.

## 05. 메모리·Dataflow·Fusion

- **Pellauer et al., Buffets: An Efficient and Composable Storage Idiom for Explicit Decoupled Data Orchestration — ASPLOS 2019**: [PDF](05_memory_dataflow_fusion/Pellauer_2019_Buffets_ASPLOS.pdf) · [저자 공개본](https://ysshao.github.io/assets/papers/Buffet_ASPLOS19_Final.pdf) · [참고 RTL](https://github.com/cwfletcher/buffets). Section 3.1, 4.2, 4.3을 먼저 읽는다.

- **Chen et al., Eyeriss v2: A Flexible Accelerator for Emerging Deep Neural Networks on Mobile Devices — IEEE JETCAS 2019**: [PDF](05_memory_dataflow_fusion/Chen_2019_Eyeriss_v2_JETCAS.pdf) · [MIT 공개본](https://eems.mit.edu/wp-content/uploads/2019/04/2019_jetcas_eyerissv2.pdf). Hierarchical Mesh, CSC sparse PE, 메모리 읽기 의존성과 SIMD 비용.
- **Kwon, Samajdar & Krishna, MAERI: Enabling Flexible Dataflow Mapping over DNN Accelerators via Reconfigurable Interconnects — ASPLOS 2018**: [PDF](05_memory_dataflow_fusion/Kwon_2018_MAERI_ASPLOS.pdf) · [저자 공개본](https://bpb-us-e1.wpmucdn.com/sites.gatech.edu/dist/c/332/files/2018/01/maeri_asplos2018.pdf?bid=332). 분배망과 Augmented Reduction Tree를 통해 다양한 mapping을 지원.

- **Chen, Emer & Sze, Eyeriss: A Spatial Architecture for Energy-Efficient Dataflow for Convolutional Neural Networks — ISCA 2016**: [PDF](05_memory_dataflow_fusion/eyeriss_isca_2016.pdf) · [MIT](https://people.csail.mit.edu/emer/media/papers/2016.06.isca.eyeriss_architecture.pdf).
- **Niu et al., DNNFusion: Accelerating Deep Neural Networks Execution with Advanced Operator Fusion — 기존 보관본**: [PDF](05_memory_dataflow_fusion/DNN_Accelerating_with_Advanced_Operator_Fusion.pdf).

## 06. 회로 기술 자료

- [FIFO Architecture, Functions, and Applications](06_circuit_reference/FIFO_Architecture.pdf): SCAA042A, November 1999. 학회 논문이 아닌 기술 문서.

## NVDLA 공식 문서

- [문서 안내](nvdla/README.md)
- [Primer](nvdla/primer.html)
- [Hardware Architecture](nvdla/hardware_architecture.html)
- [Unit Description](nvdla/unit_description.html)

## 검증과 관련 자료

- [collection_manifest.json](collection_manifest.json): 파일별 이전 경로, 현재 경로, 페이지 수, SHA-256, 신규 다운로드 주소.
- PDF 14편의 모든 페이지 텍스트 파싱과 이동 전후 해시 일치를 확인했다. 기존 PDF 판본은 변경하지 않았다.
- 2026-10-26 추가 PDF 3편도 전체 페이지 파싱·제목·SHA-256을 확인했다. 주요 구조 그림을 렌더링해 읽기 노트와 대조했다.
- [기존 Winograd 읽기 목록](../winograd_paper_reading_list.md)
- [대회 수상작 폴더](../수상작/): 논문과 구분해 기존 위치 유지.
