# 지정주제 최종 ASIC 설정

`config.mk`는 루트 `verilog/`의 bypass + ICG `b1_g1` 최종본을 사용한다.
실행은 저장소 루트에서 `make synth-asic` 또는 WSL의
`bash flow/openroad/run_designated_final.sh`를 사용한다.

기준 설정과 SDC는 `flow/openroad/designated_final.mk`, `designated_final.sdc`이다.
`OPENROAD_CLKGATE`와 ASAP7 플랫폼 ICG mapping을 유지해야 한다.
결과는 `build/designated_final/openroad/`에 저장한다.

기존 AES 예제 설정과 생성물은 정리 전 복구용 ZIP에 보관했다.
현재 측정 근거는 `docs/designated_final/`에 있다.
