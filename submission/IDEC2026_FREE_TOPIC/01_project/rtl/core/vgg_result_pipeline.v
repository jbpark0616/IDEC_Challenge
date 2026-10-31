`default_nettype none
// Designated result dataflow: normal M FIFO -> OT, with a small order FIFO
// joining whole-zero jobs directly at postprocess. Complete results only;
// no partial-sum contexts or extra accumulator are stored here.
module vgg_result_pipeline (
    input wire clk, rst_n, start,
    input wire pooling,
    input wire [255:0] biases,
    input wire [191:0] multipliers,
    input wire in_valid,
    output wire in_ready,
    input wire [767:0] in_m,
    input wire in_zero, in_last,
    input wire [2:0] in_channel,
    output reg word_valid,
    input wire word_ready,
    output reg [63:0] word_data,
    output reg word_last,
    output wire byte_accepted
);
    wire order_in_ready, order_valid, order_ready;
    wire [4:0] order;
    wire m_in_ready, m_valid, m_ready;
    wire [767:0] m_tile;

    // Atomically enqueue a descriptor and, for nonzero jobs, its M payload.
    assign in_ready = order_in_ready && (in_zero || m_in_ready);
    elastic_fifo #(.DATA_WIDTH(5), .DEPTH(8)) u_order_fifo (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid && (in_zero || m_in_ready)), .in_ready(order_in_ready),
        .in_data({in_last,in_zero,in_channel}),
        .out_valid(order_valid), .out_ready(order_ready), .out_data(order),
        .full(), .empty()
    );
    winograd_m_fifo #(.ACC_BITS(48), .DEPTH(1), .CHANNEL_BITS(3)) u_m_fifo (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid && !in_zero && order_in_ready), .in_ready(m_in_ready),
        .in_m_tile(in_m), .in_output_channel(3'b0),
        .out_valid(m_valid), .out_ready(m_ready), .out_m_tile(m_tile),
        .out_output_channel(), .full(), .empty()
    );

    wire normal_valid, normal_ready;
    wire [191:0] normal_tile;
    winograd_output_transform #(.ACC_BITS(48), .USER_BITS(1)) u_output (
        .clk(clk), .rst_n(rst_n),
        .in_valid(m_valid), .in_ready(m_ready), .m_tile(m_tile), .in_user(1'b0),
        .out_valid(normal_valid), .out_ready(normal_ready),
        .y_tile(normal_tile), .out_user()
    );

    // Hold the head tile while its four pixels enter the pipelined post unit.
    // Advancing its input cursor does not wait for previous pixel outputs.
    reg [1:0] pixel;
    wire joined_valid = order_valid && (order[3] || normal_valid);
    wire [191:0] joined_tile = order[3] ? 192'b0 : normal_tile;
    wire [47:0] selected_pixel = joined_tile[pixel*48 +: 48];
    wire last_pixel = pooling || pixel == 3;
    wire post_in_ready, post_valid, post_ready, post_last;
    wire [7:0] post_activation;
    wire post_input_fire = joined_valid && post_in_ready;
    assign order_ready = post_in_ready && (order[3] || normal_valid) && last_pixel;
    assign normal_ready = order_valid && !order[3] && post_in_ready && last_pixel;

    winograd_postprocess #(.ACC_BITS(48), .BIAS_BITS(32), .USER_BITS(1)) u_post (
        .clk(clk), .rst_n(rst_n),
        .in_valid(joined_valid), .in_ready(post_in_ready),
        .y_tile(pooling ? joined_tile : {4{selected_pixel}}),
        .bias(biases[order[2:0]*32 +: 32]),
        .requant_multiplier(multipliers[order[2:0]*24 +: 24]),
        .in_user(order[4] && last_pixel),
        .out_valid(post_valid), .out_ready(post_ready),
        .activation(post_activation), .out_user(post_last)
    );

    // One 64-bit output staging word. Drain and begin the next word on the
    // same edge, so no explicit ADVANCE/WRITE wait state is needed per byte.
    reg [2:0] pack_count;
    wire word_fire = word_valid && word_ready;
    assign post_ready = !word_valid || word_ready;
    assign byte_accepted = post_valid && post_ready;

    always @(posedge clk) begin
        if (start || word_fire) word_data <= 0;
        if (byte_accepted) begin
            if (pack_count == 0)
                word_data <= {56'b0,post_activation};
            else
                word_data[pack_count*8 +: 8] <= post_activation;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel <= 0;
            pack_count <= 0;
            word_valid <= 0;
            word_last <= 0;
        end else if (start) begin
            pixel <= 0;
            pack_count <= 0;
            word_valid <= 0;
            word_last <= 0;
        end else begin
            if (post_input_fire) pixel <= last_pixel ? 0 : pixel+1'b1;
            if (word_fire) word_valid <= 0;
            if (byte_accepted) begin
                if (pack_count == 7 || post_last) begin
                    pack_count <= 0;
                    word_valid <= 1;
                    word_last <= post_last;
                end else
                    pack_count <= pack_count+1'b1;
            end
        end
    end
endmodule
`default_nettype wire
