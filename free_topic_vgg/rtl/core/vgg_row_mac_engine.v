`default_nettype none
// SRAM operand scheduler for the designated winograd_mac_array.
// Arithmetic, row enables, first/last accumulation and zero-weight isolation
// remain in the designated module. This adapter only replaces FF operand
// selection with four independently addressed synchronous SRAM row reads.
module vgg_row_mac_engine #(
    parameter ENABLE_FC = 0,
    parameter integer EXPLICIT_U_BASE = 0,
    parameter integer U8_PACKED = 0,
    parameter integer V8_PACKED = 0,
    parameter integer ARBITRATED = 0,
    parameter integer STREAMING = 0,
    parameter integer CHANNEL_BITS = 7
) (
    input wire fc_mode, fc_valid, fc_first, fc_last,
    output wire fc_ready, fc_result_valid,
    input wire fc_result_ready,
    input wire [7:0] fc_activation,
    input wire [255:0] fc_weights,
    input wire [511:0] fc_biases,
    output wire [767:0] fc_result,
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start_valid,
    output wire         start_ready,
    input  wire [2:0]   tile_index,
    input  wire [3:0]   output_index,
    input  wire [9:0]   u_base_address,
    input  wire [2:0]   u_shift,
    input wire [2:0] v_shift,
    input  wire [CHANNEL_BITS:0] channel_count,
    input  wire         sparse_enable,
    input  wire [4*(1<<CHANNEL_BITS)-1:0] zero_mask,
    input  wire [CHANNEL_BITS:0] available_channels,
    input  wire         clear_accumulator,
    output reg          busy,
    output wire [3:0]   row_read,
    input  wire         row_accept,
    output wire [39:0]  u_addr,
    output wire [39:0]  v_addr,
    input  wire [255:0] u_data,
    input  wire [255:0] v_data,
    output wire         result_valid,
    input  wire         result_ready,
    output wire [767:0] result_data,
    output wire [4*(CHANNEL_BITS+1)-1:0] issued_rows
);
    wire active_fc = ENABLE_FC && fc_mode;
    localparam integer FC_LANES=ENABLE_FC ? 16 : 10;
    assign fc_ready = active_fc && mac_ready;
    assign fc_result_valid = active_fc && mac_result_valid;
    assign fc_result = mac_result;
    localparam integer CHANNELS=1<<CHANNEL_BITS;
    reg [3:0] saved_stride;
    wire [3:0] command_stride=CHANNEL_BITS==7 ? 4'd7
                            : channel_count>256 ? 4'd9 : channel_count>128 ? 4'd8 : 4'd7;
    reg [2:0] saved_tile;
    reg [3:0] saved_output;
    reg [9:0] saved_u_base;
    reg [2:0] saved_u_shift, saved_v_shift;
    wire [255:0] mac_operands;
    wire [255:0] mac_weights;
    reg first_request;
    reg last_requested;
    reg response_valid;
    reg response_first;
    reg response_last;
    reg [3:0] response_rows;
    wire [3:0] remaining_valid;
    wire [3:0] last_in_row;
    wire [CHANNELS-1:0] channel_mask;
    wire [CHANNELS-1:0] ready_mask;
    wire mac_ready;
    wire mac_result_valid;
    wire [767:0] mac_result;
    reg bypass_valid;
    reg accumulator_is_zero;
    wire [3:0] empty_row;
    wire whole_zero_job = sparse_enable && (&empty_row);
    wire start_fire = start_valid && start_ready;
    // SRAM output retains the previous response until another read. A new
    // read can replace it only when the MAC accepts it or no response exists.
    // A gap in the producer stream is not end-of-reduction. An empty final
    // beat is allowed only after every channel has arrived and was skipped.
    wire request_beat = busy && !bypass_valid && !last_requested
                      && (!response_valid || mac_ready)
                      && ((|remaining_valid) || (&last_in_row));
    // Preserve whole-zero bypass even when its zero status becomes known
    // incrementally. No MAC beat has been issued while first_request is set.
    wire streaming_zero_complete = STREAMING && request_beat
                                 && !(|remaining_valid) && first_request;
    wire issue_beat = request_beat && !streaming_zero_complete
                   && (!ARBITRATED || row_accept);
    assign start_ready = !active_fc && !busy && !result_valid;
    assign result_valid = !active_fc && (bypass_valid || mac_result_valid);
    assign result_data = bypass_valid && accumulator_is_zero ? 768'b0 : mac_result;

    genvar c, r, lane;
    generate for (c=0; c<CHANNELS; c=c+1) begin : g_channel
        assign channel_mask[c] = c < channel_count;
        assign ready_mask[c] = !STREAMING || c < available_channels;
    end endgenerate
    generate for (r=0; r<4; r=r+1) begin : g_row
        reg [CHANNELS-1:0] remaining;
        reg [CHANNEL_BITS:0] row_count;
        wire [CHANNEL_BITS-1:0] next_channel;
        wire [CHANNELS-1:0] chosen;
        wire [CHANNELS-1:0] known_zero = STREAMING && sparse_enable
                               ? zero_mask[r*CHANNELS +: CHANNELS] & ready_mask : {CHANNELS{1'b0}};
        wire [CHANNELS-1:0] pending_channels = remaining & ~known_zero;
        assign empty_row[r] = !(|(channel_mask & ~zero_mask[r*CHANNELS +: CHANNELS]));
        vgg_first_one_channels #(.CHANNEL_BITS(CHANNEL_BITS)) u_pick (
            .bits(pending_channels & ready_mask), .valid(remaining_valid[r]),
            .index(next_channel), .onehot(chosen)
        );
        assign last_in_row[r] = !(|(pending_channels & ~chosen));
        assign row_read[r] = request_beat && remaining_valid[r];
        // U8 packs two input-channel rows per word. Divide the stride
        // BEFORE narrowing the physical address, including K>=2 at C=512.
        assign u_addr[r*10 +: 10] = EXPLICIT_U_BASE
            ? saved_u_base + (U8_PACKED ? ({{(10-CHANNEL_BITS){1'b0}},next_channel} >> 1)
                                       : {{(10-CHANNEL_BITS){1'b0}},next_channel})
            : U8_PACKED
            ? (({6'b0,saved_output} << (saved_stride-4'd1))
               + ({{(10-CHANNEL_BITS){1'b0}},next_channel} >> 1))
            : (({6'b0,saved_output} << saved_stride)
               + {{(10-CHANNEL_BITS){1'b0}},next_channel});
        if (U8_PACKED) begin : g_unpack
            reg response_half;
            wire [31:0] packed_row = response_half
                ? u_data[r*64+32 +: 32] : u_data[r*64 +: 32];
            // Each row can skip to a different channel. Carry that row's
            // half selector alongside the synchronous SRAM response.
            always @(posedge clk)
                if (issue_beat) response_half <= next_channel[0];
            for (lane=0; lane<4; lane=lane+1) begin : g_lane
                wire signed [7:0] quantized = packed_row[lane*8 +: 8];
                wire signed [15:0] extended = {{8{quantized[7]}},quantized};
                // Restore the per-output-channel power-of-two scale before
                // the existing MAC. Accumulator/OT/bias units stay unchanged.
                assign mac_weights[r*64+lane*16 +: 16] = extended <<< saved_u_shift;
            end
        end else begin : g_u16
            assign mac_weights[r*64 +: 64] = u_data[r*64 +: 64];
        end
        wire [9:0] logical_v_addr=({7'b0,saved_tile} << saved_stride) + {{(10-CHANNEL_BITS){1'b0}},next_channel};
        assign v_addr[r*10 +:10]=V8_PACKED ? logical_v_addr >> 1 : logical_v_addr;
        if(V8_PACKED) begin : g_v_unpack
            reg response_half;
            always @(posedge clk) if(issue_beat) response_half<=next_channel[0];
            wire [31:0] bytes=response_half ? v_data[r*64+32 +:32] : v_data[r*64 +:32];
            for(lane=0;lane<4;lane=lane+1) begin : g_lane
                wire signed [7:0] q=bytes[lane*8 +:8];
                wire signed [15:0] extended={{8{q[7]}},q};
                assign mac_operands[r*64+lane*16 +:16]=extended <<< saved_v_shift;
            end
        end else assign mac_operands[r*64 +:64]=v_data[r*64 +:64];
        assign issued_rows[r*(CHANNEL_BITS+1) +: (CHANNEL_BITS+1)] = row_count;
        always @(posedge clk) begin
            if (start_fire) begin
                remaining <= channel_mask & ((!STREAMING && sparse_enable)
                           ? ~zero_mask[r*CHANNELS +: CHANNELS] : {CHANNELS{1'b1}});
                row_count <= 0;
            end else if (busy) begin
                remaining <= pending_channels & (issue_beat ? ~chosen : {CHANNELS{1'b1}});
                if (issue_beat && remaining_valid[r]) row_count <= row_count + 1'b1;
            end
        end
    end endgenerate

    winograd_mac_array #(
        .FC_CLASSES(FC_LANES), .WEIGHT_BITS(16), .OPERAND_BITS(16), .PRODUCT_BITS(32),
        .ACC_BITS(48), .BIAS_BITS(32)
    ) u_mac (
        .clk(clk), .rst_n(rst_n), .mode_fc(active_fc),
        .in_valid(active_fc ? fc_valid : response_valid), .in_ready(mac_ready),
        .txn_first(active_fc ? fc_first : response_first), .txn_last(active_fc ? fc_last : response_last),
        .conv_row_enable(response_rows), .conv_operand_vec(mac_operands), .conv_weight_vec(mac_weights),
        .fc_activation(fc_activation), .fc_weight_vec(fc_weights[FC_LANES*16-1:0]), .fc_bias_vec(fc_biases[FC_LANES*32-1:0]),
        .out_valid(mac_result_valid), .out_ready(active_fc ? fc_result_ready : result_ready && !bypass_valid),
        .result_vec(mac_result), .accumulator_vec()
    );

    always @(posedge clk) begin
        if (start_fire) begin
            saved_tile <= tile_index;
            saved_stride <= command_stride;
            saved_output <= output_index;
            saved_u_base <= u_base_address;
            saved_u_shift <= U8_PACKED ? u_shift : 3'd0;
            saved_v_shift <= V8_PACKED ? v_shift : 3'd0;
            first_request <= clear_accumulator || accumulator_is_zero;
        end else if (issue_beat)
            first_request <= 1'b0;
        if (issue_beat) begin
            response_rows <= remaining_valid;
            response_first <= first_request;
            response_last <= &last_in_row;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            last_requested <= 1'b0;
            response_valid <= 1'b0;
            bypass_valid <= 1'b0;
            accumulator_is_zero <= 1'b1;
        end else begin
            if (!response_valid || mac_ready)
                response_valid <= issue_beat;
            if (issue_beat && (&last_in_row))
                last_requested <= 1'b1;
            if (streaming_zero_complete) begin
                bypass_valid <= 1'b1;
                accumulator_is_zero <= 1'b1;
            end
            if (result_valid && result_ready) begin
                busy <= 1'b0;
                bypass_valid <= 1'b0;
            end
            if (start_fire) begin
                busy <= 1'b1;
                last_requested <= 1'b0;
                bypass_valid <= !STREAMING && whole_zero_job;
                // A zero first block need not clock the MAC to clear its FFs.
                // Its next nonzero continuation uses txn_first instead.
                if (clear_accumulator || !whole_zero_job || STREAMING)
                    accumulator_is_zero <= !STREAMING && whole_zero_job;
            end
        end
    end
endmodule
`default_nettype wire
