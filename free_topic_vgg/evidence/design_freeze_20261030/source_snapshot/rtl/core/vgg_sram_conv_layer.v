`default_nettype none
// Designated transform/MAC datapath with SRAM storage and CB boundaries.
// Main cluster: SRAM-addressed tiles, one fixed 128-bit tile assembly register.
// Legacy standalone fixtures retain their raster/line adapter via TILE_INPUT=0.
// Independent X reader, V writer, MAC row reads, Y writer and host ports.
// Bank 13 controls optional X/Y streaming pages; reset selects resident mode.
module vgg_sram_conv_layer #(
    parameter integer HEIGHT = 8,
                      WIDTH = 8,
    parameter ENABLE_FC=0,
    parameter EXTERNAL_ACTIVATION = 1'b0,
    parameter TILE_INPUT = 1'b0,
    parameter RUNTIME_SHAPE = 1'b0,
    parameter STREAM_TILE = 1'b1,
    parameter RETAIN_V = 1'b0,
    parameter integer V8_PACKED=0,
    parameter integer U8_PACKED=0,
    parameter integer CHANNEL_BITS=7
) (
    input wire clk, rst_n,
    input wire fc_mode, fc_final,
    output wire [3:0] fc_class,

    // Host/DMA access: fill X/U in IDLE, read completed Y in DONE.
    input wire mem_valid,
    output wire mem_ready,
    input wire mem_write,
    input wire [3:0] mem_bank,
    input wire [9:0] mem_addr,
    input wire [63:0] mem_wdata,
    output wire mem_rvalid,
    input wire mem_rready,
    output wire [63:0] mem_rdata,

    // One layer command; held configuration is private to this core.
    input wire start_valid,
    output wire start_ready,
    input wire [CHANNEL_BITS:0] input_channels,
    input wire [5:0] input_height, input_width,
    input wire [3:0] output_channels,
    input wire [7:0] total_output_channels,
    input wire pooling, sparse_enable,
    input wire input_signed,
    input wire [255:0] biases,
    input wire [191:0] multipliers,
    input wire [23:0] u_shifts, // Eight local K shifts, 3 bits each; U8 only.

    // Completion owns Y until the external consumer acknowledges it.
    output wire done_valid,
    input wire done_ready,
    output wire done_error,
    output wire [31:0] active_cycles, mac_row_issues,
    output wire [(EXTERNAL_ACTIVATION ? 15 : 14)-1:0] output_bytes,

    // Optional A/B memory boundary. Only storage/transport moves outside;
    // line/window/transform/V replay/MAC/result pipeline stay in this core.
    input wire activation_valid,
    output wire activation_ready,
    input wire [63:0] activation_data,
    output wire output_valid,
    input wire output_ready_external,
    output wire [10:0] output_address,
    output wire [63:0] output_data,
    output wire output_last
);
    wire active_fc=ENABLE_FC && fc_mode;
    wire fc_ready, fc_done, fc_input_ready, fc_valid, fc_last;
    wire [63:0] fc_data;
    wire [10:0] fc_address;
    wire [31:0] fc_cycles, fc_issues;
    wire conv_activation_ready;
    reg conv_done_error;
    reg [31:0] conv_active_cycles, conv_mac_row_issues;
    reg [(EXTERNAL_ACTIVATION ? 15 : 14)-1:0] conv_output_bytes;
    assign done_error=active_fc ? 1'b0 : conv_done_error;
    assign active_cycles=active_fc ? fc_cycles : conv_active_cycles;
    // FC issues count features/16-lane group, not Conv coordinate rows.
    assign mac_row_issues=active_fc ? fc_issues : conv_mac_row_issues;
    assign output_bytes=active_fc ? (fc_done ? (fc_final ? 80 : 32) : 0) : conv_output_bytes;
    assign activation_ready=active_fc ? fc_input_ready : conv_activation_ready;
    localparam [1:0] IDLE = 2'd0, RUN = 2'd1, DONE = 2'd2;

    localparam [2:0]
        P_IDLE       = 3'd0,
        P_RESERVE    = 3'd1,
        P_START      = 3'd2,
        P_TRANSFORM  = 3'd3,
        P_WRITE_V    = 3'd4,
        P_COMMIT     = 3'd6,
        P_DONE       = 3'd7;

    // Consumer controls ONLY acquisition and a single MAC accumulator.
    // Completed results continue through independent elastic output stages.
    localparam [3:0] C_WAIT=0, C_JOB=1, C_MAC=2, C_WEIGHTS=3, C_DONE=8;

    // Lifecycle and the two independent execution states.
    reg [1:0] state;
    reg [2:0] producer_state;
    reg [3:0] consumer_state;

    // Latched layer configuration.
    reg [CHANNEL_BITS:0] channels;
    reg [5:0] height, width;
    wire [5:0] command_height = RUNTIME_SHAPE ? input_height : HEIGHT[5:0];
    wire [5:0] command_width = RUNTIME_SHAPE ? input_width : WIDTH[5:0];
    wire [5:0] feature_height = height + 6'd2;
    wire [5:0] feature_width = width + 6'd2;
    wire [11:0] spatial_pixels = height * width;
    reg [3:0] outputs;
    reg [7:0] total_outputs, output_base;
    // Number of output bytes whose postprocessing must finish before changing
    // the shared bias/multiplier registers. The output packer need not flush.
    reg [17:0] post_bytes_expected;
    reg pool, sparse, signed_input;
    reg [255:0] saved_biases;
    reg [191:0] saved_multipliers;
    reg [23:0] saved_u_shifts;

    // Producer cursors and consumer cursors; these do not share a task context.
    reg [CHANNEL_BITS-1:0] channel;
    reg [4:0] tile_y, tile_x;
    reg [2:0] output_channel;
    reg [8:0] consumed_tiles;

    // Small staging registers only. V payload remains in the SRAM CB slots.
    reg [3:0] transformed_zero_rows;
    reg [255:0] transformed_v;
    reg [3:0] v_pending_rows;
    wire [3:0] v_ready;
    wire [63:0] output_pack;
    wire output_word_valid, output_word_last, byte_accepted;
    wire result_pipe_ready;
    wire result_fire = state==RUN && consumer_state==C_MAC && result_valid
                     && (result_error || result_pipe_ready);
    wire output_word_fire = state==RUN && output_word_valid && output_ready;
    reg [10:0] output_word;
    reg host_read_pending;

    // Shared local SRAM request/response port, driven by the arbiter below.
    wire local_ready, local_rvalid;
    wire [63:0] local_rdata;
    reg local_valid, local_write, local_rready;
    reg [3:0] local_bank;
    reg [9:0] local_addr;
    reg [63:0] local_wdata;

    // MAC job interface. One output's entire C reduction stays in its ACC.
    wire job_ready, result_valid, result_error, core_busy;
    wire [767:0] result_data;
    wire [4*(CHANNEL_BITS+1)-1:0] issued_rows;
    // This layer always uses job_first=1. No issued rows means an exact zero M.
    wire zero_result = issued_rows == 0;

    // Host ownership is independent of compute. Bank 13 publishes/releases
    // streaming X/Y pages; resident mode remains compatible with old tests.
    wire host_valid, host_ready, host_write, host_rvalid, host_rready, host_idle;
    wire [3:0] host_bank;
    wire [9:0] host_addr;
    wire [63:0] host_wdata, host_rdata;
    wire streaming, io_drained, control_idle;
    wire x_slot, x_available, x_release;
    wire [10:0] x_words;
    wire x_valid, x_ready, x_rvalid, x_rready;
    wire [9:0] x_addr;
    wire [63:0] x_rdata;
    wire y_valid, y_ready, y_slot, output_ready;
    wire [9:0] y_addr;
    assign start_ready = (active_fc ? fc_ready : state==IDLE) && !mem_valid && control_idle;
    assign done_valid = active_fc ? fc_done : state==DONE;
    wire start_fire = start_valid && start_ready && !active_fc;
    wire weights_waiting = RETAIN_V && state==RUN && consumer_state==C_WEIGHTS
                         && {3'b0,conv_output_bytes}==post_bytes_expected;
    wire weight_control = RETAIN_V && mem_bank==14;
    wire weight_commit;
    // Host bank14/word2 bit0 opts into full-layer U residency. Metadata
    // remains an eight-output staging window; arithmetic and V leases do not change.
    reg resident_requested, resident_u;
    // bank14/word4 bit0 selects dense U rows. Zero retains the old fixture
    // layout; the full-model host explicitly selects dense addressing.
    reg dense_u_requested;
    reg [10:0] u_words_per_output;
    reg [9:0] u_output_address;
    wire [10:0] dense_u_words = U8_PACKED
        ? ({1'b0,input_channels} + 11'd1) >> 1 : {1'b0,input_channels};
    wire [10:0] command_u_words = dense_u_requested ? dense_u_words
        : (11'd1 << (command_stride-(U8_PACKED ? 4'd1 : 4'd0)));
    // Full-width products are range checks, never truncated SRAM addresses.
    wire [18:0] command_u_extent = {11'b0,total_output_channels} * {8'b0,command_u_words};
    wire [18:0] block_u_extent = {15'b0,output_channels} * {8'b0,command_u_words};
    // bank14/word3: layer V quantization shift. Only writable while idle.
    reg [2:0] v_shift;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) v_shift<=0;
        else if(state==IDLE && mem_valid && mem_ready && mem_write && mem_bank==14 && mem_addr==3)
            v_shift<=mem_wdata[2:0];
    wire resident_config_write = EXTERNAL_ACTIVATION && RETAIN_V && state==IDLE
                               && mem_valid && mem_ready && mem_write
                               && mem_bank==14 && mem_addr==2;
    wire command_u_fits = command_u_extent <= 19'd1024;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin dense_u_requested<=0; u_words_per_output<=0; end
        else begin
            if (state==IDLE && mem_valid && mem_ready && mem_write && weight_control && mem_addr==4)
                dense_u_requested <= mem_wdata[0];
            if (start_fire) u_words_per_output <= command_u_words;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin resident_requested<=0; resident_u<=0; end
        else begin
            if (resident_config_write) resident_requested<=mem_wdata[0];
            if (start_fire) resident_u<=resident_requested && command_u_fits && RETAIN_V;
        end
    end
    wire [23:0] input_size = {{(23-CHANNEL_BITS){1'b0}},input_channels} * {18'b0,command_height} * {18'b0,command_width};
    wire [3:0] command_stride=CHANNEL_BITS==7 ? 4'd7
                              : input_channels>256 ? 4'd9 : input_channels>128 ? 4'd8 : 4'd7;
    wire [3:0] channel_stride=CHANNEL_BITS==7 ? 4'd7
                              : channels>256 ? 4'd9 : channels>128 ? 4'd8 : 4'd7;
    wire [15:0] command_beats=({{(15-CHANNEL_BITS){1'b0}},input_channels}+16'd31)>>5;
    wire [15:0] required_line_words=3*({10'b0,command_width}+16'd2)*command_beats;
    wire [2:0] active_slots=channel_stride==9 ? 3'd1 : channel_stride==8 ? 3'd2 : 3'd4;
    wire bad_command = HEIGHT < 2 || HEIGHT > 32 || WIDTH < 2 || WIDTH > 32
                    || HEIGHT % 2 != 0 || WIDTH % 2 != 0
                    || command_height<6'd2 || command_height>HEIGHT[5:0] || command_height[0]
                    || command_width<6'd2 || command_width>WIDTH[5:0] || command_width[0]
                    || input_channels == 0 || input_channels > (1<<CHANNEL_BITS)
                    || output_channels == 0 || output_channels > 8
                    || block_u_extent > 19'd1024
                    || (!(EXTERNAL_ACTIVATION && TILE_INPUT) && CHANNEL_BITS>7 && required_line_words>512)
                    || (!streaming && input_size > 8192)
                    || (RETAIN_V && (!EXTERNAL_ACTIVATION || total_output_channels==0
                        || total_output_channels>128
                        || (output_channels!=1 && output_channels!=2
                            && output_channels!=4 && output_channels!=8)
                        || (total_output_channels & ({4'b0,output_channels}-8'd1))!=0));

    wire last_output = output_channel == outputs - 1'b1;
    wire last_reuse = !RETAIN_V || output_base + {4'b0,outputs} == total_outputs;
    wire last_tile = {1'b0,consumed_tiles} == spatial_pixels[11:2] - 10'd1;

    // Four V slots occupy words 0..511 in banks 4..7.
    // Words 512..1023 of those banks hold the three circular raster lines.
    // These signals are metadata handshakes; the CB module contains no payload.
    wire reserve_ready, commit_ready, cb_available, release_ready;
    wire [2:0] producer_slot, consumer_slot;
    wire [3:0] cb_occupancy;
    wire reserve_valid = state == RUN && producer_state == P_RESERVE;
    wire commit_valid = state == RUN && producer_state == P_COMMIT;
    wire cb_acquire = state == RUN && consumer_state == C_WAIT && cb_available;
    wire cb_release = result_fire && !result_error && last_output && last_reuse;

    wire [1:0] producer_slot_small, consumer_slot_small;
    wire [2:0] occupancy_small;
    assign producer_slot = {1'b0, producer_slot_small};
    assign consumer_slot = {1'b0, consumer_slot_small};
    assign cb_occupancy = {1'b0, occupancy_small};
    vgg_cb_slots #(.SLOT_BITS(2), .EARLY_READ(1), .RUNTIME_SLOTS(CHANNEL_BITS>7)) u_cb_v (
        .clk           (clk),
        .rst_n         (rst_n),
        .clear         (start_fire),
        .slot_limit    (active_slots),

        .reserve_valid (reserve_valid),
        .reserve_ready (reserve_ready),
        .producer_slot (producer_slot_small),
        .commit_valid  (commit_valid),
        .commit_ready  (commit_ready),

        .available     (cb_available),
        .acquire       (cb_acquire),
        .consumer_slot (consumer_slot_small),
        .release_valid (cb_release),
        .release_ready (release_ready),
        .occupancy     (occupancy_small)
    );

    // The original horizontal window receives padded raster vectors plus three
    // delayed column taps from SRAM. Layout and page ownership remain at X.
    wire window_valid;
    wire [127:0] activation_tile;
    wire it_in_ready, it_valid;
    wire [255:0] it_v;
    wire [3:0] it_zero;
    wire producer_grant = state==RUN;
    wire pixel_valid, pixel_ready;
    wire [8*(1<<CHANNEL_BITS)-1:0] pixel_vector;

    assign output_valid = active_fc ? fc_valid : EXTERNAL_ACTIVATION && state==RUN && output_word_valid;
    assign output_address = active_fc ? fc_address : output_word;
    assign output_data = active_fc ? fc_data : output_pack;
    assign output_last = active_fc ? fc_last : output_word_last;
    generate if (!EXTERNAL_ACTIVATION) begin : g_legacy_io
    assign weight_commit = 1'b0;
    vgg_io_cbs u_io_cbs (
        .clk(clk), .rst_n(rst_n), .idle(state==IDLE), .running(state==RUN),
        .done(state==DONE), .start(start_fire && !bad_command),
        .mem_valid(mem_valid), .mem_ready(mem_ready), .mem_write(mem_write),
        .mem_bank(mem_bank), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_rvalid(mem_rvalid), .mem_rready(mem_rready), .mem_rdata(mem_rdata),
        .host_valid(host_valid), .host_ready(host_ready), .host_write(host_write),
        .host_bank(host_bank), .host_addr(host_addr), .host_wdata(host_wdata),
        .host_rvalid(host_rvalid), .host_rready(host_rready), .host_rdata(host_rdata),
        .host_idle(host_idle), .streaming(streaming),
        .x_slot(x_slot), .x_release(x_release), .x_available(x_available), .x_words(x_words),
        .out_valid(state==RUN && output_word_valid), .out_ready(output_ready),
        .out_last(output_word_last), .resident_y_addr(output_word[9:0]),
        .y_valid(y_valid), .y_ready(y_ready), .y_slot(y_slot), .y_addr(y_addr),
        .drained(io_drained), .control_idle(control_idle)
    );
    end else begin : g_ab_io
        // The cluster owns activation regions and their lifetime. Local host
        // accesses cover only U/V/debug; activation banks are not duplicated.
        // During a weight request only U may be overwritten. Live V payload,
        // masks and line history remain protected throughout all K reuses.
        reg control_rvalid;
        reg [63:0] control_rdata;
        wire allowed = (state!=RUN && (mem_bank<8 || mem_bank==12))
                     || (weights_waiting && mem_bank<4 && mem_write);
        wire control_ready = !control_rvalid && host_idle
                           && (!mem_write || weights_waiting || (state==IDLE && (mem_addr==2 || mem_addr==3 || mem_addr==4)));
        wire control_fire = mem_valid && weight_control && control_ready;
        assign weight_commit = control_fire && mem_write && mem_addr==1
                             && mem_wdata[15:8]==output_base
                             && mem_wdata[24:16]==consumed_tiles;
        assign host_valid = mem_valid && allowed && !weight_control && !control_rvalid;
        assign host_write = mem_write;
        assign host_bank = mem_bank;
        assign host_addr = mem_addr;
        assign host_wdata = mem_wdata;
        assign host_rready = mem_rready;
        assign mem_ready = weight_control ? control_ready : allowed && host_ready && !control_rvalid;
        assign mem_rvalid = control_rvalid || host_rvalid;
        assign mem_rdata = control_rvalid ? control_rdata : host_rdata;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) control_rvalid <= 0;
            else begin
                if (control_rvalid && mem_rready) control_rvalid <= 0;
                if (control_fire && !mem_write) control_rvalid <= 1;
            end
        end
        always @(posedge clk)
            if (control_fire && !mem_write)
                // bit40: U payload already resident; only metadata and commit needed.
                control_rdata <= {23'b0,resident_u,4'b0,outputs,7'b0,consumed_tiles,output_base,7'b0,weights_waiting};
        assign streaming = 1'b1;
        assign io_drained = 1'b1;
        assign control_idle = host_idle && !control_rvalid;
        assign x_available = 1'b0;
        assign x_words = 11'b0;
        assign y_valid = 1'b0;
        assign y_slot = 1'b0;
        assign y_addr = 10'b0;
        assign output_ready = output_ready_external;
    end endgenerate
    wire line_valid, line_ready, line_write, line_rvalid, line_rready;
    wire [8:0] line_addr;
    wire [255:0] line_wdata, line_rdata;
    generate if (EXTERNAL_ACTIVATION && TILE_INPUT) begin : g_sram_tiles
        assign line_valid=1'b0;
        assign line_write=1'b0;
        assign line_rready=1'b0;
        assign line_addr=9'b0;
        assign line_wdata=256'b0;
        assign x_valid=1'b0;
        assign x_slot=1'b0;
        assign x_addr=10'b0;
        assign x_rready=1'b0;
        assign x_release=1'b0;
        vgg_tile_stream_reader u_tile (
            .clk(clk), .rst_n(rst_n), .clear(start_fire && !bad_command),
            .in_valid(activation_valid && !active_fc), .in_ready(conv_activation_ready),
            .in_data(activation_data), .out_valid(window_valid),
            .out_ready(it_in_ready && state==RUN && producer_state==P_TRANSFORM),
            .tile(activation_tile)
        );
    end else begin : g_legacy_raster
    vgg_activation_reader #(.HEIGHT(HEIGHT), .WIDTH(WIDTH), .MAX_CHANNELS(1<<CHANNEL_BITS),
                           .DIRECT_STREAM(EXTERNAL_ACTIVATION), .RUNTIME_SHAPE(RUNTIME_SHAPE)) u_reader (
        .clk(clk), .rst_n(rst_n), .start(start_fire && !bad_command),
        .channels(channels), .streaming(streaming),
        .input_height(height), .input_width(width),
        .pixel_valid(pixel_valid), .pixel_ready(pixel_ready), .pixel_vector(pixel_vector),
        .mem_valid(x_valid), .mem_ready(x_ready), .mem_slot(x_slot), .mem_addr(x_addr),
        .mem_rvalid(x_rvalid), .mem_rready(x_rready), .mem_rdata(x_rdata),
        .page_available(x_available), .page_words(x_words), .page_release(x_release),
        .page_slot(), .done(),
        .stream_in_valid(EXTERNAL_ACTIVATION && !active_fc ? activation_valid : 1'b0),
        .stream_in_ready(conv_activation_ready), .stream_in_data(activation_data)
    );
    wire raster_valid, raster_ready;
    wire [8*(1<<CHANNEL_BITS)-1:0] raster_pixel, raster_row0, raster_row1, raster_row2;
    vgg_sram_line_buffer #(.FEATURE_WIDTH(WIDTH+2), .FEATURE_HEIGHT(HEIGHT+2),
                          .RUNTIME_SHAPE(RUNTIME_SHAPE), .CHANNEL_BITS(CHANNEL_BITS)) u_lines (
        .clk(clk), .rst_n(rst_n), .start(start_fire && !bad_command), .channels(channels),
        .input_feature_height(feature_height), .input_feature_width(feature_width),
        .in_valid(pixel_valid), .in_ready(pixel_ready), .in_pixel(pixel_vector),
        .out_valid(raster_valid), .out_ready(raster_ready), .out_pixel(raster_pixel),
        .row0(raster_row0), .row1(raster_row1), .row2(raster_row2),
        .mem_valid(line_valid), .mem_ready(line_ready), .mem_write(line_write),
        .mem_addr(line_addr), .mem_wdata(line_wdata), .mem_rvalid(line_rvalid),
        .mem_rready(line_rready), .mem_rdata(line_rdata)
    );
    winograd_sliding_window_generator #(
        .EXTERNAL_LINES(1), .STREAM_TILE(STREAM_TILE), .ACT_BITS(8), .CHANNELS(1<<CHANNEL_BITS), .CHANNEL_BITS(CHANNEL_BITS), .RUNTIME_CHANNELS(1),
        .RUNTIME_SHAPE(RUNTIME_SHAPE),
        .FEATURE_WIDTH(WIDTH+2), .FEATURE_HEIGHT(HEIGHT+2), .POSITION_BITS(6),
        .TILE_ROWS(HEIGHT/2), .TILE_COLS(WIDTH/2), .TILE_INDEX_BITS(5)
    ) u_window (
        .clk(clk), .rst_n(rst_n), .start(start_fire && !bad_command),
        .channel_count_minus1(channels[CHANNEL_BITS-1:0]-1'b1), .start_ready(), .busy(), .done(),
        .input_feature_height(feature_height), .input_feature_width(feature_width),
        .input_tile_rows(height[5:1]), .input_tile_cols(width[5:1]),
         .in_valid(raster_valid), .in_ready(raster_ready), .pixel_vector(raster_pixel),
        .external_row0(raster_row0), .external_row1(raster_row1), .external_row2(raster_row2),
        .out_valid(window_valid),
        .out_ready(it_in_ready && state==RUN && producer_state==P_TRANSFORM),
        .activation_tile(activation_tile), .output_input_channel(),
        .output_tile_row(), .output_tile_col(), .output_last()
    );

    end endgenerate

    winograd_input_transform #(
        .ACT_BITS  (8),
        .TEMP_BITS (10),
        .V_BITS    (16),
        .RUNTIME_SIGNED(CHANNEL_BITS>7)
    ) u_input (
        .clk             (clk),
        .rst_n           (rst_n),
        .in_valid        (window_valid && state == RUN && producer_state == P_TRANSFORM),
        .in_ready        (it_in_ready),
        .activation_tile (activation_tile),
        .activation_signed(signed_input),
        .out_valid       (it_valid),
        .out_ready       (state == RUN && producer_state == P_TRANSFORM),
        .v_tile          (it_v),
        .zero_rows       (it_zero)
    );

    wire [255:0] quantized_v;
    wire [3:0] quantized_zero;
    vgg_v8_quantizer u_v_quantizer (.in_tile(it_v), .shift(v_shift),
        .out_tile(quantized_v), .zero_rows(quantized_zero));

    // Same normal/bypass ordering pattern as designated winograd_conv_core.
    // The MAC can advance after its complete result is accepted here; no
    // dependency on OT/post/output SRAM completion remains in its scheduler.
    vgg_result_pipeline u_results (
        .clk(clk), .rst_n(rst_n), .start(start_fire && !bad_command),
        .pooling(pool), .biases(saved_biases), .multipliers(saved_multipliers),
        .in_valid(state==RUN && consumer_state==C_MAC && result_valid && !result_error),
        .in_ready(result_pipe_ready), .in_m(result_data), .in_zero(zero_result),
        .in_last(last_output && last_reuse && last_tile), .in_channel(output_channel),
        .word_valid(output_word_valid), .word_ready(state==RUN && output_ready),
        .word_data(output_pack), .word_last(output_word_last), .byte_accepted(byte_accepted)
    );

    // Twelve SRAM macros and the designated MAC behind synchronous row reads.
    vgg_dataflow_core #(.ENABLE_FC(ENABLE_FC), .EXPLICIT_U_BASE(1), .SRAM_LINES(1), .INTERNAL_ACTIVATION(!EXTERNAL_ACTIVATION),
                        .STREAM_V(1), .U8_PACKED(U8_PACKED), .V8_PACKED(V8_PACKED), .CHANNEL_BITS(CHANNEL_BITS)) u_core (
        .fc_mode(active_fc),.fc_start(active_fc && start_valid && start_ready),.fc_final(fc_final),
        .fc_start_ready(fc_ready),.fc_done(fc_done),.fc_done_ready(done_ready && active_fc),
        .fc_input_valid(active_fc && activation_valid),.fc_input_ready(fc_input_ready),.fc_input_data(activation_data),
        .fc_word_valid(fc_valid),.fc_word_ready(output_ready_external && active_fc),
        .fc_word_data(fc_data),.fc_word_address(fc_address),.fc_word_last(fc_last),
        .fc_class(fc_class),.fc_cycles(fc_cycles),.fc_issues(fc_issues),
        .line_valid(line_valid), .line_write(line_write), .line_ready(line_ready),
        .line_addr(line_addr), .line_wdata(line_wdata), .line_rvalid(line_rvalid),
        .line_rready(line_rready), .line_rdata(line_rdata),
        .clk          (clk),
        .rst_n        (rst_n),
        .mem_valid    (local_valid),
        .mem_ready    (local_ready),
        .mem_write    (local_write),
        .mem_bank     (local_bank),
        .mem_addr     (local_addr),
        .mem_wdata    (local_wdata),
        .v_rows       (v_pending_rows),
        .v_tile       (transformed_v),
        .v_last_channel(channel==channels-1'b1), .job_v_shift(v_shift),
        .v_zero_rows  (transformed_zero_rows),
        .v_reserve    (reserve_valid && reserve_ready),
        .v_reserve_slot(producer_slot),
        .v_ready      (v_ready),
        .mem_rvalid   (local_rvalid),
        .mem_rready   (local_rready),
        .mem_rdata    (local_rdata),

        .host_valid(host_valid), .host_ready(host_ready), .host_write(host_write),
        .host_bank(host_bank), .host_addr(host_addr), .host_wdata(host_wdata),
        .host_rvalid(host_rvalid), .host_rready(host_rready), .host_rdata(host_rdata),
        .host_idle(host_idle),
        .x_valid(x_valid), .x_ready(x_ready), .x_slot(x_slot), .x_addr(x_addr),
        .x_rvalid(x_rvalid), .x_rready(x_rready), .x_rdata(x_rdata),
        .y_valid(y_valid), .y_ready(y_ready), .y_slot(y_slot), .y_addr(y_addr), .y_data(output_pack),

        .job_valid    (state == RUN && consumer_state == C_JOB),
        .job_ready    (job_ready),
        .job_tile     (consumer_slot),
        .job_output   (4'b0),
        .job_u_base   (u_output_address),
        .job_u_shift  (saved_u_shifts[output_channel*3 +: 3]),
        .job_channels (channels),
        .channel_stride(channel_stride),
        .job_first    (1'b1),
        .job_sparse   (sparse),

        .result_valid (result_valid),
        .result_ready (state == RUN && consumer_state == C_MAC && (result_error || result_pipe_ready)),
        .result_data  (result_data),
        .result_error (result_error),
        .issued_rows  (issued_rows),
        .busy         (core_busy)
    );

    // Producer-only port: V rows with sideband masks. X/Y/host have their own
    // physical-bank decoders; neither job dispatch nor Y output stalls this port.
    always @* begin
        local_valid = 0;
        local_write = 1;
        local_bank = 0;
        local_addr = 0;
        local_wdata = 0;
        local_rready = 1;
        if(state==RUN) case(producer_state)
            P_WRITE_V: begin
                local_valid = 1;
                local_bank = 4; // Four parallel row banks selected by v_pending_rows.
                local_addr = ({7'b0,producer_slot} << channel_stride) + {{(10-CHANNEL_BITS){1'b0}},channel};
                local_wdata = 0; // Payload travels on v_tile, not this legacy scalar port.
            end
            default: begin end
        endcase
    end

    wire producer_write_fire = producer_grant && local_valid && local_ready && local_write;

    // Payload storage: synchronous enables, without a frame-sized reset network.
    // This block owns data; the following FSM blocks own validity and cursors.
    always @(posedge clk) begin
        if (start_fire) begin
            height <= command_height;
            width <= command_width;
            channels <= input_channels;
            outputs <= output_channels;
            total_outputs <= RETAIN_V ? total_output_channels : {4'b0,output_channels};
            pool <= pooling;
            sparse <= sparse_enable;
            signed_input <= CHANNEL_BITS>7 && input_signed;
            saved_biases <= biases;
            saved_multipliers <= multipliers;
            saved_u_shifts <= U8_PACKED ? u_shifts : 24'd0;
        end
        // Metadata belongs to the currently loaded U block. Prior results have
        // passed postprocess before this window opens, so no bias FIFO is needed.
        if (weight_control && mem_valid && mem_ready && mem_write && weights_waiting) begin
            if (mem_addr>=8 && mem_addr<16)
                saved_biases[mem_addr[2:0]*32 +: 32] <= mem_wdata[31:0];
            if (mem_addr>=16 && mem_addr<24)
                saved_multipliers[mem_addr[2:0]*24 +: 24] <= mem_wdata[23:0];
            if (U8_PACKED && mem_addr >= 24 && mem_addr < 32)
                saved_u_shifts[mem_addr[2:0]*3 +: 3] <= mem_wdata[2:0];
        end
        if (state == RUN && producer_state == P_TRANSFORM && it_valid) begin
            transformed_v <= V8_PACKED ? quantized_v : it_v;
            transformed_zero_rows <= V8_PACKED ? quantized_zero : it_zero;
        end

    end

    // CB_V PRODUCER
    // Reserve exposes the slot to the consumer. Each accepted V channel
    // advances its readable watermark; commit only closes producer ownership.
    // Release remains separate and waits for the last output-channel reuse.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            producer_state <= P_IDLE;
            channel <= 0;
            tile_y <= 0;
            tile_x <= 0;
            v_pending_rows <= 0;
        end else if (start_fire) begin
            producer_state <= bad_command ? P_IDLE : P_RESERVE;
            channel <= 0;
            tile_y <= 0;
            tile_x <= 0;
            v_pending_rows <= 0;
        end else if (state == RUN)
            case (producer_state)
                P_RESERVE:
                    if (reserve_ready) begin
                        channel <= 0;
                        producer_state <= P_START;
                    end
                P_START:
                    producer_state <= P_TRANSFORM;
                P_TRANSFORM:
                    if (it_valid) begin
                        v_pending_rows <= 4'b1111;
                        producer_state <= P_WRITE_V;
                    end
                P_WRITE_V: begin
                    v_pending_rows <= v_pending_rows & ~v_ready;
                    if (producer_write_fire) begin
                        if ({1'b0, channel} == channels - 1'b1) begin
                            producer_state <= P_COMMIT;
                        end else begin
                            channel <= channel + 1'b1;
                            producer_state <= P_START;
                        end
                    end
                end
                P_COMMIT:
                    if (commit_ready) begin
                        if (tile_y == height[5:1]-5'd1 && tile_x == width[5:1]-5'd1)
                            producer_state <= P_DONE;
                        else begin
                            if (tile_x == width[5:1]-5'd1) begin
                                tile_x <= 0;
                                tile_y <= tile_y + 1'b1;
                            end else
                                tile_x <= tile_x + 1'b1;
                            producer_state <= P_RESERVE;
                        end
                    end
                default: begin end
            endcase
    end

    // CB_V CONSUMER. V is released after the last K result is safely buffered.
    // OT/post no longer reference V, so they may run while this slot is reused.
    // Layer DONE still waits until the final output word is accepted by Y CB.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            consumer_state <= C_WAIT;
            host_read_pending <= 0;
            conv_done_error <= 0;
            conv_active_cycles <= 0;
            conv_mac_row_issues <= 0;
            conv_output_bytes <= 0;
            output_channel <= 0;
            output_base <= 0;
            u_output_address <= 0;
            post_bytes_expected <= 0;
            consumed_tiles <= 0;
            output_word <= 0;
        end else begin
            if (mem_valid && mem_ready && !mem_write) host_read_pending <= 1;
            if (mem_rvalid && mem_rready) host_read_pending <= 0;
            if (state == RUN) conv_active_cycles <= conv_active_cycles + 1'b1;
            if (start_fire) begin
                state <= bad_command ? DONE : RUN;
                conv_done_error <= bad_command;
                consumer_state <= C_WAIT;
                conv_active_cycles <= 0;
                conv_mac_row_issues <= 0;
                conv_output_bytes <= 0;
                output_channel <= 0;
                output_base <= 0;
                u_output_address <= 0;
                post_bytes_expected <= 0;
                consumed_tiles <= 0;
                output_word <= 0;
            end else if (state == DONE) begin
                if (done_ready && io_drained && control_idle && !host_read_pending && !mem_valid)
                    state <= IDLE;
            end else if (state == RUN) begin
                if (byte_accepted) conv_output_bytes <= conv_output_bytes+1'b1;
                if (output_word_fire) begin
                    output_word <= output_word+1'b1;
                    if (output_word_last) state <= DONE;
                end
                case (consumer_state)
                    C_WAIT: if (cb_acquire) begin
                        output_channel <= 0;
                        output_base <= 0;
                        u_output_address <= 0;
                        consumer_state <= RETAIN_V && consumed_tiles!=0 && total_outputs>{4'b0,outputs}
                                        ? C_WEIGHTS : C_JOB;
                    end
                    C_JOB: if (job_ready) consumer_state <= C_MAC;
                    C_WEIGHTS: if (weight_commit) consumer_state <= C_JOB;
                    C_MAC: if (result_fire) begin
                        // Address progression is independent of metadata-window
                        // size. Resident payload survives every window switch.
                        if (last_output && !resident_u) u_output_address <= 0;
                        else u_output_address <= u_output_address + u_words_per_output[9:0];
                        if (result_error) begin
                            conv_done_error <= 1;
                            state <= DONE;
                        end else begin
                            post_bytes_expected <= post_bytes_expected + (pool ? 18'd1 : 18'd4);
                            conv_mac_row_issues <= conv_mac_row_issues
                                 + {{(31-CHANNEL_BITS){1'b0}},issued_rows[0*(CHANNEL_BITS+1) +: CHANNEL_BITS+1]}
                                + {{(31-CHANNEL_BITS){1'b0}},issued_rows[1*(CHANNEL_BITS+1) +: CHANNEL_BITS+1]}
                                + {{(31-CHANNEL_BITS){1'b0}},issued_rows[2*(CHANNEL_BITS+1) +: CHANNEL_BITS+1]}
                                + {{(31-CHANNEL_BITS){1'b0}},issued_rows[3*(CHANNEL_BITS+1) +: CHANNEL_BITS+1]};
                            if (last_output) begin
                                if (last_reuse) begin
                                    consumed_tiles <= consumed_tiles+1'b1;
                                    consumer_state <= last_tile ? C_DONE : C_WAIT;
                                end else begin
                                    // Keep the same CB lease, V words and masks.
                                    // U is reloaded; the next K block replays C.
                                    output_base <= output_base + {4'b0,outputs};
                                    output_channel <= 0;
                                    consumer_state <= C_WEIGHTS;
                                end
                            end else begin
                                output_channel <= output_channel+1'b1;
                                consumer_state <= C_JOB;
                            end
                        end
                    end
                    default: begin end
                endcase
            end
        end
    end
endmodule
`default_nettype wire
