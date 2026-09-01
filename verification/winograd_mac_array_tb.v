`timescale 1ns/1ps

module winograd_mac_array_tb;
    localparam integer NUM_MACS = 16;
    localparam integer FC_CLASSES = 10;
    localparam integer OPERAND_BITS = 11;
    localparam integer WEIGHT_BITS = 4;
    localparam integer BIAS_BITS = 16;
    localparam integer ACC_BITS = 18;

    reg clk;
    reg rst_n;
    reg mode_fc;
    reg in_valid;
    wire in_ready;
    reg txn_first;
    reg txn_last;
    reg [NUM_MACS*OPERAND_BITS-1:0] conv_operand_vec;
    reg [NUM_MACS*WEIGHT_BITS-1:0] conv_weight_vec;
    reg [7:0] fc_activation;
    reg [FC_CLASSES*WEIGHT_BITS-1:0] fc_weight_vec;
    reg [FC_CLASSES*BIAS_BITS-1:0] fc_bias_vec;
    wire out_valid;
    reg out_ready;
    wire [NUM_MACS*ACC_BITS-1:0] result_vec;
    wire [NUM_MACS*ACC_BITS-1:0] accumulator_vec;

    integer expected [0:NUM_MACS-1];
    integer operand_value;
    integer weight_value;
    integer got;
    integer i;
    integer ch;
    integer feature;
    integer bias_value [0:FC_CLASSES-1];
    integer errors;
    reg [NUM_MACS*ACC_BITS-1:0] held_result;

    winograd_mac_array dut (
        .clk(clk),
        .rst_n(rst_n),
        .mode_fc(mode_fc),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .txn_first(txn_first),
        .txn_last(txn_last),
        .conv_operand_vec(conv_operand_vec),
        .conv_weight_vec(conv_weight_vec),
        .fc_activation(fc_activation),
        .fc_weight_vec(fc_weight_vec),
        .fc_bias_vec(fc_bias_vec),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .result_vec(result_vec),
        .accumulator_vec(accumulator_vec)
    );

    always #5 clk = ~clk;

    function integer sat18;
        input integer value;
        begin
            if (value > 131071)
                sat18 = 131071;
            else if (value < -131072)
                sat18 = -131072;
            else
                sat18 = value;
        end
    endfunction

    task send_beat;
        input first_beat;
        input last_beat;
        begin
            @(negedge clk);
            while (!in_ready)
                @(negedge clk);
            txn_first = first_beat;
            txn_last = last_beat;
            in_valid = 1'b1;
            @(negedge clk);
            in_valid = 1'b0;
            txn_first = 1'b0;
            txn_last = 1'b0;
        end
    endtask

    task wait_for_result;
        begin
            while (!out_valid)
                @(negedge clk);
        end
    endtask

    task check_all_lanes;
        input [8*40-1:0] test_name;
        begin
            for (i = 0; i < NUM_MACS; i = i + 1) begin
                got = $signed(result_vec[i*ACC_BITS +: ACC_BITS]);
                if (got !== expected[i]) begin
                    $display("FAIL %-40s lane=%0d expected=%0d got=%0d",
                             test_name, i, expected[i], got);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        mode_fc = 1'b0;
        in_valid = 1'b0;
        txn_first = 1'b0;
        txn_last = 1'b0;
        conv_operand_vec = 0;
        conv_weight_vec = 0;
        fc_activation = 0;
        fc_weight_vec = 0;
        fc_bias_vec = 0;
        out_ready = 1'b1;
        errors = 0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // Conv1: a single input channel. first and last are the same beat.
        mode_fc = 1'b0;
        for (i = 0; i < NUM_MACS; i = i + 1) begin
            operand_value = i*37 - 250;
            case (i % 5)
                0: weight_value = 0;
                1: weight_value = -7;
                2: weight_value = 7;
                3: weight_value = -1;
                default: weight_value = 3;
            endcase
            conv_operand_vec[i*OPERAND_BITS +: OPERAND_BITS] = operand_value;
            conv_weight_vec[i*WEIGHT_BITS +: WEIGHT_BITS] = weight_value;
            expected[i] = operand_value * weight_value;
        end
        send_beat(1'b1, 1'b1);
        wait_for_result();
        check_all_lanes("conv1 single-channel product");

        // Conv2: three input channels reduced temporally in every lane.
        for (i = 0; i < NUM_MACS; i = i + 1)
            expected[i] = 0;
        for (ch = 0; ch < 3; ch = ch + 1) begin
            for (i = 0; i < NUM_MACS; i = i + 1) begin
                operand_value = (i - 8)*29 + ch*11;
                weight_value = ((i + ch*3) % 8) - 4;
                if (((i + ch) % 6) == 0)
                    weight_value = 0;
                conv_operand_vec[i*OPERAND_BITS +: OPERAND_BITS] = operand_value;
                conv_weight_vec[i*WEIGHT_BITS +: WEIGHT_BITS] = weight_value;
                expected[i] = expected[i] + operand_value * weight_value;
            end
            send_beat(ch == 0, ch == 2);
        end
        wait_for_result();
        check_all_lanes("conv2 three-channel reduction");

        // Let the ready/valid handshake consume the Conv2 result before the
        // FC backpressure test intentionally deasserts out_ready.
        @(negedge clk);

        // FC: run the model's full 75-feature accumulation. Activation is
        // broadcast to class lanes and signed bias is loaded on the first beat.
        mode_fc = 1'b1;
        fc_bias_vec = 0;
        for (i = 0; i < NUM_MACS; i = i + 1) begin
            if (i < FC_CLASSES) begin
                bias_value[i] = (i - 5)*13;
                expected[i] = 0;
                fc_bias_vec[i*BIAS_BITS +: BIAS_BITS] = bias_value[i];
            end else begin
                expected[i] = 0;
            end
        end

        out_ready = 1'b0;
        for (feature = 0; feature < 75; feature = feature + 1) begin
            fc_activation = (feature*37 + 3) & 8'hff;
            if ((feature % 11) == 0)
                fc_activation = 8'd0;
            for (i = 0; i < FC_CLASSES; i = i + 1) begin
                weight_value = ((i + feature) % 8) - 4;
                if (((i + feature) % 5) == 0)
                    weight_value = 0;
                fc_weight_vec[i*WEIGHT_BITS +: WEIGHT_BITS] = weight_value;
                expected[i] = sat18(expected[i] + fc_activation * weight_value);
            end
            send_beat(feature == 0, feature == 74);
        end
        for (i = 0; i < FC_CLASSES; i = i + 1)
            expected[i] = sat18(expected[i] + bias_value[i]);
        wait_for_result();
        check_all_lanes("FC bias plus 75-feature dot products");

        // The output register must remain stable under backpressure.
        held_result = result_vec;
        repeat (3) begin
            @(negedge clk);
            if (!out_valid || result_vec !== held_result) begin
                $display("FAIL output changed while out_ready=0");
                errors = errors + 1;
            end
        end
        out_ready = 1'b1;
        @(negedge clk);

        // Force both INT18 rails. Applying bias after the saturated dot product
        // gives a different answer than applying it on the first feature.
        fc_bias_vec = 0;
        for (i = 0; i < FC_CLASSES; i = i + 1) begin
            bias_value[i] = 0;
            expected[i] = 0;
        end
        bias_value[0] = -32768;
        bias_value[1] = 32767;
        fc_bias_vec[0*BIAS_BITS +: BIAS_BITS] = bias_value[0];
        fc_bias_vec[1*BIAS_BITS +: BIAS_BITS] = bias_value[1];
        for (feature = 0; feature < 75; feature = feature + 1) begin
            fc_activation = 8'd255;
            fc_weight_vec = 0;
            fc_weight_vec[0*WEIGHT_BITS +: WEIGHT_BITS] = 4'sd7;
            fc_weight_vec[1*WEIGHT_BITS +: WEIGHT_BITS] = -4'sd8;
            expected[0] = sat18(expected[0] + 255*7);
            expected[1] = sat18(expected[1] - 255*8);
            send_beat(feature == 0, feature == 74);
        end
        expected[0] = sat18(expected[0] + bias_value[0]);
        expected[1] = sat18(expected[1] + bias_value[1]);
        wait_for_result();
        check_all_lanes("FC saturating accumulation then bias");

        if (errors == 0)
            $display("PASS winograd_mac_array: all tests passed");
        else
            $display("FAIL winograd_mac_array: %0d error(s)", errors);

        $finish;
    end

endmodule
