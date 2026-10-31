"""Independent address/cache replay for the measured Conv5 core0 HWC layout."""
from pathlib import Path
import json
tags=[None]*4
reads=hits=padding=0
unique=set()
for ty in range(4):
    for tx in range(4):
        for channel in range(128):
            for py in range(4):
                for px in range(4):
                    y,x=2*ty+py-1,2*tx+px-1
                    if not (0<=y<8 and 0<=x<8):
                        padding+=1
                        continue
                    word=((y*8+x)*128+channel)//8
                    slot=word&3
                    if tags[slot]==word:
                        hits+=1
                    else:
                        reads+=1;unique.add(word);tags[slot]=word
result=dict(input_shape=[1,8,8,128],valid_pixel_uses=reads+hits,padding_pixel_uses=padding,
            cache_reused_pixels=hits,sram_reads=reads,unique_words=len(unique),
            requested_bytes=8*reads,input_bytes=8*8*128,
            note='Address-only replay, not cycle simulation. A retry after a fetched response is not counted as reuse.')
assert reads==25088 and hits==0 and len(unique)==1024
out=Path(__file__).resolve().parents[2]/'evidence/cluster_bottleneck'
out.mkdir(parents=True,exist_ok=True)
(out/'address_audit.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
