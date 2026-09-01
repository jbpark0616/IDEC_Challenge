`timescale 1ns/1ps

// Integrated F(2x2, 3x3) convolution core for the fixed MNIST channel limits.
// One input transaction is a 4x4 UINT8 tile for one input channel. Channels
// for the same spatial tile must arrive consecutively in c=0..C-1 order.
// One output transaction is the fused pooled UINT8 activation for one output
// channel, accompanied by its channel index.
module winograd_conv_core #(
    parameter integer MAX_INPUT_CHANNELS  = 3,
    parameter integer MAX_OUTPUT_CHANNELS = 3,
    parameter integer CHANNEL_BITS        = 2,
    parameter integer ACT_BITS            = 8,
    parameter integer V_BITS              = 11,
    parameter integer WEIGHT_BITS         = 4,
    parameter integer ACC_BITS            = 18,
    parameter integer BIAS_BITS           = 16,
    parameter integer MULT_BITS           = 24,
    parameter integer V_REPLAY_GROUP_DEPTH = 2,
    parameter integer M_FIFO_DEPTH         = 1
) (
    input  wire clk,
    input  wire rst_n,

    // The shared 16-lane MAC can be switched to FC mode only after the
    // convolution pipeline has drained.
    input  wire                         mode_fc,

    // Static layer configuration. Change only after the pipeline is drained.
    input  wire [CHANNEL_BITS-1:0] input_channels_minus1,
    input  wire [CHANNEL_BITS-1:0] output_channels_minus1,
    input  wire [MAX_OUTPUT_CHANNELS*MAX_INPUT_CHANNELS*16*WEIGHT_BITS-1:0]
                                          u_weight_bank,
    input  wire [MAX_OUTPUT_CHANNELS*BIAS_BITS-1:0] bias_bank,
    input  wire [MULT_BITS-1:0]         requant_multiplier,

    input  wire                         in_valid,
    output wire                         in_ready,
    input  wire [16*ACT_BITS-1:0]       activation_tile,

    output wire                         out_valid,
    input  wire                         out_ready,
    output wire [ACT_BITS-1:0]          activation,
    output wire [CHANNEL_BITS-1:0]      output_channel,

    input  wire                         fc_in_valid,
    output wire                         fc_in_ready,
    input  wire [ACT_BITS-1:0]          fc_activation,
    input  wire [10*WEIGHT_BITS-1:0]    fc_weight_vec,
    input  wire [10*BIAS_BITS-1:0]      fc_bias_vec,
    input  wire                         fc_txn_first,
    input  wire                         fc_txn_last,
    output wire                         fc_result_valid,
    input  wire                         fc_result_ready,
    output wire [16*ACC_BITS-1:0]       fc_result_vec
);

    localparam integer V_TILE_BITS = 16*V_BITS;
    localparam integer U_TILE_BITS = 16*WEIGHT_BITS;
    localparam integer M_TILE_BITS = 16*ACC_BITS;

    wire transform_valid;
    wire transform_ready;
    wire [V_TILE_BITS-1:0] transform_v;

    winograd_input_transform u_input_transform (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .activation_tile(activation_tile),
        .out_valid(transform_valid),
        .out_ready(transform_ready),
        .v_tile(transform_v)
    );

    wire v_valid;
    wire v_ready;
    wire [V_TILE_BITS-1:0] v_tile;
    wire [CHANNEL_BITS-1:0] v_input_channel;
    wire [CHANNEL_BITS-1:0] v_output_channel;
    wire v_txn_first;
    wire v_txn_last;

    winograd_v_replay_buffer #(
        .GROUP_DEPTH(V_REPLAY_GROUP_DEPTH)
    ) u_v_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .input_channels_minus1(input_channels_minus1),
        .output_channels_minus1(output_channels_minus1),
        .in_valid(transform_valid),
        .in_ready(transform_ready),
        .in_v_tile(transform_v),
        .out_valid(v_valid),
        .out_ready(v_ready),
        .out_v_tile(v_tile),
        .input_channel(v_input_channel),
        .output_channel(v_output_channel),
        .txn_first(v_txn_first),
        .txn_last(v_txn_last),
        .full(),
        .empty()
    );

    wire [U_TILE_BITS-1:0] selected_u;
    wire [CHANNEL_BITS*2-1:0] u_bank_index;
    assign u_bank_index = v_output_channel*MAX_INPUT_CHANNELS + v_input_channel;
    assign selected_u = u_weight_bank[u_bank_index*U_TILE_BITS +: U_TILE_BITS];

    wire mac_valid;
    wire mac_input_ready;
    wire conv_mac_ready;
    wire [M_TILE_BITS-1:0] mac_result;

    assign v_ready = mode_fc ? 1'b0 : mac_input_ready;
    assign fc_in_ready = mode_fc && mac_input_ready;
    assign fc_result_valid = mode_fc && mac_valid;
    assign fc_result_vec = mac_result;

    winograd_mac_array u_mac (
        .clk(clk),
        .rst_n(rst_n),
        .mode_fc(mode_fc),
        .in_valid(mode_fc ? fc_in_valid : v_valid),
        .in_ready(mac_input_ready),
        .txn_first(mode_fc ? fc_txn_first : v_txn_first),
        .txn_last(mode_fc ? fc_txn_last : v_txn_last),
        .conv_operand_vec(v_tile),
        .conv_weight_vec(selected_u),
        .fc_activation(fc_activation),
        .fc_weight_vec(fc_weight_vec),
        .fc_bias_vec(fc_bias_vec),
        .out_valid(mac_valid),
        .out_ready(mode_fc ? fc_result_ready : conv_mac_ready),
        .result_vec(mac_result),
        .accumulator_vec()
    );

    // MAC results are produced in deterministic k=0..K-1 order. The counter
    // tags each completed M tile before the elastic FIFO decouples the stages.
    reg [CHANNEL_BITS-1:0] mac_output_channel;
    wire mac_result_transfer;
    assign mac_result_transfer = mac_valid & conv_mac_ready & (~mode_fc);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mac_output_channel <= {CHANNEL_BITS{1'b0}};
        else if (mac_result_transfer) begin
            if (mac_output_channel == output_channels_minus1)
                mac_output_channel <= {CHANNEL_BITS{1'b0}};
            else
                mac_output_channel <= mac_output_channel + 1'b1;
        end
    end

    wire m_valid;
    wire m_ready;
    wire [M_TILE_BITS-1:0] m_tile;
    wire [CHANNEL_BITS-1:0] m_output_channel;

    winograd_m_fifo #(
        .DEPTH(M_FIFO_DEPTH)
    ) u_m_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(mac_valid & (~mode_fc)),
        .in_ready(conv_mac_ready),
        .in_m_tile(mac_result),
        .in_output_channel(mac_output_channel),
        .out_valid(m_valid),
        .out_ready(m_ready),
        .out_m_tile(m_tile),
        .out_output_channel(m_output_channel),
        .full(),
        .empty()
    );

    wire y_valid;
    wire y_ready;
    wire [4*ACC_BITS-1:0] y_tile;
    wire [CHANNEL_BITS-1:0] y_output_channel;

    winograd_output_transform u_output_transform (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(m_valid),
        .in_ready(m_ready),
        .m_tile(m_tile),
        .in_user(m_output_channel),
        .out_valid(y_valid),
        .out_ready(y_ready),
        .y_tile(y_tile),
        .out_user(y_output_channel)
    );

    wire signed [BIAS_BITS-1:0] selected_bias;
    assign selected_bias =
        bias_bank[y_output_channel*BIAS_BITS +: BIAS_BITS];

    winograd_postprocess u_postprocess (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(y_valid),
        .in_ready(y_ready),
        .y_tile(y_tile),
        .bias(selected_bias),
        .requant_multiplier(requant_multiplier),
        .in_user(y_output_channel),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .activation(activation),
        .out_user(output_channel)
    );

endmodule
