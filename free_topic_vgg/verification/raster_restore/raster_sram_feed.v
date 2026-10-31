`default_nettype none
// Isolated three-channel designated-generator integration.
// Sequential HWC reads; bounded 16-byte word queue; no per-channel cache.
// The generator itself is the unmodified designated final RTL (renamed at build).
module raster_sram_feed #(
    parameter integer H=4, W=4
) (
    input wire clk, rst_n, start,
    output wire rd_valid, input wire rd_ready,
    output wire [9:0] rd_addr,
    input wire rsp_valid, output wire rsp_ready, input wire [63:0] rsp_data,
    output wire out_valid, input wire out_ready, output wire [63:0] out_data
);
    localparam integer WORDS=(H*W*3+7)/8;
    reg active, pending;
    reg [9:0] issued;
    reg [127:0] bytes_q;
    reg [4:0] byte_count;
    reg [5:0] x,y;
    wire padding=(x==0 || y==0 || x==W+1 || y==H+1);
    wire pixel_ready;
    wire pixel_valid=active && (padding || byte_count>=3);
    wire pixel_fire=pixel_valid && pixel_ready;
    wire pop_bytes=pixel_fire && !padding;
    wire [4:0] kept=byte_count-(pop_bytes ? 5'd3 : 5'd0);
    wire [127:0] shifted=pop_bytes ? (bytes_q>>24) : bytes_q;
    assign rd_valid=active && !pending && issued<WORDS && byte_count<=8;
    assign rd_addr=issued;
    assign rsp_ready=pending;
    wire response=rsp_valid && rsp_ready;
    always @(posedge clk) begin
        if(response) bytes_q <= shifted | ({64'b0,rsp_data} << (kept*8));
        else if(pop_bytes) bytes_q <= shifted;
        if(start) bytes_q<=0;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            active<=0;pending<=0;issued<=0;byte_count<=0;x<=0;y<=0;
        end else if(start) begin
            active<=1;pending<=0;issued<=0;byte_count<=0;x<=0;y<=0;
        end else begin
            byte_count<=kept+(response ? 5'd8 : 5'd0);
            if(rd_valid && rd_ready) begin issued<=issued+1'b1;pending<=1;end
            if(response) pending<=0;
            if(pixel_fire) begin
                if(x==W+1) begin
                    x<=0;
                    if(y==H+1) active<=0;
                    else y<=y+1'b1;
                end else x<=x+1'b1;
            end
        end
    end
    wire tile_valid, tile_ready;
    wire [127:0] tile;
    reg half;
    assign out_valid=tile_valid;
    assign out_data=half ? tile[127:64] : tile[63:0];
    assign tile_ready=out_ready && half;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) half<=0;
        else if(start) half<=0;
        else if(out_valid && out_ready) half<=!half;
    end
    designated_final_window #(
        .ACT_BITS(8),.CHANNELS(3),.CHANNEL_BITS(2),
        .FEATURE_WIDTH(W+2),.FEATURE_HEIGHT(H+2),.POSITION_BITS(6),
        .TILE_ROWS(H/2),.TILE_COLS(W/2),.TILE_INDEX_BITS(5)
    ) window (
        .clk(clk),.rst_n(rst_n),.start(start),.start_ready(),.busy(),.done(),
        .in_valid(pixel_valid),.in_ready(pixel_ready),
        .pixel_vector(padding ? 24'b0 : bytes_q[23:0]),
        .out_valid(tile_valid),.out_ready(tile_ready),.activation_tile(tile),
        .output_input_channel(),.output_tile_row(),.output_tile_col(),.output_last()
    );
endmodule
`default_nettype wire
