`timescale 1ns/1ps

module winograd_conv_core_tb;
    localparam integer ACC_MAX = 131071;
    localparam integer ACC_MIN = -131072;
    localparam integer CONV1_MULT = 1616163;
    localparam integer CONV2_MULT = 1827841;

    reg clk;
    reg rst_n;
    reg [1:0] input_channels_minus1;
    reg [1:0] output_channels_minus1;
    reg [575:0] u_weight_bank;
    reg [47:0] bias_bank;
    reg [23:0] requant_multiplier;
    reg in_valid;
    wire in_ready;
    reg [127:0] activation_tile;
    wire out_valid;
    reg out_ready;
    wire [7:0] activation;
    wire [1:0] output_channel;

    integer pixel [0:47];
    integer temp [0:47];
    integer v_value [0:47];
    integer weight [0:143];
    integer bias_value [0:2];
    integer m_value [0:47];
    integer left_value [0:23];
    integer y_value [0:11];
    integer expected_activation [0:2];
    integer row;
    integer col;
    integer channel;
    integer kernel;
    integer lane;
    integer first_value;
    integer pooled;
    integer biased;
    integer errors;
    reg [63:0] wide_result;
    reg [7:0] held_activation;
    reg [1:0] held_channel;

    winograd_conv_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .mode_fc(1'b0),
        .input_channels_minus1(input_channels_minus1),
        .output_channels_minus1(output_channels_minus1),
        .u_weight_bank(u_weight_bank),
        .bias_bank(bias_bank),
        .requant_multiplier(requant_multiplier),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .activation_tile(activation_tile),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .activation(activation),
        .output_channel(output_channel),
        .fc_in_valid(1'b0),
        .fc_in_ready(),
        .fc_activation(8'd0),
        .fc_weight_vec(40'd0),
        .fc_bias_vec(160'd0),
        .fc_txn_first(1'b0),
        .fc_txn_last(1'b0),
        .fc_result_valid(),
        .fc_result_ready(1'b1),
        .fc_result_vec()
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

    task pack_parameters;
        begin
            u_weight_bank = 0;
            bias_bank = 0;
            for (kernel = 0; kernel < 3; kernel = kernel + 1) begin
                bias_bank[kernel*16 +: 16] = bias_value[kernel];
                for (channel = 0; channel < 3; channel = channel + 1)
                    for (lane = 0; lane < 16; lane = lane + 1)
                        u_weight_bank[((kernel*3+channel)*16+lane)*4 +: 4]
                            = weight[(kernel*3+channel)*16+lane];
            end
        end
    endtask

    task calculate_golden;
        input integer channels;
        begin
            for (channel = 0; channel < channels; channel = channel + 1) begin
                for (col = 0; col < 4; col = col + 1) begin
                    temp[channel*16+0*4+col] =
                        pixel[channel*16+0*4+col] - pixel[channel*16+2*4+col];
                    temp[channel*16+1*4+col] =
                        pixel[channel*16+1*4+col] + pixel[channel*16+2*4+col];
                    temp[channel*16+2*4+col] =
                        pixel[channel*16+2*4+col] - pixel[channel*16+1*4+col];
                    temp[channel*16+3*4+col] =
                        pixel[channel*16+1*4+col] - pixel[channel*16+3*4+col];
                end
                for (row = 0; row < 4; row = row + 1) begin
                    v_value[channel*16+row*4+0] =
                        temp[channel*16+row*4+0] - temp[channel*16+row*4+2];
                    v_value[channel*16+row*4+1] =
                        temp[channel*16+row*4+1] + temp[channel*16+row*4+2];
                    v_value[channel*16+row*4+2] =
                        temp[channel*16+row*4+2] - temp[channel*16+row*4+1];
                    v_value[channel*16+row*4+3] =
                        temp[channel*16+row*4+1] - temp[channel*16+row*4+3];
                end
            end

            for (kernel = 0; kernel < 3; kernel = kernel + 1) begin
                for (lane = 0; lane < 16; lane = lane + 1) begin
                    m_value[kernel*16+lane] = 0;
                    for (channel = 0; channel < channels; channel = channel + 1)
                        m_value[kernel*16+lane] = sat18(
                            m_value[kernel*16+lane]
                            + v_value[channel*16+lane]
                            * weight[(kernel*3+channel)*16+lane]);
                end

                for (col = 0; col < 4; col = col + 1) begin
                    first_value = sat18(m_value[kernel*16+0*4+col]
                                      + m_value[kernel*16+1*4+col]);
                    left_value[kernel*8+0*4+col] = sat18(
                        first_value + m_value[kernel*16+2*4+col]);
                    first_value = sat18(m_value[kernel*16+1*4+col]
                                      - m_value[kernel*16+2*4+col]);
                    left_value[kernel*8+1*4+col] = sat18(
                        first_value - m_value[kernel*16+3*4+col]);
                end
                for (row = 0; row < 2; row = row + 1) begin
                    first_value = sat18(left_value[kernel*8+row*4+0]
                                      + left_value[kernel*8+row*4+1]);
                    y_value[kernel*4+row*2+0] = sat18(
                        first_value + left_value[kernel*8+row*4+2]);
                    first_value = sat18(left_value[kernel*8+row*4+1]
                                      - left_value[kernel*8+row*4+2]);
                    y_value[kernel*4+row*2+1] = sat18(
                        first_value - left_value[kernel*8+row*4+3]);
                end

                pooled = y_value[kernel*4];
                for (lane = 1; lane < 4; lane = lane + 1)
                    if (y_value[kernel*4+lane] > pooled)
                        pooled = y_value[kernel*4+lane];
                biased = sat18(pooled + bias_value[kernel]);
                if (biased < 0)
                    biased = 0;
                wide_result = biased;
                wide_result = wide_result * requant_multiplier;
                wide_result = (wide_result + 64'd8388608) >> 24;
                expected_activation[kernel] =
                    (wide_result > 255) ? 255 : wide_result;
            end
        end
    endtask

    task send_input_group;
        input integer channels;
        begin
            for (channel = 0; channel < channels; channel = channel + 1) begin
                for (lane = 0; lane < 16; lane = lane + 1)
                    activation_tile[lane*8 +: 8] = pixel[channel*16+lane];
                @(negedge clk);
                while (!in_ready)
                    @(negedge clk);
                in_valid = 1'b1;
                @(negedge clk);
                in_valid = 1'b0;
            end
        end
    endtask

    task check_three_outputs;
        input [8*40-1:0] test_name;
        begin
            for (kernel = 0; kernel < 3; kernel = kernel + 1) begin
                while (!out_valid)
                    @(negedge clk);
                if (output_channel !== kernel[1:0]
                    || activation !== expected_activation[kernel][7:0]) begin
                    $display("FAIL %-40s k=%0d expected=%0d got_k=%0d got=%0d",
                             test_name, kernel, expected_activation[kernel],
                             output_channel, activation);
                    errors = errors + 1;
                end
                @(negedge clk);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        input_channels_minus1 = 0;
        output_channels_minus1 = 2;
        u_weight_bank = 0;
        bias_bank = 0;
        requant_multiplier = CONV1_MULT;
        in_valid = 1'b0;
        activation_tile = 0;
        out_ready = 1'b1;
        errors = 0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // Conv1-style C=1, K=3 tile.
        for (lane = 0; lane < 48; lane = lane + 1)
            pixel[lane] = (lane*29 + 7) & 8'hff;
        for (lane = 0; lane < 144; lane = lane + 1)
            weight[lane] = 0;
        for (kernel = 0; kernel < 3; kernel = kernel + 1)
            for (lane = 0; lane < 16; lane = lane + 1)
                weight[(kernel*3)*16+lane] = ((kernel*5+lane) % 15) - 7;
        bias_value[0] = -36;
        bias_value[1] = -232;
        bias_value[2] = -156;
        pack_parameters();
        calculate_golden(1);
        send_input_group(1);
        check_three_outputs("Conv1 end-to-end");

        // Conv2-style C=3, K=3. Stall the final output to verify that
        // backpressure propagates through every integrated stage.
        repeat (3) @(negedge clk);
        input_channels_minus1 = 2;
        requant_multiplier = CONV2_MULT;
        for (channel = 0; channel < 3; channel = channel + 1)
            for (lane = 0; lane < 16; lane = lane + 1)
                pixel[channel*16+lane] =
                    (channel*71 + lane*17 + 11) & 8'hff;
        for (kernel = 0; kernel < 3; kernel = kernel + 1)
            for (channel = 0; channel < 3; channel = channel + 1)
                for (lane = 0; lane < 16; lane = lane + 1)
                    weight[(kernel*3+channel)*16+lane] =
                        ((kernel*7+channel*3+lane) % 16) - 8;
        bias_value[0] = 315;
        bias_value[1] = -417;
        bias_value[2] = 129;
        pack_parameters();
        calculate_golden(3);
        out_ready = 1'b0;
        send_input_group(3);
        while (!out_valid)
            @(negedge clk);
        held_activation = activation;
        held_channel = output_channel;
        repeat (3) begin
            @(negedge clk);
            if (!out_valid || activation !== held_activation
                || output_channel !== held_channel) begin
                $display("FAIL integrated output changed under backpressure");
                errors = errors + 1;
            end
        end
        out_ready = 1'b1;
        check_three_outputs("Conv2 end-to-end with replay");

        if (errors == 0)
            $display("PASS winograd_conv_core: all tests passed");
        else
            $display("FAIL winograd_conv_core: %0d error(s)", errors);
        $finish;
    end

endmodule
