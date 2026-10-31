"""Independent arithmetic checks before dataset evaluation."""
import argparse
import torch
import torch.nn.functional as F
from uv_common import make_u, from_v, transform_tiles, quant_v, round_shift

torch.set_num_threads(2)
torch.manual_seed(19)
parser = argparse.ArgumentParser()
parser.add_argument('--device', default='cpu')
device = parser.parse_args().device
values = torch.tensor([-1020, -257, -255, -3, -1, 0, 1, 3, 255, 257, 1020])
for shift in range(5):
    scale = 1 << shift
    expected = torch.tensor([max(-127, min(127, (int(v) + scale//2)//scale)) for v in values])
    assert torch.equal(quant_v(values, shift), expected)
    assert quant_v(torch.zeros(4, dtype=torch.int64), shift).eq(0).all()

a = torch.tensor([[1,1,1,0], [0,1,-1,-1]], dtype=torch.float64, device=device)
for channels,h,k in [(3,4,5),(17,6,3),(512,2,2)]:
    x = torch.randint(-127,128,(1,channels,h,h)).to(device)
    w = torch.randint(-127,128,(k,channels,3,3)).to(device)
    _,_,v = transform_tiles(x)
    u16,s16,_ = make_u(w.cpu(),16)
    u16,s16 = u16.to(device),s16.to(device)
    actual = from_v(v,u16,s16,h,h)
    direct = F.conv2d(x.double(),w.double(),padding=1).long()*4
    assert torch.equal(actual,direct)
    u8,s8,_ = make_u(w.cpu(),8)
    u8,s8 = u8.to(device),s8.to(device)
    qv = quant_v(v,3)
    actual = from_v(qv,u8,s8,h,h,3)
    # Independent coordinate contraction using restored operands.
    restored_u = u8 * (1 << s8).reshape(k,1,1,1)
    m = torch.einsum('ntcij,kcij->ntkij',(qv*8).double(),restored_u.double())
    y = torch.einsum('ri,ntkij,sj->ntkrs',a,m,a)
    reference = y.reshape(1,h//2,h//2,k,2,2).permute(0,3,1,4,2,5).reshape(1,k,h,h).long()
    assert torch.equal(actual,reference)
print(f'PASS {device}: U/V signed rounding, saturation, zero preservation, scale restoration, and direct convolution identity')
