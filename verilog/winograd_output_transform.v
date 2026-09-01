`timescale 1ns/1ps

// Winograd F(2x2, 3x3) output transform: Y = A^T M A
//
// Input M is a row-major 4x4 INT18 tile from channel reduction.
// Output Y is a row-major 2x2 INT18 tile. Every add/sub saturates to INT18,
// matching training/integer_inference.py exactly.
module winograd_output_transform #(
    parameter integer ACC_BITS = 18,
    parameter integer USER_BITS = 2
) (
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         in_valid,
    output wire                         in_ready,
    input  wire [16*ACC_BITS-1:0]       m_tile,
    input  wire [USER_BITS-1:0]         in_user,

    output reg                          out_valid,
    input  wire                         out_ready,
    output reg [4*ACC_BITS-1:0]         y_tile,
    output reg [USER_BITS-1:0]          out_user
);

    localparam signed [ACC_BITS:0] SAT_MAX_EXT =
        {2'b00, {(ACC_BITS-1){1'b1}}};
    localparam signed [ACC_BITS:0] SAT_MIN_EXT =
        {2'b11, {(ACC_BITS-1){1'b0}}};
    localparam signed [ACC_BITS-1:0] SAT_MAX =
        {1'b0, {(ACC_BITS-1){1'b1}}};
    localparam signed [ACC_BITS-1:0] SAT_MIN =
        {1'b1, {(ACC_BITS-1){1'b0}}};

    function signed [ACC_BITS-1:0] sat_add;
        input signed [ACC_BITS-1:0] lhs;
        input signed [ACC_BITS-1:0] rhs;
        reg signed [ACC_BITS:0] wide_result;
        begin
            wide_result = {lhs[ACC_BITS-1], lhs} + {rhs[ACC_BITS-1], rhs};
            if (wide_result > SAT_MAX_EXT)
                sat_add = SAT_MAX;
            else if (wide_result < SAT_MIN_EXT)
                sat_add = SAT_MIN;
            else
                sat_add = wide_result[ACC_BITS-1:0];
        end
    endfunction

    function signed [ACC_BITS-1:0] sat_sub;
        input signed [ACC_BITS-1:0] lhs;
        input signed [ACC_BITS-1:0] rhs;
        reg signed [ACC_BITS:0] wide_result;
        begin
            wide_result = {lhs[ACC_BITS-1], lhs} - {rhs[ACC_BITS-1], rhs};
            if (wide_result > SAT_MAX_EXT)
                sat_sub = SAT_MAX;
            else if (wide_result < SAT_MIN_EXT)
                sat_sub = SAT_MIN;
            else
                sat_sub = wide_result[ACC_BITS-1:0];
        end
    endfunction

    // A^T*M produces a 2x4 intermediate tile.
    reg  [8*ACC_BITS-1:0] left_tile;
    wire [8*ACC_BITS-1:0] left_next;
    wire [4*ACC_BITS-1:0] y_next;
    reg                    left_valid;
    reg  [USER_BITS-1:0]   left_user;

    wire output_stage_ready;
    wire left_stage_ready;

    assign output_stage_ready = (~out_valid) | out_ready;
    assign left_stage_ready = (~left_valid) | output_stage_ready;
    assign in_ready = left_stage_ready;

    // Stage O0: A^T*M. Two serial saturating operations per output value.
    genvar col;
    generate
        for (col = 0; col < 4; col = col + 1) begin : g_left
            wire signed [ACC_BITS-1:0] m0;
            wire signed [ACC_BITS-1:0] m1;
            wire signed [ACC_BITS-1:0] m2;
            wire signed [ACC_BITS-1:0] m3;
            wire signed [ACC_BITS-1:0] top_first;
            wire signed [ACC_BITS-1:0] bottom_first;
            wire signed [ACC_BITS-1:0] top_result;
            wire signed [ACC_BITS-1:0] bottom_result;

            assign m0 = m_tile[(0*4+col)*ACC_BITS +: ACC_BITS];
            assign m1 = m_tile[(1*4+col)*ACC_BITS +: ACC_BITS];
            assign m2 = m_tile[(2*4+col)*ACC_BITS +: ACC_BITS];
            assign m3 = m_tile[(3*4+col)*ACC_BITS +: ACC_BITS];

            assign top_first = sat_add(m0, m1);
            assign top_result = sat_add(top_first, m2);
            assign bottom_first = sat_sub(m1, m2);
            assign bottom_result = sat_sub(bottom_first, m3);

            assign left_next[(0*4+col)*ACC_BITS +: ACC_BITS] = top_result;
            assign left_next[(1*4+col)*ACC_BITS +: ACC_BITS] = bottom_result;
        end
    endgenerate

    // Stage O1: (A^T*M)*A. Again saturate after both operations.
    genvar row;
    generate
        for (row = 0; row < 2; row = row + 1) begin : g_right
            wire signed [ACC_BITS-1:0] s0;
            wire signed [ACC_BITS-1:0] s1;
            wire signed [ACC_BITS-1:0] s2;
            wire signed [ACC_BITS-1:0] s3;
            wire signed [ACC_BITS-1:0] left_first;
            wire signed [ACC_BITS-1:0] right_first;
            wire signed [ACC_BITS-1:0] left_result;
            wire signed [ACC_BITS-1:0] right_result;

            assign s0 = left_tile[(row*4+0)*ACC_BITS +: ACC_BITS];
            assign s1 = left_tile[(row*4+1)*ACC_BITS +: ACC_BITS];
            assign s2 = left_tile[(row*4+2)*ACC_BITS +: ACC_BITS];
            assign s3 = left_tile[(row*4+3)*ACC_BITS +: ACC_BITS];

            assign left_first = sat_add(s0, s1);
            assign left_result = sat_add(left_first, s2);
            assign right_first = sat_sub(s1, s2);
            assign right_result = sat_sub(right_first, s3);

            assign y_next[(row*2+0)*ACC_BITS +: ACC_BITS] = left_result;
            assign y_next[(row*2+1)*ACC_BITS +: ACC_BITS] = right_result;
        end
    endgenerate

    // Datapath registers intentionally have no reset. Valid bits make their
    // contents unobservable until real data has passed through each stage.
    always @(posedge clk) begin
        if (left_stage_ready && in_valid) begin
            left_tile <= left_next;
            left_user <= in_user;
        end
    end

    always @(posedge clk) begin
        if (output_stage_ready && left_valid) begin
            y_tile <= y_next;
            out_user <= left_user;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            left_valid <= 1'b0;
            out_valid  <= 1'b0;
        end else begin
            if (output_stage_ready)
                out_valid <= left_valid;
            if (left_stage_ready)
                left_valid <= in_valid;
        end
    end

endmodule
