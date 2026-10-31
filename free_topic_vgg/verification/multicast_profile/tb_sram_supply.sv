`timescale 1ns/1ps
module tb_sram_supply;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    integer cycle=0,h=4,cin=32,mode=0,period=1;
    integer size_id,rate_id,c,w,b,nwords,expected_words,accepted,begin_cycle,load_end,total_received;
    reg host_valid=0;
    integer host_core=0,host_word=0;
    reg [63:0] host_data=0;
    wire [15:0] host_ready,feed_valid,feed_ready,feed_done,rx_valid,rx_empty;
    wire [1023:0] feed_data;
    reg [15:0] feed_start=0;
    integer received[0:15];
    wire [31:0] read_counts[0:15];
    wire [15:0] mc_valid,mc_ready;
    wire [63:0] mc_data;
    wire mc_idle;
    function automatic [7:0] pixel(input integer index);
        pixel=8'((index*37+19)%251);
    endfunction
    function automatic [63:0] expected(input integer index);
        integer tile,ch,p,y,x,j;
        begin
            tile=(index/2)/cin;ch=(index/2)%cin;expected=0;
            for(j=0;j<8;j++) begin
                p=(index%2)*8+j;y=(tile/(h/2))*2+p/4-1;x=(tile%(h/2))*2+p%4-1;
                if(y>=0 && y<h && x>=0 && x<h) expected[j*8+:8]=pixel((y*h+x)*cin+ch);
            end
        end
    endfunction
    vgg_mcast_fanout #(.DEPTH(4),.CORES(16)) fanout(
        .clk(clk),.rst_n(rst_n),.in_valid(mode==1 && feed_valid[0]),.in_ready(feed_ready[0]),
        .in_data(feed_data[63:0]),.in_keep(8'hff),.in_last(1'b0),.in_destinations(16'hffff),
        .out_valid(mc_valid),.out_ready(mc_ready),.out_data(mc_data),.out_keep(),.out_last(),.idle(mc_idle));
    genvar g;
    generate for(g=0;g<16;g++) begin: cores
        wire [15:0] rd,rr;
        wire [1:0] bank;
        wire [9:0] addr;
        wire tx_ready,tx_valid;
        wire [63:0] tx_data;
        wire local_ready,rx_in_ready;
        wire [63:0] rx_data;
        vgg_activation_sram mem(
            .clk(clk),.rst_n(rst_n),.host_valid(host_valid && host_core==g),.host_ready(host_ready[g]),
            .host_write(1'b1),.host_bank(2'(host_word/1024)),.host_addr(10'(host_word%1024)),.host_wdata(host_data),
            .host_rvalid(),.host_rready(1'b1),.host_rdata(),
            .tx_valid(rd[0]),.tx_ready(tx_ready),.tx_bank(bank),.tx_addr(addr),
            .tx_rvalid(tx_valid),.tx_rready(rr[0]),.tx_rdata(tx_data),
            .writer_valid(1'b0),.writer_ready(),.writer_bank(2'b0),.writer_addr(10'b0),.writer_data(64'b0));
        vgg_activation_feed #(.HEIGHT(32),.WIDTH(32),.CORES(16),.CHANNEL_BITS(9),.SHARD_BITS(8),.TILE_STREAM(1)) feed(
            .clk(clk),.rst_n(rst_n),.start(feed_start[g]),.phase(1'b0),.sharded(1'b0),.tile_mode(1'b1),
            .input_height(6'(h)),.input_width(6'(h)),.source_pooled(1'b0),.base_word(11'b0),
            .channels(10'(cin)),.shard_channels(8'b0),.source_block_channels(4'b0),.source_block_words(11'b0),
            .done(feed_done[g]),.read_valid(rd),.read_ready({15'b0,tx_ready}),.read_bank(bank),.read_addr(addr),
            .response_valid({15'b0,tx_valid}),.response_ready(rr),.response_data({960'b0,tx_data}),
            .out_valid(feed_valid[g]),.out_ready(local_ready),.out_data(feed_data[g*64+:64]),.out_last(),
            .source_reads(read_counts[g]),.stream_words());
        assign local_ready=mode==0 ? rx_in_ready : (g==0 ? feed_ready[0] : 1'b0);
        assign mc_ready[g]=rx_in_ready;
        elastic_fifo #(.DATA_WIDTH(64),.DEPTH(4)) rx(
            .clk(clk),.rst_n(rst_n),.in_valid(mode==0 ? feed_valid[g] : mc_valid[g]),
            .in_ready(rx_in_ready),.in_data(mode==0 ? feed_data[g*64+:64] : mc_data),
            .out_valid(rx_valid[g]),.out_ready(1'b1),.out_data(rx_data),.empty(rx_empty[g]),.full());
        always @(posedge clk) begin
            if(!rst_n) received[g]<=0;
            else if(rx_valid[g]) begin
                if(received[g]>=expected_words || rx_data!==expected(received[g]))
                    $fatal(1,"Bad tile core=%0d word=%0d got=%h expected=%h",g,received[g],rx_data,expected(received[g]));
                received[g]<=received[g]+1;
            end
        end
    end endgenerate
    always @(posedge clk) cycle<=cycle+1;
    initial begin
        for(size_id=0;size_id<3;size_id++) begin
            h=size_id==0 ? 4 : 8;cin=size_id==0 ? 32 : size_id==1 ? 64 : 256;
            nwords=h*h*cin/8;expected_words=h*h/4*cin*2;
            for(rate_id=0;rate_id<2;rate_id++) begin
                period=rate_id==0 ? 1 : 4;
                for(mode=0;mode<2;mode++) begin
                    @(negedge clk);rst_n=0;host_valid=0;feed_start=0;
                    repeat(4) @(negedge clk);rst_n=1;begin_cycle=cycle;accepted=0;
                    for(c=0;c<(mode==0 ? 16 : 1);c++) begin
                        host_core=c;w=0;
                        while(w<nwords) begin
                            host_valid=((cycle-begin_cycle)%period)==0;host_word=w;
                            for(b=0;b<8;b++) host_data[b*8+:8]=pixel(w*8+b);
                            @(posedge clk);if(host_valid && host_ready[c]) begin w++;accepted++;end
                            @(negedge clk);feed_start=0;
                        end
                        // Start this source immediately; its reads overlap later cores' loads.
                        host_valid=0;feed_start[c]=1;
                    end
                    load_end=cycle;
                    @(negedge clk);feed_start=0;
                    total_received=0;
                    while(total_received!=16*expected_words || !(&rx_empty) || (mode==1 && !mc_idle)) begin
                        @(negedge clk);total_received=0;
                        for(b=0;b<16;b++) total_received+=received[b];
                    end
                    $display("SUPPLY h=%0d cin=%0d bytes=%0d period=%0d multicast=%0d cycles=%0d load_cycles=%0d external_bytes=%0d received_words=%0d source0_reads=%0d",h,cin,nwords*8,period,mode,cycle-begin_cycle,load_end-begin_cycle,accepted*8,total_received,read_counts[0]);
                    $fflush();
                end
            end
        end
        $display("PASS SRAM_SUPPLY all_tiles_verified");$finish;
    end
    initial begin #100000000;$fatal(1,"timeout");end
endmodule
