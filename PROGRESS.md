# IDEC CCDC 2026 — Progress Log

> 세션 이어갈 때: Claude에게 "PROGRESS.md 읽고 이어서 하자"

## 🎯 대회 목표 (요약)
Baseline CNN 가속기(MNIST 96%)를 정확도 유지하며 **Fmax↑ / Power↓ / Area↓** 로 개선.
평가: Vivado 2024.1 RTL+게이트 시뮬(정확도) + OpenROAD 합성 리포트(성능).
자세한 내용 → `docs/2026 KNU IDEC CCDC 교육.pdf`

## 📌 다음 할 일 (Next up)
- [ ] Vivado 2025.2로 `baseline/baseline.xpr` 열어 `top_tb_1000` 시뮬 → **원본 96% accuracy 재현 확인 및 스크린샷/메모**
- [ ] Baseline 성능 기준선 기록 (여기 아래 "베이스라인 측정치" 섹션 채우기)
- [ ] RTL 분석 시작 — `chip.v` 부터 읽어서 데이터 흐름 파악

## ⏳ 나중에 (Deferred)
- WSL Ubuntu 22.04 + OpenROAD-flow-scripts 설치 (합성 리포트 뽑을 때)
- XDC 제약파일 작성 (Vivado로 Fmax 리포트 볼 때)
- `OpenRoad project/config/config.mk`를 AES → chip 디자인용으로 수정
- Vivado 2024.1 마이그레이션 (제출 직전 필수)

## 📊 베이스라인 측정치
아직 미측정. Vivado 시뮬 후 여기에 기록.
- Accuracy (top_tb_1000): _pending_
- Fmax / WNS: _pending_ (XDC 필요)
- Area (ASAP7): _pending_ (OpenROAD 필요)
- Power: _pending_ (OpenROAD 필요)

## 🗂️ 프로젝트 구조
```
C:/IDEC_challenge/
├── verilog/            # 작업용 RTL (수정 대상)
├── data/               # 가중치/바이어스/테스트 이미지 (수정 X)
├── baseline/           # Vivado 프로젝트 (baseline.xpr)
├── OpenRoad project/   # 대회 제공 참조 baseline (config/, std_cell/, verilog/) — 원본 보존, 수정 X
└── docs/               # 대회 PDF 문서
```

---

## 📝 작업 이력

### 2026-07-15 — 환경 세팅
- **결정**: Vivado 2025.2로 우선 진행, 제출 직전 2024.1 마이그레이션
  - _이유: 재설치 코스트 회피, RTL 개발엔 버전 영향 적음_
- **결정**: OpenROAD는 지금 안 붙임 (합성 리포트 볼 단계 아님)
- **수정**: `verilog/top_tb.v`의 `$readmemh` 경로 34곳 `C:/cnn_verilog/data/` → `C:/IDEC_challenge/data/`
- **확인**: `top_tb_1000` 모듈은 `top_tb.v` 안에 포함되어 있음 (별도 파일 불필요)
- **셋업**: Git init (main 브랜치), `.gitignore` 작성 (Vivado 생성물/DCP 제외), 초기 커밋
- **참고**: `OpenRoad project/config/config.mk`는 현재 AES 예제 그대로 — chip용 수정 필요 (나중에)

<!-- 새 세션 시작할 때 위에 날짜 헤더 추가하며 이어서 기록 -->
