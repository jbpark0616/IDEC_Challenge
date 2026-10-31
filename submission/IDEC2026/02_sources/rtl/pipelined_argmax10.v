`timescale 1ns/1ps

// Four-stage balanced signed argmax tree for ten FC logits.
// Equal values select the lower class index, matching Python argmax.
module pipelined_argmax10 #(
    parameter integer DATA_BITS = 18
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     in_valid,
    output wire                     in_ready,
    input  wire [10*DATA_BITS-1:0]  values,
    output reg                      out_valid,
    output reg  [3:0]               out_index
);

    reg signed [DATA_BITS-1:0] stage0_value [0:4];
    reg [3:0]                  stage0_index [0:4];
    reg signed [DATA_BITS-1:0] stage1_value [0:2];
    reg [3:0]                  stage1_index [0:2];
    reg signed [DATA_BITS-1:0] stage2_value [0:1];
    reg [3:0]                  stage2_index [0:1];
    reg stage0_valid;
    reg stage1_valid;
    reg stage2_valid;

    wire signed [DATA_BITS-1:0] input_value [0:9];
    genvar input_lane;
    generate
        for (input_lane = 0; input_lane < 10; input_lane = input_lane + 1) begin : g_input
            assign input_value[input_lane] =
                values[input_lane*DATA_BITS +: DATA_BITS];
        end
    endgenerate

    assign in_ready = 1'b1;

    integer pair;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage0_valid <= 1'b0;
            stage1_valid <= 1'b0;
            stage2_valid <= 1'b0;
            out_valid    <= 1'b0;
            out_index    <= 4'd0;
        end else begin
            stage0_valid <= in_valid;
            stage1_valid <= stage0_valid;
            stage2_valid <= stage1_valid;
            out_valid    <= stage2_valid;

            if (in_valid) begin
                for (pair = 0; pair < 5; pair = pair + 1) begin
                    if (input_value[pair*2] >= input_value[pair*2+1]) begin
                        stage0_value[pair] <= input_value[pair*2];
                        stage0_index[pair] <= pair*2;
                    end else begin
                        stage0_value[pair] <= input_value[pair*2+1];
                        stage0_index[pair] <= pair*2+1;
                    end
                end
            end

            if (stage0_valid) begin
                if (stage0_value[0] >= stage0_value[1]) begin
                    stage1_value[0] <= stage0_value[0];
                    stage1_index[0] <= stage0_index[0];
                end else begin
                    stage1_value[0] <= stage0_value[1];
                    stage1_index[0] <= stage0_index[1];
                end
                if (stage0_value[2] >= stage0_value[3]) begin
                    stage1_value[1] <= stage0_value[2];
                    stage1_index[1] <= stage0_index[2];
                end else begin
                    stage1_value[1] <= stage0_value[3];
                    stage1_index[1] <= stage0_index[3];
                end
                stage1_value[2] <= stage0_value[4];
                stage1_index[2] <= stage0_index[4];
            end

            if (stage1_valid) begin
                if (stage1_value[0] >= stage1_value[1]) begin
                    stage2_value[0] <= stage1_value[0];
                    stage2_index[0] <= stage1_index[0];
                end else begin
                    stage2_value[0] <= stage1_value[1];
                    stage2_index[0] <= stage1_index[1];
                end
                stage2_value[1] <= stage1_value[2];
                stage2_index[1] <= stage1_index[2];
            end

            if (stage2_valid) begin
                if (stage2_value[0] >= stage2_value[1])
                    out_index <= stage2_index[0];
                else
                    out_index <= stage2_index[1];
            end
        end
    end
endmodule
