2026-10-30 폴더 정리
===================
최종 설계:
  지정주제 verilog/ — bypass+ICG, docs/designated_final/rtl_sha256.json
  자유주제 free_topic_vgg/rtl/sources.f — 고정 28개 RTL, 16코어 U8/V8
  자유주제 최신 합성 evidence/single_core_fixed_window/ (single_core_synth는 이전 비교값)

폐기 실험/중단 빌드/수정 전 복사본 및 캐시 삭제: deleted.json 참고.
작은 폐기 소스는 archive/retired_experiment_sources_20261030.zip로 압축 보존했고
파일별 SHA256 검증 후 작업 폴더에서 제거했다. 대용량 VCD/합성 중간물은 삭제했다.
중단한 셀 크기 실험의 로그/수치만 cell_sizing_incomplete/에 남겼다.
이 실험은 최종본에 채택하지 않았으며 allow_small의 전력 검증은 미완료다.

유지: 현재 RTL, 현재 테스트/검증 도구, 최신 합성 원본, 동결 스냅샷,
보고서 근거, 데이터/가중치/양자화 자산, SRAM 매크로와 라이선스.
코드의 조건부 legacy 경로 제거는 설계 변경이므로 이번 정리에 포함하지 않았다.
RTL 및 sources.f는 고정 해시와 전후 동일. commit/push는 하지 않았다.
