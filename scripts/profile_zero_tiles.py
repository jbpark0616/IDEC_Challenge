"""Count exact all-zero tiles in the fixed-task RTL's windows (NumPy only).

Reproduce exported W4/INT18 inference to obtain Conv2 inputs. This measures
data/operation opportunities, not cycle savings. No RTL is modified.
"""
import hashlib
import json
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
EXPORT = ROOT / 'training/export/qat_winograd3x3_w4_frozen_aug'
BT = np.array([[1, 0, -1, 0], [0, 1, 1, 0], [0, -1, 1, 0], [0, 1, 0, -1]], dtype=np.int64)


def sat(x):
    return np.clip(x, -(1 << 17), (1 << 17) - 1)


def tiles(x):
    return np.lib.stride_tricks.sliding_window_view(x, (4, 4), axis=(-2, -1))[:, :, ::2, ::2]


def conv_pool(x, u, bias, multiplier):
    v = BT @ tiles(x) @ BT.T
    assert v.min() >= -1024 and v.max() <= 1023
    m = np.zeros((x.shape[0], u.shape[0], *v.shape[2:]), dtype=np.int64)
    for c in range(x.shape[1]):
        product = v[:, None, c] * u[None, :, c, None, None]
        assert product.min() >= -(1 << 14) and product.max() < (1 << 14)
        m = sat(m + product)
    left = np.stack((sat(sat(m[..., 0, :] + m[..., 1, :]) + m[..., 2, :]),
                     sat(sat(m[..., 1, :] - m[..., 2, :]) - m[..., 3, :])), axis=-2)
    y = np.stack((sat(sat(left[..., 0] + left[..., 1]) + left[..., 2]),
                  sat(sat(left[..., 1] - left[..., 2]) - left[..., 3])), axis=-1)
    # Fused max-pool/bias/ReLU/requant order used by winograd_postprocess.v.
    pooled = np.maximum(sat(y.max(axis=(-2, -1)) + bias[None, :, None, None]), 0)
    return np.clip((pooled * multiplier + (1 << 23)) >> 24, 0, 255)


def stats(x, output_channels, u):
    d = tiles(x)
    v = BT @ d @ BT.T
    zero = (d == 0).all(axis=(-2, -1))  # image, input channel, row, col
    assert np.array_equal(zero, (v == 0).all(axis=(-2, -1)))
    counts = zero.sum(axis=(1, 2, 3))
    channels_zero = zero.sum(axis=1)
    zero_per_channel = zero.sum(axis=(0, 2, 3))
    # Among skipped vector beats, do not count already-zero weights as new work.
    nonzero_weights = (u != 0).sum(axis=(0, 2, 3))
    return {
        'input_shape': list(x.shape),
        'tile_shape': list(d.shape),
        'input_zero_percent': 100 * float((x == 0).mean()),
        'channel_tiles': int(zero.size),
        'zero_channel_tiles': int(zero.sum()),
        'zero_channel_tile_percent': 100 * float(zero.mean()),
        'zero_tiles_per_image_mean': float(counts.mean()),
        'zero_tiles_per_image_min': int(counts.min()),
        'zero_tiles_per_image_max': int(counts.max()),
        'zero_channel_tiles_by_channel': zero_per_channel.tolist(),
        'zero_tile_percent_by_channel': (100 * zero.mean(axis=(0, 2, 3))).tolist(),
        'spatial_tiles': int(channels_zero.size),
        'all_channels_zero_spatial_tiles': int((channels_zero == x.shape[1]).sum()),
        'zero_channel_count_histogram': np.bincount(channels_zero.ravel(), minlength=x.shape[1]+1).tolist(),
        'zero_rate_by_spatial_position': zero.mean(axis=(0, 1)).tolist(),
        'dense_mac_vector_beats': int(zero.size * output_channels),
        'zero_tile_mac_vector_beats': int(zero.sum() * output_channels),
        'nonzero_weight_multiplications_in_zero_tiles': int(zero_per_channel @ nonzero_weights),
        'per_image_zero_channel_tiles': counts.tolist(),
    }


def pattern_stats(x, u):
    """Exact row/column patterns and ideal MAC issue counts, without RTL timing."""
    d = tiles(x)
    temp = BT @ d
    v = temp @ BT.T
    whole_zero = (d == 0).all(axis=(-2, -1))
    partial = ~whole_zero
    raw_rows = (d == 0).all(axis=-1)
    raw_cols = (d == 0).all(axis=-2)
    rows = (v == 0).all(axis=-1)
    cols = (v == 0).all(axis=-2)
    # Right multiplication by invertible B cannot turn a nonzero row into zero.
    assert np.array_equal(rows, (temp == 0).all(axis=-1))
    row_conditions = np.stack((
        (d[..., 0, :] == d[..., 2, :]).all(axis=-1),
        raw_rows[..., 1] & raw_rows[..., 2],  # input activations are unsigned
        (d[..., 1, :] == d[..., 2, :]).all(axis=-1),
        (d[..., 1, :] == d[..., 3, :]).all(axis=-1)), axis=-1)
    col_conditions = np.stack((
        (d[..., 0] == d[..., 2]).all(axis=-1),
        raw_cols[..., 1] & raw_cols[..., 2],
        (d[..., 1] == d[..., 2]).all(axis=-1),
        (d[..., 1] == d[..., 3]).all(axis=-1)), axis=-1)
    assert np.array_equal(rows, row_conditions)
    assert np.array_equal(cols, col_conditions)
    row_zero_pairs = np.stack((raw_rows[..., 0] & raw_rows[..., 2],
                               raw_rows[..., 1] & raw_rows[..., 2],
                               raw_rows[..., 1] & raw_rows[..., 2],
                               raw_rows[..., 1] & raw_rows[..., 3]), axis=-1)
    nonzero_equal_rows = rows & ~row_zero_pairs
    # d[i,j] = a[i] + b[j]: every row difference is spatially constant.
    # The nine coordinates with row/column indices in {0,2,3} vanish exactly.
    additive_rows_columns = (d == d[..., :, :1] + d[..., :1, :] - d[..., :1, :1]).all(axis=(-2, -1))
    difference_indices = [0, 2, 3]
    nine_zero = (v[..., difference_indices, :][..., difference_indices] == 0).all(axis=(-2, -1))
    assert np.array_equal(additive_rows_columns, nine_zero)

    def summarize(select):
        count = int(select.sum())
        rr, vr, vc, vv = raw_rows[select], rows[select], cols[select], v[select]
        zero_entries = int((vv == 0).sum())
        row_covered = int(vr.sum()) * 4
        union_covered = int((vr[..., :, None] | vc[..., None, :]).sum())
        ratio = lambda n, denom: 100 * n / denom if denom else None
        return {
            'channel_tiles': count,
            'input_zero_rows': int(rr.sum()),
            'input_zero_row_percent': ratio(int(rr.sum()), count * 4),
            'tiles_with_any_input_zero_row': int(rr.any(axis=-1).sum()),
            'transformed_zero_rows': int(vr.sum()),
            'transformed_zero_row_percent': ratio(int(vr.sum()), count * 4),
            'transformed_zero_rows_by_row': vr.sum(axis=0).tolist(),
            'tiles_with_any_transformed_zero_row': int(vr.any(axis=-1).sum()),
            'tiles_with_any_transformed_zero_row_percent': ratio(int(vr.any(axis=-1).sum()), count),
            'transformed_zero_row_count_histogram': np.bincount(vr.sum(axis=-1), minlength=5).tolist(),
            'transformed_zero_columns': int(vc.sum()),
            'transformed_zero_columns_by_column': vc.sum(axis=0).tolist(),
            'tiles_with_any_transformed_zero_column': int(vc.any(axis=-1).sum()),
            'zero_v_entries': zero_entries,
            'zero_v_entry_percent': ratio(zero_entries, count * 16),
            'zero_v_entries_covered_by_rows': row_covered,
            'zero_v_entries_covered_by_rows_percent': ratio(row_covered, zero_entries),
            'zero_v_entries_covered_by_rows_or_columns': union_covered,
            'zero_rows_from_equal_nonzero_input_rows': int(nonzero_equal_rows[select].sum()),
            'zero_rows_from_equal_nonzero_input_rows_by_row': nonzero_equal_rows[select].sum(axis=0).tolist(),
        }

    # Each job is one spatial tile and one output channel. All C inputs available.
    # Row groups and lanes may advance independently, but meet at a job boundary.
    # This is a work bound: skips, pipeline fill/drain, output tokens cost zero here.
    whole_steps = partial.sum(axis=1)
    row_steps = (~rows).sum(axis=1).max(axis=-1)
    col_steps = (~cols).sum(axis=1).max(axis=-1)
    lane_steps = (v != 0).sum(axis=1).max(axis=(-2, -1))
    assert np.all(lane_steps <= row_steps) and np.all(row_steps <= whole_steps)
    assert np.all(lane_steps <= col_steps) and np.all(col_steps <= whole_steps)
    spatial = whole_steps.size
    k = u.shape[0]
    cycles = {
        'assumptions': 'Activation-only skip; all input channels resident; independent fixed-coordinate groups; common tile/output-channel boundary; zero-cost scheduling and zero-result delivery. Not latency or RTL simulation.',
        'dense_mac_issue_slots': int(spatial * x.shape[1] * k),
        'whole_tile_skip_mac_issue_slots': int(whole_steps.sum() * k),
        'row_group_skip_mac_issue_slots': int(row_steps.sum() * k),
        'column_group_skip_mac_issue_slots': int(col_steps.sum() * k),
        'coordinate_skip_mac_issue_slots': int(lane_steps.sum() * k),
        'spatial_tiles_improved_by_rows_over_whole': int((row_steps < whole_steps).sum()),
        'spatial_tiles_improved_by_coordinates_over_whole': int((lane_steps < whole_steps).sum()),
        'whole_steps_histogram': np.bincount(whole_steps.ravel(), minlength=x.shape[1]+1).tolist(),
        'row_steps_histogram': np.bincount(row_steps.ravel(), minlength=x.shape[1]+1).tolist(),
        'coordinate_steps_histogram': np.bincount(lane_steps.ravel(), minlength=x.shape[1]+1).tolist(),
    }
    # Relax the per-job rendezvous: each fixed-coordinate group may advance to
    # later spatial tiles/output channels, with unbounded buffering and results.
    # Keep an image boundary. This is only a compute-work lower bound; input
    # release times, limited queue capacity and output-transform bandwidth remain.
    row_image_work = (~rows).sum(axis=(1, 2, 3)) * k
    lane_image_work = (v != 0).sum(axis=(1, 2, 3)) * k
    cycles['cross_tile_unbounded_row_work_bound'] = int(row_image_work.max(axis=-1).sum())
    cycles['cross_tile_unbounded_coordinate_work_bound'] = int(lane_image_work.max(axis=(-2, -1)).sum())
    cycles['cross_tile_bound_assumptions'] = 'Groups may progress into different tiles/output channels; unlimited buffering and completed-result storage; no input-release/output-bandwidth constraint; synchronize only per image. Not a schedule simulation.'
    # Count only multiplications whose weight was nonzero (existing weight gating).
    nonzero_weight_count = (u != 0).sum(axis=0)
    row_extra = rows[..., :, None] & partial[..., None, None]
    point_extra = (v == 0) & partial[..., None, None]
    extras = {
        'row_skipped_nonzero_weight_products_beyond_whole_tile': int((row_extra * nonzero_weight_count[None, :, None, None]).sum()),
        'coordinate_skipped_nonzero_weight_products_beyond_whole_tile': int((point_extra * nonzero_weight_count[None, :, None, None]).sum()),
    }
    examples = []
    for index in np.argwhere(partial & rows.any(axis=-1))[:3]:
        ix = tuple(index)
        examples.append({'image_channel_tile_row_tile_col': index.tolist(),
                         'input': d[ix].tolist(), 'transformed': v[ix].tolist()})
    per_channel = []
    for c in range(x.shape[1]):
        select = np.zeros_like(partial)
        select[:, c] = partial[:, c]
        per_channel.append(summarize(select))
    return {'all_channel_tiles': summarize(np.ones_like(partial)),
            'excluding_whole_zero_tiles': summarize(partial),
            'excluding_whole_zero_tiles_by_channel': per_channel,
            'ideal_mac_work': cycles, 'beyond_existing_weight_gating': extras,
            'additive_row_column_pattern': {
                'definition': 'd[i,j] = a[i] + b[j]; equivalently V[r,s]=0 for r,s in {0,2,3}',
                'all_channel_tiles': int(additive_rows_columns.sum()),
                'nonzero_channel_tiles': int((additive_rows_columns & partial).sum()),
                'nonzero_matches_by_channel': (additive_rows_columns & partial).sum(axis=(0, 2, 3)).tolist(),
                'nonzero_matches_percent_of_nonzero_tiles': 100 * float((additive_rows_columns & partial).sum()) / int(partial.sum()),
            },
            'partial_tile_examples': examples}


def main():
    manifest = json.loads((EXPORT / 'manifest.json').read_text())
    tensors = {name: np.loadtxt(EXPORT / spec['decimal_file'], dtype=np.int64).reshape(spec['shape'])
               for name, spec in manifest['tensors'].items()}
    for name, spec in manifest['tensors'].items():
        raw = np.array([int(s, 16) for s in (EXPORT / spec['hex_file']).read_text().split()])
        signed = np.where(raw >= (1 << (spec['bits']-1)), raw - (1 << spec['bits']), raw)
        assert np.array_equal(signed.reshape(spec['shape']), tensors[name]), name
    rq = manifest['requantization']

    def run(x):
        a1 = conv_pool(x, tensors['conv1_u'], tensors['conv1_bias'], rq['conv1_multiplier'])
        # RTL stores only the top-left 12x12; row/column 12 cannot affect pooled Conv2.
        a2 = conv_pool(a1[:, :, :12, :12], tensors['conv2_u'], tensors['conv2_bias'], rq['conv2_multiplier'])
        return a1, a2

    ref = ROOT / 'verification/data/two_conv_real'
    read_hex = lambda p: np.array([int(s, 16) for s in p.read_text().split()], dtype=np.int64)
    reference_input = read_hex(ref / 'image_u8.hex').reshape(1, 1, 28, 28)
    reference_activations = run(reference_input)
    for i, activation in enumerate(reference_activations, 1):
        assert np.array_equal(activation.ravel(), read_hex(ref / f'conv{i}_activation_u8.hex'))

    source = ROOT / 'data/input_1000.txt'
    x = read_hex(source).reshape(-1, 1, 28, 28)
    assert x.min() >= 0 and x.max() <= 255
    a1, a2 = run(x)
    flat = a2.reshape(len(x), -1)
    logits = np.zeros((len(x), 10), dtype=np.int64)
    for f in range(flat.shape[1]):
        logits = sat(logits + flat[:, f, None] * tensors['fc_weight'][None, :, f])
    logits = sat(logits + tensors['fc_bias'])
    expected = np.loadtxt(EXPORT / 'competition_predictions_1000.txt', dtype=np.int64)
    mismatches = int((logits.argmax(axis=1) != expected).sum())
    assert mismatches == 0, mismatches
    report = {
        'input_file': str(source.relative_to(ROOT)),
        'input_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'export_dir': str(EXPORT.relative_to(ROOT)),
        'images': len(x),
        'unique_input_images': len(np.unique(x.reshape(len(x), -1), axis=0)),
        'validation': {'reference_conv1_conv2_activation_values': 'exact match',
                       'export_hex_decimal': 'exact match', 'prediction_mismatches_1000': mismatches},
        'scope': '4x4 stride-2 unpadded RTL windows; Conv1 13x13, Conv2 5x5 per channel. Not cycle simulation.',
        'conv1_bias_only_output': np.clip((np.maximum(tensors['conv1_bias'], 0) * rq['conv1_multiplier'] + (1 << 23)) >> 24, 0, 255).tolist(),
        'conv2_bias_only_output': np.clip((np.maximum(tensors['conv2_bias'], 0) * rq['conv2_multiplier'] + (1 << 23)) >> 24, 0, 255).tolist(),
        'conv1': stats(x, 3, tensors['conv1_u']),
        'conv2': stats(a1[:, :, :12, :12], 3, tensors['conv2_u']),
    }
    destination = ROOT / 'verification/reports/zero_tiles_1000.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    for layer in ('conv1', 'conv2'):
        print(layer, json.dumps({k: v for k, v in report[layer].items()
                                if k not in ('per_image_zero_channel_tiles', 'zero_rate_by_spatial_position')}))
    print('validation', report['validation'])
    print('unique input images', report['unique_input_images'])
    print('bias-only outputs', report['conv1_bias_only_output'], report['conv2_bias_only_output'])
    print(destination)
    patterns = {
        'input_file': report['input_file'], 'input_sha256': report['input_sha256'],
        'export_dir': report['export_dir'], 'validation': report['validation'],
        'images': len(x), 'unique_input_images': report['unique_input_images'], 'scope': report['scope'],
        'conv1': pattern_stats(x, tensors['conv1_u']),
        'conv2': pattern_stats(a1[:, :, :12, :12], tensors['conv2_u']),
    }
    pattern_destination = destination.with_name('row_patterns_1000.json')
    pattern_destination.write_text(json.dumps(patterns, indent=2) + '\n', encoding='utf-8')
    for layer in ('conv1', 'conv2'):
        print(layer, 'partial tile patterns', json.dumps(patterns[layer]['excluding_whole_zero_tiles']))
        print(layer, 'MAC work', json.dumps(patterns[layer]['ideal_mac_work']))
        print(layer, 'weight-aware extra', json.dumps(patterns[layer]['beyond_existing_weight_gating']))
        print(layer, 'additive row-column pattern', json.dumps(patterns[layer]['additive_row_column_pattern']))
    print(pattern_destination)


if __name__ == '__main__':
    main()
