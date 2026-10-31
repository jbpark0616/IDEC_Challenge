`timescale 1ns/1ps

// FF-based circular buffer for transformed Winograd activation tiles.
//
// One spatial tile consists of C transformed channel tiles. The complete group
// is replayed K times. Four independent row cursors choose the next nonzero
// channel, preserving channel order within each row. A common first/last beat
// initializes normal-job accumulators and joins the four reductions. An
// entirely zero group emits one metadata beat (row_enable=0, first=last=1).
// The integrated core routes that beat around MAC and output-transform into
// its ordering FIFO; it is NOT a MAC issue or an arithmetic completion beat.
module winograd_v_replay_buffer #(
    parameter integer V_TILE_BITS        = 176,
    parameter integer MAX_INPUT_CHANNELS = 3,
    parameter integer GROUP_DEPTH        = 2,
    parameter integer CHANNEL_BITS       = 2
) (
    input  wire                       clk,
    input  wire                       rst_n,

    // Configuration must remain stable while the buffer is nonempty or while
    // an input group is being assembled. Values are encoded as count minus 1.
    input  wire [CHANNEL_BITS-1:0]     input_channels_minus1,
    input  wire [CHANNEL_BITS-1:0]     output_channels_minus1,

    input  wire                       in_valid,
    output wire                       in_ready,
    input  wire [V_TILE_BITS-1:0]     in_v_tile,
    input  wire [3:0]                 in_zero_rows,

    output wire                       out_valid,
    input  wire                       out_ready,
    output reg [V_TILE_BITS-1:0]      out_v_tile,
    output reg [4*CHANNEL_BITS-1:0]   input_channels,
    output reg [4*MAX_INPUT_CHANNELS-1:0] channel_select,
    output reg [3:0]                 row_enable,
    output wire [CHANNEL_BITS-1:0]    output_channel,
    output reg                        txn_first,
    output wire                       txn_last,

    output wire                       full,
    output wire                       empty
);

    function integer clog2;
        input integer value;
        integer temp;
        begin
            temp = value - 1;
            for (clog2 = 0; temp > 0; clog2 = clog2 + 1)
                temp = temp >> 1;
        end
    endfunction

    localparam integer GROUP_PTR_BITS =
        (GROUP_DEPTH <= 1) ? 1 : clog2(GROUP_DEPTH);
    localparam integer GROUP_COUNT_BITS =
        (GROUP_DEPTH <= 1) ? 1 : clog2(GROUP_DEPTH + 1);

    (* ram_style = "registers" *) reg [V_TILE_BITS-1:0]
        memory [0:GROUP_DEPTH*MAX_INPUT_CHANNELS-1];
    reg [3:0] zero_memory [0:GROUP_DEPTH*MAX_INPUT_CHANNELS-1];
    reg [GROUP_PTR_BITS-1:0] write_group_pointer;
    reg [GROUP_PTR_BITS-1:0] read_group_pointer;
    reg [CHANNEL_BITS-1:0] write_channel;
    // One bit per channel, cleared when its row is issued. Avoid binary
    // cursor increment/comparators and binary encode/decode on the data path.
    reg [MAX_INPUT_CHANNELS-1:0] row_remaining [0:3];
    reg [CHANNEL_BITS-1:0] read_output_channel;
    reg [GROUP_COUNT_BITS-1:0] group_count;
    reg write_active;

    wire push;
    wire pop;
    wire complete_write;
    wire complete_read;
    wire [GROUP_PTR_BITS+CHANNEL_BITS-1:0] write_address;

    assign empty = (group_count == 0);
    assign full = (group_count == GROUP_DEPTH);
    assign out_valid = ~empty;
    assign output_channel = read_output_channel;
    reg [3:0] row_has_more;
    assign txn_last = ~|row_has_more;

    reg [MAX_INPUT_CHANNELS-1:0] eligible [0:3];
    reg [MAX_INPUT_CHANNELS-1:0] picked [0:3];
    integer r, c;
    always @* begin
        out_v_tile = {V_TILE_BITS{1'b0}};
        input_channels = {4*CHANNEL_BITS{1'b0}};
        channel_select = {4*MAX_INPUT_CHANNELS{1'b0}};
        row_enable = 4'b0;
        row_has_more = 4'b0;
        for (r=0; r<4; r=r+1) begin
            eligible[r] = 0;
            picked[r] = 0;
            for (c=0; c<MAX_INPUT_CHANNELS; c=c+1) begin
                eligible[r][c] = out_valid && row_remaining[r][c]
                    && c <= input_channels_minus1
                    && !zero_memory[read_group_pointer*MAX_INPUT_CHANNELS+c][r];
                if (eligible[r][c]) begin
                    if (!row_enable[r]) begin
                        row_enable[r] = 1'b1;
                        picked[r][c] = 1'b1;
                        input_channels[r*CHANNEL_BITS +: CHANNEL_BITS] = c;
                    end else
                        row_has_more[r] = 1'b1;
                end
            end
            channel_select[r*MAX_INPUT_CHANNELS +: MAX_INPUT_CHANNELS] = picked[r];
            // The control priority is resolved once. Data uses mutually
            // exclusive masked-OR terms instead of a priority mux cascade.
            for (c=0; c<MAX_INPUT_CHANNELS; c=c+1)
                out_v_tile[r*(V_TILE_BITS/4) +: V_TILE_BITS/4] =
                    out_v_tile[r*(V_TILE_BITS/4) +: V_TILE_BITS/4] |
                    ({(V_TILE_BITS/4){picked[r][c]}} &
                     memory[read_group_pointer*MAX_INPUT_CHANNELS+c]
                           [r*(V_TILE_BITS/4) +: V_TILE_BITS/4]);
        end
    end

    assign write_address = write_group_pointer * MAX_INPUT_CHANNELS
                         + write_channel;

    assign pop = out_valid & out_ready;
    assign complete_read = pop
                         & txn_last
                         & (read_output_channel == output_channels_minus1);

    // An unfinished group has already reserved its write slot. When all slots
    // contain complete groups, a same-cycle final read releases one for reuse.
    assign in_ready = write_active | (~full) | complete_read;
    assign push = in_valid & in_ready;
    assign complete_write = push & (write_channel == input_channels_minus1);

    // The payload array is an FF scratchpad and has no reset. Group count and
    // pointers make unwritten contents unobservable.
    always @(posedge payload_clk) begin
        if (push) begin
            memory[write_address] <= in_v_tile;
            zero_memory[write_address] <= in_zero_rows;
        end
    end

    integer row_index;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_group_pointer <= {GROUP_PTR_BITS{1'b0}};
            read_group_pointer  <= {GROUP_PTR_BITS{1'b0}};
            write_channel       <= {CHANNEL_BITS{1'b0}};
            txn_first           <= 1'b1;
            for (row_index=0; row_index<4; row_index=row_index+1)
                row_remaining[row_index] <= {MAX_INPUT_CHANNELS{1'b1}};
            read_output_channel <= {CHANNEL_BITS{1'b0}};
            group_count         <= {GROUP_COUNT_BITS{1'b0}};
            write_active        <= 1'b0;
        end else begin
            if (push) begin
                if (write_channel == input_channels_minus1) begin
                    write_channel <= {CHANNEL_BITS{1'b0}};
                    write_active <= 1'b0;
                    if (write_group_pointer == GROUP_DEPTH-1)
                        write_group_pointer <= {GROUP_PTR_BITS{1'b0}};
                    else
                        write_group_pointer <= write_group_pointer + 1'b1;
                end else begin
                    write_channel <= write_channel + 1'b1;
                    write_active <= 1'b1;
                end
            end

            if (pop) begin
                txn_first <= txn_last;
                for (row_index=0; row_index<4; row_index=row_index+1) begin
                    if (txn_last)
                        row_remaining[row_index] <= {MAX_INPUT_CHANNELS{1'b1}};
                    else
                        row_remaining[row_index] <= row_remaining[row_index] & ~picked[row_index];
                end
                if (txn_last) begin
                    if (read_output_channel == output_channels_minus1) begin
                        read_output_channel <= {CHANNEL_BITS{1'b0}};
                        if (read_group_pointer == GROUP_DEPTH-1)
                            read_group_pointer <= {GROUP_PTR_BITS{1'b0}};
                        else
                            read_group_pointer <= read_group_pointer + 1'b1;
                    end else begin
                        read_output_channel <= read_output_channel + 1'b1;
                    end
                end
            end

            case ({complete_write, complete_read})
                2'b10: group_count <= group_count + 1'b1;
                2'b01: group_count <= group_count - 1'b1;
                default: group_count <= group_count;
            endcase
        end
    end


    // Data clocks only; handshake/control registers retain the root clock.
    wire payload_clk;
    winograd_clock_gate cg_payload_clk (.clk(clk), .enable(push), .gclk(payload_clk));

endmodule
