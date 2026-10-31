별도 HWC 8채널 묶음 공급기 변형
============================
사용자 승인 범위: 원본을 건드리지 않고 공급기를 따로 수정/검증.
메인 rtl/sources.f, RTL, 기준본 manifest는 수정하지 않는다.

prepare.py: 원본 공급기 snapshot + wrapper + hwc8_body.vh 기반 모듈을
이 폴더 안에 생성하고 별도 sources.f를 만든다.
run_cluster.py: 원본 해시 확인, 단위 테스트, 동일 즉시TB Conv5 OFF/ON 실행.
실행: free_topic_vgg에서 python3 verification/feed_hwc8/run_cluster.py (WSL).

최적화 대상: TILE_STREAM, tile_mode, HWC(!sharded), C가 8의 배수.
기타 입력은 원본 snapshot으로 fallback. sharded/FC 최적화는 하지 않았다.
원본과 같은 공간타일 -> 채널 -> 4x4 pixel 순서, 64bit 2word/tile.

추가 작업저장소는 고정 16x64bit=128byte. 채널 수에 비례하지 않는다.
한 공간위치의 8채널이 같은 HWC word에 있는 점을 사용해 각 공간위치에서
한번 읽고 8채널 전체를 보존한다. 16개 위치가 준비되면 채널별로 출력한다.
첫 버전은 하나의 fill/emit 버퍼와 한개 outstanding read를 사용한다.
읽기와 출력 이중버퍼링/다중 outstanding은 넣지 않았다.
FF/MUX/주소 계산 회로가 추가되므로 면적과 timing 개선은 합성 전 미확인.
wrapper에 원본 fallback도 남으므로 전체 저장소가128byte뿐이라는 뜻은 아니다.

단위시험은 실제 activation_sram + macro 모델, 독립 HWC oracle 사용.
가짜 타일 직접주입 없음. 출력 stall 중 data/last 안정성 확인.
16코어 비교는 TB/가중치/입력/출력 golden 동일, SRAM source_reads만 감소 허용.
