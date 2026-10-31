`timescale 1ns/1ps
module tb_fanout16;
    localparam WORDS=192;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;
    reg in_valid=0;
    wire in_ready, idle;
    reg [63:0] in_data=0;
    reg [7:0] in_keep=0;
    reg in_last=0;
    reg [15:0] in_destinations=0, out_ready=0;
    wire [15:0] out_valid;
    wire [63:0] out_data;
    wire [7:0] out_keep;
    wire out_last;
    vgg_mcast_fanout #(.CORES(16), .DEPTH(4)) dut (.*);

    function automatic [15:0] destinations(input integer word_id);
        case(word_id%5)
            0: destinations=16'hffff;
            1: destinations=16'h0001<<(word_id%16);
            2: destinations=16'ha55a;
            3: destinations=16'h8001;
            default: destinations=16'h0000;
        endcase
    endfunction
    function automatic [63:0] payload(input integer word_id);
        payload=64'h3579bdf024680000 | 64'(word_id);
    endfunction
    integer sent=0, cycle=0, checked=0, c;
    integer next_word[0:15];
    reg [15:0] mask;
    always @(negedge clk) if(rst_n) begin
        in_valid=sent<WORDS && cycle%7!=0;
        in_data=payload(sent);
        in_destinations=destinations(sent);
        in_keep=8'hff>>(sent%8);
        in_last=sent%11==0;
        for(integer r=0;r<16;r=r+1)
            out_ready[r]=(cycle%(r+3)!=0) && (cycle%29<r+6);
    end
    always @(posedge clk) if(rst_n) begin
        cycle=cycle+1;
        if(in_valid && in_ready) sent=sent+1;
        for(c=0;c<16;c=c+1) if(out_valid[c] && out_ready[c]) begin
            mask=destinations(next_word[c]);
            while(next_word[c]<WORDS && !mask[c]) begin
                next_word[c]=next_word[c]+1;
                mask=destinations(next_word[c]);
            end
            if(next_word[c]>=WORDS || out_data!==payload(next_word[c])
               || out_keep!==(8'hff>>(next_word[c]%8)) || out_last!==(next_word[c]%11==0))
                $fatal(1,"Fanout corruption/duplication core=%0d next=%0d data=%h",c,next_word[c],out_data);
            next_word[c]=next_word[c]+1;
            checked=checked+1;
        end
        if(sent==WORDS && idle) begin
            for(c=0;c<16;c=c+1) begin
                mask=destinations(next_word[c]);
                while(next_word[c]<WORDS && !mask[c]) begin
                    next_word[c]=next_word[c]+1;
                    mask=destinations(next_word[c]);
                end
                if(next_word[c]!=WORDS) $fatal(1,"Missing endpoint word core=%0d",c);
            end
            $display("PASS FANOUT16 words=%0d endpoint_deliveries=%0d independent_stalls subset_masks empty_masks",WORDS,checked);
            $finish;
        end
        if(cycle>20000) $fatal(1,"Fanout timeout");
    end
    initial begin
        for(c=0;c<16;c=c+1) next_word[c]=0;
        repeat(4) @(negedge clk);
        rst_n=1;
    end
endmodule
