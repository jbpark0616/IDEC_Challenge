// Measurement wrapper only; production parameters are unchanged.
module fanout16_synth (
    input wire clk, rst_n, in_valid,
    output wire in_ready,
    input wire [63:0] in_data,
    input wire [7:0] in_keep,
    input wire in_last,
    input wire [15:0] in_destinations,
    output wire [15:0] out_valid,
    input wire [15:0] out_ready,
    output wire [63:0] out_data,
    output wire [7:0] out_keep,
    output wire out_last, idle
);
    vgg_mcast_fanout #(.DEPTH(4), .CORES(16)) u_dut (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_ready(in_ready),
        .in_data(in_data), .in_keep(in_keep), .in_last(in_last),
        .in_destinations(in_destinations), .out_valid(out_valid),
        .out_ready(out_ready), .out_data(out_data), .out_keep(out_keep),
        .out_last(out_last), .idle(idle)
    );
endmodule
