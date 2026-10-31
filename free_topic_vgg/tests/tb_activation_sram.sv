`timescale 1ns/1ps
module tb_activation_sram;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0;
    reg host_valid=0, host_write=0, host_rready=0;
    wire host_ready, host_rvalid;
    reg [1:0] host_bank=0;
    reg [9:0] host_addr=0;
    reg [63:0] host_wdata=0;
    wire [63:0] host_rdata;
    reg tx_valid=0, tx_rready=0;
    wire tx_ready, tx_rvalid;
    reg [1:0] tx_bank=0;
    reg [9:0] tx_addr=0;
    wire [63:0] tx_rdata;
    reg writer_valid=0;
    wire writer_ready;
    reg [1:0] writer_bank=0;
    reg [9:0] writer_addr=0;
    reg [63:0] writer_data=0;
    integer checks=0, rounds=0, h_grants=0, t_grants=0, w_grants=0;
    reg [63:0] held;
    vgg_activation_sram dut (.*);

    genvar g;
    generate for(g=0;g<4;g=g+1) begin : assertions
        always @(posedge clk) if(rst_n) begin
            if(dut.g_bank[g].rd_en && dut.g_bank[g].wr_en)
                $fatal(1,"1RW violation");
            if(!$onehot0(dut.g_bank[g].grant)) $fatal(1,"Multiple bank grants");
        end
    end endgenerate

    task automatic write_word(input integer bank, address, input [63:0] value);
        begin
            @(negedge clk);
            host_valid=1; host_write=1; host_bank=2'(bank);
            host_addr=10'(address); host_wdata=value;
            do @(posedge clk); while(!host_ready);
            @(negedge clk); host_valid=0;
        end
    endtask
    task automatic host_read(input integer bank, address);
        begin
            @(negedge clk);
            host_valid=1; host_write=0; host_bank=2'(bank); host_addr=10'(address);
            do @(posedge clk); while(!host_ready);
            @(negedge clk); host_valid=0;
            if(!host_rvalid) $fatal(1,"Missing synchronous host response");
        end
    endtask
    task automatic tx_read(input integer bank, address);
        begin
            @(negedge clk);
            tx_valid=1; tx_bank=2'(bank); tx_addr=10'(address);
            do @(posedge clk); while(!tx_ready);
            @(negedge clk); tx_valid=0;
            if(!tx_rvalid) $fatal(1,"Missing synchronous TX response");
        end
    endtask
    task automatic consume;
        begin
            @(negedge clk); host_rready=1; tx_rready=1;
            @(negedge clk); host_rready=0; tx_rready=0;
        end
    endtask

    initial begin
        repeat(3) @(negedge clk);
        rst_n=1;
        for(integer b=0;b<4;b=b+1) begin
            write_word(b,0,64'h1000+b);
            write_word(b,1,64'h2000+b);
        end

        // A held HOST response forbids a TX read to that same bank; a write
        // remains legal because the physical macro retains its read output.
        for(integer b=0;b<4;b=b+1) begin
            host_read(b,0);
            held=64'h1000+b;
            if(host_rdata!==held) $fatal(1,"Host value mismatch");
            tx_valid=1; tx_bank=2'(b); tx_addr=1;
            writer_valid=1; writer_bank=2'(b); writer_addr=2; writer_data=64'hface;
            repeat(8) begin
                @(posedge clk);
                if(tx_ready || !writer_ready || host_rdata!==held || !host_rvalid)
                    $fatal(1,"Held host response corrupted/locked writes");
                checks=checks+1;
            end
            @(negedge clk); host_rready=1; writer_valid=0;
            @(posedge clk);
            if(!tx_ready) $fatal(1,"Read not admitted on response consumption");
            @(negedge clk); tx_valid=0; host_rready=0;
            if(!tx_rvalid || tx_rdata!==(64'h2000+b)) $fatal(1,"TX wrong after release");
            consume();

            // Reverse ownership: held TX must also protect against HOST reads.
            tx_read(b,0);
            host_valid=1; host_write=0; host_bank=2'(b); host_addr=1;
            repeat(8) begin
                @(posedge clk);
                if(host_ready || tx_rdata!==held || !tx_rvalid) $fatal(1,"Held TX overwritten");
                checks=checks+1;
            end
            @(negedge clk); tx_rready=1;
            @(posedge clk);
            if(!host_ready) $fatal(1,"Host blocked after TX release");
            @(negedge clk); host_valid=0; tx_rready=0;
            if(!host_rvalid || host_rdata!==(64'h2000+b)) $fatal(1,"Host wrong after release");
            consume();
        end

        // A stalled read in one bank must not block another bank's read.
        host_read(0,0);
        tx_read(1,1);
        if(host_rdata!==64'h1000 || tx_rdata!==64'h2001) $fatal(1,"Independent banks failed");
        consume();

        // Three persistent clients on one bank must each win once per round.
        @(negedge clk);
        host_valid=1; host_write=0; host_bank=2; host_addr=0; host_rready=1;
        tx_valid=1; tx_bank=2; tx_addr=1; tx_rready=1;
        writer_valid=1; writer_bank=2; writer_addr=3; writer_data=64'h1234;
        repeat(60) begin
            @(posedge clk);
            if(host_ready) h_grants=h_grants+1;
            if(tx_ready) t_grants=t_grants+1;
            if(writer_ready) w_grants=w_grants+1;
            if(host_rvalid && host_rdata!==64'h1002) $fatal(1,"Round robin host mismatch");
            if(tx_rvalid && tx_rdata!==64'h2002) $fatal(1,"Round robin TX mismatch");
            rounds=rounds+1;
        end
        @(negedge clk); host_valid=0; tx_valid=0; writer_valid=0;
        if(h_grants!=20 || t_grants!=20 || w_grants!=20) $fatal(1,"Starvation / unfair arbitration");
        consume();

        // Reset cancels outstanding control state without clearing stored data.
        host_read(3,0);
        @(negedge clk); rst_n=0;
        @(negedge clk);
        if(host_rvalid || tx_rvalid) $fatal(1,"Reset failed to cancel response");
        rst_n=1;
        host_read(3,0);
        if(host_rdata!==64'h1003) $fatal(1,"Reset cleared SRAM payload");
        consume();
        $display("PASS activation_sram held_response_checks=%0d fair_grants=%0d/%0d/%0d independent_banks/reset/1RW",
                 checks,h_grants,t_grants,w_grants);
        $finish;
    end
    initial begin #100000; $fatal(1,"Timeout"); end
endmodule
