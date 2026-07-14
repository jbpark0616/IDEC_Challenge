# IDEC CCDC 2026 — Progress Log

> 세션 이어갈 때: Claude에게 "PROGRESS.md 읽고 이어서 하자"

## 🎯 대회 목표 (요약)
Baseline CNN 가속기(MNIST 96%)를 정확도 유지하며 **Fmax↑ / Power↓ / Area↓** 로 개선.
평가: Vivado 2024.1 RTL+게이트 시뮬(정확도) + OpenROAD 합성 리포트(성능).
자세한 내용 → `docs/2026 KNU IDEC CCDC 교육.pdf`

## 📌 다음 할 일 (Next up)
- [ ] `make synth` 돌려서 baseline Fmax / Area / Power 기록 (아래 "베이스라인 측정치")
- [ ] RTL 분석 시작 — `chip.v` 부터 읽어서 데이터 흐름 파악
- [ ] 최적화 아이디어 도출 → 지정주제 (모듈 재사용, MAC 공유, 파이프라인화)

## 🛠️ 개발 워크플로우 (Level 2 pro flow)
| 명령 | 하는 일 | 시간 |
|---|---|---|
| `make sim` | 1000장 accuracy 판정 (PASS/FAIL) | ~23s |
| `make sim TOP=top_tb` | 1장 스모크 테스트 | ~5s |
| `make sim WAVE=1` | 파형 dump까지 | ~30s |
| `make wave` | 마지막 파형을 Vivado GUI로 열기 | GUI |
| `make synth` | 합성 + timing/util/power 리포트 | ~1min |
| `make xpr` | 제출용 .xpr export | ~30s |
| `make clean` | build/ 정리 | 즉시 |

VS Code에선 `Ctrl+Shift+B` → 첫 항목이 `make sim`. 나머진 커맨드 팔레트 `Tasks: Run Task`.

## ⏳ 나중에 (Deferred)
- WSL Ubuntu 22.04 + OpenROAD-flow-scripts 설치 (합성 리포트 뽑을 때)
- XDC 제약파일 작성 (Vivado로 Fmax 리포트 볼 때)
- `OpenRoad project/config/config.mk`를 AES → chip 디자인용으로 수정
- Vivado 2024.1 마이그레이션 (제출 직전 필수)

## 📊 베이스라인 측정치 (2026-07-15, `make sim` + `make synth`)
| 항목 | 값 | 참고 |
|---|---|---|
| Accuracy (top_tb_1000) | **97.0%** ✅ | PDF baseline 96% 대비 +1 |
| Timing WNS @ 100 MHz | **-60.156 ns** ❌ | 100 MHz 목표 미달 |
| **실제 Fmax** | **~14.25 MHz** | 1 / 70.156 ns |
| LUT | 21,922 (18.72%) | logic 21,850 + memory 72 |
| FF | 3,792 (1.62%) | |
| Total Power | 0.497 W | Dyn 0.208 + Static 0.289 (confidence: Low) |
| 합성 소요 시간 | 12min 50s | xck26 target |

- ASAP7 Area/Power: _pending_ (OpenROAD 필요)
- **핵심 관찰**: baseline이 100 MHz도 못 맞춤 → Fmax 개선 여지 매우 큼 → 지정주제 점수 노리기 좋음

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

### 2026-07-15 — Level 2 pro flow 구축
- **결정**: Vivado project mode(GUI) 대신 **non-project mode Tcl + Makefile** 채택
  - _이유: 재현성 (git diff 가능), 자동화 (PASS/FAIL 판정), 대회 완성도 평가에 유리. 트레이드오프는 초기 세팅 비용 (~1시간)._
- **구현**: xvlog → xelab → xsim 파이프라인. `scripts/check_accuracy.py`로 로그 자동 파싱.
- **디렉토리**: `flow/vivado/*.tcl`, `flow/constraints/timing.xdc`, `Makefile`, `.vscode/tasks.json`
- **버그 fix**: `xelab -timescale 1ps/1ps` 없으면 XSIM 43-4099 에러 (RTL 모듈들엔 `` `timescale ``이 없고 top_tb.v에만 있어서 mix라고 판정됨). RTL 수정 없이 툴 옵션으로 해결.
- **검증**: `make sim` → 1000장 accuracy **97%** PASS, 23초.
- **결정**: XDC는 우선 100MHz (`period 10.000`) 로 고정. 나중에 baseline WNS 보면서 조정.
- **버그 fix (2번의 삽질 후 진짜 원인)**: GNU Make 3.81 on Windows는 `mkdir -p`, `rm -rf` 같은 "단순" 명령은 SHELL을 우회해서 `CreateProcess`로 직접 실행. Windows PATH에 `mkdir.exe`/`rm.exe`가 없으면 실패. 해결: Makefile에서 `export PATH := C:/PROGRA~1/Git/usr/bin:$(PATH)` 로 Git Bash 툴 경로를 PATH 앞에 추가. (SHELL 지정만으론 부족했음)
- **베이스라인 합성 완료**: WNS -60.156 ns (100 MHz 못 맞춤, 실측 Fmax ~14 MHz), LUT 21,922, Power 0.497 W. 상세는 위 "베이스라인 측정치" 참고.

<!-- 새 세션 시작할 때 위에 날짜 헤더 추가하며 이어서 기록 -->
