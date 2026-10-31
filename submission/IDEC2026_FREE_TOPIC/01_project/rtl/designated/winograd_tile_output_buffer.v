`timescale 1ns/1ps
// Completed-tile holding stage, separate from raster line/window generation.
// Capture all channel slices at a spatial position and deliver them in order.
// Reading a slice does not change payload storage. The slot may be replaced
// only after the last channel transfers. Downstream V reuse belongs to V CB.
module winograd_tile_output_buffer #(
    parameter integer ACT_BITS = 8,
                      CHANNELS = 1,
                      CHANNEL_BITS = 2,
                      TILE_INDEX_BITS = 4
) (
    input wire clk, rst_n, clear,
    input wire [CHANNEL_BITS-1:0] channel_count_minus1,

    input wire capture_valid,
    output wire capture_ready,
    input wire [16*CHANNELS*ACT_BITS-1:0] capture_window,
    input wire [TILE_INDEX_BITS-1:0] capture_row, capture_col,
    input wire capture_last,

    output reg out_valid,
    input wire out_ready,
    output wire [16*ACT_BITS-1:0] activation_tile,
    output reg [CHANNEL_BITS-1:0] output_channel,
    output reg [TILE_INDEX_BITS-1:0] output_row, output_col,
    output reg spatial_last,
    output wire output_last
);
    localparam integer PIXEL_BITS = CHANNELS * ACT_BITS;
    reg [16*PIXEL_BITS-1:0] pending_window;
    wire last_channel = output_channel == channel_count_minus1;
    wire transfer = out_valid && out_ready;
    wire capture = capture_valid && capture_ready;
    wire payload_clk;

    assign capture_ready = !out_valid || (transfer && last_channel && !spatial_last);
    assign output_last = out_valid && spatial_last && last_channel;

    // Preserve the existing payload layout and channel selection mapping.
    // No channel-shifting register network or new serialization is introduced.
    genvar lane;
    generate for (lane = 0; lane < 16; lane = lane + 1) begin : g_channel_select
        assign activation_tile[lane*ACT_BITS +: ACT_BITS] =
            pending_window[lane*PIXEL_BITS + output_channel*ACT_BITS +: ACT_BITS];
    end endgenerate

    winograd_clock_gate cg_payload (
        .clk(clk), .enable(capture), .gclk(payload_clk)
    );
    always @(posedge payload_clk)
        if (capture) pending_window <= capture_window;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 0;
            output_channel <= 0;
            output_row <= 0;
            output_col <= 0;
            spatial_last <= 0;
        end else if (clear) begin
            out_valid <= 0;
            output_channel <= 0;
            spatial_last <= 0;
        end else begin
            if (transfer) begin
                if (last_channel)
                    out_valid <= 0;
                else
                    output_channel <= output_channel + 1'b1;
            end
            // A new completed spatial tile may replace the prior one on the
            // same edge as the prior tile's last-channel handshake.
            if (capture) begin
                out_valid <= 1;
                output_channel <= 0;
                output_row <= capture_row;
                output_col <= capture_col;
                spatial_last <= capture_last;
            end
        end
    end
endmodule
