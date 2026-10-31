현재 자유주제 RTL — 고정본
========================
Top: vgg_sixteen_core_cluster
빌드 목록: sources.f (28개 RTL). 메인 소스 목록은 변경하지 않았다.
16코어 x 16 MAC, 코어당 SRAM 12 x 8KiB, U8/V8.

메인 입력 경로:
activation A/B SRAM -> vgg_activation_feed -> multicast/rx
-> vgg_tile_stream_reader -> input transform -> V SRAM 재사용
-> row MAC -> output transform/postprocess.
FC는 기존 선형 공급 경로를 사용한다.

sources.f에 남은 기존 reader/line/window는 조건부 legacy 검증 경로에도 사용된다.
파일이 존재한다고 메인 경로에서 채널별 FF 이력을 사용하는 것은 아니다.
메인 TILE_INPUT=1 구조가 기준이며, 임의 제거/파라미터 변경을 하지 않는다.
고정 규칙: ../architecture/DESIGN_FREEZE_20261030.txt
최신 합성: ../evidence/single_core_fixed_window/REPORT_KO.txt
이전 비교값: ../evidence/single_core_synth/ (최신 결과가 아님)
