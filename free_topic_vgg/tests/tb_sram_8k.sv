`timescale 1ns/1ps
module tb_sram_8k;
    reg clk = 0;
    always #5 clk = ~clk;
    reg en = 0, rd_en = 0, wr_en = 0;
    reg [9:0] addr = 0;
    reg [63:0] wdata = 0;
    wire [63:0] rdata;
    reg [63:0] expected [0:1023];
    reg [63:0] held;
    integer i, n, a, checks = 0;
    reg [31:0] rng = 32'hc1fa0010;
    vgg_sram_8k dut (.*);

    task step(input bit active, input bit rd, input bit wr,
              input integer address, input [63:0] data);
        begin
            @(negedge clk);
            en = active; rd_en = rd; wr_en = wr; addr = address; wdata = data;
            #1;
            if (checks > 0 && rdata !== held) $fatal(1, "Output changed before clock");
            @(posedge clk); #1;
            if (active && wr) expected[address] = data;
            if (active && rd && !wr) begin
                if (rdata !== expected[address]) $fatal(1, "Read mismatch addr=%0d", address);
                held = rdata;
                checks = checks + 1;
            end else if (checks > 0 && rdata !== held) $fatal(1, "Output did not hold");
        end
    endtask

    initial begin
        // Full-address coverage catches depth/word-address errors.
        for (i = 0; i < 1024; i = i + 1)
            step(1, 0, 1, i, {32'habcde000 ^ i, 32'h12345678 + i});
        for (i = 1023; i >= 0; i = i - 1) step(1, 1, 0, i, 0);
        // Disabled write must not destroy contents; disabled read must hold.
        step(0, 0, 1, 0, 64'hbad);
        step(0, 1, 0, 0, 0);
        step(1, 1, 0, 0, 0);
        for (n = 0; n < 2000; n = n + 1) begin
            rng = {rng[30:0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
            a = rng[9:0];
            case (rng[12:10])
                0,1,2: step(1, 0, 1, a, {rng, ~rng});
                3,4,5: step(1, 1, 0, a, 0);
                6: step(0, 0, 1, a, 0);
                7: step(1, 0, 0, a, 0);
            endcase
        end
        for (i = 0; i < 1024; i = i + 1) step(1, 1, 0, i, 0);
        $display("PASS SRAM: 1024 words, %0d read checks, synchronous read/hold/disabled write", checks);
        $finish;
    end
    initial begin #100000; $fatal(1, "Timeout"); end
endmodule
