`default_nettype none
// SRAM-to-raster boundary. The line-buffer adapter supplies delayed rows;
// the designated generator retains its horizontal windows. CHW/HWC layouts stay unchanged.
// A small per-channel word cache reuses all eight bytes of CHW SRAM reads.
module vgg_activation_reader #(
    parameter integer HEIGHT=8, WIDTH=8, MAX_CHANNELS=128, CHANNEL_BITS=$clog2(MAX_CHANNELS),
    parameter DIRECT_STREAM=1'b0, RUNTIME_SHAPE=1'b0
) (
    input wire clk, rst_n, start,
    input wire [CHANNEL_BITS:0] channels,
    input wire [5:0] input_height, input_width,
    input wire streaming,
    output wire pixel_valid,
    input wire pixel_ready,
    output wire [MAX_CHANNELS*8-1:0] pixel_vector,
    output wire mem_valid,
    input wire mem_ready,
    output wire mem_slot,
    output wire [9:0] mem_addr,
    input wire mem_rvalid,
    output wire mem_rready,
    input wire [63:0] mem_rdata,
    input wire page_available,
    input wire [10:0] page_words,
    output wire page_release,
    output wire page_slot,
    output reg done,
    // Optional local multicast boundary; raster/vector construction is unchanged.
    input wire stream_in_valid,
    output wire stream_in_ready,
    input wire [63:0] stream_in_data
);
    localparam IDLE=0, BUILD=1, REQUEST=2, RESPONSE=3, SEND=4;
    reg [2:0] state;
    reg [5:0] y, x;
    reg [CHANNEL_BITS-1:0] channel;
    reg [MAX_CHANNELS*8-1:0] vector;
    reg [63:0] cache [0:MAX_CHANNELS-1];
    reg [9:0] tag [0:MAX_CHANNELS-1];
    reg [MAX_CHANNELS-1:0] cache_valid;
    reg [63:0] stream_word;
    reg [2:0] stream_byte;
    reg stream_valid, slot;
    reg [9:0] word_index;
    wire [5:0] height = RUNTIME_SHAPE ? input_height : HEIGHT[5:0];
    wire [5:0] width = RUNTIME_SHAPE ? input_width : WIDTH[5:0];
    wire padding = y==0 || x==0 || y==height+6'd1 || x==width+6'd1;
    wire [23:0] byte_address = {{(24-CHANNEL_BITS){1'b0}},channel} * {18'b0,height} * {18'b0,width}
                             + ({18'b0,y}-24'd1)*{18'b0,width}+({18'b0,x}-24'd1);
    wire [9:0] word_address = byte_address[12:3];
    wire cache_hit = cache_valid[channel] && tag[channel]==word_address;
    wire byte_available = streaming ? stream_valid : cache_hit;
    wire [7:0] selected_byte = streaming ? stream_word[stream_byte*8 +: 8]
                                         : cache[channel][byte_address[2:0]*8 +: 8];
    assign pixel_vector = vector;
    assign pixel_valid = state==SEND;
    assign mem_valid = !DIRECT_STREAM && state==REQUEST && (!streaming || page_available);
    assign stream_in_ready = DIRECT_STREAM && state!=IDLE && !done && !stream_valid;
    assign mem_slot = streaming ? slot : 1'b0;
    assign mem_addr = streaming ? word_index : word_address;
    assign mem_rready = state==RESPONSE;
    assign page_slot = slot;
    assign page_release = streaming && state==RESPONSE && mem_rvalid
                        && {1'b0, word_index}==page_words-1'b1;
    genvar c;
    generate for(c=0; c<MAX_CHANNELS; c=c+1) begin : g_pixel
        always @(posedge clk) begin
            if (state==BUILD && padding) vector[c*8 +: 8] <= 0;
            else if (state==BUILD && !padding && channel==c && byte_available)
                vector[c*8 +: 8] <= selected_byte;
            if (state==RESPONSE && mem_rvalid && !streaming && channel==c) begin
                cache[c] <= mem_rdata;
                tag[c] <= word_address;
            end
        end
    end endgenerate
    always @(posedge clk) begin
        if (state==RESPONSE && mem_rvalid && streaming) stream_word <= mem_rdata;
        if (stream_in_valid && stream_in_ready) stream_word <= stream_in_data;
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; y<=0; x<=0; channel<=0; cache_valid<=0;
            stream_valid<=0; stream_byte<=0; slot<=0; word_index<=0; done<=0;
        end else if(start) begin
            state<=BUILD; y<=0; x<=0; channel<=0; cache_valid<=0;
            stream_valid<=0; stream_byte<=0; slot<=0; word_index<=0; done<=0;
        end else begin
          if (stream_in_valid && stream_in_ready) begin
              stream_valid<=1; stream_byte<=0;
          end
          case(state)
            BUILD: begin
                if(padding) state<=SEND;
                else if(!byte_available) begin
                    if(!DIRECT_STREAM) state<=REQUEST;
                end
                else begin
                    if(streaming) begin
                        stream_byte<=stream_byte+1'b1;
                        if(stream_byte==7) stream_valid<=0;
                    end
                    if({1'b0, channel}==channels-1'b1) begin
                        channel<=0; state<=SEND;
                    end else channel<=channel+1'b1;
                end
            end
            REQUEST: if(mem_valid && mem_ready) state<=RESPONSE;
            RESPONSE: if(mem_rvalid) begin
                if(streaming) begin
                    stream_valid<=1; stream_byte<=0;
                    if(page_release) begin slot<=!slot; word_index<=0; end
                    else word_index<=word_index+1'b1;
                end else cache_valid[channel]<=1;
                state<=BUILD;
            end
            SEND: if(pixel_ready) begin
                if(x==width+6'd1) begin
                    x<=0;
                    if(y==height+6'd1) begin state<=IDLE; done<=1; end
                    else begin y<=y+1'b1; state<=BUILD; end
                end else begin x<=x+1'b1; state<=BUILD; end
            end
            default: begin end
          endcase
        end
    end
endmodule
`default_nettype wire
