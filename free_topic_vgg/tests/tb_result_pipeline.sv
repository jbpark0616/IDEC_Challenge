`timescale 1ns/1ps
module tb_result_pipeline #(parameter integer POOL=0);
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,start=0,in_valid=0,in_zero=0,in_last=0;
    wire in_ready,word_valid,word_last,byte_accepted;
    reg word_ready=0;
    reg [767:0] in_m=0;
    reg [2:0] in_channel=0;
    reg [255:0] biases=0;
    reg [191:0] multipliers=0;
    wire [63:0] word_data;
    integer cycle=0,received=0,accepted=0,blocked=0,before_first=0,checks=0;
    integer frame,job,b;
    localparam JOBS=19, BYTES=JOBS*(POOL?1:4);
    reg held=0;
    reg [64:0] held_word;
    vgg_result_pipeline dut (
        .clk(clk),.rst_n(rst_n),.start(start),.pooling(1'(POOL)),
        .biases(biases),.multipliers(multipliers),
        .in_valid(in_valid),.in_ready(in_ready),.in_m(in_m),
        .in_zero(in_zero),.in_last(in_last),.in_channel(in_channel),
        .word_valid(word_valid),.word_ready(word_ready),.word_data(word_data),
        .word_last(word_last),.byte_accepted(byte_accepted)
    );
    function automatic [7:0] expected(input integer index,epoch);
        integer j,p,value,bias;
        begin
            j=index/(POOL?1:4);p=index%4;
            bias=j%3==0 ? -7 : (j%3==1 ? 3 : 20);
            value=(j%3==1 || (!POOL && p!=0)) ? 0 : 40+j*4+epoch*8;
            value=value+bias;
            expected=index>=BYTES || value<0 ? 0 : (value+2)/4;
        end
    endfunction
    always @(negedge clk)
        word_ready=cycle>200 && cycle%9!=3 && cycle%9!=4;
    always @(posedge clk) begin
        if(!rst_n || start) begin
            cycle=0;received=0;accepted=0;blocked=0;before_first=0;held=0;
        end else begin
            cycle++;
            if(in_valid && !in_ready) blocked++;
            if(in_valid && in_ready) begin
                accepted++;
                if(received==0) before_first++;
            end
            if(held && (!word_valid || {word_last,word_data}!==held_word))
                $fatal(1,"Output changed under backpressure");
            if(word_valid && word_ready) begin
                for(b=0;b<8;b++) begin
                    if(word_data[b*8+:8]!==expected(received+b,frame))
                        $fatal(1,"Order/bias/pixel/padding mismatch index=%0d actual=%0d expected=%0d",received+b,word_data[b*8+:8],expected(received+b,frame));
                    checks++;
                end
                if(word_last !== (received+8>=BYTES)) $fatal(1,"Last tag mismatch");
                received=received+8;
            end
            held=word_valid && !word_ready;
            held_word={word_last,word_data};
        end
    end
    initial begin
        biases[0+:32]=-7;biases[32+:32]=3;biases[64+:32]=20;
        for(b=0;b<8;b++) multipliers[b*24+:24]=24'h400000;
        repeat(4) @(negedge clk);rst_n=1;
        // Abort with complete results already in the downstream pipeline.
        // This exercises reset beyond the layer test's producer-only abort.
        frame=0;
        @(negedge clk);start=1;
        @(negedge clk);start=0;
        for(job=0;job<4;job++) begin
            @(negedge clk);in_valid=1;in_channel=job%3;in_last=0;
            in_zero=job%3==1;in_m=0;in_m[0+:48]=40+job*4;
            do @(posedge clk);while(!in_ready);
            @(negedge clk);in_valid=0;
        end
        repeat(5) @(negedge clk);
        if(!word_valid && !dut.order_valid && !dut.normal_valid && !dut.post_valid)
            $fatal(1,"Reset did not cover an occupied pipeline");
        rst_n=0;repeat(3) @(negedge clk);rst_n=1;
        if(word_valid) $fatal(1,"Reset leaked output validity");
        for(frame=0;frame<2;frame++) begin
            @(negedge clk);start=1;
            @(negedge clk);start=0;
            for(job=0;job<JOBS;job++) begin
                @(negedge clk);in_valid=1;in_channel=job%3;in_last=job==JOBS-1;
                in_zero=job%3==1;in_m=0;in_m[0+:48]=40+job*4+frame*8;
                do @(posedge clk);while(!in_ready);
                @(negedge clk);in_valid=0;
            end
            wait(received>=BYTES);
            @(negedge clk);
            if(accepted!=JOBS || blocked==0 || before_first<2) $fatal(1,"Missing pipeline/backpressure coverage");
            repeat(6) @(negedge clk);
            if(word_valid) $fatal(1,"Extra output word");
        end
        $display("PASS result pipeline pool=%0d checks=%0d; mixed bypass/normal, bias tags, stalled words, partial word, restart, overlapped jobs",POOL,checks);
        $finish;
    end
    initial begin #1000000; $fatal(1,"Watchdog");end
endmodule
