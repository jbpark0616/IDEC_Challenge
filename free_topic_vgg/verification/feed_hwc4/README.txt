고정 4채널 공급 묶음 실험 — 원본 RTL 보존

prepare.py는 feed_hwc8 실험에서 64byte 작업 버퍼 변형을 생성한다.
SRAM 64bit 응답 중 필요한 32bit를 보관하며, 나머지 반쪽은 다음 묶음에서
다시 읽는다. 따라서 채널 수가 8의 배수이면 8채널 변형보다 읽기가 두 배다.
버퍼 크기는 전체 입력 채널 수와 무관하게 고정이다. MAC 수는 바꾸지 않는다.

HWC, C가 4의 배수인 tile 입력에 적용하고 다른 모드는 원본으로 fallback한다.
단위시험은 C=4/12 포함 8개 형상에 정상 및 역압을 적용한다.
레이어 시험은 같은 TB, 이미지, golden으로 Conv3/5/11의 original/group4/group8,
각 zero-skipping OFF/ON을 비교한다. 16코어와 SRAM 모델을 포함한다.

WSL에서 free_topic_vgg를 작업 디렉터리로 실행:
 python3 verification/feed_hwc4/run_sweep.py
 python3 verification/feed_hwc4/report.py

결과: evidence/feed_group_sweep/REPORT_KO.txt 및 results.json
초기 적재 제외, 실행 중 weight 공급 포함. 합성/PPA 미측정.
run_sweep.py는 완료된 로그를 재사용하므로 새로운 코드로 재실험할 때는
기존 결과를 보존하고 별도 출력 디렉터리를 사용해야 한다.
