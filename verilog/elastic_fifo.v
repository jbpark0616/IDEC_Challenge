`timescale 1ns/1ps

// Small FF-based synchronous FIFO with a valid-ready interface.
// Memory contents are intentionally not reset; count makes unused entries
// unobservable. Arbitrary DEPTH values are supported, not only powers of two.
module elastic_fifo #(
    parameter integer DATA_WIDTH = 176,
    parameter integer DEPTH      = 2
) (
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  in_valid,
    output wire                  in_ready,
    input  wire [DATA_WIDTH-1:0] in_data,

    output wire                  out_valid,
    input  wire                  out_ready,
    output wire [DATA_WIDTH-1:0] out_data,

    output wire                  full,
    output wire                  empty
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

    localparam integer PTR_BITS = (DEPTH <= 1) ? 1 : clog2(DEPTH);
    localparam integer COUNT_BITS = (DEPTH <= 1) ? 1 : clog2(DEPTH + 1);

    (* ram_style = "registers" *) reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    reg [PTR_BITS-1:0] write_pointer;
    reg [PTR_BITS-1:0] read_pointer;
    reg [COUNT_BITS-1:0] count;

    wire push;
    wire pop;

    assign empty = (count == 0);
    assign full = (count == DEPTH);
    assign out_valid = ~empty;
    assign out_data = memory[read_pointer];

    // A full FIFO can still accept one item when the current head is consumed
    // on the same edge. This preserves one-item-per-cycle throughput.
    assign in_ready = (~full) | (out_ready & out_valid);
    assign push = in_valid & in_ready;
    assign pop = out_valid & out_ready;

    // Keep storage out of the asynchronous-reset process. Only occupancy and
    // pointers define whether an entry is observable.
    always @(posedge clk) begin
        if (push)
            memory[write_pointer] <= in_data;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_pointer <= {PTR_BITS{1'b0}};
            read_pointer  <= {PTR_BITS{1'b0}};
            count         <= {COUNT_BITS{1'b0}};
        end else begin
            if (push) begin
                if (write_pointer == DEPTH-1)
                    write_pointer <= {PTR_BITS{1'b0}};
                else
                    write_pointer <= write_pointer + 1'b1;
            end

            if (pop) begin
                if (read_pointer == DEPTH-1)
                    read_pointer <= {PTR_BITS{1'b0}};
                else
                    read_pointer <= read_pointer + 1'b1;
            end

            case ({push, pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule
