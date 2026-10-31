`timescale 1ns/1ps
module tb_transport;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    reg in_valid=0;
    wire in_ready,idle;
    reg [63:0] in_data=0;
    reg in_last=0;
    reg [15:0] destinations=0;
    wire [15:0] out_valid,out_ready,rx_valid,rx_empty;
    wire [63:0] out_data;
    wire [7:0] keep;
    wire last;
    integer count[0:15],cycle=0,sent=0,words=0,mode=0,period=1;
    integer size_index,rate_index,received_total,start_cycle,elapsed,i;
    function automatic [63:0] payload(input integer index);
        payload=64'h193ac57200000000 ^ (64'(index)*64'h102030405);
    endfunction
    vgg_mcast_fanout #(.DEPTH(4),.CORES(16)) dut(
        .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_ready(in_ready),
        .in_data(in_data),.in_keep(8'hff),.in_last(in_last),.in_destinations(destinations),
        .out_valid(out_valid),.out_ready(out_ready),.out_data(out_data),.out_keep(keep),.out_last(last),.idle(idle));
    genvar c;
    generate for(c=0;c<16;c++) begin : g_rx
        wire [63:0] data;
        elastic_fifo #(.DATA_WIDTH(64),.DEPTH(4)) rx(
            .clk(clk),.rst_n(rst_n),.in_valid(out_valid[c]),.in_ready(out_ready[c]),.in_data(out_data),
            .out_valid(rx_valid[c]),.out_ready(1'b1),.out_data(data),.empty(rx_empty[c]),.full());
        always @(posedge clk) begin
            if(!rst_n) count[c]<=0;
            else if(rx_valid[c]) begin
                if(count[c]>=words || data!==payload(count[c]))
                    $fatal(1,"receiver mismatch core=%0d index=%0d",c,count[c]);
                count[c]<=count[c]+1;
            end
        end
    end endgenerate
    always @(posedge clk) cycle<=cycle+1;
    initial begin
        for(size_index=0;size_index<3;size_index++) begin
            words=size_index==0 ? 64 : size_index==1 ? 512 : 2048;
            for(rate_index=0;rate_index<2;rate_index++) begin
                period=rate_index==0 ? 1 : 4;
                for(mode=0;mode<2;mode++) begin
                    @(negedge clk);rst_n=0;in_valid=0;
                    repeat(4) @(negedge clk);
                    rst_n=1;sent=0;start_cycle=cycle;
                    while(sent<(mode==0 ? 16*words : words)) begin
                        in_valid=((cycle-start_cycle)%period)==0;
                        in_data=payload(sent%words);
                        in_last=(sent%words)==words-1;
                        destinations=mode==0 ? (16'b1<<(sent/words)) : 16'hffff;
                        @(posedge clk);
                        if(in_valid && in_ready) sent++;
                        @(negedge clk);
                    end
                    in_valid=0;
                    received_total=0;
                    while(received_total!=16*words || !idle || !(&rx_empty)) begin
                        @(negedge clk);
                        received_total=0;
                        for(i=0;i<16;i++) received_total+=count[i];
                    end
                    elapsed=cycle-start_cycle;
                    $display("RESULT bytes=%0d period=%0d multicast=%0d cycles=%0d external_bytes=%0d received_words=%0d",words*8,period,mode,elapsed,sent*8,received_total);
                end
            end
        end
        $display("PASS TRANSPORT all_receivers_ordered_exactly_once");$finish;
    end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule
