"""Single-core before/after with actual activation SRAM and designated final generator."""
from pathlib import Path
import subprocess, hashlib, json, argparse
ap=argparse.ArgumentParser()
ap.add_argument('--immediate',action='store_true',help='Request-driven host, continuous writes, no injected stalls')
args=ap.parse_args()
R=Path(__file__).resolve().parents[2]
suffix='raster_restore_immediate' if args.immediate else 'raster_restore'
W=R/'build'/suffix; O=R/'evidence'/suffix
W.mkdir(parents=True,exist_ok=True); O.mkdir(parents=True,exist_ok=True)
original=R.parent/'verilog/winograd_sliding_window_generator.v'
(W/'designated_final_window.v').write_text(original.read_text().replace('module winograd_sliding_window_generator','module designated_final_window'))
tb=(R/'verification/v8/tb_v8_packed.sv').read_text()
if args.immediate:
    # Observe the request descriptor only; all changes still enter through
    # the normal host port. No hierarchical writes/force or zero-time SRAM fill.
    tb=tb.replace('                    fetch_status();', '''                    while(!dut.weights_waiting && !done_valid) @(negedge clk);
                    status={23'b0,dut.resident_u,4'b0,dut.outputs,7'b0,dut.consumed_tiles,dut.output_base,7'b0,dut.weights_waiting};''')
    tb=tb.replace('                        store(14,1,status ^ 64\'h10000);','')
    tb=tb.replace('                        if(dut.consumer_state!=dut.C_WEIGHTS) $fatal(1,"Stale weight commit accepted");','')
    tb=tb.replace('                        repeat(5) @(negedge clk);','')
    tb=tb.replace('        @(negedge clk);mem_valid=1;mem_write=1;',
                  "        if(clk!==1'b0) @(negedge clk);mem_valid=1;mem_write=1;")
    tb=tb.replace('output_ready_external=running && cycle%13<9;', 'output_ready_external=running;')
    tb=tb.replace('last_use_release backpressure zero_bypass stale_commit',
                  'last_use_release zero_bypass immediate_host')
tb=tb.replace('for(case_id=0;case_id<12;case_id++)','for(case_id=0;case_id<=6;case_id=case_id+6)')
tb=tb.replace('activation_valid=running && sent<input_words && cycle%7!=0;', 'activation_valid=running && feed_valid;')
tb=tb.replace('activation_data=TILE_INPUT ? tile_word(sent) : inputs[sent];','activation_data=feed_data;')
tb=tb.replace('if(activation_valid && activation_ready) sent++;', '''if(activation_valid && activation_ready) begin
                if(activation_data!==tile_word(sent)) $fatal(1,"Tile mismatch case=%0d word=%0d",case_id,sent);
                sent++;
            end''')
tb=tb.replace('weight_writes=0;load_block(0,0);', '''weight_writes=0;load_block(0,0);
                for(integer sw=0;sw<(h*h*cin+7)/8;sw++) begin
                    @(negedge clk);src_valid=1;src_addr=10'(sw);src_data=inputs[sw];
                    do @(posedge clk);while(!src_ready);
                    @(negedge clk);src_valid=0;
                end
                read_count=0;''')
# Print identical boundaries: actual start to core completion, preload excluded.
tb=tb.replace('                @(negedge clk);running=0;done_ready=1;', '''                $display("RASTER_COMPARE raster=%0d case=%0d sparse=%0d cycles=%0d reads=%0d tiles=%0d",raster_mode,case_id,sparse,active_cycles,read_count,transforms);
                @(negedge clk);running=0;done_ready=1;''')
fixture='''
    bit raster_mode;
    initial raster_mode=$test$plusargs("RASTER");
    reg src_valid=0;
    reg [9:0] src_addr=0;
    reg [63:0] src_data=0;
    wire src_ready,tx_ready,tx_rvalid,tx_rready,tx_valid;
    wire [63:0] tx_rdata;
    wire [9:0] tx_addr;
    wire [1:0] tx_bank;
    wire feed_valid;
    wire [63:0] feed_data;
    wire feed_ready=running && activation_ready;
    wire begin_feed=start_valid && start_ready;
    wire [15:0] old_rd,old_rr;
    wire [1:0] old_bank;
    wire [9:0] old_addr,new_addr;
    wire old_valid,new_valid,new_rd,new_rr;
    wire [63:0] old_data,new_data;
    integer read_count=0;
    always @(posedge clk) if(tx_valid && tx_ready) read_count++;
    assign tx_valid=raster_mode ? new_rd : old_rd[0];
    assign tx_rready=raster_mode ? new_rr : old_rr[0];
    assign tx_addr=raster_mode ? new_addr : old_addr;
    assign tx_bank=raster_mode ? 2'b0 : old_bank;
    assign feed_valid=raster_mode ? new_valid : old_valid;
    assign feed_data=raster_mode ? new_data : old_data;
    vgg_activation_sram source_sram(
        .clk(clk),.rst_n(rst_n),.host_valid(src_valid),.host_ready(src_ready),
        .host_write(1'b1),.host_bank(2'b0),.host_addr(src_addr),.host_wdata(src_data),
        .host_rvalid(),.host_rready(1'b1),.host_rdata(),
        .tx_valid(tx_valid),.tx_ready(tx_ready),.tx_bank(tx_bank),.tx_addr(tx_addr),
        .tx_rvalid(tx_rvalid),.tx_rready(tx_rready),.tx_rdata(tx_rdata),
        .writer_valid(1'b0),.writer_ready(),.writer_bank(2'b0),.writer_addr(10'b0),.writer_data(64'b0));
    raster_sram_feed #(.H(4),.W(4)) raster(
        .clk(clk),.rst_n(rst_n),.start(begin_feed && raster_mode),
        .rd_valid(new_rd),.rd_ready(tx_ready && raster_mode),.rd_addr(new_addr),
        .rsp_valid(tx_rvalid && raster_mode),.rsp_ready(new_rr),.rsp_data(tx_rdata),
        .out_valid(new_valid),.out_ready(feed_ready && raster_mode),.out_data(new_data));
    vgg_activation_feed #(.CORES(16),.CHANNEL_BITS(9),.SHARD_BITS(8),.TILE_STREAM(1)) old_feed(
        .clk(clk),.rst_n(rst_n),.start(begin_feed && !raster_mode),.phase(1'b0),.sharded(1'b0),.tile_mode(1'b1),
        .input_height(6'd4),.input_width(6'd4),.source_pooled(1'b0),.base_word(11'b0),
        .channels(10'd3),.shard_channels(8'b0),.source_block_channels(4'b0),.source_block_words(11'b0),
        .done(),.read_valid(old_rd),.read_ready({15'b0,tx_ready && !raster_mode}),.read_bank(old_bank),.read_addr(old_addr),
        .response_valid({15'b0,tx_rvalid && !raster_mode}),.response_ready(old_rr),.response_data({960'b0,tx_rdata}),
        .out_valid(old_valid),.out_ready(feed_ready && !raster_mode),.out_data(old_data),.out_last(),.source_reads(),.stream_words());
'''
tb=tb.replace('    integer physical_writes=0;',fixture+'\n    integer physical_writes=0;')
(W/'tb.sv').write_text(tb)
with (O/'build.log').open('w') as log:
    subprocess.run(['verilator','--binary','--timing','-Wno-fatal','-j','2','--top-module','tb_v8_packed','-GDENSE_U=1','-GTILE_INPUT=1','--Mdir',str(W/'obj'),'-f','rtl/sources.f','third_party/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v',str(W/'designated_final_window.v'),'verification/raster_restore/raster_sram_feed.v',str(W/'tb.sv')],cwd=R,stdout=log,stderr=subprocess.STDOUT,check=True)
for name,extra in [('old',[]),('raster',['+RASTER'])]:
    with (O/f'{name}.log').open('w') as log:
        subprocess.run([str(W/'obj/Vtb_v8_packed'),'+RESIDENT',*extra],cwd=R,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=300)
    print((O/f'{name}.log').read_text(),flush=True)
(O/'provenance.json').write_text(json.dumps({'designated_generator_sha256':hashlib.sha256(original.read_bytes()).hexdigest(),'scope':'One core, H4 W4 C3 K6/K128, actual source SRAM; original and raster feed; sparse OFF/ON. No cluster changes.', 'immediate_host':args.immediate, 'request_observation':'internal descriptor observed; writes through real ready/valid host port' if args.immediate else 'polled status', 'tb_sha256':hashlib.sha256(tb.encode()).hexdigest()},indent=2))
