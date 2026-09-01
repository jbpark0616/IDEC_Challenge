`timescale 1ns/1ps

module winograd_cnn_accelerator_tb;
    reg clk;
    reg rst_n;
    reg image_valid;
    wire image_ready;
    reg [7:0] image_pixel;
    reg [191:0] conv1_u_bank;
    reg [575:0] conv2_u_bank;
    reg [47:0] conv1_bias_bank;
    reg [47:0] conv2_bias_bank;
    reg [23:0] conv1_requant_multiplier;
    reg [23:0] conv2_requant_multiplier;
    wire feature_valid;
    reg feature_ready;
    wire [7:0] feature_data;
    wire [6:0] feature_index;
    wire feature_last;
    wire busy;

    integer pixel_count;
    integer output_count;
    integer expected_value;
    integer errors;
    integer cycles;
    integer timeout_count;

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
        .conv1_requant_multiplier(conv1_requant_multiplier),
        .conv2_requant_multiplier(conv2_requant_multiplier),
        .fc_weight_bank(3000'd0),
        .fc_bias_bank(160'd0),
        .feature_valid(feature_valid),
        .feature_ready(feature_ready),
        .feature_data(feature_data),
        .feature_index(feature_index),
        .feature_last(feature_last),
        .decision(),
        .decision_valid(),
        .busy(busy)
    );

    always #5 clk = ~clk;

    always @(negedge clk) begin
        if (!rst_n) begin
            feature_ready <= 1'b0;
            cycles <= 0;
        end else begin
            cycles <= cycles + 1;
            feature_ready <= ((cycles % 5) != 2);
        end
    end

    always @(posedge clk) begin
        if (rst_n && feature_valid && feature_ready) begin
            if (feature_index !== output_count[6:0]) begin
                $display("ERROR: feature index got=%0d expected=%0d",
                         feature_index, output_count);
                errors = errors + 1;
            end
            if (output_count < 25)
                expected_value = 10;
            else if (output_count < 50)
                expected_value = 20;
            else
                expected_value = 30;
            if (feature_data !== expected_value) begin
                $display("ERROR: feature %0d got=%0d expected=%0d",
                         output_count, feature_data, expected_value);
                errors = errors + 1;
            end
            if (feature_last !== (output_count == 74)) begin
                $display("ERROR: feature_last at %0d", output_count);
                errors = errors + 1;
            end
            output_count = output_count + 1;
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        image_valid = 1'b0;
        image_pixel = 8'd0;
        conv1_u_bank = 0;
        conv2_u_bank = 0;
        conv1_bias_bank = 0;
        conv2_bias_bank = 0;
        conv1_requant_multiplier = 24'd8388608;
        conv2_requant_multiplier = 24'd8388608;
        feature_ready = 1'b0;
        pixel_count = 0;
        output_count = 0;
        errors = 0;
        cycles = 0;

        // Zero weights make every convolution result depend only on bias.
        // Q24 multiplier 0.5 maps biases 20/40/60 to activations 10/20/30.
        conv1_bias_bank[0 +: 16] = 16'd20;
        conv1_bias_bank[16 +: 16] = 16'd40;
        conv1_bias_bank[32 +: 16] = 16'd60;
        conv2_bias_bank[0 +: 16] = 16'd20;
        conv2_bias_bank[16 +: 16] = 16'd40;
        conv2_bias_bank[32 +: 16] = 16'd60;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        while (pixel_count < 784) begin
            @(negedge clk);
            image_valid = 1'b1;
            image_pixel = (pixel_count*13 + 5) & 255;
            if (image_ready)
                pixel_count = pixel_count + 1;
        end
        @(negedge clk);
        image_valid = 1'b0;

        timeout_count = 0;
        while (busy && timeout_count < 5000) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (busy) begin
            $display("ERROR: two-conv engine timeout");
            errors = errors + 1;
        end

        repeat (3) @(posedge clk);
        if (output_count != 75) begin
            $display("ERROR: feature count got=%0d expected=75", output_count);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: winograd_cnn_accelerator");
        else
            $display("FAIL: winograd_cnn_accelerator errors=%0d", errors);
        $finish;
    end

endmodule
