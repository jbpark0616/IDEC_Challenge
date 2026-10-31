from pathlib import Path
import csv
import hashlib
import json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SOURCE = ROOT / 'free_topic_vgg/evidence/report700/cluster_all/measurements.csv'
with SOURCE.open(newline='', encoding='utf-8-sig') as f:
    rows = list(csv.DictReader(f))
off, on = [], []
for layer in range(13):
    pair = [r for r in rows if int(r['layer']) == layer]
    assert len(pair) == 2
    a, b = [next(r for r in pair if int(r['sparse']) == s) for s in (0, 1)]
    assert a['input_NHWC'] == b['input_NHWC']
    off.append(int(a['mac_lanes']))
    on.append(int(b['mac_lanes']))
off, on = np.array(off), np.array(on)
assert np.all(on <= off)
reduction = 100 * (1 - on / off)
total_reduction = 100 * (1 - on.sum() / off.sum())
plt.rcParams.update({'font.family': 'Arial', 'font.size': 10,
                     'axes.linewidth': .6, 'svg.fonttype': 'none', 'pdf.fonttype': 42})
fig, ax = plt.subplots(figsize=(10.5, 3.8))
fig.subplots_adjust(left=.075, right=.99, bottom=.19, top=.79)
x = np.arange(13)
ax.bar(x-.18, off/1e6, .32, color='#0072BD', label='Zero-skipping disabled', zorder=3)
ax.bar(x+.18, on/1e6, .32, color='#ED7D31', label='Sparsity-aware execution', zorder=3)
for i, percent in enumerate(reduction):
    ax.text(i, off[i]/1e6+.45, f'{percent:.1f}%', ha='center', va='bottom', fontsize=9)
ax.set_xticks(x, [f'Conv{i}' for i in range(1, 14)])
ax.set_xlim(-.65, 12.65)
ax.set_ylim(0, 19)
ax.set_yticks([0, 4, 8, 12, 16])
ax.set_ylabel('MAC lane operations (million)')
ax.set_xlabel('Convolution layer', labelpad=10)
ax.set_axisbelow(True)
ax.grid(axis='y', color='#DDDDDD', linewidth=.6)
for spine in ['top', 'right']:
    ax.spines[spine].set_visible(False)
for spine in ['left', 'bottom']:
    ax.spines[spine].set_color('#999999')
ax.tick_params(length=3, width=.6, color='#999999')
legend = fig.legend(*ax.get_legend_handles_labels(), loc='upper center',
                    bbox_to_anchor=(.53, .99), ncol=2, frameon=True,
                    fancybox=False, edgecolor='#555555')
legend.get_frame().set_linewidth(.6)
fig.text(.53, .845, f'Annotations: reduction per layer  |  Total Conv reduction: {total_reduction:.2f}%',
         ha='center', fontsize=9)
for extension in ['svg', 'pdf', 'png']:
    fig.savefig(HERE / f'figure.{extension}', dpi=300, facecolor='white')
(HERE / 'CAPTION_KO.txt').write_text(
    '동일 입력·가중치에서 zero-skipping OFF/ON에 따른 레이어별 활성 MAC lane 투입 횟수.\n'
    '이미지 index 0 한 장, 16코어 합계, Conv 13개 독립 측정. FC 제외.\n'
    'response_valid && mac_ready일 때 4*countones(response_rows)를 누적한다.\n'
    '곱셈과 덧셈을 별도 두 연산으로 세지 않는다. 막대 위 숫자는 레이어별 감소율.\n'
    f'합계 {off.sum():,} -> {on.sum():,}, {total_reduction:.2f}% 감소.\n'
    '전력 또는 에너지 측정값이 아니며, 사이클 감소율을 나타내지 않는다.\n', encoding='utf-8')
(HERE / 'provenance.json').write_text(json.dumps({
    'source': str(SOURCE.relative_to(ROOT)), 'sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    'off_total': int(off.sum()), 'on_total': int(on.sum()), 'reduction_percent': total_reduction,
    'image_index': 0, 'cores': 16, 'rtl_modified': False
}, indent=2), encoding='utf-8')
print(f'Saved {HERE / "figure.svg"}')
