"""Nonintrusive layer profiling of frozen matched ICG-on variants."""
from pathlib import Path
import csv,hashlib,json,re,subprocess,zipfile
R=Path(__file__).resolve().parents[2]
O=R/'docs/experiment_results/designated/designated_layers'; O.mkdir(parents=True,exist_ok=True)
W=R/'build/report_designated_layers'
frozen=json.loads((R/'docs/experiment_results/designated/designated_final/rtl_sha256.json').read_text())
def check():
    assert {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (R/'verilog').glob('*.v')}==frozen
check()
fields=['run_cycles','mac_beats','active_lane_products','nonzero_operand_products','bypass_jobs','v_tiles','zero_rows','zero_tiles','zero_elements','output_transforms','issue_cycles','bypass_cycles','mac_blocked_cycles','order_blocked_cycles','no_v_cycles','other_cycles']
monitor='''
    integer counts[0:1][0:15];
    integer li,mi,rr,nn,zz,mask_count;
    always @(posedge clk) begin
      if (!rst_n) begin
        for(li=0;li<2;li=li+1) for(mi=0;mi<16;mi=mi+1) counts[li][mi]=0;
      end else if (dut.u_accelerator.state==2 || dut.u_accelerator.state==4) begin
        li=(dut.u_accelerator.state==2)?0:1;
        counts[li][0]=counts[li][0]+1;
        if (`CORE.u_mac.in_valid && `CORE.u_mac.in_ready) begin
          counts[li][1]=counts[li][1]+1;
          for(rr=0;rr<16;rr=rr+1) if (`CORE.v_row_enable[rr/4]) begin
            counts[li][2]=counts[li][2]+1;
            if (`CORE.v_tile[rr*11 +:11]!=0 && `CORE.selected_u[rr*4 +:4]!=0)
              counts[li][3]=counts[li][3]+1;
          end
        end
        if (`CORE.bypass_transfer) counts[li][4]=counts[li][4]+1;
        if (`CORE.transform_valid && `CORE.transform_ready) begin
          counts[li][5]=counts[li][5]+1;
          zz=0; mask_count=0;
          for(rr=0;rr<4;rr=rr+1) begin
            if (`CORE.transform_v[rr*44 +:44]==0) begin
              counts[li][6]=counts[li][6]+1; mask_count=mask_count+1;
            end
            if (`CORE.transform_zero_rows[rr] !== (`CORE.transform_v[rr*44 +:44]==0))
              $fatal(1,"zero mask mismatch");
          end
          if(mask_count==4) counts[li][7]=counts[li][7]+1;
          for(rr=0;rr<16;rr=rr+1)
            if(`CORE.transform_v[rr*11 +:11]==0) counts[li][8]=counts[li][8]+1;
        end
        if (`CORE.u_output_transform.in_valid && `CORE.u_output_transform.in_ready)
          counts[li][9]=counts[li][9]+1;
        // Exclusive MAC input-boundary classification, not a causal latency model.
        if (`CORE.u_mac.in_valid && `CORE.u_mac.in_ready) counts[li][10]=counts[li][10]+1;
        else if (`CORE.bypass_transfer) counts[li][11]=counts[li][11]+1;
        else if (!`CORE.v_valid) counts[li][14]=counts[li][14]+1;
        else if (!`CORE.order_in_ready && (`CORE.v_zero_job || `CORE.v_txn_last)) counts[li][13]=counts[li][13]+1;
        else if (!`CORE.mac_input_ready) counts[li][12]=counts[li][12]+1;
        else counts[li][15]=counts[li][15]+1;
      end
    end
    always @(posedge valid_out_6) begin
      for(nn=0;nn<2;nn=nn+1) begin
        $write("LAYER,%0d,%0d",image_index,nn+1);
        for(zz=0;zz<16;zz=zz+1) $write(",%0d",counts[nn][zz]);
        $write("\\n");
      end
    end
'''.replace('`CORE','dut.u_accelerator.u_core')
z=zipfile.ZipFile(R/'verification/designated_ablation_reference.zip')
allrows=[]
for case in ['b0_g1','b1_g1']:
    work=W/case; rtl=work/'rtl';rtl.mkdir(parents=True,exist_ok=True)
    for name,sha in frozen.items():
        data=z.read(f'experiments/row_sparse_fixed/iterations/matched_ablation/cases/{case}/rtl/{name}')
        if case=='b1_g1': assert hashlib.sha256(data).hexdigest()==sha
        (rtl/name).write_bytes(data)
    tb=(R/'verification/winograd_chip_1000_tb.v').read_text().replace('../../../',R.as_posix()+'/')
    tb=re.sub(r'localparam integer TEST_IMAGE_COUNT = \d+;', 'localparam integer TEST_IMAGE_COUNT = 100;',tb)
    tb=tb.replace('(correct == 970)','(correct == 97)').replace('module winograd_chip_1000_tb;','module winograd_chip_1000_tb;\n'+monitor)
    (work/'tb.v').write_text(tb)
    with (work/'compile.log').open('w') as f:
        subprocess.run(['iverilog','-g2012','-DTEST_M_FIFO_DEPTH_1','-s','winograd_chip_1000_tb','-o',str(work/'sim.vvp'),*map(str,sorted(rtl.glob('*.v'))),str(work/'tb.v')],check=True,stdout=f,stderr=subprocess.STDOUT)
    with (O/(case+'.log')).open('w') as f:
        subprocess.run(['vvp','-n',str(work/'sim.vvp')],cwd=work,check=True,stdout=f,stderr=subprocess.STDOUT,timeout=1200)
    log=(O/(case+'.log')).read_text();assert 'PASS' in log and 'FAIL' not in log and 'ERROR' not in log
    parsed=[]
    for line in log.splitlines():
        if not line.startswith('LAYER,'):continue
        vals=list(map(int,line.split(',')[1:])); row=dict(case=case,image_index=vals[0],layer='Conv'+str(vals[1]),**dict(zip(fields,vals[2:])))
        assert row['run_cycles']==sum(row[k] for k in fields[10:])
        parsed.append(row)
    assert len(parsed)==200
    allrows+=parsed
    print(case,'PASS 100 images, 200 layer records',flush=True)
summaries=[]
for case in ['b0_g1','b1_g1']:
    for layer in ['Conv1','Conv2']:
        subset=[r for r in allrows if r['case']==case and r['layer']==layer]
        sums={k:sum(r[k] for r in subset) for k in fields}
        summaries.append(dict(case=case,layer=layer,images=100,**{k+'_mean':v/100 for k,v in sums.items()},zero_row_percent=100*sums['zero_rows']/(4*sums['v_tiles']),zero_tile_percent=100*sums['zero_tiles']/sums['v_tiles'],zero_element_percent=100*sums['zero_elements']/(16*sums['v_tiles'])))
for layer in ['Conv1','Conv2']:
    a,b=[r for r in summaries if r['layer']==layer]
    for k in ['v_tiles_mean','zero_rows_mean','zero_tiles_mean','zero_elements_mean','nonzero_operand_products_mean']:
        assert a[k]==b[k],(layer,k)
effects=[]
for layer in ['Conv1','Conv2']:
    a,b=[r for r in summaries if r['layer']==layer]
    effects.append(dict(layer=layer,**{k+'_reduction_percent':100*(1-b[k+'_mean']/a[k+'_mean']) for k in ['run_cycles','mac_beats','active_lane_products','output_transforms']}))
for name,rows in [('per_image.csv',allrows),('layer_summary.csv',summaries),('layer_reduction.csv',effects)]:
    with (O/name).open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
check()
(O/'rtl_sha256.json').write_text(json.dumps(frozen,indent=2))
print(json.dumps(summaries,indent=2));print(json.dumps(effects,indent=2))
