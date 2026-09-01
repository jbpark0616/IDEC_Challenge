`timescale 1ns/1ps

// FF-based circular buffer for transformed Winograd activation tiles.
//
// One spatial tile consists of C transformed channel tiles. The complete group
// is replayed K times so the MAC can calculate every output channel without
// recomputing V. The group is removed only after the final (k,c) transaction.
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

    output wire                       out_valid,
    input  wire                       out_ready,
    output wire [V_TILE_BITS-1:0]     out_v_tile,
    output wire [CHANNEL_BITS-1:0]    input_channel,
    output wire [CHANNEL_BITS-1:0]    output_channel,
    output wire                       txn_first,
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
    reg [GROUP_PTR_BITS-1:0] write_group_pointer;
    reg [GROUP_PTR_BITS-1:0] read_group_pointer;
    reg [CHANNEL_BITS-1:0] write_channel;
    reg [CHANNEL_BITS-1:0] read_channel;
    reg [CHANNEL_BITS-1:0] read_output_channel;
    reg [GROUP_COUNT_BITS-1:0] group_count;
    reg write_active;

    wire push;
    wire pop;
    wire complete_write;
    wire complete_read;
    wire [GROUP_PTR_BITS+CHANNEL_BITS-1:0] write_address;
    wire [GROUP_PTR_BITS+CHANNEL_BITS-1:0] read_address;

    assign empty = (group_count == 0);
    assign full = (group_count == GROUP_DEPTH);
    assign out_valid = ~empty;
    assign input_channel = read_channel;
    assign output_channel = read_output_channel;
    assign txn_first = (read_channel == 0);
    assign txn_last = (read_channel == input_channels_minus1);

    assign write_address = write_group_pointer * MAX_INPUT_CHANNELS
                         + write_channel;
    assign read_address = read_group_pointer * MAX_INPUT_CHANNELS
                        + read_channel;
    assign out_v_tile = memory[read_address];

    assign pop = out_valid & out_ready;
    assign complete_read = pop
                         & (read_channel == input_channels_minus1)
                         & (read_output_channel == output_channels_minus1);

    // An unfinished group has already reserved its write slot. When all slots
    // contain complete groups, a same-cycle final read releases one for reuse.
    assign in_ready = write_active | (~full) | complete_read;
    assign push = in_valid & in_ready;
    assign complete_write = push & (write_channel == input_channels_minus1);

    // The payload array is an FF scratchpad and has no reset. Group count and
    // pointers make unwritten contents unobservable.
    always @(posedge clk) begin
        if (push)
            memory[write_address] <= in_v_tile;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_group_pointer <= {GROUP_PTR_BITS{1'b0}};
            read_group_pointer  <= {GROUP_PTR_BITS{1'b0}};
            write_channel       <= {CHANNEL_BITS{1'b0}};
            read_channel        <= {CHANNEL_BITS{1'b0}};
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
                if (read_channel == input_channels_minus1) begin
                    read_channel <= {CHANNEL_BITS{1'b0}};
                    if (read_output_channel == output_channels_minus1) begin
                        read_output_channel <= {CHANNEL_BITS{1'b0}};
                        if (read_group_pointer == GROUP_DEPTH-1)
                            read_group_pointer <= {GROUP_PTR_BITS{1'b0}};
                        else
                            read_group_pointer <= read_group_pointer + 1'b1;
                    end else begin
                        read_output_channel <= read_output_channel + 1'b1;
                    end
                end else begin
                    read_channel <= read_channel + 1'b1;
                end
            end

            case ({complete_write, complete_read})
                2'b10: group_count <= group_count + 1'b1;
                2'b01: group_count <= group_count - 1'b1;
                default: group_count <= group_count;
            endcase
        end
    end

endmodule
