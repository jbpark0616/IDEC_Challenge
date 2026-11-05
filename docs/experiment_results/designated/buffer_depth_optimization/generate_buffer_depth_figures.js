const fs = require('fs');
const path = require('path');

const root = __dirname;

function csv(name) {
  const lines = fs.readFileSync(path.join(root, name), 'utf8').trim().split(/\r?\n/);
  const head = lines.shift().split(',');
  return lines.map(line => Object.fromEntries(head.map((key, i) => [key, line.split(',')[i]])));
}

function write(name, body) {
  fs.writeFileSync(path.join(root, name), body, 'utf8');
}

const C = {
  ink:'#222222', axis:'#444444', grid:'#D8D8D8', gray:'#A8A8A8',
  blue:'#3F6F9F', reject:'#777777', white:'#FFFFFF'
};

function begin(w, h, label) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" role="img" aria-label="${label}">
<rect width="${w}" height="${h}" fill="${C.white}"/>
<defs><pattern id="rejected" width="7" height="7" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="7" height="7" fill="#EEEEEE"/><line x1="0" y1="0" x2="0" y2="7" stroke="#777777" stroke-width="2"/></pattern></defs>
<style>
text{font-family:Arial,'Noto Sans KR',sans-serif;fill:${C.ink};font-size:15px}
.tick{font-size:13px}.panel-label{font-size:16px;font-weight:700}.value{font-size:13px}
.axis{stroke:${C.axis};stroke-width:1}.grid{stroke:${C.grid};stroke-width:1}
</style>`;
}

function axes(s, x, y, w, h, max, ticks, ylabel) {
  const left=x+62, right=x+w-14, top=y+16, bottom=y+h-50;
  ticks.forEach(v=>{
    const yy=bottom-v/max*(bottom-top);
    s+=`<line class="grid" x1="${left}" y1="${yy}" x2="${right}" y2="${yy}"/>`;
    s+=`<text class="tick" x="${left-9}" y="${yy+5}" text-anchor="end">${v.toLocaleString('en-US')}</text>`;
  });
  s+=`<line class="axis" x1="${left}" y1="${top}" x2="${left}" y2="${bottom}"/>`;
  s+=`<line class="axis" x1="${left}" y1="${bottom}" x2="${right}" y2="${bottom}"/>`;
  s+=`<text x="${x+14}" y="${(top+bottom)/2}" text-anchor="middle" transform="rotate(-90 ${x+14} ${(top+bottom)/2})">${ylabel}</text>`;
  return {s,left,right,top,bottom};
}

function configSweep() {
  const rows=csv('depth_sweep.csv').map(r=>({
    label:`V${r.v_replay_depth}/M${r.m_fifo_depth}`,
    status:r.status,
    storage:528*(+r.v_replay_depth)+290*(+r.m_fifo_depth),
    backpressure:(+r.input_backpressure_cycles)/1000,
    latency:+r.average_post_input_cycles,
    accuracy:+r.accuracy_percent
  }));
  const specs=[
    ['storage',1800,[0,450,900,1350,1800],'Storage (bit)','(a) Pipeline-buffer storage'],
    ['backpressure',40,[0,10,20,30,40],'Backpressure (cycle/image)','(b) Input backpressure'],
    ['latency',640,[0,160,320,480,640],'Post-input latency (cycle)','(c) Completion latency'],
    ['accuracy',100,[0,25,50,75,100],'Accuracy (%)','(d) Inference accuracy']
  ];
  const W=1500,H=430,pw=365,gap=7;
  let s=begin(W,H,'Pipeline buffer depth sweep');
  specs.forEach((spec,p)=>{
    const [key,max,ticks,ylabel,caption]=spec,x=5+p*(pw+gap),y=8;
    let a=axes(s,x,y,pw,350,max,ticks,ylabel); s=a.s;
    const plotW=a.right-a.left;
    rows.forEach((r,i)=>{
      const cx=a.left+plotW*(i+0.5)/rows.length,bw=58,bh=r[key]/max*(a.bottom-a.top);
      const fill=r.status==='PASS_SELECTED'?C.blue:(r.status==='FAIL'?'url(#rejected)':C.gray);
      s+=`<rect x="${cx-bw/2}" y="${a.bottom-bh}" width="${bw}" height="${bh}" fill="${fill}"/>`;
      s+=`<text class="value" x="${cx}" y="${Math.max(a.top+13,a.bottom-bh-7)}" text-anchor="middle">${r[key].toLocaleString('en-US')}</text>`;
      s+=`<text class="tick" x="${cx}" y="${a.bottom+22}" text-anchor="middle">${r.label}</text>`;
    });
    s+=`<text x="${(a.left+a.right)/2}" y="${a.bottom+44}" text-anchor="middle">Configuration</text>`;
    s+=`<text class="panel-label" x="${x+pw/2}" y="${y+394}" text-anchor="middle">${caption}</text>`;
  });
  s+='</svg>';
  write('buffer_depth_sweep.svg',s);
}

function ppa() {
  const rows=csv('ppa_comparison.csv').map(r=>Object.fromEntries(Object.entries(r).map(([k,v])=>[k,+v])));
  const d2=rows.find(r=>r.m_fifo_depth===2),d1=rows.find(r=>r.m_fifo_depth===1);
  const specs=[
    ['total_area_um2','Area (µm²)',10500,[0,2500,5000,7500,10000],'(a) Cell area'],
    ['flip_flop_count','Flip-flops',12000,[0,3000,6000,9000,12000],'(b) Flip-flop count'],
    ['vectorless_power_mw','Power (mW)',50,[0,10,20,30,40,50],'(c) Vectorless power'],
    ['fmax_mhz','Fmax (MHz)',1200,[0,300,600,900,1200],'(d) Estimated Fmax']
  ];
  const W=1400,H=430,pw=340,gap=7;
  let s=begin(W,H,'M FIFO depth post-synthesis comparison');
  specs.forEach((spec,p)=>{
    const [key,ylabel,max,ticks,caption]=spec,x=4+p*(pw+gap),y=8;
    let a=axes(s,x,y,pw,340,max,ticks,ylabel); s=a.s;
    [[2,d2[key],C.gray],[1,d1[key],C.blue]].forEach((v,i)=>{
      const cx=a.left+(a.right-a.left)*(i+0.5)/2,bw=70,bh=v[1]/max*(a.bottom-a.top);
      s+=`<rect x="${cx-bw/2}" y="${a.bottom-bh}" width="${bw}" height="${bh}" fill="${v[2]}"/>`;
      s+=`<text class="value" x="${cx}" y="${a.bottom-bh-7}" text-anchor="middle">${v[1].toLocaleString('en-US',{maximumFractionDigits:2})}</text>`;
      s+=`<text class="tick" x="${cx}" y="${a.bottom+22}" text-anchor="middle">${v[0]}</text>`;
    });
    s+=`<text x="${(a.left+a.right)/2}" y="${a.bottom+44}" text-anchor="middle">M FIFO depth</text>`;
    s+=`<text class="panel-label" x="${x+pw/2}" y="${y+394}" text-anchor="middle">${caption}</text>`;
  });
  s+='</svg>';
  write('m_fifo_ppa.svg',s);
}

configSweep();
ppa();
console.log('Generated buffer_depth_sweep.svg and m_fifo_ppa.svg');
