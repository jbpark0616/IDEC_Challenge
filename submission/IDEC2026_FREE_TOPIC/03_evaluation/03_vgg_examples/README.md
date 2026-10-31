# 실제 VGG 추가 사례

Conv8(case12): 입력 [1,4,4,256], Conv12(case13): 입력 [1,2,2,512]. 같은 CIFAR-10 test image 0의 저장된 중간 activation과 학습된 가중치를 사용하며 각 코어 출력 4채널만 측정한다. 초기 U 적재 제외, 가중치 상주, ICG 공통 유지, sparse OFF/ON 비교이다.

Linux/WSL, Icarus Verilog 12 및 OpenROAD/ORFS 환경에서 ORFS_ROOT를 설정하고 `python3 reproduce.py --cases 12 13`을 실행한다. 공통 코어와 셀 모델은 03 폴더에서 재사용한다.
