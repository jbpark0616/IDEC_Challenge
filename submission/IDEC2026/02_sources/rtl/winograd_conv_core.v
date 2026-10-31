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
    wire [3:0] transform_zero_rows;
    // Matched ablation: a zero mask disables row compression and allows all
    // channels to reach the unchanged arithmetic pipeline. Synthesis removes
    // the now-unused detector and constant zero-mask storage.
    wire [3:0] replay_zero_rows;
    assign replay_zero_rows = transform_zero_rows;



    winograd_input_transform u_input_transform (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .activation_tile(activation_tile),
        .out_valid(transform_valid),
        .out_ready(transform_ready),
        .v_tile(transform_v),
        .zero_rows(transform_zero_rows)
    );

    wire v_valid;
    wire v_ready;
    wire [V_TILE_BITS-1:0] v_tile;
    wire [4*CHANNEL_BITS-1:0] v_input_channels;
    wire [4*MAX_INPUT_CHANNELS-1:0] v_channel_select;
    wire [3:0] v_row_enable;
    wire [CHANNEL_BITS-1:0] v_output_channel;
    wire v_txn_first;
    wire v_txn_last;

    winograd_v_replay_buffer #(
        .GROUP_DEPTH(V_REPLAY_GROUP_DEPTH),
        .V_TILE_BITS(V_TILE_BITS),
        .MAX_INPUT_CHANNELS(MAX_INPUT_CHANNELS),
        .CHANNEL_BITS(CHANNEL_BITS)
    ) u_v_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .input_channels_minus1(input_channels_minus1),
        .output_channels_minus1(output_channels_minus1),
        .in_valid(transform_valid),
        .in_ready(transform_ready),
        .in_v_tile(transform_v),
        .in_zero_rows(replay_zero_rows),
        .out_valid(v_valid),
        .out_ready(v_ready),
        .out_v_tile(v_tile),
        .input_channels(v_input_channels),
        .channel_select(v_channel_select),
        .row_enable(v_row_enable),
        .output_channel(v_output_channel),
        .txn_first(v_txn_first),
        .txn_last(v_txn_last),
        .full(),
        .empty()
    );

    reg [U_TILE_BITS-1:0] selected_u;
    integer wr, wk, wc;
    always @* begin
        selected_u = 0;
        for (wr=0; wr<4; wr=wr+1)
            for (wk=0; wk<MAX_OUTPUT_CHANNELS; wk=wk+1)
                for (wc=0; wc<MAX_INPUT_CHANNELS; wc=wc+1)
                    selected_u[wr*4*WEIGHT_BITS +: 4*WEIGHT_BITS] =
                        selected_u[wr*4*WEIGHT_BITS +: 4*WEIGHT_BITS] |
                        ({(4*WEIGHT_BITS){(v_output_channel==wk) &&
                           v_channel_select[wr*MAX_INPUT_CHANNELS+wc]}} &
                         u_weight_bank[(wk*MAX_INPUT_CHANNELS+wc)*U_TILE_BITS+
                                       wr*4*WEIGHT_BITS +: 4*WEIGHT_BITS]);
    end

    wire mac_valid;
    wire mac_input_ready;
    wire conv_mac_ready;
    wire [M_TILE_BITS-1:0] mac_result;

    // Whole-zero jobs have no MAC transaction at all. Both normal jobs and
    // bypass jobs enqueue one small ordering descriptor. Normal results pass
    // through MAC/M FIFO/output-transform; zero descriptors join directly at
    // postprocess. The descriptor FIFO prevents either path from overtaking
    // the other without draining the arithmetic pipeline at every transition.
    wire v_zero_job = v_txn_first && !(|v_row_enable);

    wire order_in_ready;
    wire conv_issue_valid = v_valid && !v_zero_job
                          && (!v_txn_last || order_in_ready) && !mode_fc;
    assign v_ready = !mode_fc && (v_zero_job ? order_in_ready
                    : (mac_input_ready && (!v_txn_last || order_in_ready)));
    assign fc_in_ready = mode_fc && mac_input_ready;
    assign fc_result_valid = mode_fc && mac_valid;
    assign fc_result_vec = mac_result;

    winograd_mac_array u_mac (
        .clk(clk),
        .rst_n(rst_n),
        .mode_fc(mode_fc),
        .in_valid(mode_fc ? fc_in_valid : conv_issue_valid),
        .in_ready(mac_input_ready),
        .txn_first(mode_fc ? fc_txn_first : v_txn_first),
        .txn_last(mode_fc ? fc_txn_last : v_txn_last),
        .conv_row_enable(v_row_enable),
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

    wire order_valid;
    wire order_ready;
    wire order_zero;
    wire bypass_transfer = v_valid && v_ready && v_zero_job;
    // k always cycles 0..K-1 for BOTH paths. Store only the path bit; derive k
    // at dequeue rather than storing the same deterministic sequence 8 times.
    reg [CHANNEL_BITS-1:0] completed_channel;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) completed_channel <= 0;
        else if (order_valid && order_ready) begin
            if (completed_channel == output_channels_minus1) completed_channel <= 0;
            else completed_channel <= completed_channel + 1'b1;
        end
    end
    elastic_fifo #(.DATA_WIDTH(1), .DEPTH(8)) u_order_fifo (
        .clk(clk), .rst_n(rst_n),
        .in_valid(v_valid && v_ready && v_txn_last),
        .in_ready(order_in_ready),
        .in_data(v_zero_job),
        .out_valid(order_valid), .out_ready(order_ready),
        .out_data(order_zero), .full(), .empty()
    );


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
        // The ordering descriptor carries k for both paths. This unused tag
        // is constant and synthesis removes its storage/arithmetic.
        .in_output_channel({CHANNEL_BITS{1'b0}}),
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
    wire normal_y_valid;
    wire normal_y_ready;
    wire [4*ACC_BITS-1:0] normal_y_tile;

    assign y_valid = order_valid && (order_zero || normal_y_valid);
    assign y_tile = order_zero ? {4*ACC_BITS{1'b0}} : normal_y_tile;
    assign y_output_channel = completed_channel;
    assign order_ready = y_ready && (order_zero || normal_y_valid);
    assign normal_y_ready = y_ready && order_valid && !order_zero;

    winograd_output_transform u_output_transform (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(m_valid),
        .in_ready(m_ready),
        .m_tile(m_tile),
        .in_user(m_output_channel),
        .out_valid(normal_y_valid),
        .out_ready(normal_y_ready),
        .y_tile(normal_y_tile),
        .out_user()
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
