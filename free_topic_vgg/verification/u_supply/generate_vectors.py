"""Direct spatial convolution oracle, independent of the RTL V replay order."""
from pathlib import Path
import json
import random
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from vector_io import dump, pack, G

OUT = Path(__file__).resolve().parent / 'vectors'
cases = []
settings = [(4,3,6,2,False,False), (4,128,6,2,False,False),
            (4,512,4,2,False,False), (2,512,4,2,True,False),
            (4,129,6,2,True,False), (4,512,4,2,True,True),
            (4,3,128,8,False,False), (2,512,8,4,False,False), (2,256,16,8,False,False)]
settings.append((4,128,16,8,False,False))
for case_id, (h, cin, kout, block, pool, zero) in enumerate(settings):
    rng = random.Random(7319 + case_id)
    stride = 128 if cin <= 128 else 256 if cin <= 256 else 512
    x = [[[0 if zero or c % 4 == 0 else rng.randrange(12)
           for _ in range(h)] for _ in range(h)] for c in range(cin)]
    w = [[[[rng.randrange(-2,3) for _ in range(3)] for _ in range(3)]
          for _ in range(cin)] for _ in range(kout)]
    bias = [4*(17-k*3) for k in range(kout)]
    mult = [(1 << (20 if cin < 129 else 18)) + k*17 for k in range(kout)]
    shifts = [k % 4 for k in range(kout)]
    u = [0]*(4*kout*stride)
    conv = []
    for k in range(kout):
        for c in range(cin):
            for r in range(4):
                row = [sum(G[r][i]*w[k][c][i][j]*G[s][j]
                           for i in range(3) for j in range(3)) for s in range(4)]
                u[r*kout*stride+k*stride+c] = sum((v & 65535) << (s*16) for s,v in enumerate(row))
        conv.append([[sum(x[c][y+dy-1][z+dx-1]*w[k][c][dy][dx]
                           for c in range(cin) for dy in range(3) for dx in range(3)
                           if 0 <= y+dy-1 < h and 0 <= z+dx-1 < h)
                      for z in range(h)] for y in range(h)])
    result = []
    for ty in range(h//2):
        for tx in range(h//2):
            for k in range(kout):
                values = [conv[k][ty*2+dy][tx*2+dx] for dy in range(2) for dx in range(2)]
                for value in ([max(values)] if pool else values):
                    result.append(min(255,(max(0,4*value*(1<<shifts[k])+bias[k])*mult[k]+(1<<23)) >> 24))
    dest = OUT / f'case{case_id}'
    dump(dest/'input.hex', pack([x[c][y][z] for y in range(h) for z in range(h) for c in range(cin)]),64)
    dump(dest/'gold.hex',pack(result),64)
    u16 = [0]*len(u)
    u8 = [0]*(len(u)//2)
    for r in range(4):
        for k in range(kout):
            for c in range(cin):
                source = u[r*kout*stride+k*stride+c]
                signed = [((source>>(16*j))&65535) for j in range(4)]
                signed = [v-65536 if v>=32768 else v for v in signed]
                assert all(-128 <= v <= 127 for v in signed)
                u16[r*kout*stride+k*stride+c] = sum(((v<<shifts[k])&65535)<<(j*16) for j,v in enumerate(signed))
                half = sum((v&255)<<(j*8) for j,v in enumerate(signed))
                u8[r*kout*(stride//2)+k*(stride//2)+c//2] |= half<<((c%2)*32)
    dump(dest/'u16.hex',u16,64)
    dump(dest/'u8.hex',u8,64)
    dump(dest/'shift.hex',shifts,4)
    dump(dest/'bias.hex',bias,32)
    dump(dest/'mult.hex',mult,24)
    cases.append(dict(h=h,cin=cin,kout=kout,block=block,pool=pool,zero=zero,stride=stride))
dump(OUT/'config.hex',[(d['h']<<40)|(d['cin']<<24)|(d['kout']<<16)|(d['block']<<8)|int(d['pool']) for d in cases],64)
(OUT/'manifest.json').write_text(json.dumps(cases,indent=2)+'\n')
print(f'Generated {len(cases)} retained-V cases, including 512 input and 128 local output channels')
