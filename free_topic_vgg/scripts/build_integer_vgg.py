"""BN-folded, bit-exact integer contract for the existing Winograd datapath.

Spatial weights: signed INT8. U=G2*w*G2^T: exact signed INT16 (no U requant).
IT input: signed INT8 first layer, UINT8 thereafter. Output transform scale=4.
Conv/FC1/FC2: bias, ReLU, round-half-up / 2**24, UINT8 saturation.
Final FC: signed common-scale INT32 logits; no ReLU. This is a software oracle,
not evidence that the complete RTL classifier has been implemented.
"""
from pathlib import Path
import argparse
import hashlib
import json
import sys
import time

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import torch
from torch import nn
from torch.nn import functional as F
from torchvision import datasets,transforms
from model import PROJECT,CONFIG,load_model

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--images',type=int,default=100)
    parser.add_argument('--threads',type=int,default=4)
    a=parser.parse_args()
    torch.set_num_threads(a.threads)
    out=PROJECT/'artifacts/integer_vgg'
    out.mkdir(parents=True,exist_ok=True)
    model=load_model()
    pre=transforms.Compose([transforms.ToTensor(),transforms.Normalize(CONFIG['mean'],CONFIG['std'])])
    train=datasets.CIFAR10(str(PROJECT/'data'),train=True,transform=pre,download=False)
    test=datasets.CIFAR10(str(PROJECT/'data'),train=False,transform=pre,download=False)
    indices=json.loads((PROJECT/'artifacts/profile_indices.json').read_text())['train_calibration']
    modules=[(n,m) for n,m in model.named_modules() if isinstance(m,(nn.Conv2d,nn.Linear))]
    maxima={n:0.0 for n,_ in modules}
    final_max=[0.0]
    def observer(name):
        def hook(module,args):
            maxima[name]=max(maxima[name],float(args[0].abs().max()))
        return hook
    hooks=[m.register_forward_pre_hook(observer(n)) for n,m in modules]
    def output_observer(module,args,value):
        final_max[0]=max(final_max[0],float(value.abs().max()))
    hooks.append(modules[-1][1].register_forward_hook(output_observer))
    started=time.perf_counter()
    with torch.inference_mode():
        for batch,(x,_) in enumerate(torch.utils.data.DataLoader(torch.utils.data.Subset(train,indices),batch_size=32)):
            model(x)
            if batch%4==0: print(f'CALIBRATION images={min((batch+1)*32,len(indices))}/{len(indices)}',flush=True)
    for handle in hooks: handle.remove()
    scales=[max(maxima[n],1e-12)/(127 if i==0 else 255) for i,(n,_) in enumerate(modules)]
    scales.append(max(final_max[0],1e-12)/32767)
    layers=[]
    tensors=[]
    g=torch.tensor(((2,0,0),(1,1,1),(1,-1,1),(0,0,2)),dtype=torch.float64)
    for i,(name,module) in enumerate(modules):
        conv=isinstance(module,nn.Conv2d)
        weight=module.weight.detach().double()
        bias=module.bias.detach().double()
        pool=False
        if conv:
            pos=int(name.split('.')[1]);bn=model.features[pos+1]
            scale=bn.weight.detach().double()/torch.sqrt(bn.running_var.double()+bn.eps)
            weight=weight*scale[:,None,None,None]
            bias=(bias-bn.running_mean.double())*scale+bn.bias.detach().double()
            pool=pos+3<len(model.features) and isinstance(model.features[pos+3],nn.MaxPool2d)
        axes=tuple(range(1,weight.ndim))
        sw=weight.abs().amax(dim=axes).clamp_min(1e-12)/127
        expand=(-1,)+(1,)*(weight.ndim-1)
        qw=torch.round(weight/sw.reshape(expand)).clamp(-127,127).to(torch.int8)
        factor=4 if conv else 1
        qb=torch.round(factor*bias/(scales[i]*sw)).to(torch.int64)
        qm=torch.round(scales[i]*sw/(factor*scales[i+1])*(1<<24)).to(torch.int64)
        assert qb.abs().max()<1<<31, (name,'bias overflow')
        assert qm.min()>=0 and qm.max()<1<<24, (name,'requant multiplier overflow')
        prefix=f'layer{i:02d}'
        if conv:
            u_exact=torch.einsum('ri,kcij,sj->kcrs',g,qw.double(),g).to(torch.int64)
            assert int(u_exact.abs().max())<1<<15
            u=u_exact.to(torch.int16)
            payload=u.numpy().astype('<i2').tobytes()
            fmt='K,C,WinogradRow,WinogradCol; little-endian signed16; G2 scale=4'
        else:
            payload=qw.numpy().tobytes()
            fmt='K,C; signed8'
        (out/f'{prefix}_weights.bin').write_bytes(payload)
        (out/f'{prefix}_bias.bin').write_bytes(qb.numpy().astype('<i4').tobytes())
        (out/f'{prefix}_multiplier.bin').write_bytes(qm.numpy().astype('<u4').tobytes())
        tensors.append(dict(weight=qw,bias=qb,multiplier=qm,pool=pool,conv=conv,final=i==15))
        layers.append(dict(id=i,name=name,op='conv3x3' if conv else 'fc',
            input_channels=weight.shape[1],output_channels=weight.shape[0],pooling=pool,
            input_scale=scales[i],output_scale=scales[i+1],weight_scales=sw.tolist(),
            first_input_signed=i==0,output_signed=i==15,payload_format=fmt,
            weights_bytes=len(payload),weights_sha256=hashlib.sha256(payload).hexdigest(),
            min_bias=int(qb.min()),max_bias=int(qb.max()),max_multiplier=int(qm.max())))
    torch.save(tensors,out/'integer_parameters.pt')
    correct=fp_correct=agreement=0
    predictions=[]
    max_acc=[0]*16
    clipped=[0]*16
    with torch.inference_mode():
        for image_id in range(a.images):
            image,label=test[image_id]
            x=torch.round(image[None]/scales[0]).clamp(-127,127).to(torch.int64)
            if image_id==0:
                (out/'input_000.bin').write_bytes(x[0].permute(1,2,0).to(torch.int8).numpy().tobytes())
            for i,params in enumerate(tensors):
                w=params['weight']
                # Every integer product and sum is exact in float64 here.
                # Conversion is before bias/requant; those operations use int64.
                if params['conv']:
                    acc=F.conv2d(x.double(),w.double(),padding=1).to(torch.int64)*4
                    shape=(1,-1,1,1)
                else:
                    x=x.flatten(1)
                    acc=F.linear(x.double(),w.double()).to(torch.int64)
                    shape=(1,-1)
                max_acc[i]=max(max_acc[i],int(acc.abs().max()))
                y=acc+params['bias'].reshape(shape)
                if not params['final']: y=y.clamp_min(0)
                mult=params['multiplier'].reshape(shape)
                assert float(y.abs().max())*float(mult.max())<2**63-2**23
                x=(y*mult+(1<<23))>>24
                if not params['final']:
                    clipped[i]+=int((x>255).sum())
                    x=x.clamp(0,255)
                if params['pool']:
                    x=F.max_pool2d(x.double(),2).to(torch.int64)
                if image_id==0:
                    values=x[0].permute(1,2,0) if params['conv'] else x[0]
                    dtype='<i4' if params['final'] else 'u1'
                    (out/f'layer{i:02d}_gold_000.bin').write_bytes(values.numpy().astype(dtype).tobytes())
                    layers[i]['output_shape']=list(x.shape)
            pred=int(x.argmax(1));fp=int(model(image[None]).argmax(1))
            correct+=pred==label;fp_correct+=fp==label;agreement+=pred==fp
            predictions.append(dict(index=image_id,label=label,integer=pred,fp32=fp))
            if image_id%100==0 or image_id+1==a.images:
                print(f'INTEGER EVAL {image_id+1}/{a.images} correct={correct} fp32={fp_correct} elapsed={time.perf_counter()-started:.1f}s',flush=True)
    manifest=dict(status='software_integer_oracle_not_full_RTL_validation',
        model=CONFIG['model'],calibration_split='train',calibration_images=len(indices),
        calibration_indices=indices,input_scale=scales[0],layers=layers,
        checkpoint_sha256=hashlib.sha256((PROJECT/CONFIG['checkpoint']).read_bytes()).hexdigest(),
        evaluation_split='full official test split' if a.images==10000 else 'test first N (not full-test accuracy)',evaluated_images=a.images,
        integer_correct=correct,fp32_correct=fp_correct,agreement=agreement,
        predictions=predictions,max_abs_accumulators=max_acc,saturated_elements=clipped,
        rounding='bias ties-even offline; (product+2^23) arithmetic shift 24 in datapath',
        elapsed_seconds=time.perf_counter()-started)
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(f'PASS INTEGER ORACLE: {correct}/{a.images}; FP32 {fp_correct}/{a.images}; 13 Conv + 5 pool + 3 FC',flush=True)

if __name__=='__main__': main()
