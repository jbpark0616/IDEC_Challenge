`timescale 1ns/1ps

module elastic_fifo_tb;
    localparam integer DATA_WIDTH = 16;
    localparam integer DEPTH = 3;

    reg clk;
    reg rst_n;
    reg in_valid;
    wire in_ready;
    reg [DATA_WIDTH-1:0] in_data;
    wire out_valid;
    reg out_ready;
    wire [DATA_WIDTH-1:0] out_data;
    wire full;
    wire empty;

    integer errors;
    integer index;

    elastic_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_data(in_data),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_data(out_data),
        .full(full),
        .empty(empty)
    );

    always #5 clk = ~clk;

    task push_word;
        input [DATA_WIDTH-1:0] value;
        begin
            @(negedge clk);
            while (!in_ready)
                @(negedge clk);
            in_data = value;
            in_valid = 1'b1;
            @(negedge clk);
            in_valid = 1'b0;
        end
    endtask

    task pop_word;
        input [DATA_WIDTH-1:0] expected;
        begin
            @(negedge clk);
            while (!out_valid)
                @(negedge clk);
            if (out_data !== expected) begin
                $display("FAIL FIFO expected=%h got=%h", expected, out_data);
                errors = errors + 1;
            end
            out_ready = 1'b1;
            @(negedge clk);
            out_ready = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        in_valid = 1'b0;
        in_data = 0;
        out_ready = 1'b0;
        errors = 0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        if (!empty || out_valid) begin
            $display("FAIL FIFO not empty after reset");
            errors = errors + 1;
        end

        // Fill a non-power-of-two depth to verify explicit pointer wrapping.
        push_word(16'h1111);
        push_word(16'h2222);
        push_word(16'h3333);
        if (!full || in_ready) begin
            $display("FAIL FIFO full signaling");
            errors = errors + 1;
        end

        pop_word(16'h1111);
        push_word(16'h4444);
        pop_word(16'h2222);
        pop_word(16'h3333);
        pop_word(16'h4444);

        if (!empty) begin
            $display("FAIL FIFO empty signaling");
            errors = errors + 1;
        end

        // Simultaneous pop/push while full must preserve throughput and order.
        push_word(16'ha001);
        push_word(16'ha002);
        push_word(16'ha003);
        @(negedge clk);
        if (!full || out_data !== 16'ha001) begin
            $display("FAIL FIFO setup before simultaneous transfer");
            errors = errors + 1;
        end
        in_data = 16'ha004;
        in_valid = 1'b1;
        out_ready = 1'b1;
        #1;
        if (!in_ready) begin
            $display("FAIL FIFO rejected push during same-cycle pop");
            errors = errors + 1;
        end
        @(negedge clk);
        in_valid = 1'b0;
        out_ready = 1'b0;
        pop_word(16'ha002);
        pop_word(16'ha003);
        pop_word(16'ha004);

        // Backpressure must hold the head stable.
        push_word(16'hbeef);
        repeat (3) begin
            @(negedge clk);
            if (!out_valid || out_data !== 16'hbeef) begin
                $display("FAIL FIFO head changed under backpressure");
                errors = errors + 1;
            end
        end
        pop_word(16'hbeef);

        if (errors == 0)
            $display("PASS elastic_fifo: all tests passed");
        else
            $display("FAIL elastic_fifo: %0d error(s)", errors);
        $finish;
    end

endmodule
