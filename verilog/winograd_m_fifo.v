`timescale 1ns/1ps

// Concrete result FIFO between the MAC/reduction engine and output transform.
// Each entry is one complete 4x4 INT18 M tile (288 bits).
module winograd_m_fifo #(
    parameter integer ACC_BITS = 18,
    parameter integer DEPTH    = 2,
    parameter integer CHANNEL_BITS = 2
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       in_valid,
    output wire                       in_ready,
    input  wire [16*ACC_BITS-1:0]     in_m_tile,
    input  wire [CHANNEL_BITS-1:0]    in_output_channel,
    output wire                       out_valid,
    input  wire                       out_ready,
    output wire [16*ACC_BITS-1:0]     out_m_tile,
    output wire [CHANNEL_BITS-1:0]    out_output_channel,
    output wire                       full,
    output wire                       empty
);

    localparam integer FIFO_BITS = 16*ACC_BITS + CHANNEL_BITS;
    wire [FIFO_BITS-1:0] in_payload;
    wire [FIFO_BITS-1:0] out_payload;

    assign in_payload = {in_output_channel, in_m_tile};
    assign out_m_tile = out_payload[0 +: 16*ACC_BITS];
    assign out_output_channel = out_payload[16*ACC_BITS +: CHANNEL_BITS];

    elastic_fifo #(
        .DATA_WIDTH(FIFO_BITS),
        .DEPTH(DEPTH)
    ) u_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_data(in_payload),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_data(out_payload),
        .full(full),
        .empty(empty)
    );

endmodule
