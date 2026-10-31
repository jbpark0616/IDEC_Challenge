"""Separate compact four-channel variant; 64B staging, real half-word rereads."""
from pathlib import Path
import subprocess
R=Path(__file__).resolve().parents[2]; D=Path(__file__).resolve().parent
S=R/'verification/feed_hwc8'
subprocess.run(['python3',str(S/'prepare.py')],check=True)
for name in ('original_feed.v','feed_wrapper.v','feed_hwc8.v','sources.f','original_sha256.json'):
    text=(S/name).read_text().replace('vgg_activation_feed_hwc8','vgg_activation_feed_hwc4')
    if name=='feed_wrapper.v': text=text.replace('channels[2:0]==0','channels[1:0]==0')
    if name=='sources.f':text=text.replace('verification/feed_hwc8/','verification/feed_hwc4/').replace('feed_hwc8.v','feed_hwc4.v')
    if name=='feed_hwc8.v':
        text=text.replace('// Fixed 128-byte staging buffer: 16 spatial positions x 8 adjacent channels.',
                          '// Fixed 64-byte staging: 16 positions x 4 channels; adjacent half-word reread is intentional.')
        text=text.replace('C divisible by 8','C divisible by 4')
        text=text.replace('reg [2:0] lane;','reg [1:0] lane;\nreg request_upper;')
        text=text.replace('reg [63:0] pixels[0:15];','reg [31:0] pixels[0:15];')
        text=text.replace('group_channel+8','group_channel+4').replace('lane==7','lane==3').replace('lane!=7','lane!=3')
        text=text.replace('pixels[p]<=response_data[63:0];',
                          'pixels[p]<=request_upper ? response_data[63:32] : response_data[31:0];')
        text=text.replace('request_word<=address[13:3];',
                          'begin request_word<=address[13:3];request_upper<=address[2];end')
    (D/('feed_hwc4.v' if name=='feed_hwc8.v' else name)).write_text(text)
tb=(S/'tb_feed.sv').read_text().replace('mode<6','mode<8')
tb=tb.replace('5:c=3;endcase','5:c=3;6:c=4;7:c=12;endcase')
tb=tb.replace('if(c%8==0)','if(c%4==0)').replace('(c/8)','(c/4)')
(D/'tb_feed.sv').write_text(tb)
