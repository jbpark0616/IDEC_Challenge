"""Create an isolated source list. Never edit main RTL or its manifest."""
from pathlib import Path
import hashlib,json
R=Path(__file__).resolve().parents[2]; D=Path(__file__).resolve().parent
orig=R/'rtl/interconnect/vgg_activation_feed.v'
s=orig.read_text(); header=s[s.index('module vgg_activation_feed'):s.index(');')+2]
ports=['clk','rst_n','start','phase','sharded','tile_mode','input_height','input_width','source_pooled',
       'base_word','channels','shard_channels','source_block_channels','source_block_words']
outs={'done':1,'read_valid':'CORES','read_bank':2,'read_addr':10,'response_ready':'CORES',
      'out_valid':1,'out_data':64,'out_last':1,'source_reads':32,'stream_words':32}
ins=['read_ready','response_valid','response_data','out_ready']
params=['HEIGHT','WIDTH','CORES','CORE_BITS','CHANNEL_BITS','BLOCK_LAYOUT','TILE_STREAM','SHARD_BITS']
(D/'original_feed.v').write_text(s.replace('module vgg_activation_feed #','module vgg_activation_feed_original #'))
wrapper=header.replace('output reg','output wire')+'\n'
wrapper+='reg use_fast;\nwire eligible=TILE_STREAM && tile_mode && !sharded && channels!=0 && channels[2:0]==0;\n'
wrapper+='always @(posedge clk or negedge rst_n) if(!rst_n) use_fast<=0; else if(start) use_fast<=eligible;\n'
for name,width in outs.items():
    shape='' if width==1 else f'[{width}-1:0] '
    wrapper+=f'wire {shape}fast_{name}, old_{name};\nassign {name}=use_fast ? fast_{name} : old_{name};\n'
for prefix,mod in [('old','vgg_activation_feed_original'),('fast','vgg_activation_feed_hwc8')]:
    con=[f'.{p}({p})' for p in ports if p!='start']
    con += [f'.start(start && {"eligible" if prefix=="fast" else "!eligible"})']
    con += [f'.{p}({p})' for p in ins]
    con += [f'.{p}({prefix}_{p})' for p in outs]
    wrapper+=f'{mod} #('+','.join(f'.{p}({p})' for p in params)+f') {prefix}_path (\n'+',\n'.join(con)+'\n);\n'
wrapper+='endmodule\n'
(D/'feed_wrapper.v').write_text(wrapper)
engine=header.replace('module vgg_activation_feed #','module vgg_activation_feed_hwc8 #')
engine=engine.replace('output reg','output wire')
body=(D/'hwc8_body.vh').read_text()
(D/'feed_hwc8.v').write_text(engine+'\n'+body+'\nendmodule\n')
lines=(R/'rtl/sources.f').read_text().splitlines()
lines=[l for l in lines if 'interconnect/vgg_activation_feed.v' not in l]
lines += ['verification/feed_hwc8/'+n for n in ['original_feed.v','feed_hwc8.v','feed_wrapper.v']]
(D/'sources.f').write_text('\n'.join(lines)+'\n')
(D/'original_sha256.json').write_text(json.dumps({'rtl/interconnect/vgg_activation_feed.v':hashlib.sha256(orig.read_bytes()).hexdigest()},indent=2))
