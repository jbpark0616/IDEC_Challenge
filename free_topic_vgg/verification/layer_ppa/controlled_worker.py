"""One auxiliary sequential worker, sharing compiled binaries and case locks."""
from pathlib import Path
import os,subprocess,sys,time
R=Path(__file__).resolve().parents[2];O=R/'evidence/controlled_power';W=R/'build/controlled_power'
for rate in os.environ.get('PPA_RATES','fast,slow').split(','):
    # Driver log appears only after the main runner has finished compilation.
    while not (O/rate/'case0_driver.log').exists():time.sleep(5)
    env=dict(os.environ,PPA_PROJECT=str(R),PPA_WORK=str(W/rate),PPA_RESULTS=str(O/rate))
    with (O/rate/'auxiliary.log').open('w') as f:
        subprocess.run([sys.executable,str(Path(__file__).with_name('run.py')),'--cases','3','4'],env=env,stdout=f,stderr=subprocess.STDOUT,check=True)
