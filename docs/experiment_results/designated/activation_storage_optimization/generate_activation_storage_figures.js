const fs = require('fs');
const path = require('path');

const root = __dirname;
const lines = fs.readFileSync(path.join(root, 'optimization_results.csv'), 'utf8')
  .trim().split(/\r?\n/);
const header = lines.shift().split(',');
const labels = ['Baseline', 'Crop', 'Prefill', 'Reuse'];
const rows = lines.map((line, i) => {
  const values = line.split(',');
  const row = Object.fromEntries(header.map((key, j) => [key, values[j]]));
  row.label = labels[i];
  return row;
});

const C = {
  ink: '#222222', axis: '#444444', grid: '#D8D8D8', gray: '#A8A8A8',
  blue: '#3F6F9F', white: '#FFFFFF'
};

function begin(w, h, label) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" role="img" aria-label="${label}">
<rect width="${w}" height="${h}" fill="${C.white}"/>
<style>
text{font-family:Arial,'Noto Sans KR',sans-serif;fill:${C.ink};font-size:15px}
.tick{font-size:13px}.panel-label{font-size:16px;font-weight:700}.value{font-size:13px}
.axis{stroke:${C.axis};stroke-width:1}.grid{stroke:${C.grid};stroke-width:1}
</style>`;
}

function axes(s, x, y, w, h, max, ticks, ylabel) {
  const left = x + 72, right = x + w - 14, top = y + 16, bottom = y + h - 50;
  ticks.forEach(v => {
    const yy = bottom - v / max * (bottom - top);
    s += `<line class="grid" x1="${left}" y1="${yy}" x2="${right}" y2="${yy}"/>`;
    s += `<text class="tick" x="${left - 9}" y="${yy + 5}" text-anchor="end">${v.toLocaleString('en-US')}</text>`;
  });
  s += `<line class="axis" x1="${left}" y1="${top}" x2="${left}" y2="${bottom}"/>`;
  s += `<line class="axis" x1="${left}" y1="${bottom}" x2="${right}" y2="${bottom}"/>`;
  s += `<text x="${x + 17}" y="${(top + bottom) / 2}" text-anchor="middle" transform="rotate(-90 ${x + 17} ${(top + bottom) / 2})">${ylabel}</text>`;
  return {s, left, right, top, bottom};
}

function bars(s, a, key, max, digits = 0) {
  const plotW = a.right - a.left;
  rows.forEach((r, i) => {
    const value = +r[key];
    const cx = a.left + plotW * (i + 0.5) / rows.length;
    const bw = 52;
    const bh = value / max * (a.bottom - a.top);
    s += `<rect x="${cx - bw / 2}" y="${a.bottom - bh}" width="${bw}" height="${bh}" fill="${i === 0 ? C.gray : C.blue}"/>`;
    s += `<text class="value" x="${cx}" y="${Math.max(a.top + 13, a.bottom - bh - 7)}" text-anchor="middle">${value.toLocaleString('en-US', {minimumFractionDigits: digits, maximumFractionDigits: digits})}</text>`;
    s += `<text class="tick" x="${cx}" y="${a.bottom + 22}" text-anchor="middle">${r.label}</text>`;
  });
  return s;
}

function storageFigure() {
  const specs = [
    ['total_interlayer_storage_bits', 5000, [0, 1000, 2000, 3000, 4000, 5000], 'Storage (bit)', '(a) Inter-layer storage'],
    ['post_input_cycles', 520, [0, 130, 260, 390, 520], 'Latency (cycle)', '(b) Post-input latency']
  ];
  const W = 1000, H = 430, pw = 490, gap = 10;
  let s = begin(W, H, 'Activation storage and latency optimization');
  specs.forEach((spec, p) => {
    const [key, max, ticks, ylabel, caption] = spec;
    const x = p * (pw + gap), y = 8;
    let a = axes(s, x, y, pw, 340, max, ticks, ylabel); s = a.s;
    s = bars(s, a, key, max);
    s += `<text x="${(a.left + a.right) / 2}" y="${a.bottom + 44}" text-anchor="middle">Optimization stage</text>`;
    s += `<text class="panel-label" x="${x + pw / 2}" y="${y + 394}" text-anchor="middle">${caption}</text>`;
  });
  fs.writeFileSync(path.join(root, 'activation_storage_optimization.svg'), s + '</svg>', 'utf8');
}

function ppaFigure() {
  const specs = [
    ['flip_flop_count', 12000, [0, 3000, 6000, 9000, 12000], 'Flip-flops', '(a) Flip-flop count', 0],
    ['total_area_um2', 10000, [0, 2500, 5000, 7500, 10000], 'Area (µm²)', '(b) Cell area', 0],
    ['vectorless_power_mw', 50, [0, 10, 20, 30, 40, 50], 'Power (mW)', '(c) Vectorless power', 1],
    ['fmax_mhz', 1200, [0, 300, 600, 900, 1200], 'Fmax (MHz)', '(d) Estimated Fmax', 0]
  ];
  const W = 1500, H = 430, pw = 368, gap = 7;
  let s = begin(W, H, 'Activation storage post-synthesis comparison');
  specs.forEach((spec, p) => {
    const [key, max, ticks, ylabel, caption, digits] = spec;
    const x = p * (pw + gap), y = 8;
    let a = axes(s, x, y, pw, 340, max, ticks, ylabel); s = a.s;
    s = bars(s, a, key, max, digits);
    s += `<text x="${(a.left + a.right) / 2}" y="${a.bottom + 44}" text-anchor="middle">Optimization stage</text>`;
    s += `<text class="panel-label" x="${x + pw / 2}" y="${y + 394}" text-anchor="middle">${caption}</text>`;
  });
  fs.writeFileSync(path.join(root, 'activation_storage_ppa.svg'), s + '</svg>', 'utf8');
}

storageFigure();
ppaFigure();
console.log('Generated activation storage optimization figures');
