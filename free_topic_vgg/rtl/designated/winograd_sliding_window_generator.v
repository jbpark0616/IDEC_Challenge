`timescale 1ns/1ps

// Raster-stream sliding-window generator for Winograd F(2x2, 3x3).
//
// One accepted input contains every channel at one spatial position. Three
// fixed line delays and three horizontal history registers per row form the
// overlapping 4x4 window without random feature-memory reads. For a
// multi-channel pixel, a separate output holding stage delivers channel
// slices. Line/window updates and input handshakes retain their original timing.
module winograd_sliding_window_generator #(
    parameter integer EXTERNAL_LINES = 0,
    // SRAM-CB path: consume each channel directly from the held raster window.
    // Do not duplicate every channel into a pending_tile FF array.
    parameter integer STREAM_TILE = 0,
    parameter integer RUNTIME_CHANNELS = 0,
    parameter RUNTIME_SHAPE = 1'b0,
    parameter integer ACT_BITS        = 8,
    parameter integer CHANNELS        = 1,
    parameter integer CHANNEL_BITS    = 2,
    parameter integer FEATURE_WIDTH   = 28,
    parameter integer FEATURE_HEIGHT  = 28,
    parameter integer POSITION_BITS   = 5,
    parameter integer TILE_ROWS       = 13,
    parameter integer TILE_COLS       = 13,
    parameter integer TILE_INDEX_BITS = 4
) (
    input  wire                              clk,
    input  wire                              rst_n,

    input  wire [CHANNEL_BITS-1:0] channel_count_minus1,
    // Optional bounds supplied by the layer controller; data path is unchanged.
    // Runtime widths require EXTERNAL_LINES: physical FF row delays stay fixed.
    input wire [POSITION_BITS-1:0] input_feature_height, input_feature_width,
    input wire [TILE_INDEX_BITS-1:0] input_tile_rows, input_tile_cols,
    input wire [CHANNELS*ACT_BITS-1:0] external_row0, external_row1, external_row2,
    input  wire                              start,
    output wire                              start_ready,
    output wire                              busy,
    output reg                               done,

    input  wire                              in_valid,
    output wire                              in_ready,
    input  wire [CHANNELS*ACT_BITS-1:0]      pixel_vector,

    output wire                              out_valid,
    input  wire                              out_ready,
    output wire [16*ACT_BITS-1:0]            activation_tile,
    output wire  [CHANNEL_BITS-1:0]           output_input_channel,
    output wire  [TILE_INDEX_BITS-1:0]        output_tile_row,
    output wire  [TILE_INDEX_BITS-1:0]        output_tile_col,
    output wire                              output_last
);

    localparam integer PIXEL_BITS = CHANNELS*ACT_BITS;
    localparam integer LAST_TILE_BOTTOM_ROW = 2*TILE_ROWS + 1;
    localparam integer LAST_TILE_RIGHT_COL  = 2*TILE_COLS + 1;
    wire [POSITION_BITS-1:0] feature_height = RUNTIME_SHAPE ? input_feature_height : FEATURE_HEIGHT[POSITION_BITS-1:0];
    wire [POSITION_BITS-1:0] feature_width = RUNTIME_SHAPE ? input_feature_width : FEATURE_WIDTH[POSITION_BITS-1:0];
    wire [TILE_INDEX_BITS-1:0] tile_rows = RUNTIME_SHAPE ? input_tile_rows : TILE_ROWS[TILE_INDEX_BITS-1:0];
    wire [TILE_INDEX_BITS-1:0] tile_cols = RUNTIME_SHAPE ? input_tile_cols : TILE_COLS[TILE_INDEX_BITS-1:0];
    wire [POSITION_BITS-1:0] last_bottom = RUNTIME_SHAPE ? (input_tile_rows*2+1) : LAST_TILE_BOTTOM_ROW[POSITION_BITS-1:0];
    wire [POSITION_BITS-1:0] last_right = RUNTIME_SHAPE ? (input_tile_cols*2+1) : LAST_TILE_RIGHT_COL[POSITION_BITS-1:0];

    wire line_clk;
    reg active;
    reg [POSITION_BITS-1:0] input_row;
    reg [POSITION_BITS-1:0] input_col;
    reg [TILE_INDEX_BITS-1:0] next_tile_row;
    reg [TILE_INDEX_BITS-1:0] next_tile_col;
    wire pending_spatial_last;

    // Fixed-depth shift registers implement delays of exactly one feature
    // row each. This avoids the variable-address read MUX of the reference
    // full-frame loader.
    // The last three columns from each of the four rows. The current input
    // and the three line-delay outputs provide the fourth column.
    reg [PIXEL_BITS-1:0] horizontal0 [0:2];
    reg [PIXEL_BITS-1:0] horizontal1 [0:2];
    reg [PIXEL_BITS-1:0] horizontal2 [0:2];
    reg [PIXEL_BITS-1:0] horizontal3 [0:2];

    wire [PIXEL_BITS-1:0] row0_new;
    wire [PIXEL_BITS-1:0] row1_new;
    wire [PIXEL_BITS-1:0] row2_new;
    wire [PIXEL_BITS-1:0] row3_new;
    assign row3_new = pixel_vector;
    generate if (EXTERNAL_LINES) begin : g_sram_lines
        assign row0_new = external_row0;
        assign row1_new = external_row1;
        assign row2_new = external_row2;
    end else begin : g_ff_lines
        reg [PIXEL_BITS-1:0] line_delay1 [0:FEATURE_WIDTH-1];
        reg [PIXEL_BITS-1:0] line_delay2 [0:FEATURE_WIDTH-1];
        reg [PIXEL_BITS-1:0] line_delay3 [0:FEATURE_WIDTH-1];
        assign row0_new = line_delay3[FEATURE_WIDTH-1];
        assign row1_new = line_delay2[FEATURE_WIDTH-1];
        assign row2_new = line_delay1[FEATURE_WIDTH-1];
        integer i;
        always @(posedge line_clk) if (input_transfer) begin
            for (i=FEATURE_WIDTH-1; i>0; i=i-1) begin
                line_delay1[i] <= line_delay1[i-1];
                line_delay2[i] <= line_delay2[i-1];
                line_delay3[i] <= line_delay3[i-1];
            end
            line_delay1[0] <= pixel_vector;
            line_delay2[0] <= line_delay1[FEATURE_WIDTH-1];
            line_delay3[0] <= line_delay2[FEATURE_WIDTH-1];
        end
    end endgenerate

    reg [16*PIXEL_BITS-1:0] next_window;
    always @(*) begin
        next_window = {16*PIXEL_BITS{1'b0}};
        next_window[(0*4+0)*PIXEL_BITS +: PIXEL_BITS] = horizontal0[0];
        next_window[(0*4+1)*PIXEL_BITS +: PIXEL_BITS] = horizontal0[1];
        next_window[(0*4+2)*PIXEL_BITS +: PIXEL_BITS] = horizontal0[2];
        next_window[(0*4+3)*PIXEL_BITS +: PIXEL_BITS] = row0_new;
        next_window[(1*4+0)*PIXEL_BITS +: PIXEL_BITS] = horizontal1[0];
        next_window[(1*4+1)*PIXEL_BITS +: PIXEL_BITS] = horizontal1[1];
        next_window[(1*4+2)*PIXEL_BITS +: PIXEL_BITS] = horizontal1[2];
        next_window[(1*4+3)*PIXEL_BITS +: PIXEL_BITS] = row1_new;
        next_window[(2*4+0)*PIXEL_BITS +: PIXEL_BITS] = horizontal2[0];
        next_window[(2*4+1)*PIXEL_BITS +: PIXEL_BITS] = horizontal2[1];
        next_window[(2*4+2)*PIXEL_BITS +: PIXEL_BITS] = horizontal2[2];
        next_window[(2*4+3)*PIXEL_BITS +: PIXEL_BITS] = row2_new;
        next_window[(3*4+0)*PIXEL_BITS +: PIXEL_BITS] = horizontal3[0];
        next_window[(3*4+1)*PIXEL_BITS +: PIXEL_BITS] = horizontal3[1];
        next_window[(3*4+2)*PIXEL_BITS +: PIXEL_BITS] = horizontal3[2];
        next_window[(3*4+3)*PIXEL_BITS +: PIXEL_BITS] = row3_new;
    end

    // Raster generation ends at next_window. The output stage owns the
    // completed tile, channel cursor and downstream backpressure.
    wire output_capture_ready;
    wire [CHANNEL_BITS-1:0] last_channel_index = (RUNTIME_CHANNELS ? channel_count_minus1 : CHANNELS-1);
    generate if (!STREAM_TILE) begin : g_buffered_tile
    winograd_tile_output_buffer #(
        .ACT_BITS(ACT_BITS), .CHANNELS(CHANNELS),
        .CHANNEL_BITS(CHANNEL_BITS), .TILE_INDEX_BITS(TILE_INDEX_BITS)
    ) u_tile_output (
        .clk(clk), .rst_n(rst_n), .clear(start && start_ready),
        .channel_count_minus1(last_channel_index),
        .capture_valid(input_forms_tile), .capture_ready(output_capture_ready),
        .capture_window(next_window), .capture_row(next_tile_row), .capture_col(next_tile_col),
        .capture_last(next_tile_row == tile_rows-1'b1 && next_tile_col == tile_cols-1'b1),
        .out_valid(out_valid), .out_ready(out_ready), .activation_tile(activation_tile),
        .output_channel(output_input_channel), .output_row(output_tile_row), .output_col(output_tile_col),
        .spatial_last(pending_spatial_last), .output_last(output_last)
    );
    end else begin : g_stream_tile
        reg [CHANNEL_BITS-1:0] channel_cursor;
        assign output_input_channel = channel_cursor;
        assign output_tile_row = next_tile_row;
        assign output_tile_col = next_tile_col;
        assign pending_spatial_last = next_tile_row == tile_rows-1'b1
                                   && next_tile_col == tile_cols-1'b1;
        assign out_valid = active && in_valid && position_forms_tile;
        assign output_last = pending_spatial_last && channel_cursor == last_channel_index;
        assign output_capture_ready = 1'b1;
        genvar tile_lane;
        for (tile_lane=0; tile_lane<16; tile_lane=tile_lane+1) begin : g_lane
            if (CHANNELS == (1 << CHANNEL_BITS)) begin : g_full_channel_range
                // Select within one fixed spatial position, not the full window.
                wire [PIXEL_BITS-1:0] spatial_pixel =
                    next_window[tile_lane*PIXEL_BITS +: PIXEL_BITS];
                assign activation_tile[tile_lane*ACT_BITS +: ACT_BITS] =
                    spatial_pixel[channel_cursor*ACT_BITS +: ACT_BITS];
            end else begin : g_legacy_channel_range
                // Preserve out-of-range selection semantics for other parameters.
                assign activation_tile[tile_lane*ACT_BITS +: ACT_BITS] =
                    next_window[tile_lane*PIXEL_BITS+channel_cursor*ACT_BITS +: ACT_BITS];
            end
        end
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) channel_cursor <= 0;
            else if (start && start_ready) channel_cursor <= 0;
            else if (output_transfer)
                channel_cursor <= output_is_last_channel ? 0 : channel_cursor+1'b1;
        end
    end endgenerate

    wire output_is_last_channel;
    wire output_transfer;
    wire can_replace_output;
    wire input_transfer;
    wire input_forms_tile;

    assign output_is_last_channel =
        output_input_channel == (RUNTIME_CHANNELS ? channel_count_minus1 : CHANNELS-1);
    assign output_transfer = out_valid && out_ready;
    assign can_replace_output = output_transfer && output_is_last_channel
                              && !pending_spatial_last;
    // pending_window is independent of the line-buffer state. Accept a
    // pixel while replaying channels if it cannot overwrite a pending tile.
    wire position_forms_tile = (input_row >= 3) && (input_col >= 3)
                            && input_row[0] && input_col[0]
                            && (input_row <= last_bottom)
                            && (input_col <= last_right);
    // In stream mode the upstream line response and horizontal taps own the
    // window until its last channel transfers. SRAM V CB owns later reuse.
    assign in_ready = STREAM_TILE
                    ? active && (!position_forms_tile || (out_ready && output_is_last_channel))
                    : active && ((!out_valid) || can_replace_output
                          || (!pending_spatial_last && !position_forms_tile));
    assign input_transfer = in_valid && in_ready;

    assign input_forms_tile = input_transfer
                            && (input_row >= 3)
                            && (input_col >= 3)
                            && input_row[0]
                            && input_col[0]
                            && (input_row <= last_bottom)
                            && (input_col <= last_right);

    assign start_ready = !active && !out_valid;
    assign busy = active || out_valid;

    always @(posedge line_clk) begin
        if (input_transfer) begin
            horizontal0[0] <= horizontal0[1];
            horizontal0[1] <= horizontal0[2];
            horizontal0[2] <= row0_new;
            horizontal1[0] <= horizontal1[1];
            horizontal1[1] <= horizontal1[2];
            horizontal1[2] <= row1_new;
            horizontal2[0] <= horizontal2[1];
            horizontal2[1] <= horizontal2[2];
            horizontal2[2] <= row2_new;
            horizontal3[0] <= horizontal3[1];
            horizontal3[1] <= horizontal3[2];
            horizontal3[2] <= row3_new;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active                <= 1'b0;
            done                  <= 1'b0;
            input_row             <= {POSITION_BITS{1'b0}};
            input_col             <= {POSITION_BITS{1'b0}};
            next_tile_row         <= {TILE_INDEX_BITS{1'b0}};
            next_tile_col         <= {TILE_INDEX_BITS{1'b0}};
        end else begin
            done <= 1'b0;

            if (start && start_ready) begin
                active               <= 1'b1;
                input_row            <= {POSITION_BITS{1'b0}};
                input_col            <= {POSITION_BITS{1'b0}};
                next_tile_row        <= {TILE_INDEX_BITS{1'b0}};
                next_tile_col        <= {TILE_INDEX_BITS{1'b0}};
            end else begin
                if (output_transfer && output_last) begin
                    active <= 1'b0;
                    done <= 1'b1;
                end

                if (input_transfer) begin
                    if (input_col == feature_width-1'b1) begin
                        input_col <= {POSITION_BITS{1'b0}};
                        if (input_row != feature_height-1'b1)
                            input_row <= input_row + 1'b1;
                    end else begin
                        input_col <= input_col + 1'b1;
                    end

                    if (input_forms_tile) begin

                        if (next_tile_col == tile_cols-1'b1) begin
                            next_tile_col <= {TILE_INDEX_BITS{1'b0}};
                            if (next_tile_row != tile_rows-1'b1)
                                next_tile_row <= next_tile_row + 1'b1;
                        end else begin
                            next_tile_col <= next_tile_col + 1'b1;
                        end
                    end
                end
            end
        end
    end


    // Data clocks only; handshake/control registers retain the root clock.
    winograd_clock_gate cg_line_clk (.clk(clk), .enable(input_transfer), .gclk(line_clk));

endmodule
