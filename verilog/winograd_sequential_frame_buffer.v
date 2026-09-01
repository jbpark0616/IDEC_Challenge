`timescale 1ns/1ps

// FF-backed frame store with deterministic sequential write and read order.
// There is one logical read port; convolution window construction is handled
// by a separate streaming sliding-window generator.
module winograd_sequential_frame_buffer #(
    parameter integer DATA_BITS = 24,
    parameter integer DEPTH = 169,
    parameter integer ADDR_BITS = 8
) (
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire                     write_clear,
    input  wire                     write_valid,
    output wire                     write_ready,
    input  wire [DATA_BITS-1:0]     write_data,
    output reg                      full,

    input  wire                     read_start,
    output wire                     read_start_ready,
    output wire                     read_valid,
    input  wire                     read_ready,
    output wire [DATA_BITS-1:0]     read_data,

    // After sequential Conv2 consumption, the already-read low addresses
    // are reused for packed Conv2 output features. Execution phases are
    // mutually exclusive, so this remains one physical write/read datapath.
    input  wire                     reuse_write_valid,
    input  wire [ADDR_BITS-1:0]     reuse_write_address,
    input  wire [DATA_BITS-1:0]     reuse_write_data,
    input  wire                     reuse_read_select,
    input  wire [ADDR_BITS-1:0]     reuse_read_address
);
    reg [DATA_BITS-1:0] memory [0:DEPTH-1];
    reg [ADDR_BITS-1:0] write_pointer;
    reg [ADDR_BITS-1:0] read_pointer;
    reg read_active;

    assign write_ready = !full;
    assign read_start_ready = full && !read_active;
    assign read_valid = read_active;
    assign read_data = memory[reuse_read_select
                              ? reuse_read_address : read_pointer];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_pointer <= {ADDR_BITS{1'b0}};
            read_pointer <= {ADDR_BITS{1'b0}};
            full <= 1'b0;
            read_active <= 1'b0;
        end else begin
            if (write_clear) begin
                write_pointer <= {ADDR_BITS{1'b0}};
                full <= 1'b0;
            end else if (reuse_write_valid) begin
                memory[reuse_write_address] <= reuse_write_data;
            end else if (write_valid && write_ready) begin
                memory[write_pointer] <= write_data;
                if (write_pointer == DEPTH-1)
                    full <= 1'b1;
                else
                    write_pointer <= write_pointer + 1'b1;
            end

            if (read_start && read_start_ready) begin
                read_pointer <= {ADDR_BITS{1'b0}};
                read_active <= 1'b1;
            end else if (read_valid && read_ready) begin
                if (read_pointer == DEPTH-1)
                    read_active <= 1'b0;
                else
                    read_pointer <= read_pointer + 1'b1;
            end
        end
    end
endmodule
