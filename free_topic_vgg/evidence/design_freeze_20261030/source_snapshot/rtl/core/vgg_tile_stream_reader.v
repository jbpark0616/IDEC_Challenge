`default_nettype none
// Two 64-bit SRAM-stream words form one row-major 4x4 INT8 tile.
// Storage is independent of tensor dimensions. Hold the tile until consumed.
module vgg_tile_stream_reader (
    input wire clk, rst_n, clear,
    input wire in_valid, output wire in_ready, input wire [63:0] in_data,
    output reg out_valid, input wire out_ready, output reg [127:0] tile
);
    reg half;
    assign in_ready = !clear && (!out_valid || out_ready);
    always @(posedge clk) begin
        if (in_valid && in_ready) begin
            if (!half) tile[63:0] <= in_data;
            else tile[127:64] <= in_data;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin half<=0; out_valid<=0; end
        else if (clear) begin half<=0; out_valid<=0; end
        else begin
            if (out_valid && out_ready) out_valid<=0;
            if (in_valid && in_ready) begin
                half<=!half;
                if (half) out_valid<=1;
            end
        end
    end
endmodule
`default_nettype wire
