"""Fetch the exact official CIFAR archive with validated HTTP byte ranges."""
from pathlib import Path
import concurrent.futures,urllib.request,hashlib,time
PROJECT=Path(__file__).resolve().parents[1]
URL='https://cave.cs.toronto.edu/kriz/cifar-10-python.tar.gz?download=1'
SIZE=170498071
MD5='c58f30108f718f92721af3b95e74349a'
parts=PROJECT/'data/download_parts';parts.mkdir(parents=True,exist_ok=True)
STEP=8*1024*1024
def fetch(start):
    end=min(start+STEP,SIZE)-1
    path=parts/str(start)
    if path.exists() and path.stat().st_size==end-start+1: return start
    for attempt in range(6):
        try:
            req=urllib.request.Request(URL,headers={'Range':f'bytes={start}-{end}','User-Agent':'IDEC-analysis'})
            with urllib.request.urlopen(req,timeout=60) as response:
                assert response.status==206 and response.headers['Content-Range']==f'bytes {start}-{end}/{SIZE}',response.headers
                with path.open('wb') as f:
                    while chunk:=response.read(1024*1024): f.write(chunk)
            assert path.stat().st_size==end-start+1
            print(f'Range done {start}-{end}',flush=True)
            return start
        except Exception:
            if attempt==5: raise
            time.sleep(2+attempt)
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    list(pool.map(fetch,range(0,SIZE,STEP)))
dest=PROJECT/'data/cifar-10-python.tar.gz.parallel'
with dest.open('wb') as f:
    for start in range(0,SIZE,STEP):
        with (parts/str(start)).open('rb') as src:
            while chunk:=src.read(1024*1024): f.write(chunk)
with dest.open('rb') as f: assert hashlib.file_digest(f,'md5').hexdigest()==MD5
print('Verified complete official archive:',dest,flush=True)
