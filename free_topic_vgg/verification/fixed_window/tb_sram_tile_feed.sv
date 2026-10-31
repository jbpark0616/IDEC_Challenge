`timescale 1ns/1ps
// Independent tensor-address oracle: SRAM -> padded Winograd tile stream.
module tb_sram_tile_feed #(
    parameter H=4,W=4,C=32,SHARDED=0,POOLED=0,PHASE=0
);
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,start=0;
    wire [3:0] req,ready,rv,rr;
    wire [1:0] bank; wire [9:0] addr;
    wire [255:0] rd;
    wire ov,ol,done; wire [63:0] od;
    wire [31:0] reads,words;
    integer cycle=0,checked=0;
    wire sink_ready=cycle%7!=2 && cycle%11!=4;
    reg [63:0] mem[0:3][0:4095];
    reg [3:0] pending=0;
    reg [63:0] response[0:3];
    genvar g;
    generate for(g=0;g<4;g=g+1) begin: banks
        assign ready[g]=(!pending[g] || rr[g]) && cycle%5!=g;
        assign rv[g]=pending[g];
        assign rd[g*64+:64]=response[g];
        always @(posedge clk) begin
            if(!rst_n) pending[g]<=0;
            else begin
                if(rr[g]) pending[g]<=0;
                if(req[g] && ready[g]) begin
                    pending[g]<=1;
                    response[g]<=mem[g][{bank,addr}];
                end
            end
        end
    end endgenerate
    vgg_activation_feed #(.CORES(4),.CORE_BITS(2),.CHANNEL_BITS(9),.SHARD_BITS(8),.TILE_STREAM(1)) dut (
        .clk(clk),.rst_n(rst_n),.start(start),.phase(1'(PHASE)),.sharded(1'(SHARDED)),.tile_mode(1'b1),
        .input_height(6'(H)),.input_width(6'(W)),.source_pooled(1'(POOLED)),.base_word(11'd7),
        .channels(10'(C)),.shard_channels(8'(C/4)),.source_block_channels(4'd8),.source_block_words(11'd0),
        .done(done),.read_valid(req),.read_ready(ready),.read_bank(bank),.read_addr(addr),
        .response_valid(rv),.response_ready(rr),.response_data(rd),
        .out_valid(ov),.out_ready(sink_ready),.out_data(od),.out_last(ol),.source_reads(reads),.stream_words(words)
    );
    function automatic [7:0] value(input integer y,x,c);
        value=(y*71+x*23+c*13+5)%256;
    endfunction
    integer y,x,c,k,a,owner,lc,localc,t,px,yy,xx,b;
    reg [63:0] expected;
    initial begin
        for(k=0;k<4;k=k+1) for(a=0;a<4096;a=a+1) mem[k][a]=0;
        for(y=0;y<H;y=y+1) for(x=0;x<W;x=x+1) for(c=0;c<C;c=c+1) begin
            owner=SHARDED ? c/(C/4) : 0; lc=SHARDED ? c%(C/4) : c; localc=SHARDED ? C/4 : C;
            if(!SHARDED || POOLED) a=(y*W+x)*localc+lc;
            else a=(((y/2)*(W/2)+x/2)*localc+lc)*4+(y%2)*2+x%2;
            a=a+7*8+PHASE*2048*8;
            mem[owner][a/8][(a%8)*8+:8]=value(y,x,c);
        end
        repeat(3) @(negedge clk); rst_n=1;
        @(negedge clk); start=1; @(negedge clk); start=0;
        wait(done); @(negedge clk);
        if(checked!=H*W/4*C*2) $fatal(1,"wrong word count %0d",checked);
        $display("PASS SRAM_TILE H=%0d W=%0d C=%0d sharded=%0d pooled=%0d phase=%0d words=%0d reads=%0d cycles=%0d",H,W,C,SHARDED,POOLED,PHASE,checked,reads,cycle);
        $finish;
    end
    always @(posedge clk) begin
        cycle<=cycle+1;
        if(cycle>2000000) $fatal(1,"watchdog");
        if(rst_n && ov && sink_ready) begin
            t=(checked/2)/C; c=(checked/2)%C;
            expected=0;
            for(b=0;b<8;b=b+1) begin
                px=(checked%2)*8+b;
                yy=(t/(W/2))*2+px/4-1; xx=(t%(W/2))*2+px%4-1;
                if(yy>=0 && yy<H && xx>=0 && xx<W) expected[b*8+:8]=value(yy,xx,c);
            end
            if(od!==expected) $fatal(1,"word %0d got=%h expected=%h",checked,od,expected);
            if(ol !== (checked==H*W/4*C*2-1)) $fatal(1,"last mismatch");
            checked=checked+1;
        end
    end
endmodule
