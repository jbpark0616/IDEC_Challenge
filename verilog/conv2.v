/*------------------------------------------------------------------------
 *
 *  Copyright (c) 2021 by Bo Young Kang, All rights reserved.
 *
 *  File name  : conv2_layer.v
 *  Written by : Kang, Bo Young
 *  Written on : Oct 11, 2021
 *  Version    : 21.2
 *  Design     : 2nd Convolution Layer for CNN MNIST dataset
 *
 *------------------------------------------------------------------------*/

/*-------------------------------------------------------------------
 *  Module: conv2_layer
 *------------------------------------------------------------------*/
 
 module conv2_layer (
   input clk,
   input rst_n,
   input valid_in,
   input [11:0] max_value_1, max_value_2, max_value_3,
   output [11:0] conv2_out_1, conv2_out_2, conv2_out_3,
   output  valid_out_conv2,
   input [0:199] w_211,
   input [0:199] w_212,
   input [0:199] w_213,
   input [0:199] w_221,
   input [0:199] w_222,
   input [0:199] w_223,
   input [0:199] w_231,
   input [0:199] w_232,
   input [0:199] w_233,
   input [0:23] b_2
 );

 localparam CHANNEL_LEN = 3;
 ///////////////////////////////////////////
  /*wire [11:0] out_data1_0, out_data1_1, out_data1_2, out_data1_3, out_data1_4,
			out_data1_5, out_data1_6, out_data1_7, out_data1_8, out_data1_9,
			out_data1_10, out_data1_11, out_data1_12, out_data1_13, out_data1_14,
			out_data1_15, out_data1_16, out_data1_17, out_data1_18, out_data1_19,
			out_data1_20, out_data1_21, out_data1_22, out_data1_23, out_data1_24,
			
			out_data2_0, out_data2_1, out_data2_2, out_data2_3, out_data2_4,
			out_data2_5, out_data2_6, out_data2_7, out_data2_8, out_data2_9,
			out_data2_10, out_data2_11, out_data2_12, out_data2_13, out_data2_14,
			out_data2_15, out_data2_16, out_data2_17, out_data2_18, out_data2_19,
			out_data2_20, out_data2_21, out_data2_22, out_data2_23, out_data2_24,
			
			out_data3_0, out_data3_1, out_data3_2, out_data3_3, out_data3_4,
			out_data3_5, out_data3_6, out_data3_7, out_data3_8, out_data3_9,
			out_data3_10, out_data3_11, out_data3_12, out_data3_13, out_data3_14,
			out_data3_15, out_data3_16, out_data3_17, out_data3_18, out_data3_19,
			out_data3_20, out_data3_21, out_data3_22, out_data3_23, out_data3_24;*/
      /////////////////////////////////
 // Channel 1
 wire [11:0] data_out1_0, data_out1_1, data_out1_2, data_out1_3, data_out1_4,
  data_out1_5, data_out1_6, data_out1_7, data_out1_8, data_out1_9,
  data_out1_10, data_out1_11, data_out1_12, data_out1_13, data_out1_14,
  data_out1_15, data_out1_16, data_out1_17, data_out1_18, data_out1_19,
  data_out1_20, data_out1_21, data_out1_22, data_out1_23, data_out1_24;
 wire valid_out1_buf;

 // Channel 2
 wire [11:0] data_out2_0, data_out2_1, data_out2_2, data_out2_3, data_out2_4,
  data_out2_5, data_out2_6, data_out2_7, data_out2_8, data_out2_9,
  data_out2_10, data_out2_11, data_out2_12, data_out2_13, data_out2_14,
  data_out2_15, data_out2_16, data_out2_17, data_out2_18, data_out2_19,
  data_out2_20, data_out2_21, data_out2_22, data_out2_23, data_out2_24;
 wire valid_out2_buf;

 // Channel 3 
 wire [11:0] data_out3_0, data_out3_1, data_out3_2, data_out3_3, data_out3_4,
  data_out3_5, data_out3_6, data_out3_7, data_out3_8, data_out3_9,
  data_out3_10, data_out3_11, data_out3_12, data_out3_13, data_out3_14,
  data_out3_15, data_out3_16, data_out3_17, data_out3_18, data_out3_19,
  data_out3_20, data_out3_21, data_out3_22, data_out3_23, data_out3_24;
 wire valid_out3_buf;

 wire signed [13:0] conv_out_1, conv_out_2, conv_out_3;
 wire valid_out_buf, valid_out_calc_1, valid_out_calc_2, valid_out_calc_3;
 assign valid_out_buf = valid_out1_buf & valid_out2_buf & valid_out3_buf;
 assign valid_out_conv2 = valid_out_calc_1 & valid_out_calc_2 & valid_out_calc_3;

 reg signed [7:0] bias [0:CHANNEL_LEN - 1];
 wire signed [11:0] exp_bias [0:CHANNEL_LEN - 1];




conv2_buf #(.WIDTH(12), .HEIGHT(12), .DATA_BITS(12)) conv2_buf_1(
   .clk(clk),
   .rst_n(rst_n),
   .valid_in(valid_in),
   .data_in(max_value_1),
   .data_out_0(data_out1_0),
   .data_out_1(data_out1_1),
   .data_out_2(data_out1_2),
   .data_out_3(data_out1_3),
   .data_out_4(data_out1_4),
   .data_out_5(data_out1_5),
   .data_out_6(data_out1_6),
   .data_out_7(data_out1_7),
   .data_out_8(data_out1_8),
   .data_out_9(data_out1_9),
   .data_out_10(data_out1_10),
   .data_out_11(data_out1_11),
   .data_out_12(data_out1_12),
   .data_out_13(data_out1_13),
   .data_out_14(data_out1_14),
   .data_out_15(data_out1_15),
   .data_out_16(data_out1_16),
   .data_out_17(data_out1_17),
   .data_out_18(data_out1_18),
   .data_out_19(data_out1_19),
   .data_out_20(data_out1_20),
   .data_out_21(data_out1_21),
   .data_out_22(data_out1_22),
   .data_out_23(data_out1_23),
   .data_out_24(data_out1_24),
   .valid_out_buf(valid_out1_buf)
 );

 conv2_buf #(.WIDTH(12), .HEIGHT(12), .DATA_BITS  (12)) conv2_buf_2(
   .clk(clk),
   .rst_n(rst_n),
   .valid_in(valid_in),
   .data_in(max_value_2),
   .data_out_0(data_out2_0),
   .data_out_1(data_out2_1),
   .data_out_2(data_out2_2),
   .data_out_3(data_out2_3),
   .data_out_4(data_out2_4),
   .data_out_5(data_out2_5),
   .data_out_6(data_out2_6),
   .data_out_7(data_out2_7),
   .data_out_8(data_out2_8),
   .data_out_9(data_out2_9),
   .data_out_10(data_out2_10),
   .data_out_11(data_out2_11),
   .data_out_12(data_out2_12),
   .data_out_13(data_out2_13),
   .data_out_14(data_out2_14),
   .data_out_15(data_out2_15),
   .data_out_16(data_out2_16),
   .data_out_17(data_out2_17),
   .data_out_18(data_out2_18),
   .data_out_19(data_out2_19),
   .data_out_20(data_out2_20),
   .data_out_21(data_out2_21),
   .data_out_22(data_out2_22),
   .data_out_23(data_out2_23),
   .data_out_24(data_out2_24),
   .valid_out_buf(valid_out2_buf)
 );

 conv2_buf #(.WIDTH(12), .HEIGHT(12), .DATA_BITS(12)) conv2_buf_3(
   .clk(clk),
   .rst_n(rst_n),
   .valid_in(valid_in),
   .data_in(max_value_3),
   .data_out_0(data_out3_0),
   .data_out_1(data_out3_1),
   .data_out_2(data_out3_2),
   .data_out_3(data_out3_3),
   .data_out_4(data_out3_4),
   .data_out_5(data_out3_5),
   .data_out_6(data_out3_6),
   .data_out_7(data_out3_7),
   .data_out_8(data_out3_8),
   .data_out_9(data_out3_9),
   .data_out_10(data_out3_10),
   .data_out_11(data_out3_11),
   .data_out_12(data_out3_12),
   .data_out_13(data_out3_13),
   .data_out_14(data_out3_14),
   .data_out_15(data_out3_15),
   .data_out_16(data_out3_16),
   .data_out_17(data_out3_17),
   .data_out_18(data_out3_18),
   .data_out_19(data_out3_19),
   .data_out_20(data_out3_20),
   .data_out_21(data_out3_21),
   .data_out_22(data_out3_22),
   .data_out_23(data_out3_23),
   .data_out_24(data_out3_24),
   .valid_out_buf(valid_out3_buf)
 );

conv2_calc conv2_calc_1(
   .clk(clk),
   .rst_n(rst_n),
   .valid_out_buf(valid_out_buf),
   .data_out1_0(data_out1_0),
   .data_out1_1(data_out1_1),
   .data_out1_2(data_out1_2),
   .data_out1_3(data_out1_3),
   .data_out1_4(data_out1_4),
   .data_out1_5(data_out1_5),
   .data_out1_6(data_out1_6),
   .data_out1_7(data_out1_7),
   .data_out1_8(data_out1_8),
   .data_out1_9(data_out1_9),
   .data_out1_10(data_out1_10),
   .data_out1_11(data_out1_11),
   .data_out1_12(data_out1_12),
   .data_out1_13(data_out1_13),
   .data_out1_14(data_out1_14),
   .data_out1_15(data_out1_15),
   .data_out1_16(data_out1_16),
   .data_out1_17(data_out1_17),
   .data_out1_18(data_out1_18),
   .data_out1_19(data_out1_19),
   .data_out1_20(data_out1_20),
   .data_out1_21(data_out1_21),
   .data_out1_22(data_out1_22),
   .data_out1_23(data_out1_23),
   .data_out1_24(data_out1_24),
   .data_out2_0(data_out2_0),
   .data_out2_1(data_out2_1),
   .data_out2_2(data_out2_2),
   .data_out2_3(data_out2_3),
   .data_out2_4(data_out2_4),
   .data_out2_5(data_out2_5),
   .data_out2_6(data_out2_6),
   .data_out2_7(data_out2_7),
   .data_out2_8(data_out2_8),
   .data_out2_9(data_out2_9),
   .data_out2_10(data_out2_10),
   .data_out2_11(data_out2_11),
   .data_out2_12(data_out2_12),
   .data_out2_13(data_out2_13),
   .data_out2_14(data_out2_14),
   .data_out2_15(data_out2_15),
   .data_out2_16(data_out2_16),
   .data_out2_17(data_out2_17),
   .data_out2_18(data_out2_18),
   .data_out2_19(data_out2_19),
   .data_out2_20(data_out2_20),
   .data_out2_21(data_out2_21),
   .data_out2_22(data_out2_22),
   .data_out2_23(data_out2_23),
   .data_out2_24(data_out2_24),
   .data_out3_0(data_out3_0),
   .data_out3_1(data_out3_1),
   .data_out3_2(data_out3_2),
   .data_out3_3(data_out3_3),
   .data_out3_4(data_out3_4),
   .data_out3_5(data_out3_5),
   .data_out3_6(data_out3_6),
   .data_out3_7(data_out3_7),
   .data_out3_8(data_out3_8),
   .data_out3_9(data_out3_9),
   .data_out3_10(data_out3_10),
   .data_out3_11(data_out3_11),
   .data_out3_12(data_out3_12),
   .data_out3_13(data_out3_13),
   .data_out3_14(data_out3_14),
   .data_out3_15(data_out3_15),
   .data_out3_16(data_out3_16),
   .data_out3_17(data_out3_17),
   .data_out3_18(data_out3_18),
   .data_out3_19(data_out3_19),
   .data_out3_20(data_out3_20),
   .data_out3_21(data_out3_21),
   .data_out3_22(data_out3_22),
   .data_out3_23(data_out3_23),
   .data_out3_24(data_out3_24),
   .conv_out_calc(conv_out_1),
   .valid_out_calc(valid_out_calc_1),
   .w_1(w_211),
  .w_2(w_212),
  .w_3(w_213)
);

conv2_calc conv2_calc_2(
   .clk(clk),
   .rst_n(rst_n),
   .valid_out_buf(valid_out_buf),
   .data_out1_0(data_out1_0),
   .data_out1_1(data_out1_1),
   .data_out1_2(data_out1_2),
   .data_out1_3(data_out1_3),
   .data_out1_4(data_out1_4),
   .data_out1_5(data_out1_5),
   .data_out1_6(data_out1_6),
   .data_out1_7(data_out1_7),
   .data_out1_8(data_out1_8),
   .data_out1_9(data_out1_9),
   .data_out1_10(data_out1_10),
   .data_out1_11(data_out1_11),
   .data_out1_12(data_out1_12),
   .data_out1_13(data_out1_13),
   .data_out1_14(data_out1_14),
   .data_out1_15(data_out1_15),
   .data_out1_16(data_out1_16),
   .data_out1_17(data_out1_17),
   .data_out1_18(data_out1_18),
   .data_out1_19(data_out1_19),
   .data_out1_20(data_out1_20),
   .data_out1_21(data_out1_21),
   .data_out1_22(data_out1_22),
   .data_out1_23(data_out1_23),
   .data_out1_24(data_out1_24),
   .data_out2_0(data_out2_0),
   .data_out2_1(data_out2_1),
   .data_out2_2(data_out2_2),
   .data_out2_3(data_out2_3),
   .data_out2_4(data_out2_4),
   .data_out2_5(data_out2_5),
   .data_out2_6(data_out2_6),
   .data_out2_7(data_out2_7),
   .data_out2_8(data_out2_8),
   .data_out2_9(data_out2_9),
   .data_out2_10(data_out2_10),
   .data_out2_11(data_out2_11),
   .data_out2_12(data_out2_12),
   .data_out2_13(data_out2_13),
   .data_out2_14(data_out2_14),
   .data_out2_15(data_out2_15),
   .data_out2_16(data_out2_16),
   .data_out2_17(data_out2_17),
   .data_out2_18(data_out2_18),
   .data_out2_19(data_out2_19),
   .data_out2_20(data_out2_20),
   .data_out2_21(data_out2_21),
   .data_out2_22(data_out2_22),
   .data_out2_23(data_out2_23),
   .data_out2_24(data_out2_24),
   .data_out3_0(data_out3_0),
   .data_out3_1(data_out3_1),
   .data_out3_2(data_out3_2),
   .data_out3_3(data_out3_3),
   .data_out3_4(data_out3_4),
   .data_out3_5(data_out3_5),
   .data_out3_6(data_out3_6),
   .data_out3_7(data_out3_7),
   .data_out3_8(data_out3_8),
   .data_out3_9(data_out3_9),
   .data_out3_10(data_out3_10),
   .data_out3_11(data_out3_11),
   .data_out3_12(data_out3_12),
   .data_out3_13(data_out3_13),
   .data_out3_14(data_out3_14),
   .data_out3_15(data_out3_15),
   .data_out3_16(data_out3_16),
   .data_out3_17(data_out3_17),
   .data_out3_18(data_out3_18),
   .data_out3_19(data_out3_19),
   .data_out3_20(data_out3_20),
   .data_out3_21(data_out3_21),
   .data_out3_22(data_out3_22),
   .data_out3_23(data_out3_23),
   .data_out3_24(data_out3_24),
   .conv_out_calc(conv_out_2),
   .valid_out_calc(valid_out_calc_2),
   .w_1(w_221),
  .w_2(w_222),
  .w_3(w_223)   
);

conv2_calc conv2_calc_3(
   .clk(clk),
   .rst_n(rst_n),
   .valid_out_buf(valid_out_buf),
   .data_out1_0(data_out1_0),
   .data_out1_1(data_out1_1),
   .data_out1_2(data_out1_2),
   .data_out1_3(data_out1_3),
   .data_out1_4(data_out1_4),
   .data_out1_5(data_out1_5),
   .data_out1_6(data_out1_6),
   .data_out1_7(data_out1_7),
   .data_out1_8(data_out1_8),
   .data_out1_9(data_out1_9),
   .data_out1_10(data_out1_10),
   .data_out1_11(data_out1_11),
   .data_out1_12(data_out1_12),
   .data_out1_13(data_out1_13),
   .data_out1_14(data_out1_14),
   .data_out1_15(data_out1_15),
   .data_out1_16(data_out1_16),
   .data_out1_17(data_out1_17),
   .data_out1_18(data_out1_18),
   .data_out1_19(data_out1_19),
   .data_out1_20(data_out1_20),
   .data_out1_21(data_out1_21),
   .data_out1_22(data_out1_22),
   .data_out1_23(data_out1_23),
   .data_out1_24(data_out1_24),
   .data_out2_0(data_out2_0),
   .data_out2_1(data_out2_1),
   .data_out2_2(data_out2_2),
   .data_out2_3(data_out2_3),
   .data_out2_4(data_out2_4),
   .data_out2_5(data_out2_5),
   .data_out2_6(data_out2_6),
   .data_out2_7(data_out2_7),
   .data_out2_8(data_out2_8),
   .data_out2_9(data_out2_9),
   .data_out2_10(data_out2_10),
   .data_out2_11(data_out2_11),
   .data_out2_12(data_out2_12),
   .data_out2_13(data_out2_13),
   .data_out2_14(data_out2_14),
   .data_out2_15(data_out2_15),
   .data_out2_16(data_out2_16),
   .data_out2_17(data_out2_17),
   .data_out2_18(data_out2_18),
   .data_out2_19(data_out2_19),
   .data_out2_20(data_out2_20),
   .data_out2_21(data_out2_21),
   .data_out2_22(data_out2_22),
   .data_out2_23(data_out2_23),
   .data_out2_24(data_out2_24),
   .data_out3_0(data_out3_0),
   .data_out3_1(data_out3_1),
   .data_out3_2(data_out3_2),
   .data_out3_3(data_out3_3),
   .data_out3_4(data_out3_4),
   .data_out3_5(data_out3_5),
   .data_out3_6(data_out3_6),
   .data_out3_7(data_out3_7),
   .data_out3_8(data_out3_8),
   .data_out3_9(data_out3_9),
   .data_out3_10(data_out3_10),
   .data_out3_11(data_out3_11),
   .data_out3_12(data_out3_12),
   .data_out3_13(data_out3_13),
   .data_out3_14(data_out3_14),
   .data_out3_15(data_out3_15),
   .data_out3_16(data_out3_16),
   .data_out3_17(data_out3_17),
   .data_out3_18(data_out3_18),
   .data_out3_19(data_out3_19),
   .data_out3_20(data_out3_20),
   .data_out3_21(data_out3_21),
   .data_out3_22(data_out3_22),
   .data_out3_23(data_out3_23),
   .data_out3_24(data_out3_24),
   .conv_out_calc(conv_out_3),
   .valid_out_calc(valid_out_calc_3),
  .w_1(w_231),
  .w_2(w_232),
  .w_3(w_233)   
);

integer i;
always @(*) begin
    for(i=0;i<=2;i=i+1) begin
        bias[i]=b_2[(8*i)+:8];
    end
end
 assign exp_bias[0] = (bias[0][7] == 1) ? {4'b1111, bias[0]} : {4'b0000, bias[0]};
 assign exp_bias[1] = (bias[1][7] == 1) ? {4'b1111, bias[1]} : {4'b0000, bias[1]};
 assign exp_bias[2] = (bias[2][7] == 1) ? {4'b1111, bias[2]} : {4'b0000, bias[2]};

 assign conv2_out_1 = conv_out_1[13:1] + exp_bias[0];
 assign conv2_out_2 = conv_out_2[13:1] + exp_bias[1];
 assign conv2_out_3 = conv_out_3[13:1] + exp_bias[2];
 
 endmodule

/*------------------------------------------------------------------------
 *
 *  Copyright (c) 2021 by Bo Young Kang, All rights reserved.
 *
 *  File name  : conv2_buf.v
 *  Written by : Kang, Bo Young
 *  Written on : Oct 13, 2021
 *  Version    : 21.2
 *  Design     : 2nd Convolution Layer for CNN MNIST dataset
 *               Input Buffer
 *
 *------------------------------------------------------------------------*/

/*-------------------------------------------------------------------
 *  Module: conv2_buf
 *------------------------------------------------------------------*/
 module conv2_buf #(parameter WIDTH = 12, HEIGHT = 12, DATA_BITS = 12) (
   input clk,
   input rst_n,
   input valid_in,
   input [DATA_BITS - 1:0] data_in,
   output reg [DATA_BITS - 1:0] data_out_0, data_out_1, data_out_2, data_out_3, data_out_4,
   data_out_5, data_out_6, data_out_7, data_out_8, data_out_9,
   data_out_10, data_out_11, data_out_12, data_out_13, data_out_14,
   data_out_15, data_out_16, data_out_17, data_out_18, data_out_19,
   data_out_20, data_out_21, data_out_22, data_out_23, data_out_24,
   output reg valid_out_buf
 );

 localparam FILTER_SIZE = 5;
 
 reg [DATA_BITS - 1:0] buffer [0:WIDTH * FILTER_SIZE - 1];
 reg [DATA_BITS - 1:0] buf_idx;
 reg [4:0] w_idx, h_idx;
 reg [2:0] buf_flag;  // 0 ~ 4
 reg state;

 always @(posedge clk) begin
   if(~rst_n) begin
     buf_idx <= 0;
     w_idx <= 0;
     h_idx <= 0;
     buf_flag <= 0;
     state <= 0;
     valid_out_buf <= 0;
     data_out_0 <= 12'bx;
     data_out_1 <= 12'bx;
     data_out_2 <= 12'bx;
     data_out_3 <= 12'bx;
     data_out_4 <= 12'bx;
     data_out_5 <= 12'bx;
     data_out_6 <= 12'bx;
     data_out_7 <= 12'bx;
     data_out_8 <= 12'bx;
     data_out_9 <= 12'bx;
     data_out_10 <= 12'bx;
     data_out_11 <= 12'bx;
     data_out_12 <= 12'bx;
     data_out_13 <= 12'bx;
     data_out_14 <= 12'bx;
     data_out_15 <= 12'bx;
     data_out_16 <= 12'bx;
     data_out_17 <= 12'bx;
     data_out_18 <= 12'bx;
     data_out_19 <= 12'bx;
     data_out_20 <= 12'bx;
     data_out_21 <= 12'bx;
     data_out_22 <= 12'bx;
     data_out_23 <= 12'bx;
     data_out_24 <= 12'bx;
   end else begin
   if(valid_in) begin
     buf_idx <= buf_idx + 1'b1;
     if(buf_idx == WIDTH * FILTER_SIZE - 1) begin // buffer size = 140 = 28(w) * 5(h)
       buf_idx <= 0;
     end

     buffer[buf_idx] <= data_in;  // data input

     // Wait until first 140 input data filled in buffer
     if(!state) begin
       if(buf_idx == WIDTH * FILTER_SIZE - 1) begin
         state <= 1;
       end
     end else begin // valid state
       w_idx <= w_idx + 1'b1; // move right

      if(w_idx == WIDTH - FILTER_SIZE + 1) begin
        valid_out_buf <= 1'b0;  // unvalid area
      end else if(w_idx == WIDTH - 1) begin
        buf_flag <= buf_flag + 1;
        if(buf_flag == FILTER_SIZE - 1) begin
          buf_flag <= 0;
        end

        w_idx <= 0;

        if(h_idx == HEIGHT - FILTER_SIZE) begin // done 1 input read -> 28 * 28
          h_idx <= 0;
          state <= 0;
        end
          h_idx <= h_idx + 1;

      end else if(w_idx == 0) begin
        valid_out_buf <= 1'b1;  // start valid area
      end

      // Buffer Selection -> 5 * 5
     if(buf_flag == 3'd0) begin
       data_out_0 <= buffer[w_idx];
       data_out_1 <= buffer[w_idx + 1];
       data_out_2 <= buffer[w_idx + 2];
       data_out_3 <= buffer[w_idx + 3];
       data_out_4 <= buffer[w_idx + 4];

       data_out_5 <= buffer[w_idx + WIDTH];
       data_out_6 <= buffer[w_idx + 1 + WIDTH];
       data_out_7 <= buffer[w_idx + 2 + WIDTH];
       data_out_8 <= buffer[w_idx + 3 + WIDTH];
       data_out_9 <= buffer[w_idx + 4 + WIDTH];

       data_out_10 <= buffer[w_idx + WIDTH * 2];
       data_out_11 <= buffer[w_idx + 1 + WIDTH * 2];
       data_out_12 <= buffer[w_idx + 2 + WIDTH * 2];
       data_out_13 <= buffer[w_idx + 3 + WIDTH * 2];
       data_out_14 <= buffer[w_idx + 4 + WIDTH * 2];

       data_out_15 <= buffer[w_idx + WIDTH * 3];
       data_out_16 <= buffer[w_idx + 1 + WIDTH * 3];
       data_out_17 <= buffer[w_idx + 2 + WIDTH * 3];
       data_out_18 <= buffer[w_idx + 3 + WIDTH * 3];
       data_out_19 <= buffer[w_idx + 4 + WIDTH * 3];

       data_out_20 <= buffer[w_idx + WIDTH * 4];
       data_out_21 <= buffer[w_idx + 1 + WIDTH * 4];
       data_out_22 <= buffer[w_idx + 2 + WIDTH * 4];
       data_out_23 <= buffer[w_idx + 3 + WIDTH * 4];
       data_out_24 <= buffer[w_idx + 4 + WIDTH * 4];
     end else if(buf_flag == 3'd1) begin
       data_out_0 <= buffer[w_idx + WIDTH];
       data_out_1 <= buffer[w_idx + 1 + WIDTH];
       data_out_2 <= buffer[w_idx + 2 + WIDTH];
       data_out_3 <= buffer[w_idx + 3 + WIDTH];
       data_out_4 <= buffer[w_idx + 4 + WIDTH];

       data_out_5 <= buffer[w_idx + WIDTH * 2];
       data_out_6 <= buffer[w_idx + 1 + WIDTH * 2];
       data_out_7 <= buffer[w_idx + 2 + WIDTH * 2];
       data_out_8 <= buffer[w_idx + 3 + WIDTH * 2];
       data_out_9 <= buffer[w_idx + 4 + WIDTH * 2];

       data_out_10 <= buffer[w_idx + WIDTH * 3];
       data_out_11 <= buffer[w_idx + 1 + WIDTH * 3];
       data_out_12 <= buffer[w_idx + 2 + WIDTH * 3];
       data_out_13 <= buffer[w_idx + 3 + WIDTH * 3];
       data_out_14 <= buffer[w_idx + 4 + WIDTH * 3];

       data_out_15 <= buffer[w_idx + WIDTH * 4];
       data_out_16 <= buffer[w_idx + 1 + WIDTH * 4];
       data_out_17 <= buffer[w_idx + 2 + WIDTH * 4];
       data_out_18 <= buffer[w_idx + 3 + WIDTH * 4];
       data_out_19 <= buffer[w_idx + 4 + WIDTH * 4];

       data_out_20 <= buffer[w_idx];
       data_out_21 <= buffer[w_idx + 1];
       data_out_22 <= buffer[w_idx + 2];
       data_out_23 <= buffer[w_idx + 3];
       data_out_24 <= buffer[w_idx + 4];
     end else if(buf_flag == 3'd2) begin
       data_out_0 <= buffer[w_idx + WIDTH * 2];
       data_out_1 <= buffer[w_idx + 1 + WIDTH * 2];
       data_out_2 <= buffer[w_idx + 2 + WIDTH * 2];
       data_out_3 <= buffer[w_idx + 3 + WIDTH * 2];
       data_out_4 <= buffer[w_idx + 4 + WIDTH * 2];

       data_out_5 <= buffer[w_idx + WIDTH * 3];
       data_out_6 <= buffer[w_idx + 1 + WIDTH * 3];
       data_out_7 <= buffer[w_idx + 2 + WIDTH * 3];
       data_out_8 <= buffer[w_idx + 3 + WIDTH * 3];
       data_out_9 <= buffer[w_idx + 4 + WIDTH * 3];

       data_out_10 <= buffer[w_idx + WIDTH * 4];
       data_out_11 <= buffer[w_idx + 1 + WIDTH * 4];
       data_out_12 <= buffer[w_idx + 2 + WIDTH * 4];
       data_out_13 <= buffer[w_idx + 3 + WIDTH * 4];
       data_out_14 <= buffer[w_idx + 4 + WIDTH * 4];

       data_out_15 <= buffer[w_idx];
       data_out_16 <= buffer[w_idx + 1];
       data_out_17 <= buffer[w_idx + 2];
       data_out_18 <= buffer[w_idx + 3];
       data_out_19 <= buffer[w_idx + 4];

       data_out_20 <= buffer[w_idx + WIDTH];
       data_out_21 <= buffer[w_idx + 1 + WIDTH];
       data_out_22 <= buffer[w_idx + 2 + WIDTH];
       data_out_23 <= buffer[w_idx + 3 + WIDTH];
       data_out_24 <= buffer[w_idx + 4 + WIDTH];
     end else if(buf_flag == 3'd3) begin
       data_out_0 <= buffer[w_idx + WIDTH * 3];
       data_out_1 <= buffer[w_idx + 1 + WIDTH * 3];
       data_out_2 <= buffer[w_idx + 2 + WIDTH * 3];
       data_out_3 <= buffer[w_idx + 3 + WIDTH * 3];
       data_out_4 <= buffer[w_idx + 4 + WIDTH * 3];

       data_out_5 <= buffer[w_idx + WIDTH * 4];
       data_out_6 <= buffer[w_idx + 1 + WIDTH * 4];
       data_out_7 <= buffer[w_idx + 2 + WIDTH * 4];
       data_out_8 <= buffer[w_idx + 3 + WIDTH * 4];
       data_out_9 <= buffer[w_idx + 4 + WIDTH * 4];

       data_out_10 <= buffer[w_idx];
       data_out_11 <= buffer[w_idx + 1];
       data_out_12 <= buffer[w_idx + 2];
       data_out_13 <= buffer[w_idx + 3];
       data_out_14 <= buffer[w_idx + 4];

       data_out_15 <= buffer[w_idx + WIDTH];
       data_out_16 <= buffer[w_idx + 1 + WIDTH];
       data_out_17 <= buffer[w_idx + 2 + WIDTH];
       data_out_18 <= buffer[w_idx + 3 + WIDTH];
       data_out_19 <= buffer[w_idx + 4 + WIDTH];

       data_out_20 <= buffer[w_idx + WIDTH * 2];
       data_out_21 <= buffer[w_idx + 1 + WIDTH * 2];
       data_out_22 <= buffer[w_idx + 2 + WIDTH * 2];
       data_out_23 <= buffer[w_idx + 3 + WIDTH * 2];
       data_out_24 <= buffer[w_idx + 4 + WIDTH * 2];      
     end else if(buf_flag == 3'd4) begin
       data_out_0 <= buffer[w_idx + WIDTH * 4];
       data_out_1 <= buffer[w_idx + 1 + WIDTH * 4];
       data_out_2 <= buffer[w_idx + 2 + WIDTH * 4];
       data_out_3 <= buffer[w_idx + 3 + WIDTH * 4];
       data_out_4 <= buffer[w_idx + 4 + WIDTH * 4];

       data_out_5 <= buffer[w_idx];
       data_out_6 <= buffer[w_idx + 1];
       data_out_7 <= buffer[w_idx + 2];
       data_out_8 <= buffer[w_idx + 3];
       data_out_9 <= buffer[w_idx + 4];

       data_out_10 <= buffer[w_idx + WIDTH];
       data_out_11 <= buffer[w_idx + 1 + WIDTH];
       data_out_12 <= buffer[w_idx + 2 + WIDTH];
       data_out_13 <= buffer[w_idx + 3 + WIDTH];
       data_out_14 <= buffer[w_idx + 4 + WIDTH];

       data_out_15 <= buffer[w_idx + WIDTH * 2];
       data_out_16 <= buffer[w_idx + 1 + WIDTH * 2];
       data_out_17 <= buffer[w_idx + 2 + WIDTH * 2];
       data_out_18 <= buffer[w_idx + 3 + WIDTH * 2];
       data_out_19 <= buffer[w_idx + 4 + WIDTH * 2];

       data_out_20 <= buffer[w_idx + WIDTH * 3];
       data_out_21 <= buffer[w_idx + 1 + WIDTH * 3];
       data_out_22 <= buffer[w_idx + 2 + WIDTH * 3];
       data_out_23 <= buffer[w_idx + 3 + WIDTH * 3];
       data_out_24 <= buffer[w_idx + 4 + WIDTH * 3];   
     end
     end
   end
 end
 end
endmodule

/*------------------------------------------------------------------------
 *
 *  Copyright (c) 2021 by Bo Young Kang, All rights reserved.
 *
 *  File name  : conv2_calc_1.v
 *  Written by : Kang, Bo Young
 *  Written on : Oct 14, 2021
 *  Version    : 21.2
 *  Design     : 2nd Convolution Layer for CNN MNIST dataset
 *               Convolution Sum Calculation - 1st Channel
 *
 *------------------------------------------------------------------------*/

/*-------------------------------------------------------------------
 *  Module: conv2_calc_1
 *------------------------------------------------------------------*/

 module conv2_calc(
	input clk,
  input rst_n,
  input valid_out_buf,
	input signed [11:0] data_out1_0, data_out1_1, data_out1_2, data_out1_3, data_out1_4,
	  data_out1_5, data_out1_6, data_out1_7, data_out1_8, data_out1_9,
	  data_out1_10, data_out1_11, data_out1_12, data_out1_13, data_out1_14,
	  data_out1_15, data_out1_16, data_out1_17, data_out1_18, data_out1_19,
	  data_out1_20, data_out1_21, data_out1_22, data_out1_23, data_out1_24,
	
	  data_out2_0, data_out2_1, data_out2_2, data_out2_3, data_out2_4,
	  data_out2_5, data_out2_6, data_out2_7, data_out2_8, data_out2_9,
	  data_out2_10, data_out2_11, data_out2_12, data_out2_13, data_out2_14,
	  data_out2_15, data_out2_16, data_out2_17, data_out2_18, data_out2_19,
	  data_out2_20, data_out2_21, data_out2_22, data_out2_23, data_out2_24,
	
	  data_out3_0, data_out3_1, data_out3_2, data_out3_3, data_out3_4,
	  data_out3_5, data_out3_6, data_out3_7, data_out3_8, data_out3_9,
	  data_out3_10, data_out3_11, data_out3_12, data_out3_13, data_out3_14,
	  data_out3_15, data_out3_16, data_out3_17, data_out3_18, data_out3_19,
	  data_out3_20, data_out3_21, data_out3_22, data_out3_23, data_out3_24,

	  output reg [13:0] conv_out_calc,
  	output reg valid_out_calc,
  	input [0:199] w_1,
   input [0:199] w_2,
   input [0:199] w_3
);

wire signed [19:0] calc_out, calc_out_1, calc_out_2, calc_out_3;


reg signed [7:0] weight_1 [0:24];
reg signed [7:0] weight_2 [0:24];
reg signed [7:0] weight_3 [0:24];

integer i;
always @(*) begin
    for(i=0;i<=24;i=i+1) begin
        weight_1[i]=w_1[(8*i)+:8];
        weight_2[i]=w_2[(8*i)+:8];
        weight_3[i]=w_3[(8*i)+:8];
    end
end


assign calc_out_1 = data_out1_0*weight_1[0] + data_out1_1*weight_1[1] + data_out1_2*weight_1[2] + data_out1_3*weight_1[3] + data_out1_4*weight_1[4] + 
					data_out1_5*weight_1[5] + data_out1_6*weight_1[6] + data_out1_7*weight_1[7] + data_out1_8*weight_1[8] + data_out1_9*weight_1[9] + 
					data_out1_10*weight_1[10] + data_out1_11*weight_1[11] + data_out1_12*weight_1[12] + data_out1_13*weight_1[13] + data_out1_14*weight_1[14] + 
					data_out1_15*weight_1[15] + data_out1_16*weight_1[16] + data_out1_17*weight_1[17] + data_out1_18*weight_1[18] + data_out1_19*weight_1[19] + 
					data_out1_20*weight_1[20] + data_out1_21*weight_1[21] + data_out1_22*weight_1[22] + data_out1_23*weight_1[23] + data_out1_24*weight_1[24];

assign calc_out_2 = data_out2_0*weight_2[0] + data_out2_1*weight_2[1] + data_out2_2*weight_2[2] + data_out2_3*weight_2[3] + data_out2_4*weight_2[4] + 
					data_out2_5*weight_2[5] + data_out2_6*weight_2[6] + data_out2_7*weight_2[7] + data_out2_8*weight_2[8] + data_out2_9*weight_2[9] + 
					data_out2_10*weight_2[10] + data_out2_11*weight_2[11] + data_out2_12*weight_2[12] + data_out2_13*weight_2[13] + data_out2_14*weight_2[14] + 
					data_out2_15*weight_2[15] + data_out2_16*weight_2[16] + data_out2_17*weight_2[17] + data_out2_18*weight_2[18] + data_out2_19*weight_2[19] + 
					data_out2_20*weight_2[20] + data_out2_21*weight_2[21] + data_out2_22*weight_2[22] + data_out2_23*weight_2[23] + data_out2_24*weight_2[24];

assign calc_out_3 = data_out3_0*weight_3[0] + data_out3_1*weight_3[1] + data_out3_2*weight_3[2] + data_out3_3*weight_3[3] + data_out3_4*weight_3[4] + 
					data_out3_5*weight_3[5] + data_out3_6*weight_3[6] + data_out3_7*weight_3[7] + data_out3_8*weight_3[8] + data_out3_9*weight_3[9] + 
					data_out3_10*weight_3[10] + data_out3_11*weight_3[11] + data_out3_12*weight_3[12] + data_out3_13*weight_3[13] + data_out3_14*weight_3[14] + 
					data_out3_15*weight_3[15] + data_out3_16*weight_3[16] + data_out3_17*weight_3[17] + data_out3_18*weight_3[18] + data_out3_19*weight_3[19] + 
					data_out3_20*weight_3[20] + data_out3_21*weight_3[21] + data_out3_22*weight_3[22] + data_out3_23*weight_3[23] + data_out3_24*weight_3[24];

assign calc_out = calc_out_1 + calc_out_2 + calc_out_3;


always @ (posedge clk) begin
	if(~rst_n) begin
		valid_out_calc <= 0;
    conv_out_calc <= 0;
	end
	else begin
	    conv_out_calc <= calc_out[19:6]; 
		// Toggling Valid Output Signal
		if(valid_out_buf == 1) begin
			if(valid_out_calc == 1)
				valid_out_calc <= 0;
			else
				valid_out_calc <= 1;
		end
	end
end

endmodule


