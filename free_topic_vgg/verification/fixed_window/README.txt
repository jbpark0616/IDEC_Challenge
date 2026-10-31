고정 크기 4x4 타일 SRAM 공급 검증

메인 경로: A/B SRAM -> vgg_activation_feed 타일 주소 생성 -> multicast/rx
           -> 코어별 vgg_tile_stream_reader 128bit -> 기존 input transform
           -> V SRAM/metadata -> 기존 row MAC -> output transform/postprocess.
입력 전체 채널 벡터, 수평 이력, 세로 행 응답 벡터 FF를 메인 경로에서 제거.
코어의 타일 payload는128bit, 제어는half/out_valid 2bit.
공유 feed는 기존 4word/source 고정 캐시를 유지한다. 채널 수에 비례하지 않는다.
원본 activation은 기존 A/B SRAM에 계속 존재하며, 중복 픽셀을 다시 읽는다.
별도 64bit 가로 겹침 이력을 모든 채널에 대해 저장하지 않는다.
U/V 보관 수명 및 SRAM12개/코어 구성은 그대로다.
V/line bank 상단의 기존 line 영역은 현재 경로에서 사용하지 않는다.
이번 작업은 저장 영역을 재할당하거나 새로운 SRAM을 추가하지 않는다.
FC에는 기존 선형 입력 순서를 사용한다.
지정주제 최종 verilog/는 변경하지 않는다.

검사
  bash verification/fixed_window/run_tile_feed.sh
    3/32/128/512채널, HWC/분산tile/분산pooled, padding, read/output stalls.
    독립 주소 oracle와 스트림 전체 비교. 10사례 PASS.
  bash verification/fixed_window/run_core.sh
    U8/V8 12사례 x sparse OFF/ON x U상주/재적재 =48사례 PASS.
    각 공급 모드694워드 기준값 일치, last-use release/backpressure/stale commit 확인.
    여기서는 타일 스트림을TB가 공급하므로 SRAM 주소 생성 비용은 포함하지 않는다.
  verification/v8/tb_fc_v8_regression.sv를 현재 rtl/sources.f로 실행:
    16코어 Conv->FC1->FC2->FC3->Conv,202워드 및 class8 PASS.
    Conv4796->4700cycles; FC1/2/3는1277/1277/731cycles로 이전과 동일.

주의: SRAM 재읽기가 늘어 전 계층 latency 개선을 주장할 수 없다.
전체 VGG 모델은 이번에 다시 실행하지 않았다.
로그는 build/fixed_window/에 저장한다.
