"""Compare timing-cleanup transport behavior; no compute RTL changes."""
from pathlib import Path
import subprocess,re,json
R=Path(__file__).resolve().parents[2];O=R/'evidence/interconnect_timing';W=R/'build/interconnect_timing'
W.mkdir(parents=True,exist_ok=True)
results={}
for name,folder in [('before',O/'before'),('after',R/'rtl/interconnect')]:
    results[name]={}
    tb=(R/'tests/tb_fanout16.sv').read_text().replace('independent_stalls subset_masks empty_masks','cycles=%0d independent_stalls subset_masks empty_masks').replace('WORDS,checked);','WORDS,checked,cycle);')
    for mode in ['stalls','continuous']:
        t=tb
        if mode=='continuous':
            t=t.replace('sent<WORDS && cycle%7!=0','sent<WORDS').replace('(cycle%(r+3)!=0) && (cycle%29<r+6)',"1'b1")
            t=t.replace('if(sent==WORDS && idle) begin','if(sent==WORDS && idle) begin\n if(cycle>WORDS+3) $fatal(1,"Continuous throughput regression");')
        (W/'fanout_test.sv').write_text(t)
        subprocess.run(['iverilog','-g2012','-s','tb_fanout16','-o',str(W/'compare.vvp'),str(R/'rtl/designated/elastic_fifo.v'),str(folder/'vgg_mcast_fanout.v'),str(W/'fanout_test.sv')],check=True)
        log=subprocess.check_output(['vvp',str(W/'compare.vvp')],text=True);assert 'PASS FANOUT16' in log
        (O/f'{name}_{mode}.log').write_text(log);results[name][mode]=int(re.search(r'cycles=(\d+)',log)[1])
    lines=[]
    for c in [3,32,128,512]:
        for mode in [0,1,2]:
            if c==3 and mode:continue
            subprocess.run(['iverilog','-g2012','-s','tb_sram_tile_feed',f'-Ptb_sram_tile_feed.C={c}',f'-Ptb_sram_tile_feed.SHARDED={int(mode>0)}',f'-Ptb_sram_tile_feed.POOLED={int(mode==2)}',f'-Ptb_sram_tile_feed.PHASE={int(mode==2)}','-o',str(W/'compare.vvp'),str(folder/'vgg_activation_feed.v'),str(R/'verification/fixed_window/tb_sram_tile_feed.sv')],check=True)
            log=subprocess.check_output(['vvp',str(W/'compare.vvp')],text=True);assert 'PASS SRAM_TILE' in log
            lines.append(log.splitlines()[0])
    results[name]['feed']=lines
assert results['before']['feed']==results['after']['feed'],'Address retiming changed cycles/read count'
(O/'comparison.json').write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2))
