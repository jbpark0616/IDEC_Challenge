`timescale 1ns/1ps
module tb_feed;
reg clk=0,rst_n=0,start=0;
always #5 clk=~clk;
integer h,c,n,word_count,cycle=0,received,mode,rate,expected_reads;
reg host_valid=0;
reg [9:0] host_addr=0;
reg [1:0] host_bank=0;
reg [63:0] host_data=0;
wire host_ready,tx_ready,tx_rvalid;
wire [63:0] tx_rdata,data;
wire [15:0] rd,rr;
wire [1:0] bank;
wire [9:0] addr;
wire valid,done,last;
wire ready=rate==0 || cycle%7<4;
wire allow_request=rate==0 || cycle%5!=0;
wire [31:0] reads,words;
always @(posedge clk) cycle<=cycle+1;
function automatic [7:0] pixel(input integer idx);
    pixel=8'((idx*37+19)%251);
endfunction
function automatic [63:0] expected(input integer idx);
    integer t,ch,p,y,x,b;
    begin
        t=(idx/2)/c;ch=(idx/2)%c;expected=0;
        for(b=0;b<8;b++) begin
            p=(idx%2)*8+b;y=(t/(h/2))*2+p/4-1;x=(t%(h/2))*2+p%4-1;
            if(y>=0 && y<h && x>=0 && x<h) expected[b*8+:8]=pixel((y*h+x)*c+ch);
        end
    end
endfunction
vgg_activation_sram mem(
 .clk(clk),.rst_n(rst_n),.host_valid(host_valid),.host_ready(host_ready),.host_write(1'b1),
 .host_bank(host_bank),.host_addr(host_addr),.host_wdata(host_data),.host_rvalid(),.host_rready(1'b1),.host_rdata(),
 .tx_valid(rd[0] && allow_request),.tx_ready(tx_ready),.tx_bank(bank),.tx_addr(addr),
 .tx_rvalid(tx_rvalid),.tx_rready(rr[0]),.tx_rdata(tx_rdata),
 .writer_valid(1'b0),.writer_ready(),.writer_bank(2'b0),.writer_addr(10'b0),.writer_data(64'b0));
vgg_activation_feed #(.CORES(16),.CHANNEL_BITS(9),.SHARD_BITS(8),.TILE_STREAM(1)) dut(
 .clk(clk),.rst_n(rst_n),.start(start),.phase(1'b0),.sharded(1'b0),.tile_mode(1'b1),
 .input_height(6'(h)),.input_width(6'(h)),.source_pooled(1'b0),.base_word(11'b0),
 .channels(10'(c)),.shard_channels(8'b0),.source_block_channels(4'b0),.source_block_words(11'b0),
 .done(done),.read_valid(rd),.read_ready({15'b0,tx_ready && allow_request}),.read_bank(bank),.read_addr(addr),
 .response_valid({15'b0,tx_rvalid}),.response_ready(rr),.response_data({960'b0,tx_rdata}),
 .out_valid(valid),.out_ready(ready),.out_data(data),.out_last(last),.source_reads(reads),.stream_words(words));
reg held=0;
reg [64:0] held_data;
always @(posedge clk) begin
 if(!rst_n || start) held<=0;
 else begin
    if(held && (!valid || {last,data}!==held_data)) $fatal(1,"unstable stalled output");
    held<=valid && !ready;
    held_data<={last,data};
    if(valid && ready) begin
        if(data!==expected(received) || last!==(received==word_count-1))
            $fatal(1,"tile mismatch C=%0d word=%0d got=%h expected=%h",c,received,data,expected(received));
        received++;
    end
 end
end
initial begin
 for(mode=0;mode<6;mode++) begin
    h=mode==2 || mode==3 ? 8 : 4;
    case(mode) 0:c=8;1:c=32;2:c=128;3:c=256;4:c=512;5:c=3;endcase
    for(rate=0;rate<2;rate++) begin
        @(negedge clk);rst_n=0;received=0;host_valid=0;
        repeat(3) @(negedge clk);rst_n=1;
        word_count=h*h*c/2;
        for(n=0;n<(h*h*c+7)/8;n++) begin
            host_valid=1;host_bank=2'(n/1024);host_addr=10'(n%1024);
            for(integer b=0;b<8;b++) host_data[b*8+:8]=pixel(n*8+b);
            do @(posedge clk);while(!host_ready);
            @(negedge clk);host_valid=0;
        end
        start=1;@(negedge clk);start=0;
        wait(done);@(negedge clk);
        if(received!=word_count || words!=word_count) $fatal(1,"count mismatch");
        if(c%8==0) begin
            expected_reads=(2*h-2)*(2*h-2)*(c/8);
            if(reads!=expected_reads) $fatal(1,"read count got=%0d expected=%0d",reads,expected_reads);
        end
        $display("PASS FEED H=%0d C=%0d stalls=%0d words=%0d reads=%0d",h,c,rate,words,reads);
    end
 end
 $display("PASS ALL_FEED");$finish;
end
initial begin #10000000;$fatal(1,"timeout");end
endmodule
