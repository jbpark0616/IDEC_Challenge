# 최종 보고서 및 설계 자료

## 보고서

| 구분 | 제출 PDF | 편집 원본 |
|---|---|---|
| 지정주제 | [제출용 PDF](IDEC_지정주제_결과보고서_제출용.pdf) | [결과보고서 Word](IDEC_지정주제_결과보고서.docx) |
| 자유주제 | [제출용 PDF](IDEC_자유주제_결과보고서_제출용.pdf) | [검토수정본 Word](IDEC_자유주제_결과보고서_검토수정본.docx) |

위 편집 원본을 기준으로 유지한다. 본문 PDF와 표지 PDF는 제출본 조립에 사용한 원본이다.

## 설계와 제출물

- `verilog/`: 지정주제 최종 bypass + ICG RTL.
- `free_topic_vgg/rtl/`: 자유주제 RTL. 정리 작업으로 회로를 변경하지 않았다.
- `submission/IDEC2026/`: Vivado 2024.1 제출 프로젝트, 소스, 합성 산출물.
- `submission/IDEC2026_Vivado2024_1.zip`: 제출 폴더의 압축본. 보고서는 별도 PDF이다.
- `docs/designated_final/`: 지정주제 합성·전력·정확도 근거와 RTL 해시.
- `free_topic_vgg/evidence/timing_writer_pipeline/`: 자유주제 최종 합성·타이밍 및 통합 검증 근거. `netlist/`에 합성 netlist와 SDC를 보존했다.
- `free_topic_vgg/evidence/report_baseline_700mhz/`: 보고용 소스 해시와 평가 조건.

## 그림과 재현

자유주제 최종 PPA 재현 자료는 `submission/IDEC2026_FREE_TOPIC/`에 모았다.
`README.md`의 절차에 따라 통제 실험 30조건, VGG 레이어 4개 OFF/ON,
면적 비교를 각각 실행할 수 있다. 기존 측정 로그와 결과도 같은 폴더에 포함한다.
전체 모델 실행과 레이어 단위 PPA 측정은 서로 다른 검증이다.

메일 제출용 `IDEC2026_FREE_TOPIC_Compact.zip`과 일반 압축본은 로컬에만 보존한다.
Git에는 압축 전 원본 폴더를 저장한다. 압축본의 대용량 파일은 `restore.py`로
복원하지만, Git에서 받은 원본 폴더에는 이 과정이 필요 없다.
실패한 면적 실험과 일회성 문서 수정 도구는 `.submission_review/`에 별도 보관하며
최종 결과나 재현 경로에 포함하지 않는다.

- `docs/report_assets/`: 보고서 그림, 표, 그림 생성 소스.
- `docs/report_data/`: 원시 측정값, 비교 실험, 출처.
- `scripts/report_data/`: 지정주제 데이터 추출 스크립트.
- `free_topic_vgg/evidence/report700/`: 자유주제 통제 실험과 레이어별 결과.
- `verification/designated_ablation_reference.zip`: 보고서 ablation을 재현하는 네 가지 비교 RTL 및 전력 검증 로그만 보존한 압축본. 최종 구현 소스로 사용하지 않는다.
- `docs/report_data/final_delivery/`: 정리 전후 보호 파일 해시, 삭제 목록, Vivado RTL/게이트 1,000장 검증 로그.

보고서의 비교 결과와 한계를 확인할 수 있도록 작은 측정 로그는 보존했다. 재생성 가능한 빌드 결과·파형·문서 렌더링 캐시와 폐기된 대용량 복구 ZIP은 삭제했다. 학습 가중치와 데이터셋은 로컬에 유지하며 Git에는 기존 다운로드·생성 스크립트와 manifest를 저장한다.

2026-10-31 최종 선별에서 미채택 HWC4/HWC8·raster 공급 실험, 중단한 셀 크기 실험, 중간보고서와 다운로드한 참고 논문 사본을 제거했다. 삭제 파일 목록과 해시는 `report_data/final_delivery/final_only_removed.json`에 남겼다. 최종 회로의 검증 oracle, 보고서 비교군, 동결 스냅샷은 재현 근거이므로 보존한다.
