`timescale 1ps/1ps

// Competition wrapper for the INT4 F(2x2,3x3) Winograd accelerator.
//
// Pixels follow the reference harness contract: one UINT8 raster pixel per
// cycle, with no input valid/ready pins. Static model tensors are supplied by
// an external ROM/testbench through conventional descending packed vectors.
module chip #(
    parameter integer CONV1_TILE_FIFO_DEPTH = 2,
    parameter integer V_REPLAY_GROUP_DEPTH = 2,
    parameter integer M_FIFO_DEPTH = 1
) (

    // chip interface
    input  wire          clk,
    input  wire          rst_n,     // active-low reset
    input  wire [7:0]    data_in,
    output wire [3:0]    decision,
    output wire          valid_out_6,

    // model tensors
    input  wire [191:0]  conv1_u,
    input  wire [575:0]  conv2_u,
    // model biases and requantization multipliers
    input  wire [47:0]   conv1_bias,
    input  wire [47:0]   conv2_bias,
    input  wire [23:0]   conv1_requant_multiplier,
    input  wire [23:0]   conv2_requant_multiplier,
    // model fully-connected layer weights and biases
    input  wire [2999:0] fc_weight,
    input  wire [159:0]  fc_bias
);

    wire image_ready;
    wire feature_valid;
    wire [7:0] feature_data;
    wire [6:0] feature_index;
    wire feature_last;
    wire controller_busy;
    reg [9:0] pixel_count;

    // The first pixel is held by the reference testbench while the controller
    // moves through START_CONV1. Thereafter the tile FIFO keeps image_ready
    // asserted for the complete 784-cycle raster stream.
    wire image_valid;
    assign image_valid = (pixel_count < 10'd784) && image_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pixel_count <= 10'd0;
        else if (image_valid)
            pixel_count <= pixel_count + 1'b1;
    end

    winograd_cnn_accelerator #(
        .CONV1_TILE_FIFO_DEPTH(CONV1_TILE_FIFO_DEPTH),
        .V_REPLAY_GROUP_DEPTH(V_REPLAY_GROUP_DEPTH),
        .M_FIFO_DEPTH(M_FIFO_DEPTH)
    ) u_accelerator (
        .clk(clk),
        .rst_n(rst_n),
        .image_valid(image_valid),
        .image_ready(image_ready),
        .image_pixel(data_in),
        .conv1_u_bank(conv1_u),
        .conv2_u_bank(conv2_u),
        .conv1_bias_bank(conv1_bias),
        .conv2_bias_bank(conv2_bias),
        .conv1_requant_multiplier(conv1_requant_multiplier),
        .conv2_requant_multiplier(conv2_requant_multiplier),
        .fc_weight_bank(fc_weight),
        .fc_bias_bank(fc_bias),
        .feature_valid(feature_valid),
        .feature_ready(1'b1),
        .feature_data(feature_data),
        .feature_index(feature_index),
        .feature_last(feature_last),
        .decision(decision),
        .decision_valid(valid_out_6),
        .busy(controller_busy)
    );

endmodule
