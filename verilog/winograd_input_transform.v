`timescale 1ns/1ps

// Winograd F(2x2, 3x3) activation transform: V = B^T d B
//
// Input and output use row-major, LSB-first packing:
//   element (row, col) occupies [(row*4+col)*WIDTH +: WIDTH].
//
// B^T = [ 1  0 -1  0 ]
//       [ 0  1  1  0 ]
//       [ 0 -1  1  0 ]
//       [ 0  1  0 -1 ]
//
// The transform is separable and contains only additions/subtractions.
// Stage T0 performs B^T*d; stage T1 performs the right-side *B.
module winograd_input_transform #(
    parameter integer TILE_SIZE = 4,
    parameter integer ACT_BITS  = 8,
    parameter integer TEMP_BITS = 10,
    parameter integer V_BITS    = 11
) (
    input  wire                            clk,
    input  wire                            rst_n,

    input  wire                            in_valid,
    output wire                            in_ready,
    input  wire [TILE_SIZE*TILE_SIZE*ACT_BITS-1:0] activation_tile,

    output reg                             out_valid,
    input  wire                            out_ready,
    output reg [TILE_SIZE*TILE_SIZE*V_BITS-1:0] v_tile
);

    reg                                   temp_valid;
    reg [TILE_SIZE*TILE_SIZE*TEMP_BITS-1:0] temp_tile;
    wire [TILE_SIZE*TILE_SIZE*TEMP_BITS-1:0] temp_next;
    wire [TILE_SIZE*TILE_SIZE*V_BITS-1:0] v_next;

    wire output_stage_ready;
    wire temp_stage_ready;

    assign output_stage_ready = (~out_valid) | out_ready;
    assign temp_stage_ready = (~temp_valid) | output_stage_ready;
    assign in_ready = temp_stage_ready;

    // T0: apply B^T down each input column.
    genvar col;
    generate
        for (col = 0; col < TILE_SIZE; col = col + 1) begin : g_vertical
            wire signed [TEMP_BITS-1:0] d0;
            wire signed [TEMP_BITS-1:0] d1;
            wire signed [TEMP_BITS-1:0] d2;
            wire signed [TEMP_BITS-1:0] d3;
            wire signed [TEMP_BITS-1:0] t0;
            wire signed [TEMP_BITS-1:0] t1;
            wire signed [TEMP_BITS-1:0] t2;
            wire signed [TEMP_BITS-1:0] t3;

            assign d0 = {{(TEMP_BITS-ACT_BITS){1'b0}},
                         activation_tile[(0*TILE_SIZE+col)*ACT_BITS +: ACT_BITS]};
            assign d1 = {{(TEMP_BITS-ACT_BITS){1'b0}},
                         activation_tile[(1*TILE_SIZE+col)*ACT_BITS +: ACT_BITS]};
            assign d2 = {{(TEMP_BITS-ACT_BITS){1'b0}},
                         activation_tile[(2*TILE_SIZE+col)*ACT_BITS +: ACT_BITS]};
            assign d3 = {{(TEMP_BITS-ACT_BITS){1'b0}},
                         activation_tile[(3*TILE_SIZE+col)*ACT_BITS +: ACT_BITS]};

            assign t0 = d0 - d2;
            assign t1 = d1 + d2;
            assign t2 = d2 - d1;
            assign t3 = d1 - d3;

            assign temp_next[(0*TILE_SIZE+col)*TEMP_BITS +: TEMP_BITS] = t0;
            assign temp_next[(1*TILE_SIZE+col)*TEMP_BITS +: TEMP_BITS] = t1;
            assign temp_next[(2*TILE_SIZE+col)*TEMP_BITS +: TEMP_BITS] = t2;
            assign temp_next[(3*TILE_SIZE+col)*TEMP_BITS +: TEMP_BITS] = t3;
        end
    endgenerate

    // T1: apply the same transform across every temporary row.
    genvar row;
    generate
        for (row = 0; row < TILE_SIZE; row = row + 1) begin : g_horizontal
            wire signed [TEMP_BITS-1:0] s0;
            wire signed [TEMP_BITS-1:0] s1;
            wire signed [TEMP_BITS-1:0] s2;
            wire signed [TEMP_BITS-1:0] s3;
            wire signed [V_BITS-1:0] e0;
            wire signed [V_BITS-1:0] e1;
            wire signed [V_BITS-1:0] e2;
            wire signed [V_BITS-1:0] e3;
            wire signed [V_BITS-1:0] v0;
            wire signed [V_BITS-1:0] v1;
            wire signed [V_BITS-1:0] v2;
            wire signed [V_BITS-1:0] v3;

            assign s0 = temp_tile[(row*TILE_SIZE+0)*TEMP_BITS +: TEMP_BITS];
            assign s1 = temp_tile[(row*TILE_SIZE+1)*TEMP_BITS +: TEMP_BITS];
            assign s2 = temp_tile[(row*TILE_SIZE+2)*TEMP_BITS +: TEMP_BITS];
            assign s3 = temp_tile[(row*TILE_SIZE+3)*TEMP_BITS +: TEMP_BITS];

            assign e0 = {{(V_BITS-TEMP_BITS){s0[TEMP_BITS-1]}}, s0};
            assign e1 = {{(V_BITS-TEMP_BITS){s1[TEMP_BITS-1]}}, s1};
            assign e2 = {{(V_BITS-TEMP_BITS){s2[TEMP_BITS-1]}}, s2};
            assign e3 = {{(V_BITS-TEMP_BITS){s3[TEMP_BITS-1]}}, s3};

            assign v0 = e0 - e2;
            assign v1 = e1 + e2;
            assign v2 = e2 - e1;
            assign v3 = e1 - e3;

            assign v_next[(row*TILE_SIZE+0)*V_BITS +: V_BITS] = v0;
            assign v_next[(row*TILE_SIZE+1)*V_BITS +: V_BITS] = v1;
            assign v_next[(row*TILE_SIZE+2)*V_BITS +: V_BITS] = v2;
            assign v_next[(row*TILE_SIZE+3)*V_BITS +: V_BITS] = v3;
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            temp_tile <= {TILE_SIZE*TILE_SIZE*TEMP_BITS{1'b0}};
        else if (temp_stage_ready && in_valid)
            temp_tile <= temp_next;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            v_tile <= {TILE_SIZE*TILE_SIZE*V_BITS{1'b0}};
        else if (output_stage_ready && temp_valid)
            v_tile <= v_next;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            temp_valid <= 1'b0;
            out_valid  <= 1'b0;
        end else begin
            if (output_stage_ready)
                out_valid <= temp_valid;

            if (temp_stage_ready)
                temp_valid <= in_valid;
        end
    end

endmodule
