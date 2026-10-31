`timescale 1ns/1ps
module tb_fc_head;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    reg host_valid=0,host_write=0,host_rready=0;
    wire host_ready,host_rvalid;
    reg [3:0] host_core=0,host_bank=0;
    reg [9:0] host_addr=0;
    reg [63:0] host_wdata=0;
    wire [63:0] host_rdata;
    reg cmd_valid=0,cmd_phase=0,cmd_sharded=0,cmd_fc=0,cmd_fc_final=0;
    wire cmd_ready,class_valid;
    wire [3:0] class_index;
    reg [5:0] cmd_height=2,cmd_width=2;
    reg [10:0] cmd_input_base=0,cmd_output_base=0;
    reg [9:0] cmd_channels=3;
    reg [7:0] cmd_shard_channels=0,cmd_output_total=32,cmd_output_offset=0;
    reg [3:0] cmd_outputs=8;
    reg cmd_pooling=1,cmd_sparse=1,cmd_input_signed=0;
    reg [4095:0] cmd_biases=0;
    reg [3071:0] cmd_multipliers=0;
    reg [383:0] cmd_u_shifts=0;
    wire done_valid,done_error;
    reg done_ready=0;
    wire [31:0] total_cycles,source_reads,stream_words;
    wire [511:0] core_cycles,mac_row_issues;
    wire [239:0] output_bytes;
    wire [1:0] committed_regions;
    vgg_sixteen_core_cluster #(.HEIGHT(2),.WIDTH(2)) dut(.*);
    reg [63:0] weights[0:8191],gold[0:9],inputs[0:1],status,got;
    reg [31:0] biases[0:31];
    reg [23:0] mult[0:31];
    reg [3:0] expected_class[0:0];
    integer core,row,k,c,stage,i,groups,offset,checked=0,activation_writes=0,cycle=0;
    integer weight_words=0,load_begin,load_cycles;
    string path;
    always @(posedge clk) begin
        cycle++;
        if(rst_n && host_valid && host_ready && host_write && host_bank>=8 && host_bank<12) begin
            if(stage!=0) $fatal(1,"Intermediate activation came from external TB");
            activation_writes++;
        end
    end
    task automatic store(input integer target,bank,address,input [63:0] value);
        @(negedge clk);host_valid=1;host_write=1;host_core=4'(target);host_bank=4'(bank);host_addr=10'(address);host_wdata=value;
        do @(posedge clk);while(!host_ready);
        @(negedge clk);host_valid=0;
    endtask
    task automatic fetch(input integer target,bank,address,output [63:0] value);
        @(negedge clk);host_valid=1;host_write=0;host_core=4'(target);host_bank=4'(bank);host_addr=10'(address);
        do @(posedge clk);while(!host_ready);
        @(negedge clk);host_valid=0;
        wait(host_rvalid);value=host_rdata;
        repeat(2) @(negedge clk);
        if(!host_rvalid || host_rdata!==value) $fatal(1,"Host response changed while stalled");
        host_rready=1;@(negedge clk);host_rready=0;
    endtask
    task automatic load_conv(input integer target,base_k,input bit reload);
        path=$sformatf("verification/fc/vectors/conv/core%0d/u.hex",target);$readmemh(path,weights,0,8191);
        path=$sformatf("verification/fc/vectors/conv/core%0d/bias.hex",target);$readmemh(path,biases);
        path=$sformatf("verification/fc/vectors/conv/core%0d/mult.hex",target);$readmemh(path,mult);
        for(row=0;row<4;row++) for(k=0;k<8;k++) for(c=0;c<2;c++)
            store(target,row,k*64+c,weights[row*32*64+(base_k+k)*64+c]);
        for(k=0;k<8;k++) begin
            if(reload) begin
                store(target,14,8+k,{32'b0,biases[base_k+k]});
                store(target,14,16+k,{40'b0,mult[base_k+k]});
                store(target,14,24+k,0);
            end else begin
                cmd_biases[target*256+k*32+:32]=biases[k];
                cmd_multipliers[target*192+k*24+:24]=mult[k];
            end
        end
    endtask
    task automatic command;
        @(negedge clk);cmd_valid=1;
        do @(posedge clk);while(!cmd_ready);
        @(negedge clk);cmd_valid=0;
    endtask
    task automatic acknowledge;
        @(negedge clk);done_ready=1;
        @(negedge clk);done_ready=0;wait(cmd_ready);
    endtask
    initial begin
        stage=0;
        $readmemh("verification/fc/vectors/input.hex",inputs);
        $readmemh("verification/fc/vectors/class.hex",expected_class);
        repeat(4) @(negedge clk);rst_n=1;
        for(i=0;i<2;i++) store(0,8,i,inputs[i]);
        for(core=0;core<16;core++) load_conv(core,0,0);
        command();
        while(!done_valid) begin
            for(core=0;core<16;core++) if(!dut.u_cluster.core_done[core]) begin
                fetch(core,14,0,status);
                if(status[0]) begin
                    offset=int'(status[15:8]);load_conv(core,offset,1);store(core,14,1,status);
                end
            end
            @(negedge clk);
        end
        if(done_error) $fatal(1,"Conv command failed");
        for(core=0;core<16;core++) begin
            path=$sformatf("verification/fc/vectors/conv/core%0d/gold.hex",core);$readmemh(path,gold,0,3);
            for(i=0;i<4;i++) begin fetch(core,10,i,got);if(got!==gold[i]) $fatal(1,"Conv->FC input mismatch");checked++;end
        end
        $display("FC_HEAD Conv source=[1,2,2,3] output=[1,1,1,512] cycles=%0d",total_cycles);
        acknowledge();
        for(stage=1;stage<=3;stage++) begin
            weight_words=0;load_begin=cycle;
            groups=stage==3 ? 1 : 2;
            for(core=0;core<(stage==3 ? 1 : 16);core++) begin
                path=$sformatf("verification/fc/vectors/fc%0d/core%0d/u.hex",stage-1,core);$readmemh(path,weights,0,4095);
                for(row=0;row<4;row++) begin
                    for(c=0;c<groups*256;c++) begin store(core,row,c,weights[row*1024+c]);weight_words++;end
                    for(c=0;c<groups*4;c++) store(core,row,512+c,weights[row*1024+512+c]);
                end
            end
            load_cycles=cycle-load_begin;
            cmd_fc=1;cmd_fc_final=stage==3;cmd_phase=1'(stage);cmd_sharded=1;
            cmd_channels=512;cmd_height=1;cmd_width=1;cmd_shard_channels=32;cmd_pooling=0;
            command();wait(done_valid);
            if(done_error || committed_regions!==(2'b1<<(!cmd_phase))) $fatal(1,"FC command/region failure stage=%0d",stage);
            if(stage==3 && (!class_valid || class_index!==expected_class[0])) $fatal(1,"Argmax mismatch got=%0d expected=%0d",class_index,expected_class[0]);
            for(core=0;core<(stage==3 ? 1 : 16);core++) begin
                if(mac_row_issues[core*32+:32]!=(stage==3 ? 512 : 1024)) $fatal(1,"Wrong FC reduction count");
                path=$sformatf("verification/fc/vectors/fc%0d/core%0d/gold.hex",stage-1,core);$readmemh(path,gold,0,(stage==3 ? 10 : 4)-1);
                for(i=0;i<(stage==3 ? 10 : 4);i++) begin
                    fetch(core,cmd_phase ? 8 : 10,i,got);
                    if(got!==gold[i]) $fatal(1,"FC mismatch stage=%0d core=%0d word=%0d got=%h expected=%h",stage,core,i,got,gold[i]);checked++;
                end
            end
            $display("FC_HEAD FC%0d shape=512->%0d active_cores=%0d compute_and_feed=%0d preload=%0d U_words=%0d source_reads=%0d core0_cycles=%0d",stage,stage==3 ? 10 : 512,stage==3 ? 1 : 16,total_cycles,load_cycles,weight_words,source_reads,core_cycles[31:0]);
            acknowledge();
        end
        if(activation_writes!=2) $fatal(1,"Unexpected activation traffic");
        if(committed_regions!=0) $fatal(1,"Final acknowledgement did not release A/B leases");
        // Reject an unsupported FC length without corrupting memory ownership.
        cmd_channels=511;command();wait(done_valid);
        if(!done_error || class_valid || committed_regions!=0) $fatal(1,"Bad FC command accepted");
        acknowledge();
        // Return from FC to Conv on the SAME MAC and memories, without reset.
        stage=0;cmd_fc=0;cmd_fc_final=0;cmd_phase=0;cmd_sharded=0;
        cmd_height=2;cmd_width=2;cmd_channels=3;cmd_outputs=1;cmd_output_total=1;cmd_pooling=1;
        cmd_biases=0;cmd_multipliers=0;
        for(i=0;i<2;i++) store(0,8,i,inputs[i]);
        for(core=0;core<16;core++) begin
            for(row=0;row<4;row++) for(c=0;c<2;c++) store(core,row,c,0);
            cmd_biases[core*256+:32]=14;cmd_multipliers[core*192+:24]=8388608;
        end
        command();wait(done_valid);
        if(done_error || class_valid) $fatal(1,"FC to Conv mode transition failed");
        for(core=0;core<16;core++) begin
            fetch(core,10,0,got);
            if(got!==64'd7) $fatal(1,"FC to Conv result mismatch");
        end
        acknowledge();
        $display("PASS FC_HEAD Conv_FC1_FC2_FC3 checked_words=%0d class=%0d initial_activation_words=%0d no_intermediate_TB_reload",checked,class_index,activation_writes);
        $display("PASS FC_MODE_RETURN rejected_bad_length released_final_region FC_to_Conv_without_reset cores=16");
        $finish;
    end
    initial begin #100000000; $fatal(1,"FC head timeout stage=%0d",stage);end
endmodule
