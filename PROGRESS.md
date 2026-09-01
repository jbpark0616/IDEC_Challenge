# IDEC CCDC 2026 — Progress Log

> 세션 이어갈 때: Claude에게 "PROGRESS.md 읽고 이어서 하자"

## 🎯 대회 목표 (요약)
Baseline CNN 가속기(MNIST 96%)를 정확도 유지하며 **Fmax↑ / Power↓ / Area↓** 로 개선.
평가: Vivado 2024.1 RTL+게이트 시뮬(정확도) + OpenROAD 합성 리포트(성능).
자세한 내용 → `docs/2026 KNU IDEC CCDC 교육.pdf`

## 📌 다음 할 일 (Next up)
- [ ] **Winograd RTL 분석** — `verilog/chip.v`부터 실제 데이터 흐름 순서로 읽기
- [ ] 블록별 병목과 추가 최적화 후보 점검
- [ ] `make sim-chip-winograd-1000` → `make synth-asic` → 결과 비교 → 커밋

## 🌅 내일 세션 시작할 때
1. Claude에게: **"PROGRESS.md 읽고 이어서 하자"**
2. 환경 확인 (30초): `make sim-chip-winograd-1000` — `PASS`와 Accuracy 97.0% 확인
3. 위 "다음 할 일" 첫 항목부터 진행

## 🛠️ 개발 워크플로우 (Level 2 pro flow)
| 명령 | 하는 일 | 시간 |
|---|---|---|
| `make sim-chip-winograd-1000` | Winograd RTL 1000장 accuracy 판정 | ~23s |
| `make synth` | Vivado FPGA 합성 (sanity check) | ~13min |
| **`make synth-asic ASIC_TOP=<top>`** | **OpenROAD ASAP7 범용 합성 (대회 지표)** | **~7min** |
| `make xpr` | 제출용 .xpr export | ~30s |
| `make clean` | build/ 정리 | 즉시 |

VS Code에선 `Ctrl+Shift+B` → 첫 항목이 `make sim`. 나머진 커맨드 팔레트 `Tasks: Run Task`.

**RTL 개발 루프 추천:**
1. 코드 수정 → `make sim` (23s) — accuracy 확인
2. 큰 변경/최적화 완료 → `make synth-asic ASIC_TOP=chip` (7min) — Area/Fmax/Power 실측
3. Vivado synth (`make synth`)는 이제 잘 안 쓸 예정 (OpenROAD가 대회 지표)

## ⏳ 나중에 (Deferred)
- WSL Ubuntu 22.04 + OpenROAD-flow-scripts 설치 (합성 리포트 뽑을 때)
- XDC 제약파일 작성 (Vivado로 Fmax 리포트 볼 때)
- `OpenRoad project/config/config.mk`를 AES → chip 디자인용으로 수정
- Vivado 2024.1 마이그레이션 (제출 직전 필수)

## 📊 베이스라인 측정치 (2026-07-15)

### RTL simulation (`make sim`)
- **Accuracy (top_tb_1000)**: **97.0%** ✅ (PDF 96% 대비 +1, 23초)

### OpenROAD ASAP7 7nm 합성 (`make synth-asic`, **대회 채점 지표**)
| 항목 | 값 | 참고 |
|---|---|---|
| **Area** | **23,988.79 μm²** | 100% util (400 ps 타겟 기준) |
| Sequential area | 1,773.51 μm² (7.39%) | 나머지 92.6%는 combinational |
| **WNS** | **-1,217.17 ps** ❌ | 400 ps(2.5 GHz) 타겟 미달 |
| **Achievable Fmax** | **618.37 MHz** | min period 1,617 ps |
| **Total Power** | **707 mW** | Comb 682 (96.4%) + Seq 25.4 (3.6%) |
| Combinational Power | 682 mW | 대부분 여기 (Internal 44.8% + Switching 55.2%) |
| 합성 시간 | 6min 20s (synth) + 47s (report) | Vivado보다 오히려 빠름 |

### Vivado FPGA 합성 (`make synth`, sanity check만, 대회 점수와 무관)
- WNS -60.156 ns @ 100 MHz FPGA, LUT 21,922, Power 0.497 W, 12min 50s

**핵심 관찰:**
- Baseline은 2.5 GHz(400 ps) 목표 크게 미달 (618 MHz 수준)
- Power의 96.4%가 combinational logic → 파이프라인 삽입/클럭 게이팅으로 개선 가능
- Area의 92.6%가 combinational → 모듈 재사용/MAC 공유로 큰 개선 여지

## 🗂️ 프로젝트 구조
```
C:/IDEC_challenge/
├── verilog/            # 작업용 RTL (수정 대상)
├── data/               # 가중치/바이어스/테스트 이미지 (수정 X)
├── OpenRoad project/   # OpenROAD 설정과 ASAP7 표준셀
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

### 2026-07-15 저녁 — OpenROAD 통합 (Level 2 pro flow 확장)
- **결정**: OpenROAD를 WSL Ubuntu에 붙임. Windows Vivado + WSL OpenROAD 하이브리드 (대회 sample flow PDF의 권장 조합).
- **문제 발견**: WSL side에 사용자 예전 작업(7/1)의 chip 디자인이 있었는데, Windows verilog/ 와 다른 상태 (timescale 추가 + 포트 비트 순서 flip).
- **해결**: Windows verilog/를 single source of truth로 확정. WSL config.mk 을 `/mnt/c/IDEC_challenge/verilog/*.v` 직접 가리키게. 우리 RTL 6개 파일 앞에 `` `timescale 1ps/1ps `` 추가 (Vivado xelab의 -timescale 워크어라운드 제거). WSL src/chip/은 `chip.bak_20260715` 로 archive.
- **Makefile**: `synth-asic` target 추가 (`wsl -d Ubuntu -- bash -c "..."` 로 dispatch). 완료 후 자동으로 netlist/report를 `build/asic/`에 복사.
- **베이스라인 OpenROAD 결과**: Area 23,989 μm², Fmax 618 MHz, Power 707 mW. 6분 20초. 상세는 위 표 참고.
- **인사이트**: Vivado synth (12분)보다 OpenROAD (7분)이 오히려 빠름. 앞으로 `make synth-asic`이 primary flow.

## 🏁 오늘(2026-07-15) 마무리 상태

**한 줄 요약**: **완전한 flow가 터미널 하나에서 돌아감. Baseline 실측 완료.**

**환경 완성:**
- `make sim` (23s) → Accuracy 97% PASS
- `make synth-asic` (7min, WSL OpenROAD) → Area/Fmax/Power 실측 자동화

### 2026-08-25 — 합성 흐름 top parameter화

- Vivado: `make synth SYNTH_TOP=<module> [SYNTH_RTL="file ..."]`
- OpenROAD: `make synth-asic ASIC_TOP=<module> [ASIC_RTL="file ..."]`
- RTL 목록을 생략하면 `verilog/*.v`를 읽고 선택한 top의 hierarchy만 합성한다.
- 결과를 `build/synth/<top>/`, `build/asic/<top>/`에 분리한다.
- `winograd_mac_array` ASAP7 결과: area 1,580.749 um^2, Fmax 1,786.66 MHz,
  vectorless power 28.5 mW.
- `make synth` (12min, Vivado FPGA) → sanity check용 유지
- Git 저장소, .gitignore, VS Code tasks 세팅 완료

**Baseline 확보:**
- Accuracy 97%, Area 23,989 μm², Fmax 618 MHz, Power 707 mW

**남은 것 = 진짜 대회 컨텐츠**: RTL 최적화. 환경은 이제 방해가 안 됨.

<!-- 새 세션 시작할 때 위에 날짜 헤더 추가하며 이어서 기록 -->

### 2026-08-26 — A/B full-bank Winograd CNN 기준 구현

- `winograd_cnn_accelerator`: Bank A(784 B) -> Conv1 -> Bank B(507 B) ->
  Conv2 -> Bank A(75 B) 경로 구현.
- `winograd_conv_core`의 기존 16-lane MAC에 FC mode를 연결. lane 0~9에서
  10 class를 병렬로 계산하고 feature 75개를 시간 누산한 뒤 INT18 argmax.
- 실제 INT4 U/FC weight, INT16 bias, Q24 multiplier와 대회 이미지 한 장으로
  Python golden vector 생성 (`training/export_rtl_conv_vectors.py`).
- `make sim-core`, `make sim-two-conv`, `make sim-two-conv-real` 모두 PASS.
- 실제 전체 경로 결과: 75개 Conv2 feature 및 decision 0 일치, 1730 cycles.
- 다음 최적화: 현재 FF bank의 16-port read MUX를 2-cycle/row-bank loader로
  교체한 뒤 A bank 4-row line buffer 축소를 비교. B full-bank는 기준 구조로 유지.
- OpenROAD 최신 결과:
  - 공유 Conv/FC core: 4,167.87 um^2, 1.093 GHz, vectorless 295 mW
  - DEPTH=784 activation loader: 21,434.73 um^2, 1.139 GHz, 394 mW
  - full CNN controller: 38,658.77 um^2, 427.16 MHz, 60 mW
- full controller critical path는 MAC INT18 result에서 조합 argmax를 거쳐
  decision FF로 가는 2.326 ns 경로. 다음 timing 수정은 comparator tree pipeline.
- controller sequential area는 10.89%뿐이며 조합논리가 89.11%. loader read MUX
  최적화가 면적 개선의 최우선 과제임을 합성으로 확인.
- vectorless power는 activity 추정 왜곡 때문에 최종 비교에 사용하지 않고,
  inference VCD/SAIF 기반 power를 별도로 측정할 것.

### 2026-08-26 — Argmax 및 FF-bank loader 최적화

- 10-class 조합 argmax를 tie-low-index 동작을 유지하는 4-stage balanced
  comparator tree (`pipelined_argmax10`)로 변경.
- 당시 기존 16-read loader를 `winograd_activation_tile_loader_reference`로
  보존했으며, 최종 streaming 구조 확정 후 두 구형 loader RTL을 삭제했다.
- 새 loader는 16개의 interleaved FF bank와 두 번의 bank read로 4x4 tile을
  구성하며, schedule/read 경계에 register를 넣어 critical path를 분리.
- 실제 export model 전체 RTL 검증 PASS: Conv1, Conv2, FC logit, decision 일치,
  총 1741 cycles (기준 1730 대비 +11 cycles).
- loader OpenROAD ASAP7 비교:
  - reference: 21,434.73 um^2, 1.139 GHz
  - first banked: 6,221.93 um^2, 570.33 MHz
  - registered banked: 7,190.70 um^2, 654.41 MHz
- first banked loader + pipelined argmax 전체 controller는 15,257.96 um^2,
  446.61 MHz. reference controller 38,658.77 um^2 대비 면적 60.5% 감소.
- registered loader 포함 전체 controller 재합성은 WSL 실행 권한 승인 후
  최종 Fmax를 확정할 것.

### 2026-08-26 — 순차 스트리밍 데이터 경로로 교체

- Bank A(784 B)와 16-read 임의주소 loader를 Conv1 raster stream용 sliding-window
  generator로 교체. 3 line delay와 horizontal shift register로 4x4 tile을 생성한다.
- 공유 Winograd core 때문에 Conv1/Conv2 동시 실행은 불가능하므로 B의 full-frame
  보존은 유지. 다만 3채널을 공간 위치별 24-bit word로 묶은 `169 x 24-bit`
  sequential FF buffer와 Conv2용 3-channel window generator로 구성했다.
- Conv2 최종 feature는 FC 순차 접근에 맞춘 `75 x 8-bit` linear buffer에 저장한다.
- 실제 export-model 전체 RTL 검증 PASS: Conv1/Conv2/FC/decision 일치,
  총 1,359 cycles. 이전 registered banked 구조 1,741 cycles 대비 382 cycles 감소.
- ASAP7 OpenROAD post-synthesis:
  - Conv1 sliding-window generator: 505.02 um^2, 3.959 GHz
  - packed B sequential frame buffer: 2,937.94 um^2, 2.516 GHz
  - full controller: 9,275.08 um^2, 1.083 GHz
- 이전 full controller 15,257.96 um^2, 446.61 MHz 대비 면적 39.2% 감소,
  Fmax 2.43배. 1 GHz 목표는 post-synthesis 기준 달성했으므로 추가 파이프라인은
  보류한다. 현재 임계경로는 loader가 아니라 MAC weight-zero register에서 INT18
  accumulator로 가는 경로다.
- 1.083 GHz는 배치배선 전 수치다. 이후 우수성 비교에는 동일 조건의 post-synthesis
  수치를 사용하고, 최종 보고서에는 sign-off 수치로 오해되지 않게 명시한다.

### 2026-08-26 — 대회 인터페이스 및 1000장 합성 후 검증

- 실제 제출 top `chip`을 Winograd 컨트롤러에 연결했다. 외부 포트는 순차 UINT8
  `data_in`, 4-bit Winograd/FC weight, 16-bit bias와 계층별 Q24 requant multiplier로
  구성했다.
- 대회 입력은 ready 없이 784 pixel을 연속 공급하므로 Conv1 sliding-window 출력과
  공유 코어 사이에 128-bit, depth-8 elastic tile FIFO를 추가했다. 784-byte full Bank A를
  복구하지 않고도 1000장 전체에서 입력 backpressure가 한 번도 발생하지 않았다.
- `make sim-chip-winograd-1000` 결과: Python integer golden mismatch 0/1000,
  970/1000 correct, accuracy 97.0%, PASS.
- OpenROAD ASAP7 post-synthesis `chip` 결과:
  - area 10,094.91 um^2
  - sequential area 3,488.61 um^2 (34.56%)
  - minimum period 936.72 ps, achievable Fmax 1.0675 GHz
  - vectorless power 47.0 mW (비교 참고값이며 실측 전력으로 해석하지 않음)
- 합성 넷리스트에 사용된 48종 ASAP7 셀의 zero-delay functional model을 추가했다.
  ASAP7 `FAx1/HAxp5`의 `CON/SN`은 일반 carry/sum이 아니라 반전 출력이므로 원본
  라이브러리 식과 동일하게 모델링했다.
- `make sim-chip-winograd-gate-1000` 결과: post-synthesis netlist 1000장 전부 Python
  golden과 일치(mismatch 0), 97.0%, PASS. 이 테스트는 논리 동치용 zero-delay gate
  simulation이며 timing 검증은 OpenSTA report와 분리한다.
- `make xpr`가 Winograd 전체 RTL 14개와 `winograd_chip_1000_tb`를 포함한
  `build/xpr/exported.xpr`를 생성하도록 갱신했고 실제 생성까지 확인했다.

### 2026-08-26 — 기존 대회 베이스라인 RTL 제거

- 최종 Winograd hierarchy에서 사용하지 않는 기존 `conv1`, `conv2`, `fc`,
  `maxpool_relu`, `comparator`, `top_tb`와 `chip_baseline`을 제거했다.
- 베이스라인 Vivado 프로젝트와 중복 RTL 사본을 제거하고 Makefile, Vivado,
  OpenROAD 소스 목록을 Winograd 설계만 대상으로 정리했다.
- 정리 후 `make sim-chip-winograd-1000` 재검증 결과 mismatch 0/1000,
  accuracy 97.0%, PASS로 기능 변화가 없음을 확인했다.
