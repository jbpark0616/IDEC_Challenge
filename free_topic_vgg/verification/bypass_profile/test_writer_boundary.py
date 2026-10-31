"""Exercise the exact writer queue snippet against contended physical SRAM ports."""
from pathlib import Path
import subprocess

r = Path(__file__).resolve().parents[2]
w = r / 'build/writer_boundary'
w.mkdir(parents=True, exist_ok=True)
rtl = (r/'rtl/vgg_ab_layer_cluster.v').read_text()
snippet = rtl[rtl.index('        wire [11:0] region_output_word'):rtl.index('        vgg_sram_conv_layer #')]
snippet = snippet.replace('writer_empty[c]', 'writer_empty')
snippet = snippet[:snippet.index('        vgg_activation_sram u_activation')]
tb = r'''`timescale 1ns/1ps
module tb_writer_boundary;
reg clk=0,rst_n=0;
always #5 clk=~clk;
reg phase=0;
reg [10:0] output_base=0,block_write_base=0,output_word=0;
reg [63:0] output_data=0;
reg output_valid=0;
wire output_ready,writer_empty;
SNIPPET
reg host_valid=0,host_write=0,host_rready=0;
reg [1:0] host_bank=0;
reg [9:0] host_addr=0;
reg [63:0] host_wdata=0;
wire host_ready,host_rvalid;
wire [63:0] host_rdata;
reg tx_valid=0,tx_rready=0;
reg [1:0] tx_bank=0;
reg [9:0] tx_addr=0;
wire tx_ready,tx_rvalid;
wire [63:0] tx_rdata;
vgg_activation_sram ram(
 .clk(clk),.rst_n(rst_n),
 .host_valid(host_valid),.host_ready(host_ready),.host_write(host_write),
 .host_bank(host_bank),.host_addr(host_addr),.host_wdata(host_wdata),
 .host_rvalid(host_rvalid),.host_rready(host_rready),.host_rdata(host_rdata),
 .tx_valid(tx_valid),.tx_ready(tx_ready),.tx_bank(tx_bank),.tx_addr(tx_addr),
 .tx_rvalid(tx_rvalid),.tx_rready(tx_rready),.tx_rdata(tx_rdata),
 .writer_valid(writer_valid),.writer_ready(writer_ready),
 .writer_bank(writer_payload[75:74]),.writer_addr(writer_payload[73:64]),
 .writer_data(writer_payload[63:0]));
reg [75:0] expected[0:511];
reg [75:0] held;
reg was_stalled=0,stress=0;
integer accepted=0,committed=0,cycles=0,stalls=0,checked=0;
integer h_reads=0,t_reads=0;
always @(posedge clk) begin
 cycles++;
 if(cycles>30000) $fatal(1,"timeout");
 if(rst_n) begin
  if(was_stalled && (!writer_valid || writer_payload!==held)) $fatal(1,"stalled payload changed");
  was_stalled=writer_valid&&!writer_ready;
  held=writer_payload;
  if(output_valid && output_ready) begin
   expected[accepted] = {!phase,region_output_word[10:0],output_data};
   accepted++;
  end
  if(output_valid && !output_ready) stalls++;
  if(writer_valid && writer_ready) begin
   if(committed>=accepted || writer_payload!==expected[committed]) $fatal(1,"transaction mismatch");
   committed++;
  end
  if(host_valid&&host_ready) h_reads++;
  if(tx_valid&&tx_ready) t_reads++;
 end
end
always @(negedge clk) if(stress) begin
 host_valid=1;tx_valid=1;
 host_bank=writer_payload[75:74];tx_bank=writer_payload[75:74];
 host_addr=0;tx_addr=1;
 host_rready=(cycles%7==0);tx_rready=(cycles%11==0);
end
integer i;
initial begin
 repeat(4) @(negedge clk);rst_n=1;stress=1;
 for(i=0;i<512;i++) begin
  phase=i[8];output_base=i[7] ? 11'd1024 : 0;
  block_write_base=11'd16;output_word={4'b0,i[6:0]};
  output_data=64'h1234567800000000+i;output_valid=1;
  do @(posedge clk); while(!output_ready);
  @(negedge clk);output_valid=0;
 end
 @(negedge clk);stress=0;host_valid=0;tx_valid=0;host_rready=1;tx_rready=1;
 wait(writer_empty);@(negedge clk);
 if(accepted!=512 || committed!=512 || stalls==0) $fatal(1,"coverage/count failure accepted=%0d committed=%0d stalls=%0d",accepted,committed,stalls);
 for(i=0;i<512;i++) begin
  @(negedge clk);host_valid=1;host_bank=expected[i][75:74];host_addr=expected[i][73:64];host_rready=0;
  do @(posedge clk);while(!host_ready);
  @(negedge clk);host_valid=0;
  if(!host_rvalid || host_rdata!==expected[i][63:0]) $fatal(1,"SRAM mismatch %0d",i);
  checked++;host_rready=1;@(negedge clk);
 end
 $display("PASS WRITER_BOUNDARY accepted=%0d committed=%0d checked=%0d stalls=%0d host_reads=%0d tx_reads=%0d cycles=%0d",accepted,committed,checked,stalls,h_reads,t_reads,cycles);
 $finish;
end
endmodule
'''.replace('SNIPPET', snippet)
(w/'tb.sv').write_text(tb)
sources = ['rtl/designated/elastic_fifo.v','rtl/memory/vgg_activation_sram.v','rtl/memory/vgg_sram_8k.v','third_party/asap7_sram/generated/verilog/srambank_256x4x64_6t122.v']
subprocess.run(['iverilog','-g2012','-s','tb_writer_boundary','-o',str(w/'sim'),str(w/'tb.sv')]+[str(r/p) for p in sources],check=True)
result=subprocess.run(['vvp',str(w/'sim')],text=True,capture_output=True)
(r/'evidence/timing_writer_pipeline/writer_boundary.log').write_text(result.stdout)
print(result.stdout)
result.check_returncode()
