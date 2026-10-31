"""U address/capacity regression: >16 outputs, odd C, exact fit and overflow.

Uses the existing V8 lifetime/stale-commit test harness and an independent
numpy transform oracle. No larger SRAM or MAC is instantiated.
"""
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = HERE / 'vectors'
OUT.mkdir(exist_ok=True)
BT = np.array([[1,0,-1,0],[0,1,1,0],[0,-1,1,0],[0,1,0,-1]], dtype=np.int64)
AT = np.array([[1,1,1,0],[0,1,-1,-1]], dtype=np.int64)

def dump(path, values, bits=64):
    path.write_text(''.join(f'{int(x)&((1<<bits)-1):0{bits//4}x}\n' for x in values))

def pack(values):
    values=list(values)
    return [sum((int(v)&255)<<(8*j) for j,v in enumerate(values[i:i+8]))
            for i in range(0,len(values),8)]

configs=[]
for case,(channels,outputs) in enumerate([(3,32),(3,128),(63,32),(65,32)]):
    rng=np.random.default_rng(310+case)
    dst=OUT/f'case{case}'
    dst.mkdir(exist_ok=True)
    h=4; stride=128; block=8
    x=rng.integers(0,8,(h,h,channels),dtype=np.int64)
    x[:,:,::3]=0
    u=rng.integers(-2,3,(outputs,channels,4,4),dtype=np.int64)
    # Positive small bias ensures the output is not trivially zero.
    bias=np.arange(outputs,dtype=np.int64)+8
    dump(dst/'input.hex',pack(x.flatten()))
    words=[]
    for row in range(4):
        for ko in range(outputs):
            for pair in range(stride//2):
                word=0
                for half in range(2):
                    ci=2*pair+half
                    if ci<channels:
                        for col in range(4): word|=(int(u[ko,ci,row,col])&255)<<(half*32+col*8)
                words.append(word)
    dump(dst/'u8.hex',words)
    dump(dst/'bias.hex',bias,32)
    dump(dst/'shift.hex',[0]*outputs,4)
    dump(dst/'mult.hex',[1<<20]*outputs,24)
    padded=np.pad(x,((1,1),(1,1),(0,0)))
    result=[]
    for y in range(0,h,2):
        for z in range(0,h,2):
            v=(BT @ padded[y:y+4,z:z+4].transpose(2,0,1) @ BT.T).clip(-127,127)
            transformed=(u*v[None]).sum(axis=1)
            out=AT @ transformed @ AT.T
            for ko in range(outputs):
                for value in out[ko].flatten():
                    result.append(min(255,(max(0,int(value)+int(bias[ko]))*(1<<20)+(1<<23))>>24))
    dump(dst/'gold.hex',pack(result))
    configs.append((h<<40)|(channels<<24)|(outputs<<16)|(block<<8))
dump(OUT/'config.hex',configs)
dump(OUT/'vshift.hex',[0]*len(configs),4)
tb=(ROOT/'verification/v8/tb_v8_packed.sv').read_text()
tb=tb.replace('tb_v8_packed','tb_u_address')
tb=tb.replace('DENSE_U=0','DENSE_U=1')
tb=tb.replace('[0:11]','[0:3]').replace('case_id<12','case_id<4')
tb=tb.replace('verification/v8/vectors','verification/u_supply/address_checks/vectors')
(HERE/'tb_u_address.sv').write_text(tb)
print('Generated U address tests: C/K=3/32, 3/128, 63/32 (1024 words), 65/32 (1056 words)')
