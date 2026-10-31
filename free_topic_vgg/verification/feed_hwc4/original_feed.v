`default_nettype none
// Activation SRAM address/layout boundary. TILE_STREAM emits padded 4x4 tiles
// in spatial-tile -> input-channel -> row-major-pixel order. FC keeps HWC mode.
// Reads either:
//  * a host-loaded HWC tensor in core0, or
//  * CORES equal K shards stored in tile -> local K -> 2x2 pixel order.
// A fixed 4-word direct-mapped cache per source core retains recently read words.
// It is a 32-byte/core working buffer, not a feature-map/partial-sum store.
module vgg_activation_feed_original #(
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
    output reg out_valid,
    input wire out_ready,
    output reg [63:0] out_data,
    output reg out_last,
    output reg [31:0] source_reads,
    output reg [31:0] stream_words
);
    localparam [2:0] IDLE=0, BUILD=1, REQUEST=2, RESPONSE=3, DRAIN=4, DONE=5;
    reg [2:0] state;
    reg region, tiled;
    reg pooled_layout;
    reg [5:0] height, width;
    reg [10:0] base;
    reg [CHANNEL_BITS:0] count_channels;
    reg [SHARD_BITS-1:0] local_channels;
    reg [3:0] block_channels;
    reg [10:0] block_words;
    reg [2:0] block_channel;
    reg [10:0] block_base;
    reg [1:0] block_cache_index;
    reg [5:0] y, x;
    reg window_mode;
    reg [4:0] window_y, window_x;
    reg [3:0] window_pixel;
    wire [6:0] sample_y = {window_y,1'b0} + {5'b0,window_pixel[3:2]} - 7'd1;
    wire [6:0] sample_x = {window_x,1'b0} + {5'b0,window_pixel[1:0]} - 7'd1;
    wire padding = window_mode && (sample_y >= {1'b0,height} || sample_x >= {1'b0,width});
    wire [5:0] data_y = window_mode ? sample_y[5:0] : y;
    wire [5:0] data_x = window_mode ? sample_x[5:0] : x;
    reg [CHANNEL_BITS-1:0] channel;
    reg [CORE_BITS-1:0] owner;
    reg [SHARD_BITS-1:0] local_channel;
    reg [15:0] linear_byte;
    reg [2:0] pack_index;

    reg [63:0] cache_data [0:CORES*4-1];
    reg [10:0] cache_tag [0:CORES*4-1];
    reg [CORES*4-1:0] cache_valid;

    wire [CORE_BITS-1:0] source = tiled ? owner : {CORE_BITS{1'b0}};
    wire [9:0] tile_number = {5'b0,data_y[5:1]} * {5'b0,width[5:1]} + {5'b0,data_x[5:1]};
    // Retained-V mode emits tile -> all local K -> pixel. Use the full runtime
    // shard count, not the old at-most-eight-K block field. Storage is unchanged.
    wire [SHARD_BITS-1:0] layout_channels = BLOCK_LAYOUT
        ? {{(SHARD_BITS-4){1'b0}},block_channels} : local_channels;
    wire [SHARD_BITS-1:0] layout_channel = BLOCK_LAYOUT
        ? {{(SHARD_BITS-3){1'b0}},block_channel} : local_channel;
    wire [13:0] tile_channel = tile_number * layout_channels
                            + {{(14-SHARD_BITS){1'b0}},layout_channel};
    wire [15:0] tile_byte = {tile_channel,2'b0} + {14'b0,data_y[0],data_x[0]};
    // A pooled tile produces one pixel, so each local shard is HWC after pool.
    wire [11:0] pixel_number = {6'b0,data_y} * {6'b0,width} + {6'b0,data_x};
    wire [23:0] hwc_byte = pixel_number * count_channels + channel;
    wire [15:0] pooled_byte = {4'b0,pixel_number} * layout_channels
                            + {{(16-SHARD_BITS){1'b0}},layout_channel};
    wire [15:0] shard_byte = (pooled_layout ? pooled_byte : tile_byte)
                            + (BLOCK_LAYOUT ? {2'b0,block_base,3'b0} : 16'b0);
    wire [15:0] byte_address = {2'b0,base,3'b0}
                             + (tiled ? shard_byte : window_mode ? hwc_byte[15:0] : linear_byte);
    wire [10:0] region_word = byte_address[13:3];
    // Consecutive K blocks often have the same low word address bits. Mix
    // their block index into the four cache entries instead of repeatedly
    // evicting one another while reading the same spatial tile.
    wire [1:0] cache_lane = region_word[1:0]
                         ^ ((BLOCK_LAYOUT && tiled) ? block_cache_index : 2'b0);
    wire [CORE_BITS+1:0] cache_index = {source,cache_lane};
    wire cache_hit = cache_valid[cache_index] && cache_tag[cache_index]==region_word;
    wire [7:0] selected_byte = padding ? 8'b0 : cache_data[cache_index][byte_address[2:0]*8 +: 8];
    wire [CORES-1:0] source_mask = {{(CORES-1){1'b0}},1'b1} << source;
    wire response_fire = |(response_valid & response_ready);
    wire last_channel = {1'b0,channel}==count_channels-1'b1;
    wire last_byte = window_mode
        ? last_channel && window_pixel==15 && window_y==height[5:1]-1'b1 && window_x==width[5:1]-1'b1
        : last_channel && y==height-6'd1 && x==width-6'd1;
    wire word_room = !out_valid || out_ready;

    // BUILD already precedes REQUEST. Capture only the SRAM word address
    // at that boundary: no extra FSM state or read transaction is introduced.
    // This isolates spatial address arithmetic from SRAM/host arbitration.
    // The payload register needs no reset; read_valid qualifies its use.
    reg [10:0] request_word;
    always @(posedge clk) begin
        if (state==BUILD && word_room && !padding && !cache_hit)
            request_word <= region_word;
    end

    assign done = state==DONE;
    assign read_valid = source_mask & {CORES{state==REQUEST && rst_n}};
    assign read_bank = {region,request_word[10]};
    assign read_addr = request_word[9:0];
    assign response_ready = source_mask & {CORES{state==RESPONSE && rst_n}};

    // Only tags/validity reset. SRAM and cache payload have no reset network.
    always @(posedge clk) begin
        if(response_fire) begin
            cache_data[cache_index] <= response_data[source*64 +: 64];
            cache_tag[cache_index] <= region_word;
        end
        if(state==BUILD && word_room && (padding || cache_hit)) begin
            if(pack_index==0) out_data <= {56'b0,selected_byte};
            else out_data[pack_index*8 +: 8] <= selected_byte;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; region<=0; tiled<=0; base<=0;
            window_mode<=0; window_y<=0; window_x<=0; window_pixel<=0;
            height<=0; width<=0; pooled_layout<=0;
            count_channels<=0; local_channels<=0;
            block_channels<=0; block_words<=0; block_channel<=0; block_base<=0;
            block_cache_index<=0;
            y<=0; x<=0; channel<=0; owner<=0; local_channel<=0;
            linear_byte<=0; pack_index<=0; cache_valid<=0;
            out_valid<=0; out_last<=0; source_reads<=0; stream_words<=0;
        end else if(start) begin
            state<=BUILD; region<=phase; tiled<=sharded; base<=base_word;
            window_mode<=TILE_STREAM && tile_mode;
            window_y<=0; window_x<=0; window_pixel<=0;
            height<=input_height; width<=input_width; pooled_layout<=source_pooled;
            count_channels<=channels; local_channels<=shard_channels;
            block_channels<=source_block_channels; block_words<=source_block_words;
            block_channel<=0; block_base<=0;
            block_cache_index<=0;
            y<=0; x<=0; channel<=0; owner<=0; local_channel<=0;
            linear_byte<=0; pack_index<=0; cache_valid<=0;
            out_valid<=0; out_last<=0; source_reads<=0; stream_words<=0;
        end else begin
            if(out_valid && out_ready) begin
                out_valid<=0;
                stream_words<=stream_words+1'b1;
            end
            case(state)
                BUILD: if(word_room) begin
                    if(!padding && !cache_hit) state<=REQUEST;
                    else begin
                        linear_byte<=linear_byte+1'b1;
                        pack_index<=pack_index+1'b1;
                        if(pack_index==7 || last_byte) begin
                            out_valid<=1;
                            out_last<=last_byte;
                        end
                        if(last_byte) state<=DRAIN;
                        if(window_mode) window_pixel<=window_pixel+1'b1;
                        if(!window_mode || window_pixel==15) begin
                        if(last_channel) begin
                            channel<=0; owner<=0; local_channel<=0;
                            block_channel<=0; block_base<=0;
                            block_cache_index<=0;
                            if(window_mode) begin
                                if(window_x==width[5:1]-1'b1) begin window_x<=0; window_y<=window_y+1'b1; end
                                else window_x<=window_x+1'b1;
                            end else begin
                                if(x==width-6'd1) begin x<=0; y<=y+1'b1; end
                                else x<=x+1'b1;
                            end
                        end else begin
                            channel<=channel+1'b1;
                            if({1'b0,local_channel}==local_channels-1'b1) begin
                                local_channel<=0; owner<=owner+1'b1;
                                block_channel<=0; block_base<=0;
                                block_cache_index<=0;
                            end else begin
                                local_channel<=local_channel+1'b1;
                                if({1'b0,block_channel}==block_channels-1'b1) begin
                                    block_channel<=0; block_base<=block_base+block_words;
                                    block_cache_index<=block_cache_index+1'b1;
                                end else block_channel<=block_channel+1'b1;
                            end
                        end
                        end
                    end
                end
                REQUEST: if(|(read_valid & read_ready)) begin
                    source_reads<=source_reads+1'b1;
                    state<=RESPONSE;
                end
                RESPONSE: if(response_fire) begin
                    cache_valid[cache_index]<=1;
                    state<=BUILD;
                end
                DRAIN: if(out_valid && out_ready) state<=DONE;
                default: begin end
            endcase
        end
    end
endmodule
`default_nettype wire
