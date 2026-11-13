`timescale 1ns/1ps
module tb_full_vgg_v8;
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
    vgg_sixteen_core_cluster #(.HEIGHT(32),.WIDTH(32),.V8_PACKED(1)) dut(.*);

    reg [63:0] weights[0:524287],gold[0:2047],inputs[0:383],config_words[0:15],status,got;
    reg [31:0] biases[0:511];
    reg [23:0] mult[0:511];
    reg [2:0] shifts[0:511];
    reg [2:0] vshifts[0:15];
    reg [3:0] expected_class[0:0];
    integer core,row,k,c,stage=0,i,groups,offset,checked=0,activation_writes=0,cycle=0;
    integer h,cin,kout,local_k,block_k,stride,pairs,oh,gold_words;
    integer weight_words=0,load_begin,load_cycles,requests,check_begin;
    integer total_preload=0,total_commands=0,total_check=0;
    bit stream_host;
    bit enable_resident_u, resident_u;
    string path;
    always @(posedge clk) begin
        cycle++;
        if(rst_n && host_valid && host_ready && host_write && host_bank>=8 && host_bank<12) begin
            if(stage!=0) $fatal(1,"Intermediate activation came from TB");
            activation_writes++;
        end
        if(cycle%100000==0) begin
            $display("PROGRESS stage=%0d clock=%0d U_words=%0d requests=%0d",stage,cycle,weight_words,requests);$fflush();
        end
    end
    task automatic store(input integer target,bank,address,input [63:0] value);
        // Consecutive requests may reuse the falling edge where store returned.
        // Baseline mode retains its one idle cycle between writes.
        if(!stream_host || clk!==1'b0) @(negedge clk);
        host_valid=1;host_write=1;host_core=4'(target);host_bank=4'(bank);host_addr=10'(address);host_wdata=value;
        do @(posedge clk);while(!host_ready);
        @(negedge clk);host_valid=0;
    endtask
    task automatic fetch(input integer target,bank,address,output [63:0] value);
        @(negedge clk);host_valid=1;host_write=0;host_core=4'(target);host_bank=4'(bank);host_addr=10'(address);
        do @(posedge clk);while(!host_ready);
        @(negedge clk);host_valid=0;
        wait(host_rvalid);value=host_rdata;
        @(negedge clk);host_rready=1;
        @(negedge clk);host_rready=0;
    endtask
    task automatic load_conv(input integer target,base_k,input bit reload);
        if(!reload || !resident_u)
        for(row=0;row<4;row++) for(k=0;k<(resident_u ? local_k : block_k);k++) for(c=0;c<pairs;c++) begin
            store(target,row,k*pairs+c,weights[row*kout*pairs+(target*local_k+base_k+k)*pairs+c]);
            weight_words++;
        end
        for(k=0;k<block_k;k++) begin
            if(reload) begin
                store(target,14,8+k,{32'b0,biases[target*local_k+base_k+k]});
                store(target,14,16+k,{40'b0,mult[target*local_k+base_k+k]});
                store(target,14,24+k,{61'b0,shifts[target*local_k+base_k+k]});
            end else begin
                cmd_biases[target*256+k*32+:32]=biases[target*local_k+k];
                cmd_multipliers[target*192+k*24+:24]=mult[target*local_k+k];
                cmd_u_shifts[target*24+k*3+:3]=shifts[target*local_k+k];
            end
        end
    endtask
    initial begin
        stream_host=$test$plusargs("STREAM_HOST");
        enable_resident_u=$test$plusargs("RESIDENT_U");
        $readmemh("verification/full_model/vectors_v8/vshift.hex",vshifts);
        $display("HOST_POLICY continuous=%0d",stream_host);$fflush();
        $readmemh("verification/full_model/vectors_v8/input.hex",inputs);
        $readmemh("verification/full_model/vectors_v8/config.hex",config_words);
        $readmemh("verification/full_model/vectors_v8/class.hex",expected_class);
        repeat(4) @(negedge clk);rst_n=1;
        for(i=0;i<384;i++) store(0,8,i,inputs[i]);
        for(stage=0;stage<16;stage++) begin
            h=int'((config_words[stage]>>48)&63);cin=int'((config_words[stage]>>32)&1023);
            kout=int'((config_words[stage]>>16)&65535);local_k=int'((config_words[stage]>>8)&255);
            block_k=int'((config_words[stage]>>1)&15);stride=cin>256 ? 512 : cin>128 ? 256 : 128;pairs=(cin+1)/2;
            cmd_fc=stage>=13;cmd_fc_final=stage==15;cmd_phase=1'(stage);cmd_sharded=stage!=0;
            cmd_channels=10'(cin);cmd_height=6'(h);cmd_width=6'(h);cmd_shard_channels=stage==0 ? 0 : 8'(cin/16);
            cmd_pooling=config_words[stage][0];cmd_input_signed=stage==0;
            cmd_outputs=4'(block_k);cmd_output_total=8'(local_k);cmd_output_offset=0;
            cmd_biases=0;cmd_multipliers=0;cmd_u_shifts=0;
            weight_words=0;requests=0;load_begin=cycle;
            resident_u=enable_resident_u && !cmd_fc && local_k*pairs<=1024;
            if(!cmd_fc) begin
                for(core=0;core<16;core++) store(core,14,4,64'd1);
                for(core=0;core<16;core++) begin store(core,14,2,64'(resident_u));store(core,14,3,64'(vshifts[stage]));end
                path=$sformatf("verification/full_model/vectors_v8/layer%0d/u.hex",stage);$readmemh(path,weights,0,4*kout*pairs-1);
                path=$sformatf("verification/full_model/vectors_v8/layer%0d/bias.hex",stage);$readmemh(path,biases,0,kout-1);
                path=$sformatf("verification/full_model/vectors_v8/layer%0d/mult.hex",stage);$readmemh(path,mult,0,kout-1);
                path=$sformatf("verification/full_model/vectors_v8/layer%0d/shift.hex",stage);$readmemh(path,shifts,0,kout-1);
                for(core=0;core<16;core++) load_conv(core,0,0);
            end else begin
                groups=cmd_fc_final ? 1 : 2;
                for(core=0;core<(cmd_fc_final ? 1 : 16);core++) begin
                    path=$sformatf("verification/full_model/vectors_v8/layer%0d/u%0d.hex",stage,core);$readmemh(path,weights,0,4095);
                    for(row=0;row<4;row++) begin
                        for(c=0;c<groups*256;c++) begin store(core,row,c,weights[row*1024+c]);weight_words++;end
                        for(c=0;c<groups*4;c++) store(core,row,512+c,weights[row*1024+512+c]);
                    end
                end
            end
            load_cycles=cycle-load_begin;total_preload+=load_cycles;
            $display("START layer=%0d input=[1,%0d,%0d,%0d] Cout=%0d U_block=%0d preload=%0d",stage,h,h,cin,kout,block_k,load_cycles);$fflush();
            @(negedge clk);cmd_valid=1;
            do @(posedge clk);while(!cmd_ready);
            @(negedge clk);cmd_valid=0;
            if(!cmd_fc && local_k>block_k) begin
                while(!done_valid) begin
                    for(core=0;core<16;core++) if(!dut.u_cluster.core_done[core]) begin
                        fetch(core,14,0,status);
                        if(status[0]) begin
                            if(status[40]!==resident_u) $fatal(1,"U residence status mismatch");
                            offset=int'(status[15:8]);load_conv(core,offset,1);store(core,14,1,status);requests++;
                        end
                    end
                    @(negedge clk);
                end
            end else wait(done_valid);
            if(done_error) $fatal(1,"Layer command failed stage=%0d",stage);
            if(stage==15 && (!class_valid || class_index!==expected_class[0])) $fatal(1,"Classifier mismatch got=%0d expected=%0d",class_index,expected_class[0]);
            total_commands+=int'(total_cycles);check_begin=cycle;
            oh=cmd_pooling ? h/2 : h;
            gold_words=cmd_fc_final ? 10 : (oh*oh*local_k+7)/8;
            for(core=0;core<(cmd_fc_final ? 1 : 16);core++) begin
                path=$sformatf("verification/full_model/vectors_v8/layer%0d/gold%0d.hex",stage,core);$readmemh(path,gold,0,gold_words-1);
                for(i=0;i<gold_words;i++) begin
                    fetch(core,cmd_phase ? 8 : 10,i,got);
                    if(got!==gold[i]) $fatal(1,"Layer mismatch stage=%0d core=%0d word=%0d got=%h expected=%h",stage,core,i,got,gold[i]);
                    checked++;
                end
            end
            total_check+=cycle-check_begin;
            $display("LAYER_PASS layer=%0d shape=[1,%0d,%0d,%0d]->%0d cycles=%0d preload=%0d U_words=%0d replacements=%0d source_reads=%0d compared_words=%0d resident_u=%0d",stage,h,h,cin,kout,total_cycles,load_cycles,weight_words,requests,source_reads,gold_words*(cmd_fc_final ? 1 : 16),resident_u);$fflush();
            @(negedge clk);done_ready=1;
            @(negedge clk);done_ready=0;wait(cmd_ready);
        end
        if(activation_writes!=384 || committed_regions!=0) $fatal(1,"Input traffic/final release mismatch");
        $display("PASS FULL_VGG layers=16 checked_words=%0d class=%0d activation_host_words=%0d command_cycles=%0d preload_cycles=%0d debug_read_cycles=%0d no_intermediate_reload",checked,class_index,activation_writes,total_commands,total_preload,total_check);$fflush();
        $finish;
    end
    initial begin #2000000000;$fatal(1,"Full VGG timeout stage=%0d",stage);end
endmodule
