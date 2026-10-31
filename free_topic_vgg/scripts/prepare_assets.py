"""Download pinned model references and verified public assets into this project."""
from pathlib import Path
import hashlib,json,urllib.request,shutil
from datetime import datetime,timezone
from torchvision.datasets import CIFAR10

PROJECT=Path(__file__).resolve().parents[1]
ROOT=PROJECT.parent
REPO='chenyaofo/pytorch-cifar-models'
WEIGHT='cifar10_vgg16_bn-6ee7ea24.pt'
def sha(p): return hashlib.file_digest(p.open('rb'),'sha256').hexdigest()
def download(url,path):
    path.parent.mkdir(parents=True,exist_ok=True)
    if not path.exists():
        print('Download:',url,flush=True)
        request=urllib.request.Request(url,headers={'User-Agent':'IDEC-free-topic-analysis'})
        temp=path.with_suffix(path.suffix+'.tmp')
        with urllib.request.urlopen(request,timeout=90) as response,temp.open('wb') as f:
            shutil.copyfileobj(response,f)
        temp.replace(path)
    return {'url':url,'path':path.relative_to(PROJECT).as_posix(),'sha256':sha(path),'bytes':path.stat().st_size}

def main():
    ref=PROJECT/'reference/upstream'
    ref.mkdir(parents=True,exist_ok=True)
    revision=ref/'revision.json'
    if not revision.exists():
        request=urllib.request.Request(f'https://api.github.com/repos/{REPO}/commits/master',
                                       headers={'User-Agent':'IDEC-free-topic-analysis'})
        with urllib.request.urlopen(request,timeout=60) as response:
            commit=json.load(response)['sha']
        revision.write_text(json.dumps({'repository':REPO,'commit':commit},indent=2))
    commit=json.loads(revision.read_text())['commit']
    files=[]
    for remote,local in [('pytorch_cifar_models/vgg.py','vgg.py.txt'),('LICENSE','LICENSE.txt'),('README.md','UPSTREAM_README.txt')]:
        files.append(download(f'https://raw.githubusercontent.com/{REPO}/{commit}/{remote}',ref/local))
    files.append(download(f'https://github.com/{REPO}/releases/download/vgg/{WEIGHT}',PROJECT/'weights'/WEIGHT))
    assert files[-1]['sha256'].startswith('6ee7ea24'),'Published checkpoint hash prefix mismatch'
    files.append(download('https://cdn.jsdelivr.net/gh/chenyaofo/pytorch-cifar-models@logs/logs/cifar10/vgg16_bn/default.log',ref/'training_log.txt'))
    for train in (True,False):
        dataset=CIFAR10(str(PROJECT/'data'),train=train,download=True)
        print('CIFAR-10', 'train' if train else 'test',len(dataset),flush=True)
    dataset_files=[{'path':p.relative_to(PROJECT).as_posix(),'sha256':sha(p)}
                   for p in sorted((PROJECT/'data/cifar-10-batches-py').glob('*')) if p.is_file()]
    (PROJECT/'assets_manifest.json').write_text(json.dumps({'retrieved_utc':datetime.now(timezone.utc).isoformat(),
        'model_repository':REPO,'model_commit':commit,'assets':files,
        'dataset_source':'https://www.cs.toronto.edu/~kriz/cifar.html',
        'torchvision_dataset_md5_verified':True,'dataset_files':dataset_files},indent=2))
    print('Pinned model and CIFAR assets are ready.',flush=True)

if __name__=='__main__': main()
