"""Fixed F(2,3) integer simulation shared by CPU evaluation and Colab."""
import hashlib
import pickle
import tarfile

import numpy as np
import torch
import torch.nn.functional as F
from torchvision.datasets import CIFAR10
from probe import ROOT, CONFIG, make_u, transform_tiles


def read_cifar(train=True):
    files = CIFAR10.train_list if train else CIFAR10.test_list
    images, labels = [], []
    with tarfile.open(ROOT / 'data/cifar-10-python.tar.gz', 'r:gz') as archive:
        for name, md5 in files:
            payload = archive.extractfile('cifar-10-batches-py/' + name).read()
            assert hashlib.md5(payload).hexdigest() == md5
            batch = pickle.loads(payload, encoding='latin1')
            images.append(batch['data'].reshape(-1, 3, 32, 32))
            labels.extend(batch['labels'])
    return np.concatenate(images), np.array(labels)


def image_tensor(images, index, device='cpu'):
    x = torch.tensor(images[index], device=device, dtype=torch.float32).unsqueeze(0) / 255
    mean = torch.tensor(CONFIG['mean'], device=device).view(1, 3, 1, 1)
    std = torch.tensor(CONFIG['std'], device=device).view(1, 3, 1, 1)
    return (x - mean) / std


def round_shift(value, shift):
    """Signed round-half-up. shift=0 is exact; no floating-point rounding."""
    return (value + ((1 << shift) // 2)) >> shift


def quant_v(v, shift):
    return round_shift(v, shift).clamp(-127, 127)


def postprocess(acc, p):
    shape = (1, -1, 1, 1) if p['conv'] else (1, -1)
    y = acc + p['bias'].reshape(shape)
    if not p['final']:
        y = y.clamp_min(0)
    multiplier = p['multiplier'].reshape(shape)
    assert float(y.abs().max()) * float(multiplier.max()) < 2**63 - 2**23
    x = (y * multiplier + (1 << 23)) >> 24
    if not p['final']:
        x = x.clamp(0, 255)
    if p['pool']:
        x = F.max_pool2d(x.double(), 2).long()
    return x


def direct_acc(x, p):
    if p['conv']:
        return F.conv2d(x.double(), p['weight'].double(), padding=1).long() * 4
    return F.linear(x.flatten(1).double(), p['weight'].double()).long()


def from_v(v, u, u_shift, h, w, v_shift=0):
    n, tiles, channels, _, _ = v.shape
    k = u.shape[0]
    left = v.permute(3, 4, 0, 1, 2).reshape(16, n * tiles, channels).double()
    right = u.permute(2, 3, 1, 0).reshape(16, channels, k).double()
    # <=512 channels, signed U<=127 and V<=1020: integer products/sums
    # are well below 2**53, so float64 GEMM reproduces integer reduction.
    m = torch.bmm(left, right).reshape(4, 4, n, tiles, k).permute(2, 3, 4, 0, 1).long()
    m = m * (1 << (u_shift + v_shift)).reshape(1, 1, k, 1, 1)
    t = torch.stack((m[..., 0, :] + m[..., 1, :] + m[..., 2, :],
                     m[..., 1, :] - m[..., 2, :] - m[..., 3, :]), dim=-2)
    y = torch.stack((t[..., 0] + t[..., 1] + t[..., 2],
                     t[..., 1] - t[..., 2] - t[..., 3]), dim=-1)
    return y.reshape(n, h // 2, w // 2, k, 2, 2).permute(0, 3, 1, 4, 2, 5).reshape(n, k, h, w)


def initial_input(image, scale):
    return torch.round(image / scale).clamp(-127, 127).long()
