`default_nettype none
// Parameterized cluster of unchanged convolution datapaths with locally retained activation A/B.
// Each core still owns 12 physical SRAM macros: 8 operand/line banks inside
// the compute core plus the 4 activation banks instantiated here.
//
// Equal output K shards, processed in blocks of at most eight K/core.
// RETAIN_V selects tile-major K-block replay; bank 14 requests U replacement.
// HEIGHT/WIDTH are capacity limits;
// cmd_height/width select each layer's even input shape within those limits.
// Input is host HWC or retained tiled/pooled output shards from the last layer.
// A command with sharded=0 commits the host-preloaded core0 input range.
// A sharded command requires a committed previous output descriptor.
module vgg_single_core_shell #(
    parameter integer HEIGHT=8, WIDTH=8,
    parameter ENABLE_FC=0,
    parameter integer V8_PACKED=0,
    parameter integer U8_PACKED=0,
    parameter integer CORES=4, CORE_BITS=$clog2(CORES), CHANNEL_BITS=7,
    parameter BLOCK_COMMANDS=1'b0,
    parameter RETAIN_V=1'b0,
    parameter integer SHARD_BITS=BLOCK_COMMANDS ? 8 : 4
) (
    input wire clk, rst_n,
    input wire host_valid,
    output wire host_ready,
    input wire host_write,
    input wire [CORE_BITS-1:0] host_core,
    input wire [3:0] host_bank,
    input wire [9:0] host_addr,
    input wire [63:0] host_wdata,
    output wire host_rvalid,
    input wire host_rready,
    output wire [63:0] host_rdata,

    input wire cmd_fc, cmd_fc_final,
    output wire class_valid,
    output wire [3:0] class_index,
    input wire cmd_valid,
    output wire cmd_ready,
    input wire cmd_phase, cmd_sharded,
    input wire [5:0] cmd_height, cmd_width,
    input wire [10:0] cmd_input_base, cmd_output_base,
    input wire [CHANNEL_BITS:0] cmd_channels,
    input wire [SHARD_BITS-1:0] cmd_shard_channels,
    input wire [3:0] cmd_outputs,
    // Block mode retains the input until every local output channel is written.
    // cmd_output_base addresses the whole region, not the individual block.
    input wire [7:0] cmd_output_total, cmd_output_offset,
    input wire cmd_pooling, cmd_sparse,
    input wire cmd_input_signed,
    input wire [CORES*256-1:0] cmd_biases,
    input wire [CORES*192-1:0] cmd_multipliers,
    input wire [CORES*24-1:0] cmd_u_shifts,
    output wire done_valid,
    input wire done_ready,
    output reg done_error,
    output reg [31:0] total_cycles,
    output wire [CORES*32-1:0] core_cycles, mac_row_issues,
    output wire [CORES*15-1:0] output_bytes,
    output wire [31:0] source_reads, stream_words,
    output wire [1:0] committed_regions
);
    localparam [2:0] IDLE=0, LAUNCH=1, RUN=2, DONE=3;
    reg [2:0] state;
    reg phase, sharded, pool, sparse, signed_input;
    reg fc_mode, fc_final;
    reg [1:0] region_logits;
    wire command_fc=ENABLE_FC && cmd_fc;
    wire [CORES-1:0] active_cores=fc_mode && fc_final ? {{(CORES-1){1'b0}},1'b1} : {CORES{1'b1}};
    wire [CORES*4-1:0] core_class;
    assign class_index=core_class[3:0];
    assign class_valid=done_valid && !done_error && fc_mode && fc_final;
    reg source_pooled;
    reg [5:0] height, width;
    reg [10:0] input_base, output_base;
    reg [CHANNEL_BITS:0] channels;
    reg [SHARD_BITS-1:0] shard_channels;
    reg [3:0] outputs;
    reg [7:0] output_total, output_offset;
    reg [10:0] block_write_base, block_words;
    reg partial_active;
    reg [7:0] next_output_offset;
    reg [10:0] next_block_write_base;
    reg [CORES*256-1:0] biases;
    reg [CORES*192-1:0] multipliers;
    reg [CORES*24-1:0] u_shifts;

    // Region descriptors retain source lifetime across core done acknowledgments.
    reg [1:0] region_valid;
    reg [SHARD_BITS-1:0] region_channels [0:1];
    reg [3:0] region_block_channels [0:1];
    reg [10:0] region_block_words [0:1];
    reg [10:0] region_base [0:1];
    reg [1:0] region_pooled;
    reg [5:0] region_height [0:1];
    reg [5:0] region_width [0:1];
    assign committed_regions = region_valid;
    wire [31:0] input_channels_stored = cmd_sharded
        ? {{(32-SHARD_BITS){1'b0}},cmd_shard_channels} : {{(31-CHANNEL_BITS){1'b0}},cmd_channels};
    wire [7:0] command_total = BLOCK_COMMANDS ? cmd_output_total : {4'b0,cmd_outputs};
    wire [7:0] command_offset = BLOCK_COMMANDS ? cmd_output_offset : 8'b0;
    wire final_block = fc_mode || RETAIN_V || output_offset + {4'b0,outputs} == output_total;
    wire [11:0] command_pixels = cmd_height * cmd_width;
    wire [31:0] input_words = ({20'b0,command_pixels}*input_channels_stored+7)>>3;
    wire [7:0] command_result_channels = RETAIN_V ? command_total : {4'b0,cmd_outputs};
    wire [31:0] result_words = (({20'b0,command_pixels}*{24'b0,command_result_channels})>>(cmd_pooling ? 2 : 0)) + 7;
    wire input_overflow = {21'b0,cmd_input_base}+input_words > 32'd2048;
    wire [31:0] command_block_words = result_words>>3;
    // Block sizes are powers of two in block mode. Explicit shifts avoid a
    // runtime divider in the address/capacity logic.
    wire [1:0] block_shift = cmd_outputs==8 ? 2'd3 : cmd_outputs==4 ? 2'd2 : cmd_outputs==2 ? 2'd1 : 2'd0;
    wire [7:0] block_count = command_total >> block_shift;
    wire [18:0] layer_words = RETAIN_V ? command_block_words[18:0]
                                     : block_count * command_block_words[10:0];
    wire output_overflow = {21'b0,cmd_output_base}
                         + (BLOCK_COMMANDS ? {13'b0,layer_words} : command_block_words) > 32'd2048;
    wire bad_block = BLOCK_COMMANDS &&
        (command_total==0 || command_total>128 || command_offset>=command_total
         || (cmd_outputs!=1 && cmd_outputs!=2 && cmd_outputs!=4 && cmd_outputs!=8)
         || ((command_total & ({4'b0,cmd_outputs}-8'd1))!=8'd0)
         || (RETAIN_V && command_offset!=0)
         || command_offset!=(partial_active ? next_output_offset : 8'b0)
         || (partial_active && (cmd_phase!=phase || cmd_sharded!=sharded
             || cmd_height!=height || cmd_width!=width || cmd_channels!=channels
             || cmd_input_base!=input_base || cmd_output_base!=output_base
             || cmd_shard_channels!=shard_channels || cmd_outputs!=outputs
             || command_total!=output_total || cmd_pooling!=pool || cmd_sparse!=sparse
             || (CHANNEL_BITS>7 && cmd_input_signed!=signed_input))));
    wire bad_source = cmd_sharded
        ? (region_logits[cmd_phase] || !region_valid[cmd_phase]
           || region_height[cmd_phase]!=cmd_height || region_width[cmd_phase]!=cmd_width
           || region_channels[cmd_phase]!=cmd_shard_channels
           || region_base[cmd_phase]!=cmd_input_base
           || {{(31-CHANNEL_BITS){1'b0}},cmd_channels}!=(input_channels_stored*CORES))
        : (region_valid[cmd_phase] && !(BLOCK_COMMANDS && partial_active));
    wire [3:0] command_stride=CHANNEL_BITS==7 ? 4'd7
                              : cmd_channels>256 ? 4'd9 : cmd_channels>128 ? 4'd8 : 4'd7;
    wire bad_fc_command = (CORES!=1 && CORES!=16) || cmd_channels!=512 || cmd_height!=1 || cmd_width!=1
        || cmd_pooling || cmd_input_signed || partial_active || input_overflow || bad_source
        || region_valid[!cmd_phase] || {21'b0,cmd_output_base}+(cmd_fc_final ? 32'd10 : 32'd4)>2048;
    wire bad_command = command_fc ? bad_fc_command : (CORES!=1 && CORES!=4 && CORES!=16) || HEIGHT<2 || HEIGHT>32 || WIDTH<2 || WIDTH>32
                     || (HEIGHT%2)!=0 || (WIDTH%2)!=0
                     || cmd_height<6'd2 || cmd_height>HEIGHT[5:0] || cmd_width<6'd2 || cmd_width>WIDTH[5:0]
                     || cmd_height[0] || cmd_width[0]
                     || cmd_channels==0 || cmd_channels>(1<<CHANNEL_BITS)
                     || cmd_outputs==0 || cmd_outputs>8
                     || ({11'b0,cmd_outputs}<<(command_stride-(U8_PACKED ? 4'd1 : 4'd0)))>15'd1024
                     || (cmd_sharded && (cmd_shard_channels==0 || cmd_shard_channels>(CHANNEL_BITS==7 ? 8 : ((1<<CHANNEL_BITS)/CORES))))
                     || input_overflow || output_overflow || bad_source || bad_block
                     || region_valid[!cmd_phase];

    wire [CORES-1:0] core_start_ready, core_done, core_error;
    wire launch = state==LAUNCH && (&(core_start_ready | ~active_cores));
    wire acknowledge = done_valid && done_ready;
    wire [CORES-1:0] core_ack = {CORES{acknowledge}};
    wire feed_done, fanout_idle;
    wire [CORES-1:0] rx_empty;

    // One externally visible host response at a time. Activation and operand
    // traffic use different banks. In retained-V mode the core admits U writes
    // only while explicitly waiting for weights; live V/activation stays owned.
    reg host_pending, host_activation_response;
    reg [CORE_BITS-1:0] host_response_core;
    wire activation_access = host_bank>=8 && host_bank<12;
    wire host_allowed = ((state==IDLE || state==DONE)
                     && (host_write ? (host_bank<4 ||
                         (activation_access && !region_valid[host_bank[1]] && !partial_active))
                         : (host_bank<13)))
                      || (RETAIN_V && host_bank==14 && !host_write)
                      || (RETAIN_V && state==IDLE && host_bank==14 && host_write
                          && (host_addr==2 || host_addr==3 || host_addr==4))
                      || (RETAIN_V && !fc_mode && state==RUN && host_write
                          && (host_bank==14 || host_bank<4));
    wire [CORES-1:0] core_mem_valid, core_mem_ready, core_mem_rvalid, core_mem_rready;
    wire [CORES*64-1:0] core_mem_rdata;
    wire [CORES-1:0] act_host_valid, act_host_ready, act_host_rvalid, act_host_rready;
    wire [CORES*64-1:0] act_host_rdata;
    wire [CORES-1:0] host_select = {{(CORES-1){1'b0}},1'b1} << host_core;
    assign core_mem_valid = host_select & {CORES{host_valid && host_allowed && !host_pending && !activation_access}};
    assign act_host_valid = host_select & {CORES{host_valid && host_allowed && !host_pending && activation_access}};
    assign host_ready = host_allowed && !host_pending
                      && (activation_access ? act_host_ready[host_core] : core_mem_ready[host_core]);
    assign host_rvalid = host_pending && (host_activation_response
                      ? act_host_rvalid[host_response_core] : core_mem_rvalid[host_response_core]);
    assign host_rdata = host_activation_response
                      ? act_host_rdata[host_response_core*64 +: 64]
                      : core_mem_rdata[host_response_core*64 +: 64];
    assign act_host_rready = ({{(CORES-1){1'b0}},1'b1} << host_response_core)
                          & {CORES{host_pending && host_activation_response && host_rready}};
    assign core_mem_rready = ({{(CORES-1){1'b0}},1'b1} << host_response_core)
                          & {CORES{host_pending && !host_activation_response && host_rready}};

    assign cmd_ready = state==IDLE && (&(core_start_ready | ~active_cores)) && !host_pending && !host_valid;
    assign done_valid = state==DONE && !host_pending && !host_valid;

    wire [CORES-1:0] read_valid, read_ready, response_valid, response_ready;
    wire [1:0] read_bank;
    wire [9:0] read_addr;
    wire [CORES*64-1:0] response_data;
    wire feed_valid, feed_ready, feed_last;
    wire [63:0] feed_data;
    vgg_activation_feed #(.HEIGHT(HEIGHT), .WIDTH(WIDTH), .CORES(CORES),
                          .TILE_STREAM(1), .BLOCK_LAYOUT(BLOCK_COMMANDS && !RETAIN_V), .SHARD_BITS(SHARD_BITS), .CHANNEL_BITS(CHANNEL_BITS)) u_feed (
        .clk(clk), .rst_n(rst_n), .start(launch), .phase(phase), .sharded(sharded), .tile_mode(!fc_mode),
        .input_height(height), .input_width(width), .source_pooled(source_pooled),
        .base_word(input_base), .channels(channels), .shard_channels(shard_channels),
        .source_block_channels(region_block_channels[phase]),
        .source_block_words(region_block_words[phase]),
        .done(feed_done), .read_valid(read_valid), .read_ready(read_ready),
        .read_bank(read_bank), .read_addr(read_addr),
        .response_valid(response_valid), .response_ready(response_ready), .response_data(response_data),
        .out_valid(feed_valid), .out_ready(feed_ready), .out_data(feed_data), .out_last(feed_last),
        .source_reads(source_reads), .stream_words(stream_words)
    );

    wire [CORES-1:0] multicast_valid, multicast_ready;
    wire [63:0] multicast_data;
    wire multicast_last;
    vgg_mcast_fanout #(.DEPTH(4), .CORES(CORES)) u_multicast (
        .clk(clk), .rst_n(rst_n),
        .in_valid(feed_valid), .in_ready(feed_ready), .in_data(feed_data),
        .in_keep(8'hff), .in_last(feed_last), .in_destinations(active_cores),
        .out_valid(multicast_valid), .out_ready(multicast_ready),
        .out_data(multicast_data), .out_keep(), .out_last(multicast_last), .idle(fanout_idle)
    );

    genvar c;
    generate for(c=0;c<CORES;c=c+1) begin : g_core
        wire rx_valid, rx_ready;
        wire [63:0] rx_data;
        elastic_fifo #(.DATA_WIDTH(64), .DEPTH(4)) u_rx (
            .clk(clk), .rst_n(rst_n),
            .in_valid(multicast_valid[c]), .in_ready(multicast_ready[c]), .in_data(multicast_data),
            .out_valid(rx_valid), .out_ready(rx_ready), .out_data(rx_data), .empty(rx_empty[c]), .full()
        );
        wire output_valid, output_ready, output_last;
        wire [10:0] output_word;
        wire [63:0] output_data;
        wire [11:0] region_output_word = {1'b0,output_base} + {1'b0,block_write_base} + {1'b0,output_word};
        vgg_activation_sram u_activation (
            .clk(clk), .rst_n(rst_n),
            .host_valid(act_host_valid[c]), .host_ready(act_host_ready[c]), .host_write(host_write),
            .host_bank(host_bank[1:0]), .host_addr(host_addr), .host_wdata(host_wdata),
            .host_rvalid(act_host_rvalid[c]), .host_rready(act_host_rready[c]),
            .host_rdata(act_host_rdata[c*64 +: 64]),
            .tx_valid(read_valid[c]), .tx_ready(read_ready[c]), .tx_bank(read_bank), .tx_addr(read_addr),
            .tx_rvalid(response_valid[c]), .tx_rready(response_ready[c]), .tx_rdata(response_data[c*64 +: 64]),
            .writer_valid(output_valid), .writer_ready(output_ready),
            .writer_bank({!phase,region_output_word[10]}), .writer_addr(region_output_word[9:0]),
            .writer_data(output_data)
        );
        vgg_sram_conv_layer #(.ENABLE_FC(ENABLE_FC), .HEIGHT(HEIGHT), .WIDTH(WIDTH),
                             .EXTERNAL_ACTIVATION(1'b1), .TILE_INPUT(1'b1), .RUNTIME_SHAPE(1'b1),
                             .RETAIN_V(RETAIN_V), .U8_PACKED(U8_PACKED), .V8_PACKED(V8_PACKED), .CHANNEL_BITS(CHANNEL_BITS)) u_compute (
            .fc_mode(fc_mode),.fc_final(fc_final),.fc_class(core_class[c*4 +: 4]),
            .clk(clk), .rst_n(rst_n),
            .mem_valid(core_mem_valid[c]), .mem_ready(core_mem_ready[c]), .mem_write(host_write),
            .mem_bank(host_bank), .mem_addr(host_addr), .mem_wdata(host_wdata),
            .mem_rvalid(core_mem_rvalid[c]), .mem_rready(core_mem_rready[c]), .mem_rdata(core_mem_rdata[c*64 +: 64]),
            .start_valid(launch && active_cores[c]), .start_ready(core_start_ready[c]),
            .input_height(height), .input_width(width),
            .input_channels(channels), .output_channels(outputs), .pooling(pool), .sparse_enable(sparse),
            .total_output_channels(output_total),
            .input_signed(signed_input),
            .biases(biases[c*256 +: 256]), .multipliers(multipliers[c*192 +: 192]),
            .u_shifts(u_shifts[c*24 +: 24]),
            .done_valid(core_done[c]), .done_ready(core_ack[c]), .done_error(core_error[c]),
            .active_cycles(core_cycles[c*32 +: 32]), .mac_row_issues(mac_row_issues[c*32 +: 32]),
            .output_bytes(output_bytes[c*15 +: 15]),
            .activation_valid(rx_valid), .activation_ready(rx_ready), .activation_data(rx_data),
            .output_valid(output_valid), .output_ready_external(output_ready),
            .output_address(output_word), .output_data(output_data), .output_last(output_last)
        );
    end endgenerate

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            host_pending<=0; host_activation_response<=0; host_response_core<=0;
        end else begin
            if(host_rvalid && host_rready) host_pending<=0;
            if(host_valid && host_ready && !host_write) begin
                host_pending<=1;
                host_activation_response<=activation_access;
                host_response_core<=host_core;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; phase<=0; sharded<=0; pool<=0; sparse<=0; signed_input<=0;
            height<=0; width<=0; source_pooled<=0;
            input_base<=0; output_base<=0; channels<=0; shard_channels<=0; outputs<=0;
            biases<=0; multipliers<=0; u_shifts<=0; done_error<=0; total_cycles<=0;
            region_valid<=0; region_pooled<=0; region_logits<=0; fc_mode<=0; fc_final<=0;
            region_channels[0]<=0; region_channels[1]<=0;
            region_base[0]<=0; region_base[1]<=0;
            region_height[0]<=0; region_height[1]<=0;
            region_width[0]<=0; region_width[1]<=0;
            output_total<=0; output_offset<=0; block_write_base<=0; block_words<=0;
            partial_active<=0; next_output_offset<=0;
            next_block_write_base<=0;
            region_block_channels[0]<=0; region_block_channels[1]<=0;
            region_block_words[0]<=0; region_block_words[1]<=0;
        end else begin
            if(state==LAUNCH || state==RUN) total_cycles<=total_cycles+1'b1;
            case(state)
                IDLE: if(cmd_valid && cmd_ready) begin
                    done_error<=bad_command;
                    total_cycles<=0;
                    if(bad_command) state<=DONE;
                    else begin
                        phase<=cmd_phase; sharded<=cmd_sharded;
                        fc_mode<=command_fc; fc_final<=command_fc && cmd_fc_final;
                        height<=cmd_height; width<=cmd_width;
                        source_pooled<=cmd_sharded && region_pooled[cmd_phase];
                        input_base<=cmd_input_base; output_base<=cmd_output_base;
                        channels<=cmd_channels; shard_channels<=cmd_shard_channels; outputs<=cmd_outputs;
                        output_total<=command_fc ? (cmd_fc_final ? 8'd10 : 8'd32) : command_total; output_offset<=command_fc ? 8'd0 : command_offset;
                        // If the datapath reports an error, a retry starts at
                        // this same block, including the first block of a layer.
                        next_output_offset<=command_offset;
                        if (!partial_active) next_block_write_base<=0;
                        block_write_base<=BLOCK_COMMANDS && partial_active ? next_block_write_base : 11'b0;
                        block_words<=command_block_words[10:0];
                        pool<=cmd_pooling; sparse<=cmd_sparse;
                        signed_input<=CHANNEL_BITS>7 && cmd_input_signed;
                        biases<=cmd_biases; multipliers<=cmd_multipliers;
                        u_shifts<=U8_PACKED ? cmd_u_shifts : {CORES*24{1'b0}};
                        // For initial HWC, command acceptance is the producer's
                        // explicit commit after finishing all host writes.
                        region_valid[cmd_phase]<=1;
                        state<=LAUNCH;
                    end
                end
                LAUNCH: if(launch) state<=RUN;
                RUN: if((&(core_done | ~active_cores)) && feed_done && fanout_idle && (&rx_empty)) begin
                    done_error<=|(core_error & active_cores);
                    // All old-input users and reads have finished. Release
                    // only now, and publish the complete distributed output.
                    region_valid[phase]<=BLOCK_COMMANDS && (!final_block || (|(core_error & active_cores)));
                    region_valid[!phase]<=!(|(core_error & active_cores)) && (!BLOCK_COMMANDS || final_block);
                    region_channels[!phase]<=output_total[SHARD_BITS-1:0];
                    region_block_channels[!phase]<=outputs;
                    region_block_words[!phase]<=block_words;
                    partial_active<=BLOCK_COMMANDS && (!final_block || (|(core_error & active_cores)));
                    if (!(|(core_error & active_cores))) begin
                        next_output_offset<=output_offset+{4'b0,outputs};
                        next_block_write_base<=block_write_base+block_words;
                    end
                    region_base[!phase]<=output_base;
                    region_pooled[!phase]<=fc_mode || pool;
                    region_logits[!phase]<=fc_mode && fc_final;
                    region_height[!phase]<=pool ? (height>>1) : height;
                    region_width[!phase]<=pool ? (width>>1) : width;
                    state<=DONE;
                end
                DONE: if(acknowledge) begin
                    state<=IDLE;
                    // Classification is the terminal consumer. Host reads any
                    // requested logits before acknowledgement, then the next
                    // image may reuse A/B without resetting the whole cluster.
                    if(fc_mode && fc_final && !done_error) region_valid<=0;
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
