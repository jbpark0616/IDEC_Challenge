const fs = require('fs');
const path = require('path');

const root = __dirname;
const dataDir = path.join(root, 'data');

function readCsv(name) {
  const lines = fs.readFileSync(path.join(dataDir, name), 'utf8').trim().split(/\r?\n/);
  const head = lines.shift().split(',');
  return lines.map(line => Object.fromEntries(head.map((key, i) => [key, line.split(',')[i]])));
}

function write(name, text) {
  fs.writeFileSync(path.join(root, name), text, 'utf8');
}

const c = {
  ink: '#222222', axis: '#444444', grid: '#D8D8D8', gray: '#A8A8A8',
  blue: '#3F6F9F', red: '#B44A4A', white: '#FFFFFF'
};

function begin(w, h, label) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" role="img" aria-label="${label}">
<rect width="${w}" height="${h}" fill="${c.white}"/>
<style>
text{font-family:Arial,'Noto Sans KR',sans-serif;fill:${c.ink};font-size:15px}
.tick{font-size:13px}.panel-label{font-size:16px;font-weight:700}.value{font-size:13px}
.axis{stroke:${c.axis};stroke-width:1}.grid{stroke:${c.grid};stroke-width:1}
</style>`;
}

function barAxes(s, x, y, w, h, max, ticks, ylabel) {
  const left = x + 58, right = x + w - 16, top = y + 16, bottom = y + h - 48;
  ticks.forEach(v => {
    const yy = bottom - v / max * (bottom - top);
    s += `<line class="grid" x1="${left}" y1="${yy}" x2="${right}" y2="${yy}"/>`;
    s += `<text class="tick" x="${left - 9}" y="${yy + 5}" text-anchor="end">${v}</text>`;
  });
  s += `<line class="axis" x1="${left}" y1="${top}" x2="${left}" y2="${bottom}"/>`;
  s += `<line class="axis" x1="${left}" y1="${bottom}" x2="${right}" y2="${bottom}"/>`;
  s += `<text x="${x + 14}" y="${(top + bottom) / 2}" text-anchor="middle" transform="rotate(-90 ${x + 14} ${(top + bottom) / 2})">${ylabel}</text>`;
  return {s, left, right, top, bottom};
}

function depthSweep() {
  const d = readCsv('fifo_depth_sweep.csv').map(r => ({
    depth: +r.depth, storage: +r.storage_bits, occupancy: +r.max_occupancy,
    stall: +r.input_backpressure_cycles_per_image, accuracy: +r.accuracy_percent
  }));
  const W = 1500, H = 430, pw = 365, gap = 7;
  let s = begin(W, H, 'FIFO depth sweep');
  const specs = [
    ['storage', 1024, [0,256,512,768,1024], 'Storage (bit)', '(a) FIFO storage'],
    ['occupancy', 4, [0,1,2,3,4], 'Maximum occupancy', '(b) Maximum occupancy'],
    ['stall', 40, [0,10,20,30,40], 'Backpressure (cycle/image)', '(c) Input backpressure'],
    ['accuracy', 100, [0,25,50,75,100], 'Accuracy (%)', '(d) Inference accuracy']
  ];
  specs.forEach((spec, p) => {
    const [key,max,ticks,ylabel,label] = spec;
    const x = 5 + p * (pw + gap), y = 8;
    let a = barAxes(s, x, y, pw, 350, max, ticks, ylabel); s = a.s;
    const plotW = a.right - a.left;
    d.forEach((r, i) => {
      const bw = 45, cx = a.left + plotW * (i + 0.5) / d.length;
      const bh = r[key] / max * (a.bottom - a.top);
      const color = r.depth === 2 ? c.blue : c.gray;
      s += `<rect x="${cx-bw/2}" y="${a.bottom-bh}" width="${bw}" height="${bh}" fill="${color}"/>`;
      s += `<text class="tick" x="${cx}" y="${a.bottom+22}" text-anchor="middle">${r.depth}</text>`;
      s += `<text class="value" x="${cx}" y="${Math.max(a.top+13,a.bottom-bh-7)}" text-anchor="middle">${r[key]}</text>`;
    });
    s += `<text x="${(a.left+a.right)/2}" y="${a.bottom+44}" text-anchor="middle">FIFO depth</text>`;
    s += `<text class="panel-label" x="${x+pw/2}" y="${y+394}" text-anchor="middle">${label}</text>`;
  });
  s += '</svg>';
  write('fifo_depth_sweep.svg', s);
}

function digitalPath(rows, key, x0, y0, cw, amp) {
  let p = '';
  rows.forEach((r, i) => {
    const yy = y0 - (+r[key] ? amp : 0), xx = x0 + i*cw;
    p += i ? ` H ${xx} V ${yy} H ${xx+cw}` : `M ${xx} ${yy} H ${xx+cw}`;
  });
  return p;
}

function busWaveform(rows, key, x0, y0, cw, fullValue) {
  const groups = [];
  rows.forEach((row, index) => {
    const value = +row[key];
    const last = groups[groups.length - 1];
    if (last && last.value === value) last.end = index + 1;
    else groups.push({value, start:index, end:index + 1});
  });

  const top = y0 - 22, bottom = y0;
  let s = '';
  groups.forEach((group, index) => {
    const x1 = x0 + group.start * cw;
    const x2 = x0 + group.end * cw;
    if (group.value === fullValue) {
      s += `<rect x="${x1}" y="${top}" width="${x2-x1}" height="${bottom-top}" fill="#E5E5E5"/>`;
    }
    s += `<line x1="${x1}" y1="${top}" x2="${x2}" y2="${top}" stroke="${c.ink}" stroke-width="1.2"/>`;
    s += `<line x1="${x1}" y1="${bottom}" x2="${x2}" y2="${bottom}" stroke="${c.ink}" stroke-width="1.2"/>`;
    s += `<text class="value" x="${(x1+x2)/2}" y="${y0-6}" text-anchor="middle">${group.value}</text>`;
    if (index > 0) {
      s += `<line x1="${x1-5}" y1="${top}" x2="${x1+5}" y2="${bottom}" stroke="${c.ink}" stroke-width="1.2"/>`;
      s += `<line x1="${x1-5}" y1="${bottom}" x2="${x1+5}" y2="${top}" stroke="${c.ink}" stroke-width="1.2"/>`;
    }
  });
  s += `<line x1="${x0}" y1="${top}" x2="${x0}" y2="${bottom}" stroke="${c.ink}" stroke-width="1.2"/>`;
  s += `<line x1="${x0+rows.length*cw}" y1="${top}" x2="${x0+rows.length*cw}" y2="${bottom}" stroke="${c.ink}" stroke-width="1.2"/>`;
  return s;
}

function waveformPanel(s, rows, x, y, w, label) {
  const names = ['tile_in_valid','tile_in_ready','core_in_ready','image_ready'];
  const left = x + 148, right = x + w - 12, top = y + 26, cw = (right-left)/rows.length;
  rows.forEach((r,i) => {
    if (r.image_ready === '0') {
      s += `<rect x="${left+i*cw}" y="${top}" width="${cw}" height="238" fill="#F0F0F0"/>`;
    }
  });
  rows.forEach((r,i) => {
    const xx = left+(i+0.5)*cw;
    s += `<text class="tick" x="${xx}" y="${top-8}" text-anchor="middle">${r.cycle}</text>`;
    s += `<line x1="${left+i*cw}" y1="${top}" x2="${left+i*cw}" y2="${top+238}" stroke="${c.grid}" stroke-width="0.7"/>`;
  });
  s += `<line x1="${right}" y1="${top}" x2="${right}" y2="${top+238}" stroke="${c.grid}" stroke-width="0.7"/>`;
  names.forEach((name,k) => {
    const yy = top+38+k*43;
    s += `<text class="tick" x="${left-12}" y="${yy-4}" text-anchor="end">${name}</text>`;
    s += `<path d="${digitalPath(rows,name,left,yy,cw,21)}" fill="none" stroke="${c.ink}" stroke-width="1.8" stroke-linejoin="miter"/>`;
  });
  const fy = top+220;
  s += `<text class="tick" x="${left-12}" y="${fy-4}" text-anchor="end">fifo_count</text>`;
  s += busWaveform(rows, 'fifo_count', left, fy, cw, Math.max(...rows.map(r => +r.fifo_count)));
  s += `<text class="panel-label" x="${(left+right)/2}" y="${fy+46}" text-anchor="middle">${label}</text>`;
  return s;
}

function waveforms() {
  const load = n => readCsv(`fifo_depth${n}_trace.csv`).filter(r => /^\d+$/.test(r.cycle) && +r.cycle>=103 && +r.cycle<=119);
  const d1=load(1), d2=load(2), W=1400, H=690;
  let s=begin(W,H,'FIFO handshake waveforms for depths one and two');
  s=waveformPanel(s,d1,12,8,1376,'(a) Depth 1: backpressure');
  s=waveformPanel(s,d2,12,350,1376,'(b) Depth 2: stall absorption');
  s+='</svg>';
  write('fifo_depth_waveform.svg',s);
}

function ppa() {
  const d=readCsv('fifo_depth_ppa.csv').map(r=>Object.fromEntries(Object.entries(r).map(([k,v])=>[k,+v])));
  const d8=d.find(r=>r.depth===8), d2=d.find(r=>r.depth===2);
  const metrics=[
    ['total_area_um2','Area (µm²)',12000,[0,3000,6000,9000,12000],'(a) Cell area'],
    ['flip_flop_count','Flip-flops',12000,[0,3000,6000,9000,12000],'(b) Flip-flop count'],
    ['vectorless_power_mw','Power (mW)',60,[0,15,30,45,60],'(c) Vectorless power'],
    ['fmax_mhz','Fmax (MHz)',1200,[0,300,600,900,1200],'(d) Estimated Fmax']
  ];
  const W=1400,H=430,pw=340,gap=7;
  let s=begin(W,H,'Post-synthesis PPA comparison');
  metrics.forEach((m,i)=>{
    const [key,ylabel,max,ticks,label]=m, x=4+i*(pw+gap), y=8;
    let a=barAxes(s,x,y,pw,340,max,ticks,ylabel); s=a.s;
    const vals=[[8,d8[key],c.gray],[2,d2[key],c.blue]];
    vals.forEach((v,j)=>{
      const cx=a.left+(a.right-a.left)*(j+0.5)/2,bw=70,bh=v[1]/max*(a.bottom-a.top);
      s+=`<rect x="${cx-bw/2}" y="${a.bottom-bh}" width="${bw}" height="${bh}" fill="${v[2]}"/>`;
      s+=`<text class="value" x="${cx}" y="${a.bottom-bh-7}" text-anchor="middle">${v[1].toLocaleString('en-US',{maximumFractionDigits:2})}</text>`;
      s+=`<text class="tick" x="${cx}" y="${a.bottom+22}" text-anchor="middle">${v[0]}</text>`;
    });
    s+=`<text x="${(a.left+a.right)/2}" y="${a.bottom+44}" text-anchor="middle">FIFO depth</text>`;
    s+=`<text class="panel-label" x="${x+pw/2}" y="${y+394}" text-anchor="middle">${label}</text>`;
  });
  s+='</svg>';
  write('fifo_depth_ppa.svg',s);
}

depthSweep();
waveforms();
ppa();
console.log('Generated publication-style FIFO figures.');
