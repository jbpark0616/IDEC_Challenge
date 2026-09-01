`timescale 1ns/1ps

// Raster-stream sliding-window generator for Winograd F(2x2, 3x3).
//
// One accepted input contains every channel at one spatial position. Three
// fixed line delays and three horizontal history registers per row form the
// overlapping 4x4 window without random feature-memory reads. For a
// multi-channel pixel, the completed spatial window is replayed once per
// channel in channel order before input streaming resumes.
module winograd_sliding_window_generator #(
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

    input  wire                              start,
    output wire                              start_ready,
    output wire                              busy,
    output reg                               done,

    input  wire                              in_valid,
    output wire                              in_ready,
    input  wire [CHANNELS*ACT_BITS-1:0]      pixel_vector,

    output reg                               out_valid,
    input  wire                              out_ready,
    output wire [16*ACT_BITS-1:0]            activation_tile,
    output reg  [CHANNEL_BITS-1:0]           output_input_channel,
    output reg  [TILE_INDEX_BITS-1:0]        output_tile_row,
    output reg  [TILE_INDEX_BITS-1:0]        output_tile_col,
    output wire                              output_last
);

    localparam integer PIXEL_BITS = CHANNELS*ACT_BITS;
    localparam integer LAST_TILE_BOTTOM_ROW = 2*TILE_ROWS + 1;
    localparam integer LAST_TILE_RIGHT_COL  = 2*TILE_COLS + 1;

    reg active;
    reg [POSITION_BITS-1:0] input_row;
    reg [POSITION_BITS-1:0] input_col;
    reg [TILE_INDEX_BITS-1:0] next_tile_row;
    reg [TILE_INDEX_BITS-1:0] next_tile_col;
    reg pending_spatial_last;

    // Fixed-depth shift registers implement delays of exactly one feature
    // row each. This avoids the variable-address read MUX of the reference
    // full-frame loader.
    reg [PIXEL_BITS-1:0] line_delay1 [0:FEATURE_WIDTH-1];
    reg [PIXEL_BITS-1:0] line_delay2 [0:FEATURE_WIDTH-1];
    reg [PIXEL_BITS-1:0] line_delay3 [0:FEATURE_WIDTH-1];

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
    assign row0_new = line_delay3[FEATURE_WIDTH-1];
    assign row1_new = line_delay2[FEATURE_WIDTH-1];
    assign row2_new = line_delay1[FEATURE_WIDTH-1];
    assign row3_new = pixel_vector;

    reg [16*PIXEL_BITS-1:0] next_window;
    reg [16*PIXEL_BITS-1:0] pending_window;
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

    genvar tile_lane;
    generate
        for (tile_lane = 0; tile_lane < 16; tile_lane = tile_lane + 1) begin : g_channel_select
            assign activation_tile[tile_lane*ACT_BITS +: ACT_BITS] =
                pending_window[tile_lane*PIXEL_BITS
                               + output_input_channel*ACT_BITS
                               +: ACT_BITS];
        end
    endgenerate

    wire output_is_last_channel;
    wire output_transfer;
    wire can_replace_output;
    wire input_transfer;
    wire input_forms_tile;

    assign output_is_last_channel =
        output_input_channel == CHANNELS-1;
    assign output_last = out_valid && pending_spatial_last
                       && output_is_last_channel;
    assign output_transfer = out_valid && out_ready;
    assign can_replace_output = output_transfer && output_is_last_channel
                              && !pending_spatial_last;
    assign in_ready = active && ((!out_valid) || can_replace_output);
    assign input_transfer = in_valid && in_ready;

    assign input_forms_tile = input_transfer
                            && (input_row >= 3)
                            && (input_col >= 3)
                            && input_row[0]
                            && input_col[0]
                            && (input_row <= LAST_TILE_BOTTOM_ROW)
                            && (input_col <= LAST_TILE_RIGHT_COL);

    assign start_ready = !active && !out_valid;
    assign busy = active || out_valid;

    integer delay_index;
    always @(posedge clk) begin
        if (input_transfer) begin
            for (delay_index = FEATURE_WIDTH-1; delay_index > 0;
                 delay_index = delay_index - 1) begin
                line_delay1[delay_index] <= line_delay1[delay_index-1];
                line_delay2[delay_index] <= line_delay2[delay_index-1];
                line_delay3[delay_index] <= line_delay3[delay_index-1];
            end
            line_delay1[0] <= pixel_vector;
            line_delay2[0] <= line_delay1[FEATURE_WIDTH-1];
            line_delay3[0] <= line_delay2[FEATURE_WIDTH-1];

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
            out_valid             <= 1'b0;
            input_row             <= {POSITION_BITS{1'b0}};
            input_col             <= {POSITION_BITS{1'b0}};
            next_tile_row         <= {TILE_INDEX_BITS{1'b0}};
            next_tile_col         <= {TILE_INDEX_BITS{1'b0}};
            output_input_channel  <= {CHANNEL_BITS{1'b0}};
            output_tile_row       <= {TILE_INDEX_BITS{1'b0}};
            output_tile_col       <= {TILE_INDEX_BITS{1'b0}};
            pending_spatial_last  <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start && start_ready) begin
                active               <= 1'b1;
                out_valid            <= 1'b0;
                input_row            <= {POSITION_BITS{1'b0}};
                input_col            <= {POSITION_BITS{1'b0}};
                next_tile_row        <= {TILE_INDEX_BITS{1'b0}};
                next_tile_col        <= {TILE_INDEX_BITS{1'b0}};
                output_input_channel <= {CHANNEL_BITS{1'b0}};
                pending_spatial_last <= 1'b0;
            end else begin
                if (output_transfer) begin
                    if (!output_is_last_channel) begin
                        output_input_channel <= output_input_channel + 1'b1;
                    end else if (pending_spatial_last) begin
                        out_valid <= 1'b0;
                        active <= 1'b0;
                        done <= 1'b1;
                    end else begin
                        out_valid <= 1'b0;
                    end
                end

                if (input_transfer) begin
                    if (input_col == FEATURE_WIDTH-1) begin
                        input_col <= {POSITION_BITS{1'b0}};
                        if (input_row != FEATURE_HEIGHT-1)
                            input_row <= input_row + 1'b1;
                    end else begin
                        input_col <= input_col + 1'b1;
                    end

                    if (input_forms_tile) begin
                        pending_window <= next_window;
                        output_input_channel <= {CHANNEL_BITS{1'b0}};
                        output_tile_row <= next_tile_row;
                        output_tile_col <= next_tile_col;
                        pending_spatial_last <=
                            (next_tile_row == TILE_ROWS-1)
                            && (next_tile_col == TILE_COLS-1);
                        out_valid <= 1'b1;

                        if (next_tile_col == TILE_COLS-1) begin
                            next_tile_col <= {TILE_INDEX_BITS{1'b0}};
                            if (next_tile_row != TILE_ROWS-1)
                                next_tile_row <= next_tile_row + 1'b1;
                        end else begin
                            next_tile_col <= next_tile_col + 1'b1;
                        end
                    end
                end
            end
        end
    end

endmodule
