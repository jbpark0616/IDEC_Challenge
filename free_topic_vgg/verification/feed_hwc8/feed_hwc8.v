module vgg_activation_feed_hwc8 #(
    parameter integer HEIGHT=8, WIDTH=8,
    parameter integer CORES=4, CORE_BITS=$clog2(CORES), CHANNEL_BITS=7,
    parameter BLOCK_LAYOUT=1'b0,
    parameter TILE_STREAM=1'b0,
    parameter integer SHARD_BITS=BLOCK_LAYOUT ? 8 : 4
) (
    input wire clk, rst_n, start,
    input wire phase, sharded,
    input wire tile_mode,
    input wire [5:0] input_height, input_width,
    input wire source_pooled,
    input wire [10:0] base_word,
    input wire [CHANNEL_BITS:0] channels,
    input wire [SHARD_BITS-1:0] shard_channels,
    input wire [3:0] source_block_channels,
    input wire [10:0] source_block_words,
    output wire done,
    output wire [CORES-1:0] read_valid,
    input wire [CORES-1:0] read_ready,
    output wire [1:0] read_bank,
    output wire [9:0] read_addr,
    input wire [CORES-1:0] response_valid,
    output wire [CORES-1:0] response_ready,
    input wire [CORES*64-1:0] response_data,
    output wire out_valid,
    input wire out_ready,
    output wire [63:0] out_data,
    output wire out_last,
    output wire [31:0] source_reads,
    output wire [31:0] stream_words
);
// Fixed 128-byte staging buffer: 16 spatial positions x 8 adjacent channels.
// HWC, C divisible by 8 only. Wrapper preserves all other layouts via original.
// Single outstanding SRAM read. No channel-sized FF arrays; payload not reset.
localparam [2:0] IDLE=0, PREPARE=1, REQUEST=2, RESPONSE=3, EMIT=4, FINISHED=5;
reg [2:0] state;
reg [5:0] height,width;
reg [CHANNEL_BITS:0] count_channels,group_channel;
reg [4:0] tile_y,tile_x;
reg [3:0] position;
reg [2:0] lane;
reg half,region;
reg [10:0] base,request_word;
reg [63:0] pixels[0:15];
reg [31:0] reads,words;
wire [6:0] y={tile_y,1'b0}+{5'b0,position[3:2]}-7'd1;
wire [6:0] x={tile_x,1'b0}+{5'b0,position[1:0]}-7'd1;
wire padding=(y>={1'b0,height}) || (x>={1'b0,width});
wire [23:0] address=({18'b0,y[5:0]}*width+x[5:0])*count_channels+group_channel+{10'b0,base,3'b0};
wire final_group=group_channel+8>=count_channels;
wire final_tile=tile_y==height[5:1]-1'b1 && tile_x==width[5:1]-1'b1;
assign done=state==FINISHED;
assign read_valid={{(CORES-1){1'b0}},(state==REQUEST && rst_n)};
assign read_bank={region,request_word[10]};
assign read_addr=request_word[9:0];
assign response_ready={{(CORES-1){1'b0}},(state==RESPONSE && rst_n)};
assign out_valid=state==EMIT;
assign out_last=state==EMIT && half && lane==7 && final_group && final_tile;
assign source_reads=reads;
assign stream_words=words;
genvar b;
generate for(b=0;b<8;b=b+1) begin: output_bytes
    assign out_data[b*8+:8]=half ? pixels[b+8][lane*8+:8] : pixels[b][lane*8+:8];
end endgenerate
// Fixed write destinations describe 16 word enables, not a shifting payload.
genvar p;
generate for(p=0;p<16;p=p+1) begin: payload
    always @(posedge clk) begin
        if(position==p) begin
            if(state==PREPARE && padding) pixels[p]<=0;
            else if(state==RESPONSE && response_valid[0]) pixels[p]<=response_data[63:0];
        end
    end
end endgenerate
always @(posedge clk) if(state==PREPARE && !padding) request_word<=address[13:3];
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state<=IDLE;height<=0;width<=0;count_channels<=0;group_channel<=0;
        tile_y<=0;tile_x<=0;position<=0;lane<=0;half<=0;region<=0;base<=0;reads<=0;words<=0;
    end else if(start) begin
        state<=PREPARE;height<=input_height;width<=input_width;count_channels<=channels;
        group_channel<=0;tile_y<=0;tile_x<=0;position<=0;lane<=0;half<=0;
        region<=phase;base<=base_word;reads<=0;words<=0;
    end else case(state)
        PREPARE: begin
            if(!padding) state<=REQUEST;
            else if(position==15) begin state<=EMIT;lane<=0;half<=0;end
            else position<=position+1'b1;
        end
        REQUEST: if(read_ready[0]) begin reads<=reads+1'b1;state<=RESPONSE;end
        RESPONSE: if(response_valid[0]) begin
            if(position==15) begin state<=EMIT;lane<=0;half<=0;end
            else begin position<=position+1'b1;state<=PREPARE;end
        end
        EMIT: if(out_ready) begin
            words<=words+1'b1;half<=!half;
            if(half) begin
                if(lane!=7) lane<=lane+1'b1;
                else if(final_group && final_tile) state<=FINISHED;
                else begin
                    position<=0;state<=PREPARE;
                    if(!final_group) group_channel<=group_channel+8;
                    else begin
                        group_channel<=0;
                        if(tile_x==width[5:1]-1'b1) begin tile_x<=0;tile_y<=tile_y+1'b1;end
                        else tile_x<=tile_x+1'b1;
                    end
                end
            end
        end
        default: begin end
    endcase
end

endmodule
