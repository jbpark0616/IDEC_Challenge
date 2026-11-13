# 보고서와 실험 자료

## 최종 보고서

- [지정주제 PDF](IDEC_지정주제_결과보고서_제출용.pdf) · [Word 원본](IDEC_지정주제_결과보고서.docx)
- [자유주제 PDF](IDEC_자유주제_결과보고서_제출용.pdf) · [Word 원본](IDEC_자유주제_결과보고서_검토수정본.docx)

## 발표·학회 제출 자료

- [최종 A0 포스터 PDF](IDEC_Poster_Sparsity_Focus_A0.pdf) · [편집용 PowerPoint](IDEC_Poster_Sparsity_Focus.pptx)
- [포스터 발표 대본](IDEC_Poster_발표대본.txt)
- [GitHub QR: 인쇄용 A4 PDF](IDEC_GitHub_QR_A4.pdf) · [SVG](IDEC_GitHub_QR.svg) · [PNG](IDEC_GitHub_QR.png)
- [ICEIC 2027 제출 PDF](iceic2027_draft/JunBeom_Park_ICEIC2027.pdf) · [2쪽 Word 원본](iceic2027_draft/ICEIC2027_manuscript_2page.docx)

## 그림과 그래프

주제별로 나누지 않고 종류별로 모았다. 같은 이름의 SVG·PNG·PDF는 같은 그림의 출력 형식이다.

- [그래프](figures/graphs/): 사이클·전력·에너지·MAC 활동·정확도 및 공급 성능 비교
- [아키텍처·회로 그림](figures/architecture/): Winograd 원리, 데이터 흐름, 검출 회로, 버퍼와 코어 구조
- [표](figures/tables/): 보고서에 삽입한 사양·수치 형식·비교표
- [편집·생성 원본](figures/sources/): 통합 PowerPoint, 그래프 생성 스크립트, 그림 스타일

## 실험결과

- [지정주제](experiment_results/designated/): 최종 합성·게이트 검증, sparsity/ICG 비교, 버퍼·저장소·수치 폭 실험
- [자유주제](experiment_results/free_topic/): 통제 실험, 실제 VGG 레이어, 면적·타이밍·멀티캐스트 및 정확도 근거
- [추가 Conv1·Conv2 측정](experiment_results/free_topic/vgg_conv1_conv2_ppa/README.md): OFF/ON 결과, 실제 측정 입력과 게이트 재현 진입점

자유주제는 실행 작업 공간에서 측정 보고서와 CSV·JSON·작은 로그를 모은 열람용 사본이다.
재현에 필요한 RTL·netlist·벡터·라이브러리와 원래 실행 경로는 제출 패키지 및 `free_topic_vgg/evidence/`에 유지한다.
과거 로그 안의 경로와 해시는 측정 당시 기록이므로 변경하지 않았다.

## 실행과 설계

- [지정주제 제출 패키지](../submission/IDEC2026/)
- [자유주제 제출 패키지 및 실행 방법](../submission/IDEC2026_FREE_TOPIC/README.md)
- [모듈 설계 설명](design_reference/)

제출 패키지, 최종 보고서, RTL은 이번 폴더 정리에서 수정하지 않았다.
