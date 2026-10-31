"""Independent numpy B^T d B / U*V / A^T M A oracle for packed V8 tests."""
from pathlib import Path
import shutil
import numpy as np

HERE=Path(__file__).resolve().parent
SOURCE=HERE.parent/'u_supply/vectors'
OUT=HERE/'vectors'
OUT.mkdir(exist_ok=True)
def read(p): return [int(x,16) for x in p.read_text().split()]
def dump(p,a,bits=64): p.write_text(''.join(f'{int(v)&((1<<bits)-1):0{bits//4}x}\n' for v in a))
def pack(a):
    return [sum((int(v)&255)<<(8*j) for j,v in enumerate(a[i:i+8])) for i in range(0,len(a),8)]
bt=np.array([[1,0,-1,0],[0,1,1,0],[0,-1,1,0],[0,1,0,-1]],dtype=np.int64)
at=np.array([[1,1,1,0],[0,1,-1,-1]],dtype=np.int64)
shifts=[0,1,2,3,0,2,1,3,4,1]
configs=read(SOURCE/'config.hex')
dump(OUT/'config.hex',configs)
dump(OUT/'vshift.hex',shifts,4)
for case,config in enumerate(configs):
    src=SOURCE/f'case{case}';dst=OUT/f'case{case}';dst.mkdir(exist_ok=True)
    for name in ('input.hex','u8.hex','shift.hex','bias.hex','mult.hex'):
        shutil.copyfile(src/name,dst/name)
    h=(config>>40)&63;c=(config>>24)&1023;k=(config>>16)&255;pool=config&1
    words=read(dst/'input.hex')
    x=np.array([(v>>(8*j))&255 for v in words for j in range(8)][:h*h*c],dtype=np.int64).reshape(h,h,c)
    # Saturation coverage, including negative transformed values and odd C.
    if case==4:
        x=(x*25).clip(0,255)
        dump(dst/'input.hex',pack(x.flatten()))
    x=np.pad(x,((1,1),(1,1),(0,0)))
    stride=128 if c<=128 else 256 if c<=256 else 512
    raw=read(dst/'u8.hex');u=np.zeros((k,c,4,4),dtype=np.int64)
    for r in range(4):
        for ko in range(k):
            for ci in range(c):
                word=raw[r*k*(stride//2)+ko*(stride//2)+ci//2]
                for col in range(4):
                    v=(word>>((ci%2)*32+col*8))&255
                    u[ko,ci,r,col]=v if v<128 else v-256
    us=np.array(read(dst/'shift.hex'))
    bias=np.array(read(dst/'bias.hex'),dtype=np.int64);bias=np.where(bias>=2**31,bias-2**32,bias)
    mult=np.array(read(dst/'mult.hex'),dtype=np.int64)
    result=[];s=shifts[case];clipped=0
    for y in range(0,h,2):
        for z in range(0,h,2):
            tile=x[y:y+4,z:z+4].transpose(2,0,1)
            v=bt@tile@bt.T
            rounded=(v+(1<<(s-1) if s else 0))>>s
            clipped+=int((np.abs(rounded)>127).sum())
            q=rounded.clip(-127,127)
            m=(u*q[None]).sum(axis=1)*(1<<us[:,None,None])*(1<<s)
            out=at@m@at.T
            for ko in range(k):
                values=out[ko].flatten()
                if pool:values=[max(values)]
                for value in values:
                    result.append(min(255,(max(0,int(value)+int(bias[ko]))*int(mult[ko])+(1<<23))>>24))
    dump(dst/'gold.hex',pack(result))
    if case==4:
        assert clipped>0
        print('Odd-channel saturation case: clipped V elements=',clipped)
print('Generated 10 V8 cases: shifts, odd C, saturation, pooling, all zero.')

# Actual U8/V8 propagated activations and trained weights, not random tensors.
# Compare directly to the full-model Python reference for the first 4 outputs.
full=HERE.parent/'full_model/vectors_v8'
if full.exists():
    import json
    manifest=json.loads((full/'manifest.json').read_text())
    model_shifts=read(full/'vshift.hex')
    for case,stage in enumerate((8,12),start=10):
        m=manifest['layers'][stage];src=full/f'layer{stage}'
        dst=OUT/f'case{case}';dst.mkdir(exist_ok=True)
        h=m['input_h'];c=m['cin'];k=4;block=2;stride=512
        configs.append((h<<40)|(c<<24)|(k<<16)|(block<<8)|m['pool'])
        shifts.append(model_shifts[stage])
        shutil.copyfile(src/'input.hex',dst/'input.hex')
        raw=read(src/'u.hex');pairs=(c+1)//2
        dump(dst/'u8.hex',[word for r in range(4) for ko in range(k)
                          for word in raw[(r*m['cout']+ko)*pairs:(r*m['cout']+ko+1)*pairs]])
        for name,bits in [('shift',4),('bias',32),('mult',24)]:
            dump(dst/f'{name}.hex',read(src/f'{name}.hex')[:k],bits)
        raw=read(src/'gold0.hex');a=[(v>>(8*j))&255 for v in raw for j in range(8)]
        values=a[:k] if m['pool'] else [v for t in range(h*h//4)
                  for v in a[t*m['local_k']*4:t*m['local_k']*4+k*4]]
        dump(dst/'gold.hex',pack(values))
    dump(OUT/'config.hex',configs);dump(OUT/'vshift.hex',shifts,4)
    print('Added real VGG Conv9 and Conv13; golden values from U8/V8 full-model reference.')
