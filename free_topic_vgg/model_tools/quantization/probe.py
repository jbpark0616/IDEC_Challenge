"""Fixed-transform U-domain PTQ baseline. No training or RTL changes.

One power-of-two scale per output channel, shared by all C and 16 U
coordinates. Restore scale after C reduction and before the output transform.
V stays exact INT16; existing activation/FC/bias/requant contracts are reused.
"""
from pathlib import Path
import argparse
import json
import sys
import time
import hashlib
import pickle
import tarfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
import torch
import torch.nn.functional as F
from torchvision import datasets, transforms
from model import CONFIG, load_model
from winograd_probe import transform_tiles


def make_u(weight, bits):
    g = torch.tensor([[2, 0, 0], [1, 1, 1], [1, -1, 1], [0, 0, 2]], dtype=torch.float64)
    exact = torch.einsum('ri,kcij,sj->kcrs', g, weight.double(), g).long()
    limit = (1 << (bits - 1)) - 1
    peak = exact.abs().flatten(1).amax(1).clamp_min(1)
    shift = torch.ceil(torch.log2(peak.double() / limit)).clamp_min(0).long()
    scale = (1 << shift).reshape(-1, 1, 1, 1)
    # Round-half-up, including negative values, followed by symmetric clipping.
    rounded = torch.floor((exact.double() + scale // 2) / scale).long()
    quant = rounded.clamp(-limit, limit)
    restored = quant * scale
    return quant, shift, dict(max_shift=int(shift.max()),
                             max_error=int((restored - exact).abs().max()),
                             clipped=int((rounded != quant).sum()),
                             elements=exact.numel())


def winograd(x, u, shift):
    _, _, v = transform_tiles(x)
    n, tiles, channels, _, _ = v.shape
    k = u.shape[0]
    left = v.permute(3, 4, 0, 1, 2).reshape(16, n * tiles, channels).double()
    right = u.permute(2, 3, 1, 0).reshape(16, channels, k).double()
    m = torch.bmm(left, right).reshape(4, 4, n, tiles, k).permute(2, 3, 4, 0, 1).long()
    m = m * (1 << shift).reshape(1, 1, k, 1, 1)
    # Integer A^T M A, matching F(2,3) and the G2 scale factor of four.
    t = torch.stack((m[..., 0, :] + m[..., 1, :] + m[..., 2, :],
                     m[..., 1, :] - m[..., 2, :] - m[..., 3, :]), dim=-2)
    y = torch.stack((t[..., 0] + t[..., 1] + t[..., 2],
                     t[..., 1] - t[..., 2] - t[..., 3]), dim=-1)
    h, w = x.shape[-2:]
    return y.reshape(n, h // 2, w // 2, k, 2, 2).permute(0, 3, 1, 4, 2, 5).reshape(n, k, h, w)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--images', type=int, default=100)
    parser.add_argument('--threads', type=int, default=4)
    args = parser.parse_args()
    torch.set_num_threads(args.threads)
    out = Path(__file__).parent / 'artifacts'
    out.mkdir(parents=True, exist_ok=True)
    source = ROOT / 'artifacts/integer_vgg'
    manifest = json.loads((source / 'manifest.json').read_text())
    params = torch.load(source / 'integer_parameters.pt', weights_only=True)
    pre = transforms.Compose([transforms.ToTensor(), transforms.Normalize(CONFIG['mean'], CONFIG['std'])])
    # Use the already downloaded archive. Its extracted directory may have WSL
    # permissions that Windows cannot read. Verify the official batch checksum.
    with tarfile.open(ROOT / 'data/cifar-10-python.tar.gz', 'r:gz') as archive:
        payload = archive.extractfile('cifar-10-batches-py/test_batch').read()
    assert hashlib.md5(payload).hexdigest() == datasets.CIFAR10.test_list[0][1]
    batch = pickle.loads(payload, encoding='latin1')
    images = batch['data'].reshape(-1, 3, 32, 32).transpose(0, 2, 3, 1)
    test = [(pre(images[i]), label) for i, label in enumerate(batch['labels'])]
    assert 0 < args.images <= len(test)
    fp = load_model()
    modes = (16, 12, 10, 8)
    prepared = {}
    layer_stats = {}
    for bits in modes:
        prepared[bits], layer_stats[bits] = [], []
        for p in params:
            if p['conv']:
                u, shift, stats = make_u(p['weight'], bits)
                prepared[bits].append((u, shift))
                layer_stats[bits].append(stats)
            else:
                prepared[bits].append(None)
    torch.save([dict(u=q[0].to(torch.int8), shift=q[1]) for q in prepared[8] if q is not None],
               out / 'u8_candidates.pt')
    results = {bits: dict(correct=0, agree_fp32=0, predictions=[]) for bits in modes}
    fp_correct = 0
    start = time.perf_counter()
    with torch.inference_mode():
        for image_id in range(args.images):
            image, label = test[image_id]
            fp_pred = int(fp(image[None]).argmax(1))
            fp_correct += fp_pred == label
            for bits in modes:
                x = torch.round(image[None] / manifest['input_scale']).clamp(-127, 127).long()
                for i, p in enumerate(params):
                    if p['conv']:
                        acc = winograd(x, *prepared[bits][i])
                        if bits == 16 and image_id == 0:
                            direct = F.conv2d(x.double(), p['weight'].double(), padding=1).long() * 4
                            assert torch.equal(acc, direct), f'Winograd mismatch at layer {i}'
                        shape = (1, -1, 1, 1)
                    else:
                        acc = F.linear(x.flatten(1).double(), p['weight'].double()).long()
                        shape = (1, -1)
                    y = acc + p['bias'].reshape(shape)
                    if not p['final']:
                        y = y.clamp_min(0)
                    mult = p['multiplier'].reshape(shape)
                    assert float(y.abs().max()) * float(mult.max()) < 2**63 - 2**23
                    x = (y * mult + (1 << 23)) >> 24
                    if not p['final']:
                        x = x.clamp(0, 255)
                    if p['pool']:
                        x = F.max_pool2d(x.double(), 2).long()
                pred = int(x.argmax(1))
                results[bits]['correct'] += pred == label
                results[bits]['agree_fp32'] += pred == fp_pred
                results[bits]['predictions'].append(pred)
            if (image_id + 1) % 10 == 0:
                print(f'PTQ images={image_id+1} fp32={fp_correct} correct=' +
                      str({b: r['correct'] for b, r in results.items()}) +
                      f' elapsed={time.perf_counter()-start:.1f}s', flush=True)
    report = dict(status='U-domain PTQ screening, not QAT or RTL validation',
                  images=args.images, split='first N official test images; not full-test accuracy',
                  calibration='existing train-500 activation scales; U shifts depend only on weights',
                  fp32_correct=fp_correct, results=results, layer_stats=layer_stats,
                  checkpoint_sha256=manifest['checkpoint_sha256'],
                  policy='fixed G2/B/A, U signed symmetric, one shift per K, V exact, ACC unchanged',
                  elapsed_seconds=time.perf_counter()-start)
    (out / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
    lines = ['Winograd U-domain PTQ preliminary experiment',
             'No QAT training. No RTL changes. V remains INT16.',
             f'First {args.images} CIFAR-10 test images; FP32 correct={fp_correct}',
             'bits | correct | FP32 agreement | ideal packed U bytes (metadata excluded)']
    for bits in modes:
        count = sum(s['elements'] for s in layer_stats[bits])
        lines.append(f"{bits} | {results[bits]['correct']} | {results[bits]['agree_fp32']} | {(count*bits+7)//8}")
    lines.extend(['U16 Winograd equals direct integer Conv at all 13 layers on first image.',
                  'Storage savings require SRAM packing/unpacking RTL; current cycles unchanged.',
                  'Only U quantized: no new V row-mask sparsity claim. No 8-bit ACC claim.'])
    (out / 'REPORT.txt').write_text('\n'.join(lines) + '\n')
    print('\n'.join(lines), flush=True)


if __name__ == '__main__':
    main()
