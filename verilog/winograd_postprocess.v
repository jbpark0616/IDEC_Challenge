`timescale 1ns/1ps

// Fused convolution post-processing for one Winograd F(2x2, 3x3) tile.
//
// The software order is:
//   INT18 bias add with saturation -> ReLU -> 2x2 max-pool -> UINT8 requant
//
// Because saturated bias addition and ReLU are monotonic and all four values
// use the same output-channel bias, this block computes the equivalent order:
//   max4 -> one INT18 saturated bias add -> ReLU -> UINT8 requant
// This removes three bias adders without changing the integer result.
module winograd_postprocess #(
    parameter integer ACC_BITS  = 18,
    parameter integer BIAS_BITS = 16,
    parameter integer MULT_BITS = 24,
    parameter integer SHIFT     = 24,
    parameter integer USER_BITS = 2
) (
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         in_valid,
    output wire                         in_ready,
    input  wire [4*ACC_BITS-1:0]        y_tile,
    input  wire signed [BIAS_BITS-1:0]  bias,
    input  wire [MULT_BITS-1:0]         requant_multiplier,
    input  wire [USER_BITS-1:0]         in_user,

    output reg                          out_valid,
    input  wire                         out_ready,
    output reg [7:0]                    activation,
    output reg [USER_BITS-1:0]          out_user
);

    localparam integer PRODUCT_BITS = ACC_BITS + MULT_BITS;

    localparam signed [ACC_BITS:0] SAT_MAX_EXT =
        {2'b00, {(ACC_BITS-1){1'b1}}};
    localparam signed [ACC_BITS:0] SAT_MIN_EXT =
        {2'b11, {(ACC_BITS-1){1'b0}}};
    localparam signed [ACC_BITS-1:0] SAT_MAX =
        {1'b0, {(ACC_BITS-1){1'b1}}};
    localparam signed [ACC_BITS-1:0] SAT_MIN =
        {1'b1, {(ACC_BITS-1){1'b0}}};

    function signed [ACC_BITS-1:0] signed_max;
        input signed [ACC_BITS-1:0] lhs;
        input signed [ACC_BITS-1:0] rhs;
        begin
            signed_max = (lhs >= rhs) ? lhs : rhs;
        end
    endfunction

    function signed [ACC_BITS-1:0] sat_bias_add;
        input signed [ACC_BITS-1:0] value;
        input signed [BIAS_BITS-1:0] bias_value;
        reg signed [ACC_BITS:0] value_ext;
        reg signed [ACC_BITS:0] bias_ext;
        reg signed [ACC_BITS:0] sum;
        begin
            value_ext = {value[ACC_BITS-1], value};
            bias_ext = {{(ACC_BITS+1-BIAS_BITS){bias_value[BIAS_BITS-1]}},
                        bias_value};
            sum = value_ext + bias_ext;
            if (sum > SAT_MAX_EXT)
                sat_bias_add = SAT_MAX;
            else if (sum < SAT_MIN_EXT)
                sat_bias_add = SAT_MIN;
            else
                sat_bias_add = sum[ACC_BITS-1:0];
        end
    endfunction

    function [7:0] requantize_u8;
        input [ACC_BITS-1:0] nonnegative_value;
        input [MULT_BITS-1:0] multiplier;
        reg [PRODUCT_BITS-1:0] product;
        reg [PRODUCT_BITS:0] rounded;
        reg [PRODUCT_BITS:0] shifted;
        begin
            product = nonnegative_value * multiplier;
            rounded = {1'b0, product} + ({{PRODUCT_BITS{1'b0}}, 1'b1}
                                         << (SHIFT-1));
            shifted = rounded >> SHIFT;
            if (shifted > 8'd255)
                requantize_u8 = 8'hff;
            else
                requantize_u8 = shifted[7:0];
        end
    endfunction

    wire signed [ACC_BITS-1:0] y0;
    wire signed [ACC_BITS-1:0] y1;
    wire signed [ACC_BITS-1:0] y2;
    wire signed [ACC_BITS-1:0] y3;
    wire signed [ACC_BITS-1:0] max01;
    wire signed [ACC_BITS-1:0] max23;
    wire signed [ACC_BITS-1:0] tile_max_next;

    assign y0 = y_tile[0*ACC_BITS +: ACC_BITS];
    assign y1 = y_tile[1*ACC_BITS +: ACC_BITS];
    assign y2 = y_tile[2*ACC_BITS +: ACC_BITS];
    assign y3 = y_tile[3*ACC_BITS +: ACC_BITS];
    assign max01 = signed_max(y0, y1);
    assign max23 = signed_max(y2, y3);
    assign tile_max_next = signed_max(max01, max23);

    reg signed [ACC_BITS-1:0]  tile_max;
    reg signed [BIAS_BITS-1:0] bias_stage0;
    reg [MULT_BITS-1:0]        multiplier_stage0;
    reg [USER_BITS-1:0]        user_stage0;
    reg                        max_valid;

    wire signed [ACC_BITS-1:0] biased_next;
    wire [ACC_BITS-1:0]        relu_next;
    reg  [ACC_BITS-1:0]        relu_value;
    reg  [MULT_BITS-1:0]       multiplier_stage1;
    reg  [USER_BITS-1:0]       user_stage1;
    reg                        relu_valid;

    assign biased_next = sat_bias_add(tile_max, bias_stage0);
    assign relu_next = biased_next[ACC_BITS-1] ? {ACC_BITS{1'b0}} : biased_next;

    wire output_stage_ready;
    wire relu_stage_ready;
    wire max_stage_ready;

    assign output_stage_ready = (~out_valid) | out_ready;
    assign relu_stage_ready = (~relu_valid) | output_stage_ready;
    assign max_stage_ready = (~max_valid) | relu_stage_ready;
    assign in_ready = max_stage_ready;

    // Datapath registers need no reset; valid bits hide their contents until
    // the corresponding pipeline stage contains a real transaction.
    always @(posedge clk) begin
        if (max_stage_ready && in_valid) begin
            tile_max         <= tile_max_next;
            bias_stage0      <= bias;
            multiplier_stage0 <= requant_multiplier;
            user_stage0       <= in_user;
        end
    end

    always @(posedge clk) begin
        if (relu_stage_ready && max_valid) begin
            relu_value        <= relu_next;
            multiplier_stage1 <= multiplier_stage0;
            user_stage1       <= user_stage0;
        end
    end

    always @(posedge clk) begin
        if (output_stage_ready && relu_valid) begin
            activation <= requantize_u8(relu_value, multiplier_stage1);
            out_user <= user_stage1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            max_valid  <= 1'b0;
            relu_valid <= 1'b0;
            out_valid  <= 1'b0;
        end else begin
            if (output_stage_ready)
                out_valid <= relu_valid;
            if (relu_stage_ready)
                relu_valid <= max_valid;
            if (max_stage_ready)
                max_valid <= in_valid;
        end
    end

endmodule
