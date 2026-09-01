`timescale 1ns/1ps

// 16-way reconfigurable MAC array shared by Winograd convolution and FC.
//
// Packing convention (LSB-first): lane i occupies [i*WIDTH +: WIDTH].
//   Conv mode: lane i computes one coordinate of the 4x4 Winograd domain.
//   FC mode  : lanes 0..9 compute classes 0..9; lanes 10..15 are gated.
//
// A transaction group is delimited by txn_first/txn_last.
//   Conv1: one beat,  txn_first=1 and txn_last=1
//   Conv2: three beats (one per input channel)
//   FC   : 75 beats (one per input feature)
//
// fc_bias_vec travels with the FC transaction and is added after the final
// feature accumulation, matching training/integer_inference.py.
// Convolution bias is intentionally handled after the output transform.
module winograd_mac_array #(
    parameter integer NUM_MACS     = 16,
    parameter integer FC_CLASSES   = 10,
    parameter integer WEIGHT_BITS  = 4,
    parameter integer OPERAND_BITS = 11,
    parameter integer FC_ACT_BITS  = 8,
    parameter integer BIAS_BITS    = 16,
    parameter integer PRODUCT_BITS = 15,
    parameter integer ACC_BITS     = 18
) (
    input  wire                              clk,
    input  wire                              rst_n,

    input  wire                              mode_fc,
    input  wire                              in_valid,
    output wire                              in_ready,
    input  wire                              txn_first,
    input  wire                              txn_last,

    input  wire [NUM_MACS*OPERAND_BITS-1:0]  conv_operand_vec,
    input  wire [NUM_MACS*WEIGHT_BITS-1:0]   conv_weight_vec,
    input  wire [FC_ACT_BITS-1:0]            fc_activation,
    input  wire [FC_CLASSES*WEIGHT_BITS-1:0] fc_weight_vec,
    input  wire [FC_CLASSES*BIAS_BITS-1:0]   fc_bias_vec,

    output reg                               out_valid,
    input  wire                              out_ready,
    output reg  [NUM_MACS*ACC_BITS-1:0]      result_vec,
    output wire [NUM_MACS*ACC_BITS-1:0]      accumulator_vec
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
        reg signed [ACC_BITS:0] sum;
        begin
            sum = {lhs[ACC_BITS-1], lhs} + {rhs[ACC_BITS-1], rhs};
            if (sum > SAT_MAX_EXT)
                sat_add = SAT_MAX;
            else if (sum < SAT_MIN_EXT)
                sat_add = SAT_MIN;
            else
                sat_add = sum[ACC_BITS-1:0];
        end
    endfunction

    // Stage 1: multiplier results and transaction metadata.
    reg                                      pipe_valid;
    reg                                      pipe_first;
    reg                                      pipe_last;
    reg                                      pipe_mode_fc;
    reg [NUM_MACS-1:0]                       pipe_active;
    reg [NUM_MACS-1:0]                       pipe_accumulate;
    reg [NUM_MACS*PRODUCT_BITS-1:0]          pipe_product_vec;
    reg [FC_CLASSES*BIAS_BITS-1:0]           pipe_fc_bias_vec;

    // Stage 2: temporal accumulation (channel reduction or FC dot product).
    reg signed [ACC_BITS-1:0] accumulator [0:NUM_MACS-1];

    wire output_slot_available;
    wire pipe_can_commit;

    assign output_slot_available = (~out_valid) | out_ready;
    assign pipe_can_commit = pipe_valid & ((~pipe_last) | output_slot_available);
    assign in_ready = (~pipe_valid) | pipe_can_commit;

    genvar lane;
    generate
        for (lane = 0; lane < NUM_MACS; lane = lane + 1) begin : g_lane
            wire signed [WEIGHT_BITS-1:0] conv_weight;
            wire signed [WEIGHT_BITS-1:0] selected_weight;
            wire signed [OPERAND_BITS-1:0] conv_operand;
            wire signed [OPERAND_BITS-1:0] fc_operand;
            wire signed [OPERAND_BITS-1:0] selected_operand;
            wire signed [OPERAND_BITS-1:0] isolated_operand;
            wire signed [PRODUCT_BITS-1:0] product;
            wire lane_active;
            wire weight_zero;

            wire signed [PRODUCT_BITS-1:0] pipe_product;
            wire signed [ACC_BITS-1:0] extended_product;
            wire signed [ACC_BITS-1:0] lane_base;
            wire signed [ACC_BITS-1:0] lane_term;
            wire signed [ACC_BITS-1:0] first_product;
            wire signed [ACC_BITS-1:0] accumulated_value;
            wire signed [ACC_BITS-1:0] product_accumulator;
            wire signed [ACC_BITS-1:0] next_accumulator;

            assign conv_weight = conv_weight_vec[lane*WEIGHT_BITS +: WEIGHT_BITS];
            assign conv_operand = conv_operand_vec[lane*OPERAND_BITS +: OPERAND_BITS];
            assign fc_operand = {{(OPERAND_BITS-FC_ACT_BITS){1'b0}}, fc_activation};

            if (lane < FC_CLASSES) begin : g_fc_lane
                wire signed [WEIGHT_BITS-1:0] fc_weight;
                wire signed [BIAS_BITS-1:0] pipe_fc_bias;
                assign fc_weight = fc_weight_vec[lane*WEIGHT_BITS +: WEIGHT_BITS];
                assign pipe_fc_bias = pipe_fc_bias_vec[lane*BIAS_BITS +: BIAS_BITS];
                assign selected_weight = mode_fc ? fc_weight : conv_weight;
                assign lane_active = 1'b1;
                assign lane_base = pipe_mode_fc
                                 ? {{(ACC_BITS-BIAS_BITS){pipe_fc_bias[BIAS_BITS-1]}},
                                    pipe_fc_bias}
                                 : {ACC_BITS{1'b0}};
            end else begin : g_non_fc_lane
                assign selected_weight = conv_weight;
                assign lane_active = ~mode_fc;
                assign lane_base = {ACC_BITS{1'b0}};
            end

            assign selected_operand = mode_fc ? fc_operand : conv_operand;
            assign weight_zero = (selected_weight == {WEIGHT_BITS{1'b0}});

            // Operand isolation: a zero weight prevents data activity from
            // propagating into the multiplier. Stage 2 also holds its ACC.
            assign isolated_operand = (weight_zero | ~lane_active)
                                    ? {OPERAND_BITS{1'b0}}
                                    : selected_operand;
            assign product = selected_weight * isolated_operand;

            assign pipe_product = pipe_product_vec[lane*PRODUCT_BITS +: PRODUCT_BITS];
            assign extended_product = {{(ACC_BITS-PRODUCT_BITS){pipe_product[PRODUCT_BITS-1]}},
                                       pipe_product};
            assign lane_term = extended_product;
            assign first_product = pipe_accumulate[lane]
                                 ? lane_term
                                 : {ACC_BITS{1'b0}};
            assign accumulated_value = pipe_accumulate[lane]
                                     ? sat_add(accumulator[lane], lane_term)
                                     : accumulator[lane];
            assign product_accumulator = pipe_first ? first_product
                                                     : accumulated_value;
            assign next_accumulator = (pipe_last & pipe_mode_fc & pipe_active[lane])
                                    ? sat_add(product_accumulator, lane_base)
                                    : product_accumulator;

            assign accumulator_vec[lane*ACC_BITS +: ACC_BITS] = accumulator[lane];

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    accumulator[lane] <= {ACC_BITS{1'b0}};
                end else if (pipe_can_commit) begin
                    accumulator[lane] <= next_accumulator;
                end
            end

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    pipe_product_vec[lane*PRODUCT_BITS +: PRODUCT_BITS]
                        <= {PRODUCT_BITS{1'b0}};
                    pipe_active[lane] <= 1'b0;
                    pipe_accumulate[lane] <= 1'b0;
                end else if (in_ready && in_valid) begin
                    pipe_product_vec[lane*PRODUCT_BITS +: PRODUCT_BITS] <= product;
                    pipe_active[lane] <= lane_active;
                    pipe_accumulate[lane] <= lane_active & ~weight_zero;
                end
            end

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    result_vec[lane*ACC_BITS +: ACC_BITS] <= {ACC_BITS{1'b0}};
                end else if (pipe_can_commit && pipe_last) begin
                    // Capture the value including the final product.
                    result_vec[lane*ACC_BITS +: ACC_BITS] <= next_accumulator;
                end
            end
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pipe_valid    <= 1'b0;
            pipe_first    <= 1'b0;
            pipe_last     <= 1'b0;
            pipe_mode_fc  <= 1'b0;
            pipe_fc_bias_vec <= {FC_CLASSES*BIAS_BITS{1'b0}};
            out_valid     <= 1'b0;
        end else begin
            if (out_valid && out_ready)
                out_valid <= 1'b0;

            if (pipe_can_commit && pipe_last)
                out_valid <= 1'b1;

            if (in_ready) begin
                if (in_valid) begin
                    pipe_valid    <= 1'b1;
                    pipe_first    <= txn_first;
                    pipe_last     <= txn_last;
                    pipe_mode_fc  <= mode_fc;
                    pipe_fc_bias_vec <= fc_bias_vec;
                end else begin
                    pipe_valid <= 1'b0;
                end
            end
        end
    end

endmodule
