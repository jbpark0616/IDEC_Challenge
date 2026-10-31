"""Conv5 only: frozen cluster, request-driven shared host versus saved polling run."""
from pathlib import Path
import hashlib, json, re, subprocess, time, argparse
ap=argparse.ArgumentParser()
ap.add_argument('--audit',action='store_true')
args=ap.parse_args()
R=Path(__file__).resolve().parents[2]
name='cluster_bottleneck' if args.audit else 'cluster_immediate'
W=R/'build'/name; O=R/'evidence'/name
W.mkdir(parents=True,exist_ok=True); O.mkdir(parents=True,exist_ok=True)
manifest=json.loads((R/'evidence/report_baseline_700mhz/manifest.json').read_text(encoding='utf-8-sig'))
def hashes():
    values={f['path']:hashlib.sha256((R/f['path']).read_bytes()).hexdigest() for f in manifest['files']}
    assert all(values[f['path']].lower()==f['sha256'].lower() for f in manifest['files'])
    return values
rtl=hashes()
source=R/'build/report700/cluster_all/tb.sv'
tb=source.read_text()
assert 'module tb_report_layer;' in tb
tb=tb.replace('    genvar m;', '''    wire [63:0] request_descriptor [0:15];
    genvar m;''')
tb=tb.replace('generate for(m=0;m<16;m++) begin : monitor', '''generate for(m=0;m<16;m++) begin : monitor
        // Read-only observation of the existing request. Responses still use
        // the shared physical host port, one accepted 64-bit word per cycle.
        assign request_descriptor[m] = {
            23'b0,dut.u_cluster.g_core[m].u_compute.resident_u,4'b0,
            dut.u_cluster.g_core[m].u_compute.outputs,7'b0,
            dut.u_cluster.g_core[m].u_compute.consumed_tiles,
            dut.u_cluster.g_core[m].u_compute.output_base,7'b0,
            dut.u_cluster.g_core[m].u_compute.weights_waiting};''')
assert tb.count('fetch(core,14,0,status);')==1
tb=tb.replace('fetch(core,14,0,status);','status=request_descriptor[core];')
if args.audit:
    from cluster_probe import instrument
    tb=instrument(tb)
(W/'tb.sv').write_text(tb)
start=time.monotonic()
with (O/'build.log').open('w') as log:
    subprocess.run(['verilator','--binary','--timing','-Wno-fatal','-j','2',
        '--top-module','tb_report_layer','--Mdir',str(W/'obj'),'-f','rtl/sources.f',
        'third_party/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v',str(W/'tb.sv')],
        cwd=R,stdout=log,stderr=subprocess.STDOUT,check=True)
print('BUILD COMPLETE',flush=True)
results=[]
def parse(path):
    text=path.read_text()
    assert 'PASS ISOLATED_LAYER' in text
    out={}
    for line in text.splitlines():
        if line.startswith(('PROFILE ','LAYER_PASS ')):
            out.update({k:int(v) for k,v in re.findall(r'(\w+)=([0-9]+)(?=\s|$)',line)})
    return out
for sparse in (0,1):
    logfile=O/f'conv5_sparse{sparse}.log'
    with logfile.open('w') as log:
        subprocess.run([str(W/'obj/Vtb_report_layer'),'+LAYER=4','+STREAM_HOST','+RESIDENT_U']+
            (['+SPARSE'] if sparse else []),cwd=R,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=1800)
    old=parse(R/f'evidence/report700/cluster_all/conv5_sparse{sparse}.log')
    new=parse(logfile)
    for k in ('mac_lanes','U_words','source_reads','compared_words','replacements'):
        assert old[k]==new[k],(k,old[k],new[k])
    results.append({'sparse':sparse,'old':old,'immediate':new})
    assert hashes()==rtl
    print(f'PASS sparse={sparse} cycles {old["cycles"]} -> {new["cycles"]}',flush=True)
    (O/'results.json').write_text(json.dumps(results,indent=2))
(O/'provenance.json').write_text(json.dumps({'rtl_sha256':rtl,'tb_sha256':hashlib.sha256(tb.encode()).hexdigest(),
    'original_tb_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
    'scope':'Conv5 input [1,8,8,128], Cout256, all16 cores. Only replace TB status polling with read-only request descriptor observation. Shared ready/valid port unchanged. Initial preload excluded from run cycles.',
    'elapsed_seconds':time.monotonic()-start},indent=2))
