`timescale 1ns/1ps

// Fixed-shape two-convolution-layer MNIST Winograd accelerator.
//
//   image stream -> Conv1 -> lifetime-reused frame storage -> Conv2
//                -> packed reused storage -> FC -> argmax -> decision
//
// Reset starts a new image. The external adapter supplies exactly 784 UINT8
// pixels in raster order. Final features are emitted in NCHW flatten order,
// matching the exported FC weight layout.
module winograd_cnn_accelerator #(

    // Numeric formats fixed by model training and integer export.
    parameter integer ACT_BITS    = 8,
    parameter integer WEIGHT_BITS = 4,
    parameter integer BIAS_BITS   = 16,
    parameter integer MULT_BITS   = 24,

    // Elastic buffering selected from the Conv1 producer/consumer rate.
    parameter integer CONV1_TILE_FIFO_DEPTH = 2,
    parameter integer V_REPLAY_GROUP_DEPTH = 2,
    parameter integer M_FIFO_DEPTH = 1
) (
    input  wire                         clk,
    input  wire                         rst_n,

    // UINT8 raster-image stream with ready/valid handshake.
    input  wire                         image_valid,
    output wire                         image_ready,
    input  wire [ACT_BITS-1:0]          image_pixel,

    input  wire [3*1*16*WEIGHT_BITS-1:0] conv1_u_bank,
    input  wire [3*3*16*WEIGHT_BITS-1:0] conv2_u_bank,
    input  wire [3*BIAS_BITS-1:0]        conv1_bias_bank,
    input  wire [3*BIAS_BITS-1:0]        conv2_bias_bank,
    input  wire [MULT_BITS-1:0]          conv1_requant_multiplier,
    input  wire [MULT_BITS-1:0]          conv2_requant_multiplier,
    input  wire [10*75*WEIGHT_BITS-1:0]  fc_weight_bank,
    input  wire [10*BIAS_BITS-1:0]       fc_bias_bank,

    output wire                         feature_valid,
    input  wire                         feature_ready,
    output wire [ACT_BITS-1:0]          feature_data,
    output wire [6:0]                   feature_index,
    output wire                         feature_last,
    output reg  [3:0]                   decision,
    output reg                          decision_valid,
    output wire                         busy
);

    localparam [3:0] START_CONV1 = 4'd1;
    localparam [3:0] RUN_CONV1 = 4'd2;
    localparam [3:0] START_CONV2 = 4'd3;
    localparam [3:0] RUN_CONV2 = 4'd4;
    localparam [3:0] STREAM_FEATURES = 4'd5;
    localparam [3:0] START_FC = 4'd6;
    localparam [3:0] RUN_FC = 4'd7;
    localparam [3:0] COMPLETE = 4'd8;

    reg [3:0] state;  // Current accelerator state.
    // Number of transferred scalar convolution outputs across all channels.
    reg [8:0] conv_output_count;
    // Spatial output position; advances after all three channels transfer.
    reg [7:0] spatial_index;
    // Current feature index (0-74), reused for feature streaming and FC.
    reg [6:0] feature_read_index;

    wire bank_a_start_ready;
    wire bank_a_busy;
    wire bank_a_done;
    wire bank_a_tile_valid;
    wire bank_a_tile_ready;
    wire [16*ACT_BITS-1:0] bank_a_tile;
    wire bank_a_tile_last;
    wire bank_a_raw_tile_valid;
    wire bank_a_raw_tile_ready;
    wire [16*ACT_BITS-1:0] bank_a_raw_tile;
    wire [ACT_BITS-1:0] feature_byte_data;
    wire image_window_ready;

    wire bank_b_start_ready;
    wire bank_b_busy;
    wire bank_b_done;
    wire bank_b_tile_valid;
    wire bank_b_tile_ready;
    wire [16*ACT_BITS-1:0] bank_b_tile;
    wire bank_b_tile_last;
    wire bank_b_window_input_ready;

    wire b_frame_write_ready;
    wire b_frame_full;
    wire b_frame_read_start_ready;
    wire b_frame_read_valid;
    wire b_frame_read_ready;
    wire [3*ACT_BITS-1:0] b_frame_read_data;
    wire b_frame_write_valid;
    wire [3*ACT_BITS-1:0] b_frame_write_data;
    reg [ACT_BITS-1:0] conv1_channel0;
    reg [ACT_BITS-1:0] conv1_channel1;
    // Conv2 valid convolution followed by 2x2 pooling only consumes the
    // upper-left 12x12 region of the 13x13 Conv1 result.  Track the original
    // Conv1 raster position so the unused last row and column can be dropped
    // without introducing a random-address memory.
    reg [3:0] conv1_output_row;
    reg [3:0] conv1_output_col;
    reg [5:0] conv2_prefill_count;
    wire conv1_spatial_needed;
    wire conv2_prefill_active;
    wire conv2_prefill_valid;

    wire core_in_valid;
    wire core_in_ready;
    wire [16*ACT_BITS-1:0] core_activation_tile;
    wire core_out_valid;
    wire core_out_ready;
    wire [ACT_BITS-1:0] core_activation;
    wire [1:0] core_output_channel;
    wire core_output_transfer;
    wire core_mode_fc;
    wire fc_in_ready;
    wire fc_input_transfer;
    wire fc_result_valid;
    wire [16*18-1:0] fc_result_vec;
    wire [10*WEIGHT_BITS-1:0] selected_fc_weights;
    wire argmax_in_ready;
    wire argmax_valid;
    wire [3:0] argmax_index;
    reg [ACT_BITS-1:0] conv2_channel0;
    reg [ACT_BITS-1:0] conv2_channel1;
    reg [4:0] feature_word_index;
    reg [1:0] feature_channel_index;
    wire conv2_feature_write_valid;
    wire [3*ACT_BITS-1:0] conv2_feature_write_data;

    function [3*3*16*WEIGHT_BITS-1:0] expand_conv1_weights;
        input [3*1*16*WEIGHT_BITS-1:0] compact;
        integer kernel;
        begin
            expand_conv1_weights = {(3*3*16*WEIGHT_BITS){1'b0}};
            for (kernel = 0; kernel < 3; kernel = kernel + 1)
                expand_conv1_weights[(kernel*3)*16*WEIGHT_BITS
                                     +: 16*WEIGHT_BITS]
                    = compact[kernel*16*WEIGHT_BITS +: 16*WEIGHT_BITS];
        end
    endfunction

    wire [3*3*16*WEIGHT_BITS-1:0] selected_u_bank;
    wire [3*BIAS_BITS-1:0] selected_bias_bank;
    wire [MULT_BITS-1:0] selected_multiplier;
    assign selected_u_bank = (state == START_CONV2 || state == RUN_CONV2)
                           ? conv2_u_bank : expand_conv1_weights(conv1_u_bank);
    assign selected_bias_bank = (state == START_CONV2 || state == RUN_CONV2)
                              ? conv2_bias_bank : conv1_bias_bank;
    assign selected_multiplier = (state == START_CONV2 || state == RUN_CONV2)
                               ? conv2_requant_multiplier
                               : conv1_requant_multiplier;

    assign image_ready = (state == RUN_CONV1) && image_window_ready;
    assign feature_valid = (state == STREAM_FEATURES);
    assign feature_data = feature_byte_data;
    assign feature_index = feature_read_index;
    assign feature_last = feature_read_index == 7'd74;
    assign busy = state != COMPLETE;
    assign core_mode_fc = (state == START_FC) || (state == RUN_FC);

    genvar fc_class;
    generate
        for (fc_class = 0; fc_class < 10; fc_class = fc_class + 1) begin : g_fc_weight
            assign selected_fc_weights[fc_class*WEIGHT_BITS +: WEIGHT_BITS] =
                fc_weight_bank[(fc_class*75*WEIGHT_BITS)
                               + feature_read_index*WEIGHT_BITS
                               +: WEIGHT_BITS];
        end
    endgenerate

    assign fc_input_transfer = (state == RUN_FC) && fc_in_ready;

    assign feature_byte_data =
        (feature_channel_index == 2'd0)
        ? b_frame_read_data[ACT_BITS-1:0]
        : (feature_channel_index == 2'd1)
          ? b_frame_read_data[2*ACT_BITS-1:ACT_BITS]
          : b_frame_read_data[3*ACT_BITS-1:2*ACT_BITS];

    assign conv1_spatial_needed = (conv1_output_row < 4'd12)
                                && (conv1_output_col < 4'd12);
    // The first 40 useful Conv1 vectors are exactly the first 4x4 Conv2
    // window. Stream them directly into the Conv2 window generator while
    // Conv1 owns the shared core. The completed tile then waits at the
    // generator output, so only the remaining 104 vectors need frame storage.
    assign conv2_prefill_active = conv1_spatial_needed
                                && (conv2_prefill_count < 6'd40);
    assign conv2_prefill_valid = (state == RUN_CONV1)
                               && core_out_valid
                               && (core_output_channel == 2'd2)
                               && conv2_prefill_active;
    assign b_frame_write_valid = (state == RUN_CONV1)
                               && core_output_transfer
                               && (core_output_channel == 2'd2)
                               && conv1_spatial_needed
                               && !conv2_prefill_active;
    assign b_frame_write_data =
        {core_activation, conv1_channel1, conv1_channel0};

    winograd_sliding_window_generator #(
        .ACT_BITS(ACT_BITS),
        .CHANNELS(1),
        .CHANNEL_BITS(2),
        .FEATURE_WIDTH(28),
        .FEATURE_HEIGHT(28),
        .POSITION_BITS(5),
        .TILE_ROWS(13),
        .TILE_COLS(13),
        .TILE_INDEX_BITS(4)
    ) u_conv1_window_generator (
        .clk(clk),
        .rst_n(rst_n),
        .start(state == START_CONV1),
        .start_ready(bank_a_start_ready),
        .busy(bank_a_busy),
        .done(bank_a_done),
        .in_valid(image_valid && (state == RUN_CONV1)),
        .in_ready(image_window_ready),
        .pixel_vector(image_pixel),
        .out_valid(bank_a_raw_tile_valid),
        .out_ready(bank_a_raw_tile_ready),
        .activation_tile(bank_a_raw_tile),
        .output_input_channel(),
        .output_tile_row(),
        .output_tile_col(),
        .output_last(bank_a_tile_last)
    );

    // The competition input has no ready signal and supplies one raster pixel
    // every cycle. Tile production is bursty within odd rows, while the shared
    // core consumes tiles at a steadier rate. This small FIFO absorbs that
    // short-term mismatch without restoring the 784-byte random-read Bank A.
    elastic_fifo #(
        .DATA_WIDTH(16*ACT_BITS),
        .DEPTH(CONV1_TILE_FIFO_DEPTH)
    ) u_conv1_tile_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(bank_a_raw_tile_valid),
        .in_ready(bank_a_raw_tile_ready),
        .in_data(bank_a_raw_tile),
        .out_valid(bank_a_tile_valid),
        .out_ready(bank_a_tile_ready),
        .out_data(bank_a_tile),
        .full(),
        .empty()
    );

    assign conv2_feature_write_valid = (state == RUN_CONV2)
                                     && core_output_transfer
                                     && (core_output_channel == 2'd2);
    assign conv2_feature_write_data =
        {core_activation, conv2_channel1, conv2_channel0};

    winograd_sequential_frame_buffer #(
        .DATA_BITS(3*ACT_BITS),
        .DEPTH(104),
        .ADDR_BITS(8)
    ) u_conv1_output_frame_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .write_clear(state == START_CONV1),
        .write_valid(b_frame_write_valid),
        .write_ready(b_frame_write_ready),
        .write_data(b_frame_write_data),
        .full(b_frame_full),
        .read_start(state == START_CONV2),
        .read_start_ready(b_frame_read_start_ready),
        .read_valid(b_frame_read_valid),
        .read_ready(b_frame_read_ready),
        .read_data(b_frame_read_data),
        .reuse_write_valid(conv2_feature_write_valid),
        .reuse_write_address({3'd0, spatial_index[4:0]}),
        .reuse_write_data(conv2_feature_write_data),
        .reuse_read_select((state == STREAM_FEATURES)
                           || (state == START_FC)
                           || (state == RUN_FC)),
        .reuse_read_address({3'd0, feature_word_index})
    );

    assign b_frame_read_ready = (state == RUN_CONV2)
                              && bank_b_window_input_ready;

    winograd_sliding_window_generator #(
        .ACT_BITS(ACT_BITS),
        .CHANNELS(3),
        .CHANNEL_BITS(2),
        .FEATURE_WIDTH(12),
        .FEATURE_HEIGHT(12),
        .POSITION_BITS(4),
        .TILE_ROWS(5),
        .TILE_COLS(5),
        .TILE_INDEX_BITS(4)
    ) u_conv2_window_generator (
        .clk(clk),
        .rst_n(rst_n),
        .start(state == START_CONV1),
        .start_ready(bank_b_start_ready),
        .busy(bank_b_busy),
        .done(bank_b_done),
        .in_valid(conv2_prefill_valid
                  || (b_frame_read_valid && (state == RUN_CONV2))),
        .in_ready(bank_b_window_input_ready),
        .pixel_vector((state == RUN_CONV1)
                      ? b_frame_write_data : b_frame_read_data),
        .out_valid(bank_b_tile_valid),
        .out_ready(bank_b_tile_ready),
        .activation_tile(bank_b_tile),
        .output_input_channel(),
        .output_tile_row(),
        .output_tile_col(),
        .output_last(bank_b_tile_last)
    );

    assign core_in_valid = (state == RUN_CONV1) ? bank_a_tile_valid
                         : (state == RUN_CONV2) ? bank_b_tile_valid
                         : 1'b0;
    assign core_activation_tile = (state == RUN_CONV2)
                                ? bank_b_tile : bank_a_tile;
    assign bank_a_tile_ready = (state == RUN_CONV1) && core_in_ready;
    assign bank_b_tile_ready = (state == RUN_CONV2) && core_in_ready;
    assign core_out_ready = (state == RUN_CONV1)
                          ? ((core_output_channel != 2'd2)
                             || !conv1_spatial_needed
                             // Before the 40th prefill transfer the Conv2
                             // generator cannot hold an output tile, so its
                             // input is guaranteed available. Using this
                             // static schedule avoids a combinational ready
                             // loop through the shared core pipeline.
                             || (conv2_prefill_active
                                 ? 1'b1 : b_frame_write_ready))
                          : (state == RUN_CONV2);
    assign core_output_transfer = core_out_valid && core_out_ready;

    winograd_conv_core #(
        .V_REPLAY_GROUP_DEPTH(V_REPLAY_GROUP_DEPTH),
        .M_FIFO_DEPTH(M_FIFO_DEPTH)
    ) u_core (
        .clk(clk),
        .rst_n(rst_n),
        .mode_fc(core_mode_fc),
        .input_channels_minus1((state == START_CONV2 || state == RUN_CONV2)
                              ? 2'd2 : 2'd0),
        .output_channels_minus1(2'd2),
        .u_weight_bank(selected_u_bank),
        .bias_bank(selected_bias_bank),
        .requant_multiplier(selected_multiplier),
        .in_valid(core_in_valid),
        .in_ready(core_in_ready),
        .activation_tile(core_activation_tile),
        .out_valid(core_out_valid),
        .out_ready(core_out_ready),
        .activation(core_activation),
        .output_channel(core_output_channel),
        .fc_in_valid(state == RUN_FC),
        .fc_in_ready(fc_in_ready),
        .fc_activation(feature_byte_data),
        .fc_weight_vec(selected_fc_weights),
        .fc_bias_vec(fc_bias_bank),
        .fc_txn_first(feature_read_index == 7'd0),
        .fc_txn_last(feature_read_index == 7'd74),
        .fc_result_valid(fc_result_valid),
        .fc_result_ready(argmax_in_ready),
        .fc_result_vec(fc_result_vec)
    );

    pipelined_argmax10 u_argmax (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(fc_result_valid),
        .in_ready(argmax_in_ready),
        .values(fc_result_vec[10*18-1:0]),
        .out_valid(argmax_valid),
        .out_index(argmax_index)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= START_CONV1;
            conv_output_count   <= 9'd0;
            spatial_index       <= 8'd0;
            feature_read_index  <= 7'd0;
            decision            <= 4'd0;
            decision_valid      <= 1'b0;
            conv1_channel0      <= {ACT_BITS{1'b0}};
            conv1_channel1      <= {ACT_BITS{1'b0}};
            conv1_output_row    <= 4'd0;
            conv1_output_col    <= 4'd0;
            conv2_prefill_count <= 6'd0;
            conv2_channel0      <= {ACT_BITS{1'b0}};
            conv2_channel1      <= {ACT_BITS{1'b0}};
            feature_word_index  <= 5'd0;
            feature_channel_index <= 2'd0;
        end else begin
            decision_valid <= 1'b0;
            if ((state == RUN_CONV1) && core_output_transfer) begin
                if (core_output_channel == 2'd0)
                    conv1_channel0 <= core_activation;
                else if (core_output_channel == 2'd1)
                    conv1_channel1 <= core_activation;
            end
            if ((state == RUN_CONV2) && core_output_transfer) begin
                if (core_output_channel == 2'd0)
                    conv2_channel0 <= core_activation;
                else if (core_output_channel == 2'd1)
                    conv2_channel1 <= core_activation;
            end
            case (state)
                START_CONV1: begin
                    if (bank_a_start_ready && bank_b_start_ready) begin
                        conv_output_count <= 9'd0;
                        spatial_index <= 8'd0;
                        conv1_output_row <= 4'd0;
                        conv1_output_col <= 4'd0;
                        conv2_prefill_count <= 6'd0;
                        state <= RUN_CONV1;
                    end
                end

                RUN_CONV1: begin
                    if (core_output_transfer) begin
                        if (core_output_channel == 2'd2) begin
                            spatial_index <= spatial_index + 1'b1;
                            if (conv2_prefill_active)
                                conv2_prefill_count <=
                                    conv2_prefill_count + 1'b1;
                            if (conv1_output_col == 4'd12) begin
                                conv1_output_col <= 4'd0;
                                conv1_output_row <= conv1_output_row + 1'b1;
                            end else begin
                                conv1_output_col <= conv1_output_col + 1'b1;
                            end
                        end
                        if (conv_output_count == 9'd506) begin
                            conv_output_count <= 9'd0;
                            spatial_index <= 8'd0;
                            state <= START_CONV2;
                        end else begin
                            conv_output_count <= conv_output_count + 1'b1;
                        end
                    end
                end

                START_CONV2: begin
                    if (b_frame_read_start_ready) begin
                        conv_output_count <= 9'd0;
                        spatial_index <= 8'd0;
                        state <= RUN_CONV2;
                    end
                end

                RUN_CONV2: begin
                    if (core_output_transfer) begin
                        if (core_output_channel == 2'd2)
                            spatial_index <= spatial_index + 1'b1;
                        if (conv_output_count == 9'd74) begin
                            feature_read_index <= 7'd0;
                            feature_word_index <= 5'd0;
                            feature_channel_index <= 2'd0;
                            state <= STREAM_FEATURES;
                        end else begin
                            conv_output_count <= conv_output_count + 1'b1;
                        end
                    end
                end

                STREAM_FEATURES: begin
                    if (feature_valid && feature_ready) begin
                        if (feature_read_index == 7'd74)
                            state <= START_FC;
                        else begin
                            feature_read_index <= feature_read_index + 1'b1;
                            if (feature_word_index == 5'd24) begin
                                feature_word_index <= 5'd0;
                                feature_channel_index <=
                                    feature_channel_index + 1'b1;
                            end else begin
                                feature_word_index <= feature_word_index + 1'b1;
                            end
                        end
                    end
                end

                START_FC: begin
                    feature_read_index <= 7'd0;
                    feature_word_index <= 5'd0;
                    feature_channel_index <= 2'd0;
                    state <= RUN_FC;
                end

                RUN_FC: begin
                    if (fc_input_transfer && feature_read_index != 7'd74) begin
                        feature_read_index <= feature_read_index + 1'b1;
                        if (feature_word_index == 5'd24) begin
                            feature_word_index <= 5'd0;
                            feature_channel_index <=
                                feature_channel_index + 1'b1;
                        end else begin
                            feature_word_index <= feature_word_index + 1'b1;
                        end
                    end
                    if (argmax_valid) begin
                        decision <= argmax_index;
                        decision_valid <= 1'b1;
                        state <= COMPLETE;
                    end
                end

                default: state <= COMPLETE;
            endcase
        end
    end

endmodule
