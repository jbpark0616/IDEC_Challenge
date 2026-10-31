module vgg_activation_feed #(
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
reg use_fast;
wire eligible=TILE_STREAM && tile_mode && !sharded && channels!=0 && channels[1:0]==0;
always @(posedge clk or negedge rst_n) if(!rst_n) use_fast<=0; else if(start) use_fast<=eligible;
wire fast_done, old_done;
assign done=use_fast ? fast_done : old_done;
wire [CORES-1:0] fast_read_valid, old_read_valid;
assign read_valid=use_fast ? fast_read_valid : old_read_valid;
wire [2-1:0] fast_read_bank, old_read_bank;
assign read_bank=use_fast ? fast_read_bank : old_read_bank;
wire [10-1:0] fast_read_addr, old_read_addr;
assign read_addr=use_fast ? fast_read_addr : old_read_addr;
wire [CORES-1:0] fast_response_ready, old_response_ready;
assign response_ready=use_fast ? fast_response_ready : old_response_ready;
wire fast_out_valid, old_out_valid;
assign out_valid=use_fast ? fast_out_valid : old_out_valid;
wire [64-1:0] fast_out_data, old_out_data;
assign out_data=use_fast ? fast_out_data : old_out_data;
wire fast_out_last, old_out_last;
assign out_last=use_fast ? fast_out_last : old_out_last;
wire [32-1:0] fast_source_reads, old_source_reads;
assign source_reads=use_fast ? fast_source_reads : old_source_reads;
wire [32-1:0] fast_stream_words, old_stream_words;
assign stream_words=use_fast ? fast_stream_words : old_stream_words;
vgg_activation_feed_original #(.HEIGHT(HEIGHT),.WIDTH(WIDTH),.CORES(CORES),.CORE_BITS(CORE_BITS),.CHANNEL_BITS(CHANNEL_BITS),.BLOCK_LAYOUT(BLOCK_LAYOUT),.TILE_STREAM(TILE_STREAM),.SHARD_BITS(SHARD_BITS)) old_path (
.clk(clk),
.rst_n(rst_n),
.phase(phase),
.sharded(sharded),
.tile_mode(tile_mode),
.input_height(input_height),
.input_width(input_width),
.source_pooled(source_pooled),
.base_word(base_word),
.channels(channels),
.shard_channels(shard_channels),
.source_block_channels(source_block_channels),
.source_block_words(source_block_words),
.start(start && !eligible),
.read_ready(read_ready),
.response_valid(response_valid),
.response_data(response_data),
.out_ready(out_ready),
.done(old_done),
.read_valid(old_read_valid),
.read_bank(old_read_bank),
.read_addr(old_read_addr),
.response_ready(old_response_ready),
.out_valid(old_out_valid),
.out_data(old_out_data),
.out_last(old_out_last),
.source_reads(old_source_reads),
.stream_words(old_stream_words)
);
vgg_activation_feed_hwc4 #(.HEIGHT(HEIGHT),.WIDTH(WIDTH),.CORES(CORES),.CORE_BITS(CORE_BITS),.CHANNEL_BITS(CHANNEL_BITS),.BLOCK_LAYOUT(BLOCK_LAYOUT),.TILE_STREAM(TILE_STREAM),.SHARD_BITS(SHARD_BITS)) fast_path (
.clk(clk),
.rst_n(rst_n),
.phase(phase),
.sharded(sharded),
.tile_mode(tile_mode),
.input_height(input_height),
.input_width(input_width),
.source_pooled(source_pooled),
.base_word(base_word),
.channels(channels),
.shard_channels(shard_channels),
.source_block_channels(source_block_channels),
.source_block_words(source_block_words),
.start(start && eligible),
.read_ready(read_ready),
.response_valid(response_valid),
.response_data(response_data),
.out_ready(out_ready),
.done(fast_done),
.read_valid(fast_read_valid),
.read_bank(fast_read_bank),
.read_addr(fast_read_addr),
.response_ready(fast_response_ready),
.out_valid(fast_out_valid),
.out_data(fast_out_data),
.out_last(fast_out_last),
.source_reads(fast_source_reads),
.stream_words(fast_stream_words)
);
endmodule
