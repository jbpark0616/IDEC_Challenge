`default_nettype none
// Three circular raster rows in the upper half of SRAM banks 4..7.
// One request spans four 64-bit banks (32 channels). At most four requests
// cover one 128-channel pixel. No full feature row is stored in FFs.
// Physical row slots rotate; old rows are read before the oldest is replaced.
module vgg_sram_line_buffer #(
    parameter integer FEATURE_WIDTH=34, FEATURE_HEIGHT=34,
    parameter RUNTIME_SHAPE=1'b0,
    parameter integer CHANNEL_BITS=7
) (
    input wire clk, rst_n, start,
    input wire [CHANNEL_BITS:0] channels,
    input wire [5:0] input_feature_height, input_feature_width,
    input wire in_valid,
    output wire in_ready,
    input wire [8*(1<<CHANNEL_BITS)-1:0] in_pixel,
    output wire out_valid,
    input wire out_ready,
    output wire [8*(1<<CHANNEL_BITS)-1:0] out_pixel, row0, row1, row2,
    output wire mem_valid,
    input wire mem_ready,
    output wire mem_write,
    output wire [8:0] mem_addr,
    output wire [255:0] mem_wdata,
    input wire mem_rvalid,
    output wire mem_rready,
    input wire [255:0] mem_rdata
);
    localparam [2:0] IDLE=0, READ=1, RESPONSE=2, WRITE=3, SEND=4, DONE=5;
    reg [2:0] state;
    reg [5:0] x, y;
    reg [1:0] oldest, read_row;
    reg [CHANNEL_BITS-6:0] beat;
    reg [8*(1<<CHANNEL_BITS)-1:0] pixel_hold, tap0, tap1, tap2;
    wire [2:0] slot_sum={1'b0,oldest}+{1'b0,read_row};
    wire [1:0] read_slot=slot_sum>=3 ? slot_sum-3 : slot_sum;
    wire [1:0] slot=state==WRITE ? oldest : read_slot;
    wire [CHANNEL_BITS-6:0] last_beat=(channels-1'b1)>>5;
    wire missing_row=y < (3-read_row);
    wire [5:0] height = RUNTIME_SHAPE ? input_feature_height : FEATURE_HEIGHT[5:0];
    wire [5:0] width = RUNTIME_SHAPE ? input_feature_width : FEATURE_WIDTH[5:0];

    assign in_ready=state==IDLE;
    assign out_valid=state==SEND;
    assign out_pixel=pixel_hold;
    assign row0=tap0;
    assign row1=tap1;
    assign row2=tap2;
    assign mem_valid=(state==READ && !missing_row) || state==WRITE;
    assign mem_write=state==WRITE;
    // Physical row pitch remains the compile-time capacity. Only raster bounds
    // vary per layer; no runtime stride multiplier or new SRAM is introduced.
    // Wide mode packs only the current layer's active channel beats. This
    // preserves the physical 512-word line region when C grows and W shrinks.
    wire [CHANNEL_BITS-5:0] beats_per_pixel={1'b0,last_beat}+1'b1;
    assign mem_addr=CHANNEL_BITS==7 ? (slot*FEATURE_WIDTH+x)*4+beat
                                   : (slot*width+x)*beats_per_pixel+beat;
    assign mem_wdata=pixel_hold[beat*256 +: 256];
    assign mem_rready=state==RESPONSE;
    wire response=mem_rvalid && mem_rready;

    always @(posedge clk) begin
        if(in_valid && in_ready) pixel_hold<=in_pixel;
    end
    // Fixed destinations and per-beat enables avoid describing a wide
    // variable write-mask/shift network. Payload lifetime and latency are unchanged.
    wire tap_write = response || (state==READ && missing_row);
    wire [255:0] tap_data = missing_row ? 256'b0 : mem_rdata;
    localparam integer TAP_BEATS = 1 << (CHANNEL_BITS-5);
    genvar tap_beat;
    generate for (tap_beat=0; tap_beat<TAP_BEATS; tap_beat=tap_beat+1) begin : g_tap_beat
        wire selected = beat == tap_beat;
        always @(posedge clk) begin
            if (tap_write && selected) begin
                case (read_row)
                    0: tap0[tap_beat*256 +: 256] <= tap_data;
                    1: tap1[tap_beat*256 +: 256] <= tap_data;
                    2: tap2[tap_beat*256 +: 256] <= tap_data;
                    default: begin end
                endcase
            end
        end
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=DONE; x<=0; y<=0; oldest<=0; read_row<=0; beat<=0;
        end else if(start) begin
            state<=IDLE; x<=0; y<=0; oldest<=0; read_row<=0; beat<=0;
        end else case(state)
            IDLE: if(in_valid) begin state<=READ; read_row<=0; beat<=0; end
            READ: begin
                if(missing_row) begin
                    if(beat==last_beat) begin
                        beat<=0;
                        if(read_row==2) state<=WRITE;
                        else read_row<=read_row+1'b1;
                    end else beat<=beat+1'b1;
                end else if(mem_ready) state<=RESPONSE;
            end
            RESPONSE: if(mem_rvalid) begin
                if(beat==last_beat) begin
                    beat<=0;
                    if(read_row==2) state<=WRITE;
                    else begin read_row<=read_row+1'b1; state<=READ; end
                end else begin beat<=beat+1'b1; state<=READ; end
            end
            WRITE: if(mem_ready) begin
                if(beat==last_beat) begin beat<=0; state<=SEND; end
                else beat<=beat+1'b1;
            end
            SEND: if(out_ready) begin
                state<=IDLE;
                if(x==width-6'd1) begin
                    x<=0;
                    oldest<=oldest==2 ? 0 : oldest+1'b1;
                    if(y==height-6'd1) state<=DONE;
                    else y<=y+1'b1;
                end else x<=x+1'b1;
            end
            default: begin end
        endcase
    end
endmodule
`default_nettype wire
