"""Finish navigation/dependency edits before native PowerShell deletion."""
from pathlib import Path
import hashlib
import json
import zipfile

root=Path(__file__).resolve().parents[1]
project=root/'free_topic_vgg'
folder=root/'archive/free_topic_cleanup_20261028'
plan=json.loads((folder/'plan.json').read_text())
archive=root/plan['archive']
extra=['tb_ab_layer_chain.sv','ab_cycle_profile.svh','streaming_v_check.svh','tb_generator_boundary.sv']
with zipfile.ZipFile(archive,'a',compression=zipfile.ZIP_DEFLATED) as z:
    for name in extra:
        p=project/'tests'/name
        relative=p.relative_to(root).as_posix()
        if relative in plan['targets']:
            continue
        payload=p.read_bytes()
        z.writestr(relative,payload)
        entry=dict(path=relative,bytes=len(payload),sha256=hashlib.sha256(payload).hexdigest())
        plan['archived_files'].append(entry)
        plan['deleted_files'].append(dict(path=relative,bytes=len(payload)))
        plan['targets'].append(relative)
        plan['bytes_to_remove']+=len(payload)
with zipfile.ZipFile(archive) as z:
    for entry in plan['archived_files']:
        with z.open(entry['path']) as f:
            assert hashlib.file_digest(f,'sha256').hexdigest()==entry['sha256']
with archive.open('rb') as f:
    plan['archive_sha256']=hashlib.file_digest(f,'sha256').hexdigest()
plan['archive_bytes']=archive.stat().st_size
(folder/'plan.json').write_text(json.dumps(plan,indent=2)+'\n',encoding='utf-8')

(root/'PROJECTS.txt').write_text('''IDEC 프로젝트 — 현재 작업 위치 (2026-10-28)

지정주제
  VS Code: designated_topic.code-workspace
  확정 비교: experiments/row_sparse_fixed/iterations/matched_ablation/RESULTS.txt
  최종 구현: experiments/row_sparse_fixed/iterations/matched_ablation/cases/b1_g1/rtl/
  출력 경계 비교본: experiments/channel_serial_fifo/boundary/rtl/
  기존 verilog/, data/, training/, OpenRoad project/는 보존.

자유주제
  작업 루트: free_topic_vgg/
  VS Code: free_topic_vgg/free_topic_vgg.code-workspace
  현재 회로: rtl/vgg_sixteen_core_cluster.v, 16코어 x 16 MAC, 12 SRAM/core.
  V 재사용 수명/제어: architecture/V_REUSE_LIFETIME.txt
  현재 검증: experiments/v_reuse_lifetime/artifacts/REPORT_KO.txt
  진행 중: experiments/winograd_quantization/ — U8/V8 정확도 검증.
  Colab: experiments/winograd_quantization/colab/
  전체 VGG RTL 구현 완료 또는 U8/V8 RTL 적용 완료를 뜻하지 않음.

정리한 이전 자유주제 실험
  archive/free_topic_cleanup_20261028/README.txt
  과거 소스/보고서는 검증된 압축본, 재생성 가능한 컴파일/파형은 삭제.
  현재 experiments에는 wide_channels, v_reuse_lifetime, winograd_quantization만 유지.
  지정주제의 과거 보관본: archive/designated_legacy_20261025/
''',encoding='utf-8')

(project/'README.txt').write_text('''자유주제 — SRAM 기반 Winograd 가속기 (2026-10-28)

현재 기준
  16코어, 코어당 16 MAC / 12개 8KiB SRAM = 96KiB.
  rtl/vgg_sixteen_core_cluster.v가 현재 진입점이다.
  source list: rtl/full_cluster_sources.f + rtl/ab_extension_sources.f.
  RETAIN_V=1: 한 공간 위치의 V/mask를 모든 로컬 출력 채널에 재사용 후 해제.
  전체 U 상주 대신 사용할 U 묶음을 교체한다.
  architecture/V_REUSE_LIFETIME.txt가 현재 V 수명과 제어 계약이다.
  이전 4코어 top은 호환/단위 검증용으로 남아 있으며 현재 목표 코어 수가 아니다.

활성 실험 3개
  experiments/winograd_quantization/
    현재 진행 중. U8/V16 및 U8/V8 소프트웨어 PTQ, 고정 Winograd 변환.
    colab/Winograd_U8_V8_Validation.ipynb + winograd_uv8_bundle.zip.
    아직 QAT 학습 및 U8/V8 SRAM packing RTL은 적용하지 않았다.
  experiments/v_reuse_lifetime/
    현재 V 재사용과 U 교체 구현의 검증/전후 비교.
    artifacts/REPORT_KO.txt, architecture/V_REUSE_LIFETIME.txt 참고.
  experiments/wide_channels/
    C512 경계와 VGG Conv 조각의 회귀 검증. 위 V 재사용 실험의 데이터 생성기 의존성.
    artifacts/REPORT_KO.txt는 당시 결과이며 현재 PPA/전체 VGG 성능이 아니다.

유지하는 자료
  rtl/                     현재 회로 및 source lists
  tests/                   SRAM/CB/MAC/인터페이스/현재 레이어 회귀 테스트
  scripts/                 모델/정수 기준 모델/메모리/단위 회귀 도구
  model.py, config.json    CIFAR-10 VGG-16-BN 모델과 전처리
  data/, weights/          CIFAR-10, 원본 공개 가중치
  artifacts/integer_vgg/   전체 정수 소프트웨어 모델 및 레이어 기준값
  artifacts/              측정 보고서/필요한 회귀 벡터; 오래된 값은 당시 상태의 기록
  reference/              지정주제 참조 RTL, 모델 원출처/라이선스
  third_party/asap7_sram/  SRAM 원본/라이선스/생성 매크로
  architecture/           현재 계약 및 과거 설계 설명. README.txt에서 구분.

검증 상태
  FP32 공식 CIFAR-10 test: 9416/10000.
  기존 정수 모델 U16/V16: 9411/10000 (software oracle).
  U8/V8 개발 검증 1000장은 원래 사전학습의 train 데이터이므로 test 정확도가 아니다.
  전체 VGG RTL, FC/argmax 연결, U8/V8 RTL 및 최종 PPA는 완료로 주장하지 않는다.

재현 (free_topic_vgg에서 실행)
  bash experiments/v_reuse_lifetime/run.sh
  bash experiments/v_reuse_lifetime/run_cluster.sh
  bash experiments/v_reuse_lifetime/run_comparison.sh
  python experiments/v_reuse_lifetime/report.py
  bash experiments/wide_channels/run.sh
  bash experiments/wide_channels/run_cluster.sh
  양자화는 experiments/winograd_quantization/README.txt와 Colab 노트북 참고.
  이전 컴파일 실행물은 삭제했으므로 RTL 테스트 실행 시 다시 컴파일된다.

이전 실험 정리
  ../archive/free_topic_cleanup_20261028/README.txt
  15개 이전 실험과 전용 스크립트/테스트는 검증된 ZIP으로 보관 후 작업 폴더에서 제거.
  현재 RTL, 지정주제, 모델/데이터, 정수 기준값, Colab 업로드 파일은 변경하지 않았다.
''',encoding='utf-8')

(project/'experiments/README.txt').write_text('''활성 실험
winograd_quantization: 현재 U8/V8 소프트웨어 검증과 Colab 파일.
v_reuse_lifetime: 현재 V 보관/해제와 U 교체 검증, 기준본과 결과.
wide_channels: C512/VGG Conv 조각 회귀 및 V 재사용 실험의 벡터 생성 의존성.

이전 15개 실험은 ../../archive/free_topic_cleanup_20261028/retired_experiments.zip.
보고서 값은 각 실험 당시 조건이며 현재 전체 모델 성능으로 합산하지 않는다.
''',encoding='utf-8')

(project/'architecture/README.txt').write_text('''설계 문서 구분 — 2026-10-28

현재 변경 계약
  V_REUSE_LIFETIME.txt: 현재 V 수명, U 교체 제어, 출력 레이아웃.
  양자화 목표/진행: ../experiments/winograd_quantization/README.txt.

계승한 구성요소 설명
  ACTIVATION_AB_IMPLEMENTATION.txt / ACTIVATION_AB_BANK_MAP.txt
  RESULT_PIPELINE.txt / SRAM_LINE_BUFFER.txt / EXTERNAL_INTERFACE_V1.txt
  LOCAL_MULTICAST_V1.txt / SRAM_CB_MULTICAST_V2.txt
  개별 문서는 작성 당시 코어 수/채널 범위를 포함할 수 있다. 현재 RTL이 우선한다.

나머지 문서는 설계 과정/계획의 기록이다. 특히 FIXED_FOUR_CORE, implementation_v1,
FULL_VGG_EXECUTION_PLAN은 현재 16코어 전체 구현 완료의 증거가 아니다.
기존 실험 경로가 없는 경우 ../../archive/free_topic_cleanup_20261028/에서 복원한다.
''',encoding='utf-8')

(project/'experiments/wide_channels/report.py').write_text('''"""Validate retained historical regression evidence without retired-folder dependencies.

REPORT_KO.txt and summary.json remain the original historical reports.
Use v_reuse_lifetime/report.py for the current V lifetime implementation.
"""
from pathlib import Path
import json
root=Path(__file__).resolve().parent/'artifacts'
checks={}
for name,expected in [('core.log','PASS WIDE_CONV cases=44 compared_words=1412'),
                      ('cluster.log','PASS WIDE_CLUSTER commands=34 checked_words=544')]:
    text=(root/name).read_text()
    assert expected in text, name
    checks[name]=expected
result=dict(status='retained historical logs verified; no current PPA claim',checks=checks,
            original_report='REPORT_KO.txt',current_report='../v_reuse_lifetime/artifacts/REPORT_KO.txt')
(root/'evidence_check.json').write_text(json.dumps(result,indent=2)+'\\n')
print('PASS retained wide-channel regression evidence')
''',encoding='utf-8')

(folder/'README.txt').write_text('''자유주제 정리 보관본 — 2026-10-28

현재 실험은 free_topic_vgg/experiments/의 3개 폴더에서 계속한다.
이 보관본은 이전 15개 실험과 전용 스크립트/테스트/이전 안내 문서를 담는다.
소스와 보고서를 ZIP에 저장하고 각 파일 SHA256을 검증한 뒤 원래 폴더를 삭제한다.
재생성 가능한 obj/verilated/xsim 실행물, .vvp/.vcd/.wdb 등은 보관하지 않는다.

retired_experiments.zip: 과거 파일. ZIP 내부 경로는 C:/IDEC_challenge 기준 상대경로.
plan.json: 삭제 대상, 보관 파일 SHA256, 변경 금지 파일 SHA256.
result.json: 실제 삭제 완료 후 생성되는 결과.

복원은 ZIP을 새 빈 폴더에 풀고 필요한 파일만 확인해 가져온다.
현재 프로젝트에 통째로 덮어쓰면 최신 RTL/문서와 섞이므로 그렇게 복원하지 않는다.
RTL, 원본 데이터/가중치, 현재 정수 모델, 현재 Colab 노트북/ZIP은 정리 대상이 아니다.
''',encoding='utf-8')
print('Archive reverified; current navigation and historical report dependencies updated. No deletion yet.')
