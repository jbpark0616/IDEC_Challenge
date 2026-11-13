`timescale 1ps/1ps
module tb_v8_packed #(parameter integer PACKED=1, DENSE_U=1, TILE_INPUT=1);
    reg [23:0] u_shifts=0;
    reg clk=0, rst_n=0;
    always #715 clk=~clk;
    reg mem_valid=0, mem_write=0, mem_rready=0;
    wire mem_ready, mem_rvalid;
    reg [3:0] mem_bank=0;
    reg [9:0] mem_addr=0;
    reg [63:0] mem_wdata=0;
    wire [63:0] mem_rdata;
    reg start_valid=0, done_ready=0;
    wire start_ready, done_valid, done_error;
    reg [9:0] input_channels=0;
    reg [5:0] input_height=0, input_width=0;
    reg [3:0] output_channels=0;
    reg [7:0] total_output_channels=0;
    reg pooling=0, sparse_enable=0, input_signed=0;
    reg [255:0] biases=0;
    reg [191:0] multipliers=0;
    wire [31:0] active_cycles, mac_row_issues;
    wire [14:0] output_bytes;
    reg activation_valid=0;
    wire activation_ready;
    reg [63:0] activation_data=0;
    wire output_valid;
    reg output_ready_external=0;
    wire [10:0] output_address;
    wire [63:0] output_data;
    wire output_last;
    ppa_core dut (.fc_mode(1'b0), .fc_final(1'b0), .fc_class(), .*);

    reg [63:0] config_words[0:24], inputs[0:8191], gold[0:4095], u[0:65535], status;
    reg [31:0] bias_words[0:127];
    reg [2:0] shift_words[0:127];
    reg [23:0] multiplier_words[0:127];
    reg [2:0] vshifts[0:24];
    integer physical_writes=0;
    integer case_id, sparse, row, k, c, cycle=0;
    integer cin, kout, block_k, h, stride, input_words, expected_bytes, expected_words;
    integer sent=0, received=0, writes=0, transforms=0, releases=0, early=0, requests=0;
    integer offset, tile, expected_request, expected_tile, expected_offset;
    integer weight_writes=0, weight_wait_cycles=0, compared=0;
    reg running=0;
    string path;
    bit enable_resident, resident;
    // Independent HWC -> row-major padded tile stream for the SRAM boundary.
    function automatic [63:0] tile_word(input integer word_index);
        integer spatial,channel_index,pixel_index,yy,xx,byte_index,b;
        begin
            tile_word=0;
            if(cin>0 && h>=2) begin
                spatial=(word_index/2)/cin;
                channel_index=(word_index/2)%cin;
                for(b=0;b<8;b=b+1) begin
                    pixel_index=(word_index%2)*8+b;
                    yy=(spatial/(h/2))*2+pixel_index/4-1;
                    xx=(spatial%(h/2))*2+pixel_index%4-1;
                    if(yy>=0 && yy<h && xx>=0 && xx<h) begin
                        byte_index=(yy*h+xx)*cin+channel_index;
                        tile_word[b*8+:8]=inputs[byte_index/8][(byte_index%8)*8+:8];
                    end
                end
            end
        end
    endfunction
    always @(negedge clk) begin
        activation_valid=running && sent<input_words && 1'b1;
        activation_data=TILE_INPUT ? tile_word(sent) : inputs[sent];
        output_ready_external=running && 1'b1;
    end
    always @(posedge clk) begin
        cycle++;
        if(rst_n && running) begin
            if(activation_valid && activation_ready) sent++;
            if(output_valid && output_ready_external) begin
                if(received>=expected_words || output_address!==11'(received)
                    || output_data!==gold[received] || output_last!==(received==expected_words-1))
                    $fatal(1,"Replay mismatch case=%0d sparse=%0d word=%0d got=%h expected=%h",case_id,sparse,received,output_data,gold[received]);
                received++; compared++; if(received%32==0 || received==expected_words) $display("PROGRESS case=%0d sparse=%0d outputs=%0d/%0d time_ps=%0t",case_id,sparse,received,expected_words,$time);
            end
        end
    end
    task automatic store(input integer bank,address,input [63:0] data);
        @(negedge clk);mem_valid=1;mem_write=1;mem_bank=4'(bank);mem_addr=10'(address);mem_wdata=data;
        do @(posedge clk);while(!mem_ready);
        @(negedge clk);mem_valid=0;
    endtask
    task automatic fetch_status;
        @(negedge clk);mem_valid=1;mem_write=0;mem_bank=14;mem_addr=0;
        do @(posedge clk);while(!mem_ready);
        @(negedge clk);mem_valid=0;
        wait(mem_rvalid); status=mem_rdata;
        @(negedge clk);mem_rready=1;
        @(negedge clk);mem_rready=0;
    endtask
    task automatic load_block(input integer base_k, input bit reload);
        if(!reload || !resident)
        for(row=0;row<4;row++) for(k=0;k<(resident ? kout : block_k);k++) begin
            if (PACKED) begin
                for(c=0;c<(cin+1)/2;c++) begin
                    store(row,k*(DENSE_U ? (cin+1)/2 : stride/2)+c,u[row*kout*(stride/2)+(base_k+k)*(stride/2)+c]);
                    weight_writes++;
                end
            end else begin
                for(c=0;c<cin;c++) begin
                    store(row,k*(DENSE_U ? cin : stride)+c,u[row*kout*stride+(base_k+k)*stride+c]);
                    weight_writes++;
                end
            end
        end
        for(k=0;k<block_k;k++) begin
            if(reload) begin
                store(14,8+k,{32'b0,bias_words[base_k+k]});
                store(14,16+k,{40'b0,multiplier_words[base_k+k]});
                if(PACKED) store(14,24+k,{61'b0,shift_words[base_k+k]});
            end else begin
                u_shifts[k*3 +: 3]=shift_words[k];
                biases[k*32 +: 32]=bias_words[k];
                multipliers[k*24 +: 24]=multiplier_words[k];
            end
        end
    endtask
    integer selected_case=10, selected_sparse=0;
    time start_time, end_time;
    string trace_path;
    initial begin
        if (!$value$plusargs("CASE=%d",selected_case)) selected_case=10;
        if (!$value$plusargs("SPARSE=%d",selected_sparse)) selected_sparse=0;
        if (!$value$plusargs("TRACE=%s",trace_path)) trace_path="activity.vcd";
        $dumpfile(trace_path); $dumpvars(0,dut); $dumpoff;
        enable_resident=$test$plusargs("RESIDENT");
        $readmemh("@VECTORS@/vshift.hex",vshifts);
        $readmemh("@VECTORS@/config.hex",config_words);
        repeat(4) @(negedge clk);rst_n=1;
        for(case_id=selected_case;case_id<selected_case+1;case_id++) begin
            h=int'((config_words[case_id]>>40)&63);cin=int'((config_words[case_id]>>24)&1023);
            kout=int'((config_words[case_id]>>16)&255);block_k=int'((config_words[case_id]>>8)&15);
            input_signed=(case_id==12);pooling=config_words[case_id][0];stride=cin>256 ? 512 : cin>128 ? 256 : 128;
            input_words=(h*h*cin+7)/8;expected_bytes=h*h*kout/(pooling ? 4 : 1);expected_words=(expected_bytes+7)/8;
            path=$sformatf("@VECTORS@/case%0d/input.hex",case_id);$readmemh(path,inputs,0,input_words-1);
            if(TILE_INPUT) input_words=(h*h/4)*cin*2;
            path=$sformatf("@VECTORS@/case%0d/gold.hex",case_id);$readmemh(path,gold,0,expected_words-1);
            path=$sformatf("@VECTORS@/case%0d/u%0d.hex",case_id,PACKED ? 8 : 16);$readmemh(path,u,0,4*kout*stride/(PACKED ? 2 : 1)-1);
            path=$sformatf("@VECTORS@/case%0d/shift.hex",case_id);$readmemh(path,shift_words,0,kout-1);
            path=$sformatf("@VECTORS@/case%0d/bias.hex",case_id);$readmemh(path,bias_words,0,kout-1);
            path=$sformatf("@VECTORS@/case%0d/mult.hex",case_id);$readmemh(path,multiplier_words,0,kout-1);
            for(sparse=selected_sparse;sparse<selected_sparse+1;sparse++) begin
                input_height=6'(h);input_width=6'(h);input_channels=10'(cin);
                output_channels=4'(block_k);total_output_channels=8'(kout);sparse_enable=1'(sparse);
                resident=enable_resident && kout*(DENSE_U ? (cin+1)/2 : stride/2)<=1024;
                store(14,4,64'(DENSE_U));
                store(14,2,64'(enable_resident));
                store(14,3,64'(vshifts[case_id]));
                weight_writes=0;load_block(0,0);
                physical_writes=0;sent=0;received=0;writes=0;transforms=0;releases=0;requests=0;early=0;weight_wait_cycles=0;
                @(negedge clk);start_time=$time; $dumpon; start_valid=1;
                do @(posedge clk);while(!start_ready);
                // Use the same input/output stall phase for both residence modes.
                @(negedge clk);start_valid=0;running=1;cycle=0;
                while(!done_valid) begin
                    fetch_status();
                    if(status[0]) begin
                        if(status[40]!==resident) $fatal(1,"Resident mode mismatch");
                        tile=int'(status[24:16]);offset=int'(status[15:8]);
                        expected_request=requests+1;
                        expected_tile=expected_request/(kout/block_k);
                        expected_offset=(expected_request%(kout/block_k))*block_k;
                        if(tile!=expected_tile || offset!=expected_offset || status[35:32]!=block_k)
                            $fatal(1,"Wrong weight request sequence tile=%0d offset=%0d",tile,offset);
                        // A stale commit must not advance the consumer lease.



                        load_block(offset,1);
                        store(14,1,status);
                        requests++;
                    end
                end
                end_time=$time; $dumpoff;
                $display("PPA_WINDOW start_ps=%0t end_ps=%0t duration_ps=%0t",start_time,end_time,end_time-start_time);
                if(done_error || received!=expected_words || sent!=input_words || output_bytes!=expected_bytes
                   
                    || requests!=(resident && kout==block_k ? 0 : h*h/4*(kout/block_k)-1))
                    $fatal(1,"Replay completion/lifetime violation case=%0d writes=%0d transforms=%0d releases=%0d requests=%0d",case_id,writes,transforms,releases,requests);
                if(weight_writes != 4*kout*((cin+1)/2)*(resident ? 1 : h*h/4)) $fatal(1,"Wrong U traffic");

                $display("V8_STORAGE case=%0d shift=%0d physical_bank_writes=%0d",case_id,vshifts[case_id],physical_writes);
                if(case_id==5 && sparse && mac_row_issues!=0) $fatal(1,"All-zero rows issued");
                $display("U_LOADING case=%0d input=1,%0d,%0d,%0d local_K=%0d U_block=%0d sparse=%0d cycles=%0d transforms=%0d V_writes=%0d releases=%0d requests=%0d U_words=%0d weight_wait=%0d rows=%0d early=%0d",
                    case_id,h,h,cin,kout,block_k,sparse,active_cycles,transforms,writes,releases,requests,weight_writes,weight_wait_cycles,mac_row_issues,early);
                @(negedge clk);running=0;done_ready=1;
                @(negedge clk);done_ready=0;wait(start_ready);
            end
        end
        $display("PASS U_LOADING compared_words=%0d gate_outputs_match_integer_reference",compared);
        $finish;
    end
    initial begin #2000000000; $fatal(1,"Retained V timeout case=%0d",case_id); end
endmodule
