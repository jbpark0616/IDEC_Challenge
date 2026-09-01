`timescale 1ns/1ps

module winograd_postprocess_tb;
    localparam integer ACC_BITS = 18;
    localparam integer ACC_MAX = 131071;
    localparam integer ACC_MIN = -131072;
    localparam integer CONV1_MULT = 1616163;
    localparam integer CONV2_MULT = 1827841;

    reg clk;
    reg rst_n;
    reg in_valid;
    wire in_ready;
    reg [4*ACC_BITS-1:0] y_tile;
    reg signed [15:0] bias;
    reg [23:0] requant_multiplier;
    wire out_valid;
    reg out_ready;
    wire [7:0] activation;
    wire [1:0] out_user;

    integer y_value [0:3];
    integer expected;
    integer burst_expected [0:5];
    integer element;
    integer test_index;
    integer burst_drive;
    integer burst_receive;
    integer errors;
    integer biased;
    integer pooled;
    reg [63:0] wide_result;
    reg [7:0] held_result;

    winograd_postprocess dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .y_tile(y_tile),
        .bias(bias),
        .requant_multiplier(requant_multiplier),
        .in_user(2'b00),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .activation(activation),
        .out_user(out_user)
    );

    always #5 clk = ~clk;

    function integer sat18;
        input integer value;
        begin
            if (value > ACC_MAX)
                sat18 = ACC_MAX;
            else if (value < ACC_MIN)
                sat18 = ACC_MIN;
            else
                sat18 = value;
        end
    endfunction

    // Golden follows the original Python order, deliberately not the fused
    // RTL order: bias/saturate each value, ReLU, then max-pool and requantize.
    task calculate_golden;
        begin
            pooled = 0;
            for (element = 0; element < 4; element = element + 1) begin
                biased = sat18(y_value[element] + $signed(bias));
                if (biased < 0)
                    biased = 0;
                if (biased > pooled)
                    pooled = biased;
            end
            wide_result = pooled;
            wide_result = wide_result * requant_multiplier;
            wide_result = (wide_result + 64'd8388608) >> 24;
            expected = (wide_result > 255) ? 255 : wide_result;
        end
    endtask

    task send_tile;
        begin
            calculate_golden();
            for (element = 0; element < 4; element = element + 1)
                y_tile[element*ACC_BITS +: ACC_BITS] = y_value[element];
            @(negedge clk);
            while (!in_ready)
                @(negedge clk);
            in_valid = 1'b1;
            @(negedge clk);
            in_valid = 1'b0;
        end
    endtask

    task check_result;
        input [8*48-1:0] test_name;
        begin
            while (!out_valid)
                @(negedge clk);
            if (activation !== expected[7:0]) begin
                $display("FAIL %-48s expected=%0d got=%0d",
                         test_name, expected, activation);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        in_valid = 1'b0;
        y_tile = 0;
        bias = 0;
        requant_multiplier = CONV1_MULT;
        out_ready = 1'b1;
        errors = 0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        for (element = 0; element < 4; element = element + 1)
            y_value[element] = 0;
        send_tile();
        check_result("zero tile and zero bias");

        y_value[0] = -40000;
        y_value[1] = -30000;
        y_value[2] = -20000;
        y_value[3] = -10000;
        bias = -16'sd100;
        send_tile();
        check_result("all negative becomes zero after ReLU");

        y_value[0] = 120000;
        y_value[1] = 131000;
        y_value[2] = -131072;
        y_value[3] = 45000;
        bias = 16'sd32767;
        requant_multiplier = CONV2_MULT;
        send_tile();
        check_result("positive bias saturation and UINT8 clamp");

        y_value[0] = -131072;
        y_value[1] = -120000;
        y_value[2] = -100000;
        y_value[3] = -90000;
        bias = -16'sd32768;
        send_tile();
        check_result("negative bias saturation");

        // Exact rounding boundary with a unity Q24 multiplier.
        y_value[0] = 127;
        y_value[1] = 100;
        y_value[2] = 0;
        y_value[3] = -1;
        bias = 0;
        requant_multiplier = 24'hffffff;
        send_tile();
        check_result("requantization rounding");

        for (test_index = 0; test_index < 100; test_index = test_index + 1) begin
            for (element = 0; element < 4; element = element + 1)
                y_value[element] = ($random & 18'h3ffff) - 131072;
            bias = $random;
            requant_multiplier = (test_index & 1) ? CONV1_MULT : CONV2_MULT;
            send_tile();
            check_result("random original-order golden");
        end

        // Consecutive inputs also change bias and multiplier every cycle, so
        // metadata alignment through the pipeline is verified here.
        fork
            begin : burst_driver
                @(negedge clk);
                for (burst_drive = 0; burst_drive < 6; burst_drive = burst_drive + 1) begin
                    while (!in_ready)
                        @(negedge clk);
                    for (element = 0; element < 4; element = element + 1)
                        y_value[element] = burst_drive*9000 + element*17000 - 45000;
                    bias = burst_drive*3000 - 7000;
                    requant_multiplier = (burst_drive & 1) ? CONV1_MULT : CONV2_MULT;
                    calculate_golden();
                    burst_expected[burst_drive] = expected;
                    for (element = 0; element < 4; element = element + 1)
                        y_tile[element*ACC_BITS +: ACC_BITS] = y_value[element];
                    in_valid = 1'b1;
                    @(negedge clk);
                end
                in_valid = 1'b0;
            end
            begin : burst_monitor
                for (burst_receive = 0; burst_receive < 6;
                     burst_receive = burst_receive + 1) begin
                    @(negedge clk);
                    while (!out_valid)
                        @(negedge clk);
                    if (activation !== burst_expected[burst_receive][7:0]) begin
                        $display("FAIL burst item=%0d expected=%0d got=%0d",
                                 burst_receive, burst_expected[burst_receive], activation);
                        errors = errors + 1;
                    end
                end
            end
        join

        @(negedge clk);
        out_ready = 1'b0;
        y_value[0] = 1111;
        y_value[1] = 2222;
        y_value[2] = 3333;
        y_value[3] = 4444;
        bias = 16'sd55;
        requant_multiplier = CONV1_MULT;
        send_tile();
        check_result("backpressure result");
        held_result = activation;
        repeat (3) begin
            @(negedge clk);
            if (!out_valid || activation !== held_result) begin
                $display("FAIL output changed while out_ready=0");
                errors = errors + 1;
            end
        end
        out_ready = 1'b1;
        @(negedge clk);

        if (errors == 0)
            $display("PASS winograd_postprocess: all tests passed");
        else
            $display("FAIL winograd_postprocess: %0d error(s)", errors);

        $finish;
    end

endmodule
