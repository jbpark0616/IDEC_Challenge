`default_nettype none
// One designated MAC context. SRAM and mask storage are operand boundaries;
// no partial-sum context file, C sharding, or arithmetic replacement.
module vgg_dataflow_core #(
    parameter SRAM_LINES=0, INTERNAL_ACTIVATION=1,
    parameter ENABLE_FC=0,
    parameter EXPLICIT_U_BASE=0,
    parameter STREAM_V=0,
    parameter integer V8_PACKED=0,
    parameter integer U8_PACKED=0,
    parameter integer CHANNEL_BITS=7,
    parameter V_SLOTS= SRAM_LINES ? 4 : 8
) (
    input wire clk, rst_n,
    input wire fc_mode, fc_start, fc_final, fc_done_ready,
    output wire fc_start_ready, fc_done,
    input wire fc_input_valid,
    output wire fc_input_ready,
    input wire [63:0] fc_input_data,
    output wire fc_word_valid, fc_word_last,
    input wire fc_word_ready,
    output wire [63:0] fc_word_data,
    output wire [10:0] fc_word_address,
    output wire [3:0] fc_class,
    output wire [31:0] fc_cycles, fc_issues,

    // Circular line-buffer client; banks 4..7, words 512..1023 only.
    input wire line_valid, line_write,
    output wire line_ready,
    input wire [8:0] line_addr,
    input wire [255:0] line_wdata,
    output wire line_rvalid,
    input wire line_rready,
    output wire [255:0] line_rdata,

    input wire mem_valid, mem_write,
    output wire mem_ready,
    input wire [3:0] mem_bank,
    input wire [9:0] mem_addr,
    input wire [63:0] mem_wdata,
    input wire [3:0] v_rows,
    input wire [255:0] v_tile,
    input wire v_last_channel,
    input wire [2:0] job_v_shift,
    input wire [3:0] v_zero_rows,
    input wire v_reserve,
    input wire [2:0] v_reserve_slot,
    output wire [3:0] v_ready,
    output wire mem_rvalid,
    input wire mem_rready,
    output wire [63:0] mem_rdata,

    input wire host_valid, host_write,
    output wire host_ready,
    input wire [3:0] host_bank,
    input wire [9:0] host_addr,
    input wire [63:0] host_wdata,
    output wire host_rvalid,
    input wire host_rready,
    output wire [63:0] host_rdata,
    output wire host_idle,

    input wire x_valid, x_slot,
    output wire x_ready,
    input wire [9:0] x_addr,
    output wire x_rvalid,
    input wire x_rready,
    output wire [63:0] x_rdata,
    input wire y_valid, y_slot,
    output wire y_ready,
    input wire [9:0] y_addr,
    input wire [63:0] y_data,

    input wire job_valid,
    output wire job_ready,
    input wire [2:0] job_tile,
    input wire [3:0] job_output,
    input wire [9:0] job_u_base,
    input wire [2:0] job_u_shift,
    input wire [CHANNEL_BITS:0] job_channels,
    input wire [3:0] channel_stride,
    input wire job_first, job_sparse,
    output wire result_valid,
    input wire result_ready,
    output wire [767:0] result_data,
    output wire result_error,
    output wire [4*(CHANNEL_BITS+1)-1:0] issued_rows,
    output wire busy
);
    wire [3:0] row_read;
    wire row_accept;
    wire [39:0] u_addr, v_addr;
    wire [255:0] u_data, v_data;
    // One immutable zero bit per stored V row. Reuse does not duplicate it.
    reg [511:0] masks [0:V_SLOTS-1];
    reg [7:0] completed_channels [0:V_SLOTS-1];
    reg [2:0] active_slot;
    wire [3:0] p_ready, sram_p_ready;
    wire packed_v=V8_PACKED && !active_fc;
    wire pair_complete=mem_addr[0] || v_last_channel;
    reg [31:0] first_half [0:3];
    wire [255:0] packed_tile;
    wire [3:0] packed_rows=v_rows & {4{v_write && (!packed_v || pair_complete)}};
    wire publish_channel=!V8_PACKED || pair_complete;
    genvar pr,pl;
    generate for(pr=0;pr<4;pr=pr+1) begin : g_pack_v
        wire [31:0] bytes;
        for(pl=0;pl<4;pl=pl+1) begin : g_byte
            assign bytes[pl*8 +:8]=v_tile[pr*64+pl*16 +:8];
        end
        always @(posedge clk)
            if(packed_v && v_write && v_rows[pr] && p_ready[pr] && !mem_addr[0])
                first_half[pr]<=bytes;
        // Odd C pads the unused high half and still commits the last channel.
        assign packed_tile[pr*64 +:64]=mem_addr[0] ? {bytes,first_half[pr]} : {32'b0,bytes};
    end endgenerate
    assign p_ready=packed_v && !pair_complete ? 4'hf : sram_p_ready;
    wire engine_ready;
    wire protected_slot = !STREAM_V && busy && mem_addr[9:7] == active_slot;
    wire v_write = mem_valid && mem_write && mem_bank>=4 && mem_bank<8 && !protected_slot;
    wire mask_write = !STREAM_V && mem_valid && mem_write && mem_bank==12 && mem_addr<V_SLOTS*8
                    && (!busy || mem_addr[5:3]!=active_slot);
    assign mem_ready = (mem_bank==12) ? (!STREAM_V && mem_addr<V_SLOTS*8 && (!busy || mem_addr[5:3]!=active_slot))
                                    : (mem_bank>=4 && mem_bank<8 && !protected_slot && (&(~v_rows | p_ready)));
    assign v_ready = p_ready & {4{!protected_slot}};
    assign mem_rvalid = 1'b0;
    assign mem_rdata = 64'b0;
    assign job_ready = engine_ready;
    assign result_error = 1'b0;

    // Debug mask reads share the host response contract, not the SRAM ports.
    reg mask_rvalid;
    reg [63:0] mask_rdata;
    wire sp_ready, sp_rvalid, sp_idle;
    wire [63:0] sp_rdata;
    wire host_mask = host_bank==12 && host_addr<V_SLOTS*8;
    assign host_ready = !mask_rvalid && (host_mask ? sp_idle : sp_ready);
    assign host_rvalid = mask_rvalid || sp_rvalid;
    assign host_rdata = mask_rvalid ? mask_rdata : sp_rdata;
    assign host_idle = !mask_rvalid && sp_idle;
    wire [2:0] mask_slot = STREAM_V && busy ? active_slot : job_tile;
    wire [4*(1<<CHANNEL_BITS)-1:0] engine_mask;
    wire [CHANNEL_BITS:0] engine_available;
    genvar slot, word, row, channel;
    generate if(CHANNEL_BITS==7) begin : g_narrow_metadata
    assign engine_mask=masks[mask_slot];
    assign engine_available=completed_channels[mask_slot];
    for (slot=0; slot<V_SLOTS; slot=slot+1) begin : g_mask_slot
      if (STREAM_V) begin : g_stream
        // Constant destination flops, decoded enables: no whole-vector
        // variable shift/writeback mux and no payload reset network.
        for (row=0; row<4; row=row+1) begin : g_row
          for (channel=0; channel<128; channel=channel+1) begin : g_channel
            always @(posedge clk)
              if (v_write && v_rows[row] && p_ready[row]
                  && mem_addr[9:7]==slot && mem_addr[6:0]==channel)
                masks[slot][row*128+channel] <= v_zero_rows[row];
          end
        end
        // V rows may win arbitration on different cycles. Publish the
        // channel only after all four row writes (and masks) are accepted.
        always @(posedge clk) begin
          if (v_reserve && v_reserve_slot==slot)
            completed_channels[slot] <= 0;
          else if (v_write && mem_ready && publish_channel && mem_addr[9:7]==slot)
            completed_channels[slot] <= {1'b0,mem_addr[6:0]} + 8'd1;
        end
      end else begin : g_legacy
        for (word=0; word<8; word=word+1) begin : g_word
            always @(posedge clk)
                if (mask_write && mem_addr[5:3]==slot && mem_addr[2:0]==word)
                    masks[slot][word*64 +: 64] <= mem_wdata;
        end
      end
    end
    always @(posedge clk) begin
        if (host_valid && host_ready && host_mask)
            mask_rdata <= masks[host_addr[5:3]][host_addr[2:0]*64 +: 64];
    end
    end else begin : g_wide_metadata
        // Exactly four rows x 512 physical V words = 2048 mask bits.
        // The address partition changes with C; payload and masks never grow.
        reg [511:0] physical_mask [0:3];
        reg [9:0] watermark [0:3];
        wire [2:0] write_slot=mem_addr >> channel_stride;
        wire [8:0] channel_address=channel_stride==9 ? mem_addr[8:0]
                                 : channel_stride==8 ? {1'b0,mem_addr[7:0]}
                                                     : {2'b0,mem_addr[6:0]};
        wire [8:0] read_base={6'b0,mask_slot} << channel_stride;
        assign engine_available=watermark[mask_slot[1:0]];
        for(row=0;row<4;row=row+1) begin : g_row
            // Shifts are restricted to multiples of 128 words (four choices).
            assign engine_mask[row*512 +: 512]=physical_mask[row] >> read_base;
            for(channel=0;channel<512;channel=channel+1) begin : g_word
                always @(posedge clk)
                    if(v_write && v_rows[row] && p_ready[row] && mem_addr==channel)
                        physical_mask[row][channel]<=v_zero_rows[row];
            end
        end
        for(slot=0;slot<4;slot=slot+1) begin : g_watermark
            always @(posedge clk) begin
                if(v_reserve && v_reserve_slot==slot) watermark[slot]<=0;
                else if(v_write && mem_ready && publish_channel && write_slot==slot)
                    watermark[slot]<={1'b0,channel_address}+10'd1;
            end
        end
        // Wide-mode debug mask words are physical row-major: 8 words/row.
        always @(posedge clk)
            if(host_valid && host_ready && host_mask)
                mask_rdata<=physical_mask[host_addr[4:3]][host_addr[2:0]*64 +: 64];
    end endgenerate
    always @(posedge clk)
        if(job_valid && job_ready) active_slot<=job_tile;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) mask_rvalid <= 0;
        else begin
            if (mask_rvalid && host_rready) mask_rvalid <= 0;
            if (host_valid && host_ready && host_mask && !host_write) mask_rvalid <= 1;
        end
    end


    wire active_fc=ENABLE_FC && fc_mode;
    wire [3:0] fc_read, fc_v_enable, fc_write;
    wire [39:0] fc_u_addr, fc_v_addr;
    wire [9:0] fc_write_addr;
    wire [255:0] fc_write_data, fc_weights;
    wire [511:0] fc_biases;
    wire [7:0] fc_activation;
    wire fc_valid, fc_ready, fc_first, fc_last, fc_result_valid, fc_result_ready;
    wire [767:0] fc_result;
    generate if(ENABLE_FC) begin : g_fc
        vgg_fc_engine u_fc (
            .clk(clk),.rst_n(rst_n),.start(fc_start),.final_layer(fc_final),
            .start_ready(fc_start_ready),.done(fc_done),.done_ready(fc_done_ready),
            .input_valid(fc_input_valid),.input_ready(fc_input_ready),.input_data(fc_input_data),
            .row_read(fc_read),.v_read_enable(fc_v_enable),.row_accept(row_accept),
            .u_addr(fc_u_addr),.v_addr(fc_v_addr),.u_data(u_data),.v_data(v_data),
            .write_rows(fc_write),.write_ready(p_ready),.write_addr(fc_write_addr),.write_data(fc_write_data),
            .mac_valid(fc_valid),.mac_ready(fc_ready),.mac_first(fc_first),.mac_last(fc_last),
            .mac_activation(fc_activation),.mac_weights(fc_weights),.mac_biases(fc_biases),
            .mac_result_valid(fc_result_valid),.mac_result_ready(fc_result_ready),.mac_result(fc_result),
            .word_valid(fc_word_valid),.word_ready(fc_word_ready),.word_data(fc_word_data),
            .word_address(fc_word_address),.word_last(fc_word_last),.class_index(fc_class),
            .cycles(fc_cycles),.feature_issues(fc_issues)
        );
    end else begin : g_no_fc
        assign fc_start_ready=0; assign fc_done=0; assign fc_input_ready=0;
        assign fc_word_valid=0; assign fc_word_last=0; assign fc_word_data=0; assign fc_word_address=0;
        assign fc_class=0; assign fc_cycles=0; assign fc_issues=0;
        assign fc_read=0; assign fc_v_enable=0; assign fc_u_addr=0; assign fc_v_addr=0;
        assign fc_write=0; assign fc_write_addr=0; assign fc_write_data=0;
        assign fc_valid=0; assign fc_first=0; assign fc_last=0; assign fc_activation=0;
        assign fc_weights=0; assign fc_biases=0; assign fc_result_ready=0;
    end endgenerate

    vgg_dataflow_scratchpad #(.SRAM_LINES(SRAM_LINES), .INTERNAL_ACTIVATION(INTERNAL_ACTIVATION)) u_scratchpad (
        .line_valid(line_valid), .line_write(line_write), .line_ready(line_ready),
        .line_addr(line_addr), .line_wdata(line_wdata), .line_rvalid(line_rvalid),
        .line_rready(line_rready), .line_rdata(line_rdata),
        .clk(clk), .rst_n(rst_n), .row_read(active_fc ? fc_read : row_read), .v_read_enable(active_fc ? fc_v_enable : 4'hf), .row_accept(row_accept),
        .u_addr(active_fc ? fc_u_addr : u_addr), .v_addr(active_fc ? fc_v_addr : v_addr), .u_data(u_data), .v_data(v_data),
        .p_valid(active_fc ? fc_write : packed_rows), .p_ready(sram_p_ready),
        .p_addr(active_fc ? fc_write_addr : packed_v ? (mem_addr >> 1) : mem_addr),
        .p_data(active_fc ? fc_write_data : packed_v ? packed_tile : v_tile),
        .x_valid(x_valid), .x_ready(x_ready), .x_slot(x_slot), .x_addr(x_addr),
        .x_rvalid(x_rvalid), .x_rready(x_rready), .x_rdata(x_rdata),
        .y_valid(y_valid), .y_ready(y_ready), .y_slot(y_slot), .y_addr(y_addr), .y_data(y_data),
        .host_valid(host_valid && !host_mask && !mask_rvalid), .host_ready(sp_ready),
        .host_write(host_write), .host_bank(host_bank), .host_addr(host_addr), .host_wdata(host_wdata),
        .host_rvalid(sp_rvalid), .host_rready(host_rready && !mask_rvalid), .host_rdata(sp_rdata),
        .host_idle(sp_idle), .v_conflict_cycles(), .parallel_cycles()
    );
    vgg_row_mac_engine #(.ENABLE_FC(ENABLE_FC), .EXPLICIT_U_BASE(EXPLICIT_U_BASE), .U8_PACKED(U8_PACKED), .V8_PACKED(V8_PACKED), .ARBITRATED(1), .STREAMING(STREAM_V), .CHANNEL_BITS(CHANNEL_BITS)) u_engine (
        .fc_mode(active_fc),.fc_valid(fc_valid),.fc_ready(fc_ready),.fc_first(fc_first),.fc_last(fc_last),
        .fc_activation(fc_activation),.fc_weights(fc_weights),.fc_biases(fc_biases),
        .fc_result_valid(fc_result_valid),.fc_result_ready(fc_result_ready),.fc_result(fc_result),
        .clk(clk), .rst_n(rst_n), .start_valid(job_valid && job_ready), .start_ready(engine_ready),
        .tile_index(job_tile), .output_index(job_output), .u_shift(job_u_shift), .v_shift(job_v_shift), .channel_count(job_channels),
        .u_base_address(job_u_base),
        .sparse_enable(job_sparse), .zero_mask(engine_mask), .clear_accumulator(job_first),
        .available_channels(engine_available),
        .busy(busy), .row_read(row_read), .row_accept(row_accept),
        .u_addr(u_addr), .v_addr(v_addr), .u_data(u_data), .v_data(v_data),
        .result_valid(result_valid), .result_ready(result_ready),
        .result_data(result_data), .issued_rows(issued_rows)
    );
endmodule
`default_nettype wire
