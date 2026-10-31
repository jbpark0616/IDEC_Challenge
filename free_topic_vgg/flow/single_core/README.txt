단일 코어 + SRAM 합성

실행: WSL에서 bash free_topic_vgg/flow/single_core/run.sh
현재 산출물: free_topic_vgg/build/single_core_sram_fixed_window/
이전 전체 채널 FF 버전은 evidence/single_core_synth/의 비교 근거만 보존한다.
이전 합성 빌드와 중단 실행은 정리했다. 현재 결과 분석: python flow/single_core/analyze.py
STATUS.txt에 시작 시각, 종료 코드 및 실행 시간을 기록한다.

현재 RTL sources.f의 Conv/FC 코어를 그대로 사용한다.
U8/V8, 16 MAC lane, U 4 + V/line 4 + activation A/B 4 = 12 SRAM.
매크로당 8 KiB, 총 96 KiB. SRAM behavioral Verilog는 합성하지 않는다.
Liberty를 blackbox로 읽고 LEF와 연결한다.

생산용 클러스터는 4/16코어만 명령을 허용한다. run.sh는 해당 소스에서
합성 전용 vgg_single_core_shell.v를 생성하며, 모듈명과 Conv/FC 코어 개수
검사 두 곳만 바꾼다. 원본 RTL은 수정하지 않는다. 이 shell은 16코어 시스템의
기능 검증을 대체하지 않는다. 단일 코어에 축소된 클러스터 제어/입출력 논리도
면적에 포함된다. 16코어 interconnect 면적은 이 결과로 알 수 없다.

첫 시도에서 생산용 클러스터의 코어 수 검사가 연산 경로를 제거했다.
그 결과(면적 28664.819460 um^2, FF 275개)는 유효한 코어 합성이 아니며 폐기한다.
수정 후 합성이 완료된 최신 보고서만 사용한다.

목표 주기 1000 ps, 입출력 지연 200 ps. ABC 면적 중심 매핑.
배치/배선/CTS 미실행: 타이밍은 post-synthesis 추정이며 Fmax 보장 아님.
표준셀 RVT FF와 SRAM Liberty의 전압/온도 corner가 서로 다르다.
SRAM LEF의 sdel 핀/사이트 경고 및 기존 GDS 불일치가 미해결이다.
따라서 물리 구현 완료, signoff PPA, 활동 기반 전력 결과로 사용하면 안 된다.
