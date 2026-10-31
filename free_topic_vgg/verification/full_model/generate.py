"""Official CIFAR image -> U8/V16 or --v8 U8/V8 reference and RTL payloads.

V8 output lives in vectors_v8 so the completed V16 baseline is preserved.
"""
from pathlib import Path
import sys,json,argparse,hashlib
import numpy as np
import torch
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).parent
sys.path.insert(0,str(ROOT/'model_tools/quantization'))
from uv_common import read_cifar,image_tensor,initial_input,postprocess,direct_acc,transform_tiles,quant_v,from_v
from probe import winograd,make_u
from export_u8_sram import pack_rows
sys.path.insert(0,str(ROOT/'scripts'))
from vector_io import dump,pack

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--image',type=int,default=0);ap.add_argument('--v8',action='store_true',default=True);ap.add_argument('--v16-reference',dest='v8',action='store_false');args=ap.parse_args()
    torch.set_num_threads(2)
    out=HERE/('vectors_v8' if args.v8 else 'vectors');out.mkdir(parents=True,exist_ok=True)
    params=torch.load(ROOT/'artifacts/integer_vgg/integer_parameters.pt',weights_only=True)
    manifest=json.loads((ROOT/'artifacts/integer_vgg/manifest.json').read_text())
    cal=json.loads((ROOT/'model_tools/quantization/artifacts/uv8/v_calibration.json').read_text())
    assert cal['checkpoint_sha256']==manifest['checkpoint_sha256']
    v_shifts=[r['chosen']['shift'] for r in cal['layers']]
    images,labels=read_cifar(False)
    x=initial_input(image_tensor(images,args.image),manifest['input_scale'])
    dump(out/'input.hex',pack(x[0].permute(1,2,0).flatten().tolist()),64)
    configs=[];layers=[]
    for stage,p in enumerate(params):
        d=out/f'layer{stage}';d.mkdir(exist_ok=True)
        dump(d/'input.hex',pack(x[0].permute(1,2,0).flatten().tolist() if p['conv'] else x.flatten().tolist()),64)
        if p['conv']:
            h=x.shape[2];cin=x.shape[1];kout=p['weight'].shape[0];local_k=kout//16
            stride=128 if cin<=128 else 256 if cin<=256 else 512
            block=min(local_k,8,2048//stride)
            u,shift,_=make_u(p['weight'],8)
            payload=pack_rows(u.numpy()).copy().view('<u8').flatten()
            dump(d/'u.hex',payload,64);dump(d/'bias.hex',p['bias'].tolist(),32)
            dump(d/'mult.hex',p['multiplier'].tolist(),24);dump(d/'shift.hex',shift.tolist(),4)
            if args.v8:
                _,_,v=transform_tiles(x)
                x=postprocess(from_v(quant_v(v,v_shifts[stage]),u,shift,h,h,v_shift=v_shifts[stage]),p)
            else:
                x=postprocess(winograd(x,u,shift),p)
            oh=x.shape[2]
            for core in range(16):
                shard=x[0,core*local_k:(core+1)*local_k]
                if p['pool']: data=shard.permute(1,2,0).flatten().tolist()
                else: data=shard.reshape(local_k,oh//2,2,oh//2,2).permute(1,3,0,2,4).flatten().tolist()
                dump(d/f'gold{core}.hex',pack(data),64)
            words=(oh*oh*local_k+7)//8
        else:
            h=1;cin=512;kout=p['weight'].shape[0];local_k=10 if p['final'] else 32;block=0
            x=postprocess(direct_acc(x,p),p)
            for core in range(1 if p['final'] else 16):
                weights=np.zeros((4,1024),dtype=np.uint64)
                for group in range(1 if p['final'] else 2):
                    for r in range(4):
                        for lane in range(4):
                            k=core*32+group*16+r*4+lane
                            if k>=kout:continue
                            for c in range(512):
                                weights[r,group*256+c//2] |= np.uint64((int(p['weight'][k,c])&255)<<((c%2)*32+lane*8))
                            weights[r,512+group*4+lane]=np.uint64((int(p['bias'][k])&0xffffffff)|(int(p['multiplier'][k])<<32))
                dump(d/f'u{core}.hex',weights.flatten(),64)
                values=x[0].tolist() if p['final'] else x[0,core*32:(core+1)*32].tolist()
                dump(d/f'gold{core}.hex',values if p['final'] else pack(values),64)
            words=10 if p['final'] else 4
        configs.append((h<<48)|(cin<<32)|(kout<<16)|(local_k<<8)|(block<<1)|int(p['pool']))
        layers.append(dict(stage=stage,conv=p['conv'],input_h=h,cin=cin,cout=kout,local_k=local_k,block=block,pool=p['pool'],gold_words_per_core=words))
        print('Reference stage',stage,'shape',tuple(x.shape),flush=True)
    prediction=int(x.argmax())
    dump(out/'vshift.hex',v_shifts+[0]*3,4);dump(out/'config.hex',configs,64);dump(out/'class.hex',[prediction],4)
    result=dict(image_index=args.image,label=int(labels[args.image]),prediction=prediction,logits=x[0].tolist(),mode='U8_V8' if args.v8 else 'U8_V16',checkpoint_sha256=manifest['checkpoint_sha256'],layers=layers)
    (out/'manifest.json').write_text(json.dumps(result,indent=2)+'\n')
    print('Reference classification:',prediction,'label:',int(labels[args.image]))

if __name__=='__main__':main()
