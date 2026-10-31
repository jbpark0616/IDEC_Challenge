700MHz 보고용 기준본
====================
사용자 승인: "700M로 만족하자... 이제 데이터 뽑자"

manifest.json은 승인된 타이밍 개선 이후 현재 RTL과 sources.f의 SHA256이다.
기존 design_freeze_20261030 증거는 덮어쓰지 않는다.
이 기준 이후 측정 목적으로 RTL을 변경하지 않는다.

16코어, 코어당16 MAC, U8/V8, SRAM12개 x8KiB/core.
최신 배치배선 전 STA 추정은725.89MHz. 보고용 latency는700MHz로 환산한다.
이것은 배치배선/CTS 이후700MHz signoff 또는 실측 주파수를 의미하지 않는다.
동일 조건의 합성 전후 수치는 timing_comparison.json을 참조한다.

측정 결과: ../report700/REPORT_KO.txt
집계 갱신: python verification/bypass_profile/report700.py (free_topic_vgg 기준)
원시 로그와 OFF/ON 쌍, golden 출력 확인, RTL/벡터 provenance를 함께 보존한다.
단일 코어 통제 실험과 실제16코어 VGG 레이어 측정을 구분한다.
700MHz latency(us) = cycles /700.
전력/에너지는 별도 activity 기반 분석 전까지 추정하지 않는다.
