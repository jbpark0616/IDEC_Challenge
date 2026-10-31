# NVDLA 공식 문서 로컬 사본

다운로드: 2026-09-21. 논문이 아닌 NVIDIA 공식 설계 문서다.

| 자료 | 로컬 | 원본 |
|---|---|---|
| Primer | [HTML](primer.html) | https://nvdla.org/primer.html |
| Hardware Architectural Specification | [HTML](hardware_architecture.html) | https://nvdla.org/hw/v1/hwarch.html |
| Unit Description | [HTML](unit_description.html) | https://nvdla.org/hw/v1/ias/unit_description.html |

HTML을 브라우저로 열면 된다. 본문에 연결된 NVDLA 이미지와 CSS/JS는 `assets/`에 저장했다. 세 문서 사이 링크는 로컬 파일로 연결하고, 나머지 문서 링크는 공식 웹사이트로 연결했다. MathJax 수식 렌더링 등 외부 서비스는 인터넷 연결이 필요할 수 있다. 완전한 사이트 미러는 아니다.

먼저 Hardware Architecture의 Direct Convolution / Image-input / Winograd Convolution Mode와 소형·대형 구현 예시를 읽는다. 이후 Unit Description에서 CBUF, CSC, CMAC, CACC와 Winograd 데이터 경로를 확인한다.
