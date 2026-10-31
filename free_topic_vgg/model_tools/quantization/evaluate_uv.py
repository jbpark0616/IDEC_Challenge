"""Calibrate V on train only, then compare frozen U8/V16 and U8/V8.

Development split excludes activation-calibration images. The pretrained model
did see CIFAR training images: this is NOT independent generalization accuracy.
--split test uses frozen scales and never recalibrates on test data.
"""
import argparse
import json
import time
from pathlib import Path

import numpy as np
import torch
from uv_common import (ROOT, make_u, read_cifar, image_tensor, initial_input,
                       transform_tiles, quant_v, round_shift, direct_acc,
                       postprocess, from_v)
from model import load_model

HERE = Path(__file__).parent


def calibrate(params, manifest, images, out, device):
    indices = manifest['calibration_indices']
    histogram = [torch.zeros(2041, dtype=torch.int64, device=device) for _ in range(13)]
    started = time.perf_counter()
    for count, index in enumerate(indices):
        x = initial_input(image_tensor(images, index, device), manifest['input_scale'])
        for i, p in enumerate(params[:13]):
            _, _, v = transform_tiles(x)
            assert int(v.min()) >= -1020 and int(v.max()) <= 1020
            histogram[i] += torch.bincount((v + 1020).flatten(), minlength=2041)
            x = postprocess(direct_acc(x, p), p)
        if (count + 1) % 50 == 0:
            print(f'CALIBRATION {count+1}/{len(indices)} elapsed={time.perf_counter()-started:.1f}s', flush=True)
    values = torch.arange(-1020, 1021, dtype=torch.int64, device=device)
    layers = []
    for i, hist in enumerate(histogram):
        candidates = []
        for shift in range(5):
            rounded = round_shift(values, shift)
            restored = rounded.clamp(-127, 127) * (1 << shift)
            mse = float((((values-restored).double() ** 2) * hist).sum() / hist.sum())
            clipped = int(hist[rounded.abs() > 127].sum())
            candidates.append(dict(shift=shift, mse=mse, clipped=clipped))
        chosen = min(candidates, key=lambda r: r['mse'])
        layers.append(dict(layer=i, chosen=chosen, candidates=candidates, elements=int(hist.sum())))
    result = dict(checkpoint_sha256=manifest['checkpoint_sha256'],
                  policy='per-layer power-of-two shift, minimum V reconstruction MSE on train-500',
                  calibration_indices=indices, layers=layers,
                  elapsed_seconds=time.perf_counter()-started)
    (out / 'v_calibration.json').write_text(json.dumps(result, indent=2)+'\n')
    return result


def run(args):
    torch.set_num_threads(args.threads)
    device = args.device
    source = ROOT / 'artifacts/integer_vgg'
    out = HERE / 'artifacts/uv8'
    out.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((source / 'manifest.json').read_text())
    params = torch.load(source / 'integer_parameters.pt', map_location=device, weights_only=True)
    fp = load_model().to(device)
    train_images, train_labels = read_cifar(True)
    calibration_path = out / 'v_calibration.json'
    if calibration_path.exists() and not args.recalibrate:
        calibration = json.loads(calibration_path.read_text())
        assert calibration['checkpoint_sha256'] == manifest['checkpoint_sha256']
        assert calibration['calibration_indices'] == manifest['calibration_indices']
    else:
        calibration = calibrate(params, manifest, train_images, out, device)
    v_shifts = [r['chosen']['shift'] for r in calibration['layers']]
    print(f'V shifts: {v_shifts}', flush=True)
    prepared = [make_u(p['weight'].cpu(), 8)[:2] if p['conv'] else None for p in params]
    prepared = [tuple(t.to(device) for t in pair) if pair is not None else None for pair in prepared]
    if args.split == 'test':
        images, labels = read_cifar(False)
        indices = list(range(args.images))
    else:
        images, labels = train_images, train_labels
        excluded = set(manifest['calibration_indices'])
        rng = np.random.default_rng(20261028)
        indices = []
        assert args.images % 10 == 0
        for label in range(10):
            candidates = [int(i) for i in np.flatnonzero(labels == label) if int(i) not in excluded]
            indices.extend(rng.choice(candidates, args.images // 10, replace=False).tolist())
        rng.shuffle(indices)
        assert not set(indices) & excluded
    assert 0 < args.images <= len(images)
    modes = ('U16_V16', 'U8_V16', 'U8_V8')
    result = {m: dict(correct=0, agree_reference=0, predictions=[],
                     layers=[dict(squared_error=0., reference_energy=0., elements=0,
                                  max_abs_error=0, zero_rows=0, rows=0, clipped_v=0, v_elements=0)
                             for _ in range(16)]) for m in modes}
    fp_correct = 0
    started = time.perf_counter()
    for count, index in enumerate(indices):
        image = image_tensor(images, index, device)
        label = int(labels[index])
        fp_correct += int(fp(image).argmax(1)) == label
        reference = []
        ref_pred = None
        for mode in modes:
            x = initial_input(image, manifest['input_scale'])
            for i, p in enumerate(params):
                stats = result[mode]['layers'][i]
                if mode == 'U16_V16' or not p['conv']:
                    acc = direct_acc(x, p)
                else:
                    _, _, v = transform_tiles(x)
                    v_shift = v_shifts[i] if mode == 'U8_V8' else 0
                    if mode == 'U8_V8':
                        stats['clipped_v'] += int((round_shift(v, v_shift).abs() > 127).sum())
                        v = quant_v(v, v_shift)
                    stats['v_elements'] += v.numel()
                    stats['zero_rows'] += int((v == 0).all(-1).sum())
                    stats['rows'] += v.numel() // 4
                    acc = from_v(v, *prepared[i], *x.shape[-2:], v_shift=v_shift)
                x = postprocess(acc, p)
                if mode == 'U16_V16':
                    reference.append(x)
                else:
                    delta = x.double() - reference[i].double()
                    stats['squared_error'] += float(delta.square().sum())
                    stats['reference_energy'] += float(reference[i].double().square().sum())
                    stats['elements'] += x.numel()
                    stats['max_abs_error'] = max(stats['max_abs_error'], int(delta.abs().max()))
            pred = int(x.argmax(1))
            if mode == 'U16_V16':
                ref_pred = pred
            result[mode]['correct'] += pred == label
            result[mode]['agree_reference'] += pred == ref_pred
            result[mode]['predictions'].append(pred)
        if (count + 1) % 50 == 0:
            elapsed = time.perf_counter()-started
            print(f'EVAL {args.split} {count+1}/{len(indices)} correct=' +
                  str({m:r['correct'] for m,r in result.items()}) +
                  f' elapsed={elapsed:.1f}s remaining_estimate={elapsed/(count+1)*(len(indices)-count-1):.1f}s', flush=True)
    elapsed = time.perf_counter()-started
    for r in result.values():
        for layer in r['layers']:
            layer['relative_l2'] = (layer['squared_error']/max(layer['reference_energy'],1e-12)) ** .5
    report = dict(status='PTQ software evaluation, not QAT or RTL', split=args.split,
                  images=len(indices), indices=indices, fp32_correct=fp_correct,
                  calibration=calibration, results=result, elapsed_seconds=elapsed,
                  device=device, cpu_threads=args.threads,
                  train_split_caveat='Pretrained model saw train images; validation excludes calibration and future QAT, not original pretraining.',
                  checkpoint_sha256=manifest['checkpoint_sha256'])
    name=f'{args.split}_{len(indices)}'
    (out / (name+'.json')).write_text(json.dumps(report, indent=2)+'\n')
    lines=[f'Winograd U8/V8 PTQ: {args.split}, {len(indices)} images',
           f'FP32: {fp_correct}/{len(indices)}',
           'Existing model, transform matrices and RTL unchanged; no QAT performed.']
    for mode,r in result.items():
        lines.append(f"{mode}: {r['correct']}/{len(indices)}, agreement with U16/V16: {r['agree_reference']}/{len(indices)}")
    lines.extend([f'V shifts per Conv: {v_shifts}',f'Evaluation seconds: {elapsed:.1f}',
                  'Layer errors include propagation from earlier quantized layers.',
                  'Validation train images are not independent test accuracy.',
                  'Packing and cycle/energy improvements are not RTL-validated.'])
    (out / (name+'_REPORT.txt')).write_text('\n'.join(lines)+'\n')
    print('\n'.join(lines),flush=True)


if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--images',type=int,default=1000)
    parser.add_argument('--split',choices=['validation','test'],default='validation')
    parser.add_argument('--threads',type=int,default=4)
    parser.add_argument('--device',default='cpu')
    parser.add_argument('--recalibrate',action='store_true')
    with torch.inference_mode():
        run(parser.parse_args())
