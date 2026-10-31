"""Package the frozen quantization experiment for Colab, without dataset copies."""
from pathlib import Path
import hashlib
import json
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = HERE / 'colab'
OUT.mkdir(exist_ok=True)
relative = [
    'model.py', 'config.json', 'winograd_probe.py',
    'reference/upstream/LICENSE.txt', 'reference/upstream/revision.json',
    'model_tools/quantization/README.txt',
    'weights/cifar10_vgg16_bn-6ee7ea24.pt',
    'artifacts/integer_vgg/integer_parameters.pt',
    'artifacts/integer_vgg/manifest.json',
    'model_tools/quantization/probe.py',
    'model_tools/quantization/uv_common.py',
    'model_tools/quantization/evaluate_uv.py',
    'model_tools/quantization/test_uv.py',
    'model_tools/quantization/artifacts/uv8/v_calibration.json',
    'model_tools/quantization/artifacts/uv8/validation_1000.json',
]
bundle = OUT / 'winograd_uv8_bundle.zip'
with zipfile.ZipFile(bundle, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    for name in relative:
        archive.write(ROOT / name, name)
digest = hashlib.sha256(bundle.read_bytes()).hexdigest()


def cell(kind, text):
    item = dict(cell_type=kind, id=hashlib.sha256(text.encode()).hexdigest()[:12],
                metadata={}, source=text.splitlines(keepends=True))
    if kind == 'code':
        item.update(execution_count=None, outputs=[])
    return item


cells = [
    cell('markdown', '''# Fixed-transform Winograd U8/V8 검증
로컬에서 정한 스케일을 고정하고 공식 테스트 전체를 검증합니다.
이 노트북은 **PTQ 평가용이며 QAT 학습을 수행하지 않습니다**.
GPU 런타임은 사용자가 선택합니다. float64 정수 기준 계산은 GPU에서도 빠르다고
보장할 수 없으므로 100장 벤치마크의 실측 시간을 보고 전체 평가를 실행하세요.
RTL, 저장 용량 및 사이클 개선은 이 노트북의 검증 대상이 아닙니다.
'''),
    cell('code', f'''from google.colab import files
from pathlib import Path
import hashlib, zipfile, os
uploaded = files.upload()  # winograd_uv8_bundle.zip 선택
bundle = Path('winograd_uv8_bundle.zip')
assert hashlib.sha256(bundle.read_bytes()).hexdigest() == '{digest}'
project = Path('/content/idec_quantization')
project.mkdir(exist_ok=True)
with zipfile.ZipFile(bundle) as z:
    for member in z.namelist():
        assert (project / member).resolve().is_relative_to(project.resolve())
    z.extractall(project)
os.chdir(project)
'''),
    cell('code', '''import torch, torchvision, sys
from torchvision.datasets import CIFAR10
print('torch', torch.__version__, 'torchvision', torchvision.__version__)
print('GPU:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'none')
CIFAR10('data', train=True, download=True)
CIFAR10('data', train=False, download=True)
'''),
    cell('code', '''import subprocess
base = 'model_tools/quantization/'
subprocess.run([sys.executable, base+'test_uv.py'], check=True)
device = 'cuda' if torch.cuda.is_available() else 'cpu'
if device == 'cuda':
    subprocess.run([sys.executable, base+'test_uv.py', '--device', device], check=True)
# This benchmarks a calibration-disjoint development subset, not test labels.
subprocess.run([sys.executable, '-u', base+'evaluate_uv.py', '--images', '100',
                '--split', 'validation', '--device', device], check=True)
import json
benchmark = json.loads((Path(base)/'artifacts/uv8/validation_100.json').read_text())
print('Full-test estimated minutes:', benchmark['elapsed_seconds'] * 100 / 60)
'''),
    cell('markdown', '''아래 셀은 고정된 설정으로 공식 테스트 10,000장을 평가합니다.
테스트 결과를 보고 스케일을 반복 튜닝하지 마세요. QAT가 필요하면 별도의 학습/검증
단계로 돌아가고, 최종 가중치를 정수 기준 모델에서 다시 검증해야 합니다.
'''),
    cell('code', '''subprocess.run([sys.executable, '-u', base+'evaluate_uv.py', '--images', '10000',
                '--split', 'test', '--device', device], check=True)
'''),
    cell('code', '''import shutil
output = Path(base) / 'artifacts/uv8'
shutil.make_archive('/content/winograd_uv8_results', 'zip', output)
files.download('/content/winograd_uv8_results.zip')
'''),
]
notebook = dict(cells=cells, metadata=dict(kernelspec=dict(display_name='Python 3',
                language='python', name='python3')), nbformat=4, nbformat_minor=5)
(OUT / 'Winograd_U8_V8_Validation.ipynb').write_text(json.dumps(notebook, ensure_ascii=False, indent=2), encoding='utf-8')
(OUT / 'bundle_manifest.json').write_text(json.dumps(dict(sha256=digest, bytes=bundle.stat().st_size,
                files=relative, status='prepared; Colab not executed'), indent=2))
print(f'Prepared {bundle}: {bundle.stat().st_size/1024**2:.1f} MiB; Colab not executed')
