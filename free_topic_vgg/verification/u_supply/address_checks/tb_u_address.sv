`timescale 1ns/1ps
module tb_u_address #(parameter integer PACKED=1, DENSE_U=1);
    reg [23:0] u_shifts=0;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;
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
    vgg_sram_conv_layer #(.HEIGHT(4),.WIDTH(4),.RUNTIME_SHAPE(1),
        .EXTERNAL_ACTIVATION(1),.CHANNEL_BITS(9),.RETAIN_V(1),.U8_PACKED(PACKED),.V8_PACKED(1),.ENABLE_FC(1)) dut (.fc_mode(1'b0), .fc_final(1'b0), .fc_class(), .*);

    reg [63:0] config_words[0:3], inputs[0:1023], gold[0:255], u[0:65535], status;
    reg [31:0] bias_words[0:127];
    reg [2:0] shift_words[0:127];
    reg [23:0] multiplier_words[0:127];
    reg [2:0] vshifts[0:3];
    integer physical_writes=0;
    integer case_id, sparse, row, k, c, cycle=0;
    integer cin, kout, block_k, h, stride, input_words, expected_bytes, expected_words;
    integer sent=0, received=0, writes=0, transforms=0, releases=0, early=0, requests=0;
    integer offset, tile, expected_request, expected_tile, expected_offset;
    integer weight_writes=0, weight_wait_cycles=0, compared=0;
    reg running=0;
    string path;
    bit enable_resident, resident;
    always @(negedge clk) begin
        activation_valid=running && sent<input_words && cycle%7!=0;
        activation_data=inputs[sent];
        output_ready_external=running && cycle%13<9;
    end
    always @(posedge clk) begin
        cycle++;
        if(rst_n && running) begin
            if(activation_valid && activation_ready) sent++;
            physical_writes += $countones(dut.u_core.u_scratchpad.p_fire);
            if(dut.weights_waiting) weight_wait_cycles++;
            if(dut.it_valid && dut.producer_state==dut.P_TRANSFORM) transforms++;
            if(dut.producer_write_fire) writes++;
            if(dut.u_core.row_accept && (|dut.u_core.row_read)
                && dut.u_core.engine_available<cin) early++;
            if(dut.cb_release) begin
                if(!dut.release_ready || !dut.last_reuse || dut.output_base+block_k!=kout)
                    $fatal(1,"V released before last K use");
                releases++;
            end
            if(output_valid && output_ready_external) begin
                if(received>=expected_words || output_address!==11'(received)
                    || output_data!==gold[received] || output_last!==(received==expected_words-1))
                    $fatal(1,"Replay mismatch case=%0d sparse=%0d word=%0d got=%h expected=%h",case_id,sparse,received,output_data,gold[received]);
                received++; compared++;
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
    initial begin
        enable_resident=$test$plusargs("RESIDENT");
        $readmemh("verification/u_supply/address_checks/vectors/vshift.hex",vshifts);
        $readmemh("verification/u_supply/address_checks/vectors/config.hex",config_words);
        repeat(4) @(negedge clk);rst_n=1;
        for(case_id=0;case_id<4;case_id++) begin
            h=int'((config_words[case_id]>>40)&63);cin=int'((config_words[case_id]>>24)&1023);
            kout=int'((config_words[case_id]>>16)&255);block_k=int'((config_words[case_id]>>8)&15);
            pooling=config_words[case_id][0];stride=cin>256 ? 512 : cin>128 ? 256 : 128;
            input_words=(h*h*cin+7)/8;expected_bytes=h*h*kout/(pooling ? 4 : 1);expected_words=(expected_bytes+7)/8;
            path=$sformatf("verification/u_supply/address_checks/vectors/case%0d/input.hex",case_id);$readmemh(path,inputs,0,input_words-1);
            path=$sformatf("verification/u_supply/address_checks/vectors/case%0d/gold.hex",case_id);$readmemh(path,gold,0,expected_words-1);
            path=$sformatf("verification/u_supply/address_checks/vectors/case%0d/u%0d.hex",case_id,PACKED ? 8 : 16);$readmemh(path,u,0,4*kout*stride/(PACKED ? 2 : 1)-1);
            path=$sformatf("verification/u_supply/address_checks/vectors/case%0d/shift.hex",case_id);$readmemh(path,shift_words,0,kout-1);
            path=$sformatf("verification/u_supply/address_checks/vectors/case%0d/bias.hex",case_id);$readmemh(path,bias_words,0,kout-1);
            path=$sformatf("verification/u_supply/address_checks/vectors/case%0d/mult.hex",case_id);$readmemh(path,multiplier_words,0,kout-1);
            for(sparse=0;sparse<2;sparse++) begin
                input_height=6'(h);input_width=6'(h);input_channels=10'(cin);
                output_channels=4'(block_k);total_output_channels=8'(kout);sparse_enable=1'(sparse);
                resident=enable_resident && kout*(DENSE_U ? (cin+1)/2 : stride/2)<=1024;
                store(14,4,64'(DENSE_U));
                store(14,2,64'(enable_resident));
                store(14,3,64'(vshifts[case_id]));
                weight_writes=0;load_block(0,0);
                physical_writes=0;sent=0;received=0;writes=0;transforms=0;releases=0;requests=0;early=0;weight_wait_cycles=0;
                @(negedge clk);start_valid=1;
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
                        store(14,1,status ^ 64'h10000);
                        if(dut.consumer_state!=dut.C_WEIGHTS) $fatal(1,"Stale weight commit accepted");
                        repeat(5) @(negedge clk);
                        load_block(offset,1);
                        store(14,1,status);
                        requests++;
                    end
                end
                if(done_error || received!=expected_words || sent!=input_words || output_bytes!=expected_bytes
                    || writes!=h*h/4*cin || transforms!=writes || releases!=h*h/4
                    || requests!=h*h/4*(kout/block_k)-1 || dut.cb_occupancy!=0)
                    $fatal(1,"Replay completion/lifetime violation case=%0d writes=%0d transforms=%0d releases=%0d requests=%0d",case_id,writes,transforms,releases,requests);
                if(weight_writes != 4*kout*((cin+1)/2)*(resident ? 1 : h*h/4)) $fatal(1,"Wrong U traffic");
                if(physical_writes != h*h*((cin+1)/2)) $fatal(1,"V packing writes got=%0d expected=%0d",physical_writes,h*h*((cin+1)/2));
                $display("V8_STORAGE case=%0d shift=%0d physical_bank_writes=%0d",case_id,vshifts[case_id],physical_writes);
                if(case_id==5 && sparse && mac_row_issues!=0) $fatal(1,"All-zero rows issued");
                $display("U_LOADING case=%0d input=1,%0d,%0d,%0d local_K=%0d U_block=%0d sparse=%0d cycles=%0d transforms=%0d V_writes=%0d releases=%0d requests=%0d U_words=%0d weight_wait=%0d rows=%0d early=%0d",
                    case_id,h,h,cin,kout,block_k,sparse,active_cycles,transforms,writes,releases,requests,weight_writes,weight_wait_cycles,mac_row_issues,early);
                @(negedge clk);running=0;done_ready=1;
                @(negedge clk);done_ready=0;wait(start_ready);
            end
        end
        $display("PASS U_LOADING compared_words=%0d last_use_release backpressure zero_bypass stale_commit",compared);
        $finish;
    end
    initial begin #100000000; $fatal(1,"Retained V timeout case=%0d",case_id); end
endmodule
