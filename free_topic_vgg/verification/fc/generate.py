"""Synthetic Conv boundary -> actual three quantized VGG FC layers.

Independent direct convolution and int64 dot-product oracle. All intermediate
activations remain in the RTL cluster; the TB only injects the initial image.
"""
from pathlib import Path
import sys,json,random
import torch
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).parent
OUT=HERE/'vectors'
sys.path.insert(0,str(ROOT/'scripts'))
from vector_io import G,dump,pack
torch.set_num_threads(2)
rng=random.Random(2928)
x=torch.tensor([[[rng.randrange(32) for _ in range(2)] for _ in range(2)] for _ in range(3)],dtype=torch.int64)
dump(OUT/'input.hex',pack(x.permute(1,2,0).flatten().tolist()),64)
conv=[]
for core in range(16):
    weights=torch.tensor([[[[rng.randrange(-2,3) for _ in range(3)] for _ in range(3)] for _ in range(3)] for _ in range(32)])
    bias=[k-core for k in range(32)]
    mult=[1<<21]*32
    u=[0]*(4*32*64)
    values=[]
    for k in range(32):
        for c in range(3):
            for r in range(4):
                row=[sum(G[r][i]*int(weights[k,c,i,j])*G[s][j] for i in range(3) for j in range(3)) for s in range(4)]
                u[r*32*64+k*64+c//2] |= sum((v&255)<<(s*8) for s,v in enumerate(row))<<((c%2)*32)
        pixels=[sum(int(x[c,y+dy-1,z+dx-1])*int(weights[k,c,dy,dx]) for c in range(3) for dy in range(3) for dx in range(3)
            if 0<=y+dy-1<2 and 0<=z+dx-1<2) for y in range(2) for z in range(2)]
        values.append(min(255,(max(0,4*max(pixels)+bias[k])*mult[k]+(1<<23))>>24))
    conv.extend(values)
    d=OUT/'conv'/f'core{core}'
    dump(d/'u.hex',u,64);dump(d/'bias.hex',bias,32);dump(d/'mult.hex',mult,24)
    dump(d/'gold.hex',pack(values),64)
dump(OUT/'fc_input.hex',pack(conv),64)
params=torch.load(ROOT/'artifacts/integer_vgg/integer_parameters.pt',weights_only=True)
fc=[p for p in params if not p['conv']]
v=torch.tensor(conv,dtype=torch.int64)
stats=[]
for stage,p in enumerate(fc):
    final=stage==2
    acc=p['weight'].long()@v+p['bias'].long()
    if not final: acc=acc.clamp_min(0)
    y=(acc*p['multiplier'].long()+(1<<23))>>24
    if not final: y=y.clamp(0,255)
    stats.append(dict(stage=stage,input_features=512,outputs=len(y),min_output=int(y.min()),max_output=int(y.max())))
    for core in range(1 if final else 16):
        groups=1 if final else 2
        words=[0]*4096
        for group in range(groups):
            for r in range(4):
                for lane in range(4):
                    k=core*32+group*16+r*4+lane
                    if k>=len(y):continue
                    for c in range(512):
                        words[r*1024+group*256+c//2] |= (int(p['weight'][k,c])&255)<<((c%2)*32+lane*8)
                    words[r*1024+512+group*4+lane]=(int(p['bias'][k])&0xffffffff)|(int(p['multiplier'][k])<<32)
        d=OUT/f'fc{stage}'/f'core{core}'
        dump(d/'u.hex',words,64)
        dump(d/'gold.hex',y.tolist() if final else pack(y[core*32:core*32+32].tolist()),64)
    v=y
dump(OUT/'class.hex',[int(v.argmax())],4)
(OUT/'manifest.json').write_text(json.dumps(dict(stages=stats,prediction=int(v.argmax()),logits=v.tolist(),note='Real FC parameters; synthetic Conv front-end, not full VGG inference.'),indent=2))
print('Generated Conv->FC512->FC512->FC10 oracle, predicted class',int(v.argmax()))
