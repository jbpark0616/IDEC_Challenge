`default_nettype none
// Ordered, lossless fanout. A receiver accepts each word exactly once even
// when the other receivers stall. Completion here means endpoint acceptance,
// not final use of the source activation or consumption by a MAC.
module vgg_mcast_fanout #(
    parameter integer DEPTH = 4,
    parameter integer CORES = 4
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    output wire        in_ready,
    input  wire [63:0] in_data,
    input  wire [7:0]  in_keep,
    input  wire        in_last,
    input  wire [CORES-1:0]  in_destinations,
    output wire [CORES-1:0]  out_valid,
    input  wire [CORES-1:0]  out_ready,
    output wire [63:0] out_data,
    output wire [7:0]  out_keep,
    output wire        out_last,
    output wire        idle
);
    wire        head_valid;
    wire        head_ready;
    wire        queue_full;
    wire        queue_ready;
    wire [72+CORES:0] head;
    wire [CORES-1:0]  destinations = head[73 +: CORES];
    reg  [CORES-1:0]  delivered;

    wire [CORES-1:0] pending = destinations & ~delivered;
    wire [CORES-1:0] accepted = out_valid & out_ready;

    assign out_valid = pending & {CORES{head_valid && rst_n}};
    assign {out_last, out_keep, out_data} = head[72:0];
    assign head_ready = head_valid && !(|(pending & ~out_ready));
    assign idle = !head_valid;

    // Break the receiver-ready -> FIFO lookahead -> sender-ready path.
    // DEPTH >= 2 sustains one word/cycle with occupancy below full. A full
    // queue resumes admission on the cycle after a pop, adding no storage.
    // Keep the depth-one fallback's simultaneous replacement throughput.
    assign in_ready = rst_n && ((DEPTH > 1) ? !queue_full : queue_ready);

    elastic_fifo #(.DATA_WIDTH(73+CORES), .DEPTH(DEPTH)) u_words (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid && in_ready), .in_ready(queue_ready),
        .in_data({in_destinations, in_last, in_keep, in_data}),
        .out_valid(head_valid), .out_ready(head_ready), .out_data(head),
        .full(queue_full), .empty()
    );

    // Only the current head needs a delivered mask; queued words have not
    // reached any receiver. No per-destination payload copies are necessary.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            delivered <= {CORES{1'b0}};
        else if (head_ready)
            delivered <= {CORES{1'b0}};
        else if (head_valid)
            delivered <= delivered | accepted;
    end
endmodule
`default_nettype wire
