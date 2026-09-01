`timescale 1ns/1ps

// Real exported-model test for the complete A/B-bank convolution frontend.
module winograd_cnn_accelerator_real_tb;
    reg clk;
    reg rst_n;
    reg image_valid;
    wire image_ready;
    reg [7:0] image_pixel;
    reg [191:0] conv1_u_bank;
    reg [575:0] conv2_u_bank;
    reg [47:0] conv1_bias_bank;
    reg [47:0] conv2_bias_bank;
    reg [2999:0] fc_weight_bank;
    reg [159:0] fc_bias_bank;
    wire feature_valid;
    reg feature_ready;
    wire [7:0] feature_data;
    wire [6:0] feature_index;
    wire feature_last;
    wire [3:0] decision;
    wire decision_valid;
    wire busy;

    reg [7:0] image_memory [0:783];
    reg [7:0] golden_features [0:74];
    reg [3:0] conv1_u_memory [0:47];
    reg [3:0] conv2_u_memory [0:143];
    reg [15:0] conv1_bias_memory [0:2];
    reg [15:0] conv2_bias_memory [0:2];
    reg [3:0] fc_weight_memory [0:749];
    reg [15:0] fc_bias_memory [0:9];
    reg [3:0] expected_decision [0:0];

    integer index;
    integer image_index;
    integer output_count;
    integer errors;
    integer cycles;
    integer decision_count;

    winograd_cnn_accelerator dut (
        .clk(clk),
        .rst_n(rst_n),
        .image_valid(image_valid),
        .image_ready(image_ready),
        .image_pixel(image_pixel),
        .conv1_u_bank(conv1_u_bank),
        .conv2_u_bank(conv2_u_bank),
        .conv1_bias_bank(conv1_bias_bank),
        .conv2_bias_bank(conv2_bias_bank),
        .conv1_requant_multiplier(24'd1616163),
        .conv2_requant_multiplier(24'd1827841),
        .fc_weight_bank(fc_weight_bank),
        .fc_bias_bank(fc_bias_bank),
        .feature_valid(feature_valid),
        .feature_ready(feature_ready),
        .feature_data(feature_data),
        .feature_index(feature_index),
        .feature_last(feature_last),
        .decision(decision),
        .decision_valid(decision_valid),
        .busy(busy)
    );

    always #5 clk = ~clk;

    // Exercise output backpressure. Internal Conv outputs are always accepted
    // into the full banks, while this stall only affects final feature readout.
    always @(negedge clk) begin
        if (!rst_n)
            feature_ready <= 1'b0;
        else
            feature_ready <= ((cycles % 7) != 3) && ((cycles % 7) != 4);
    end

    always @(posedge clk) begin
        if (rst_n)
            cycles = cycles + 1;
        if (rst_n && feature_valid && feature_ready) begin
            if (feature_index !== output_count[6:0]) begin
                $display("ERROR: feature index got=%0d expected=%0d",
                         feature_index, output_count);
                errors = errors + 1;
            end
            if (feature_data !== golden_features[output_count]) begin
                $display("ERROR: feature %0d got=%0d expected=%0d",
                         output_count, feature_data,
                         golden_features[output_count]);
                errors = errors + 1;
            end
            if (feature_last !== (output_count == 74)) begin
                $display("ERROR: feature_last at %0d", output_count);
                errors = errors + 1;
            end
            output_count = output_count + 1;
        end
        if (rst_n && decision_valid) begin
            decision_count = decision_count + 1;
            if (decision !== expected_decision[0]) begin
                $display("ERROR: decision got=%0d expected=%0d",
                         decision, expected_decision[0]);
                errors = errors + 1;
            end
        end
    end

    initial begin
        $readmemh("../../../verification/data/two_conv_real/image_u8.hex",
                  image_memory);
        $readmemh("../../../verification/data/two_conv_real/conv2_activation_u8.hex",
                  golden_features);
        $readmemh("../../../training/export/qat_winograd3x3_w4_frozen_aug/conv1_u_twos_complement.hex",
                  conv1_u_memory);
        $readmemh("../../../training/export/qat_winograd3x3_w4_frozen_aug/conv2_u_twos_complement.hex",
                  conv2_u_memory);
        $readmemh("../../../training/export/qat_winograd3x3_w4_frozen_aug/conv1_bias_twos_complement.hex",
                  conv1_bias_memory);
        $readmemh("../../../training/export/qat_winograd3x3_w4_frozen_aug/conv2_bias_twos_complement.hex",
                  conv2_bias_memory);
        $readmemh("../../../training/export/qat_winograd3x3_w4_frozen_aug/fc_weight_twos_complement.hex",
                  fc_weight_memory);
        $readmemh("../../../training/export/qat_winograd3x3_w4_frozen_aug/fc_bias_twos_complement.hex",
                  fc_bias_memory);
        $readmemh("../../../verification/data/two_conv_real/decision.hex",
                  expected_decision);

        clk = 1'b0;
        rst_n = 1'b0;
        image_valid = 1'b0;
        image_pixel = 8'd0;
        feature_ready = 1'b0;
        conv1_u_bank = 0;
        conv2_u_bank = 0;
        conv1_bias_bank = 0;
        conv2_bias_bank = 0;
        fc_weight_bank = 0;
        fc_bias_bank = 0;
        image_index = 0;
        output_count = 0;
        errors = 0;
        cycles = 0;
        decision_count = 0;

        for (index = 0; index < 48; index = index + 1)
            conv1_u_bank[index*4 +: 4] = conv1_u_memory[index];
        for (index = 0; index < 144; index = index + 1)
            conv2_u_bank[index*4 +: 4] = conv2_u_memory[index];
        for (index = 0; index < 3; index = index + 1) begin
            conv1_bias_bank[index*16 +: 16] = conv1_bias_memory[index];
            conv2_bias_bank[index*16 +: 16] = conv2_bias_memory[index];
        end
        for (index = 0; index < 750; index = index + 1)
            fc_weight_bank[index*4 +: 4] = fc_weight_memory[index];
        for (index = 0; index < 10; index = index + 1)
            fc_bias_bank[index*16 +: 16] = fc_bias_memory[index];

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        while (image_index < 784) begin
            @(negedge clk);
            image_valid = 1'b1;
            image_pixel = image_memory[image_index];
            if (image_ready)
                image_index = image_index + 1;
        end
        @(negedge clk);
        image_valid = 1'b0;

        while (busy && cycles < 10000)
            @(posedge clk);
        if (busy) begin
            $display("ERROR: real two-conv engine timeout");
            errors = errors + 1;
        end

        repeat (3) @(posedge clk);
        if (output_count != 75) begin
            $display("ERROR: feature count got=%0d expected=75", output_count);
            errors = errors + 1;
        end
        if (decision_count != 1) begin
            $display("ERROR: decision count got=%0d expected=1", decision_count);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: winograd_cnn_accelerator real exported model (%0d cycles)",
                     cycles);
        else
            $display("FAIL: winograd_cnn_accelerator real errors=%0d", errors);
        $finish;
    end
endmodule
