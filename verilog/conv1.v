/*------------------------------------------------------------------------
 *
 *  Copyright (c) 2021 by Bo Young Kang, All rights reserved.
 *
 *  File name  : conv1_layer.v
 *  Written by : Kang, Bo Young
 *  Written on : Sep 30, 2021
 *  Version    : 21.2
 *  Design     : 1st Convolution Layer for CNN MNIST dataset
 *
 *------------------------------------------------------------------------*/

/*-------------------------------------------------------------------
 *  Module: conv1_layer
 *------------------------------------------------------------------*/
 
 module conv1_layer (
   input clk,
   input rst_n,
   input [7:0] data_in,
   output [11:0] conv_out_1, conv_out_2, conv_out_3,
   output valid_out_conv,
   input [0:199] w_11,
   input [0:199] w_12,
   input [0:199] w_13,
   input [0:23] b_1
 );

 wire [7:0] data_out_0, data_out_1, data_out_2, data_out_3, data_out_4,
  data_out_5, data_out_6, data_out_7, data_out_8, data_out_9,
  data_out_10, data_out_11, data_out_12, data_out_13, data_out_14,
  data_out_15, data_out_16, data_out_17, data_out_18, data_out_19,
  data_out_20, data_out_21, data_out_22, data_out_23, data_out_24;
 wire valid_out_buf;

 conv1_buf #(.WIDTH(28), .HEIGHT(28), .DATA_BITS(8)) conv1_buf(
   .clk(clk),
   .rst_n(rst_n),
   .data_in(data_in),
   .data_out_0(data_out_0),
   .data_out_1(data_out_1),
   .data_out_2(data_out_2),
   .data_out_3(data_out_3),
   .data_out_4(data_out_4),
   .data_out_5(data_out_5),
   .data_out_6(data_out_6),
   .data_out_7(data_out_7),
   .data_out_8(data_out_8),
   .data_out_9(data_out_9),
   .data_out_10(data_out_10),
   .data_out_11(data_out_11),
   .data_out_12(data_out_12),
   .data_out_13(data_out_13),
   .data_out_14(data_out_14),
   .data_out_15(data_out_15),
   .data_out_16(data_out_16),
   .data_out_17(data_out_17),
   .data_out_18(data_out_18),
   .data_out_19(data_out_19),
   .data_out_20(data_out_20),
   .data_out_21(data_out_21),
   .data_out_22(data_out_22),
   .data_out_23(data_out_23),
   .data_out_24(data_out_24),
   .valid_out_buf(valid_out_buf)
 );

 conv1_calc conv1_calc(
   .valid_out_buf(valid_out_buf),
   .data_out_0(data_out_0),
   .data_out_1(data_out_1),
   .data_out_2(data_out_2),
   .data_out_3(data_out_3),
   .data_out_4(data_out_4),
   .data_out_5(data_out_5),
   .data_out_6(data_out_6),
   .data_out_7(data_out_7),
   .data_out_8(data_out_8),
   .data_out_9(data_out_9),
   .data_out_10(data_out_10),
   .data_out_11(data_out_11),
   .data_out_12(data_out_12),
   .data_out_13(data_out_13),
   .data_out_14(data_out_14),
   .data_out_15(data_out_15),
   .data_out_16(data_out_16),
   .data_out_17(data_out_17),
   .data_out_18(data_out_18),
   .data_out_19(data_out_19),
   .data_out_20(data_out_20),
   .data_out_21(data_out_21),
   .data_out_22(data_out_22),
   .data_out_23(data_out_23),
   .data_out_24(data_out_24),
   .conv_out_1(conv_out_1),
   .conv_out_2(conv_out_2),
   .conv_out_3(conv_out_3),
   .valid_out_calc(valid_out_conv),
     .w_11(w_11),
  .w_12(w_12),
  .w_13(w_13),
  .b_1(b_1)
 );
 endmodule

/*------------------------------------------------------------------------
 *
 *  Copyright (c) 2021 by Bo Young Kang, All rights reserved.
 *
 *  File name  : conv1_buf.v
 *  Written by : Kang, Bo Young
 *  Written on : Sep 30, 2021
 *  Version    : 21.2
 *  Design     : 1st Convolution Layer for CNN MNIST dataset
 *               Input Buffer
 *
 *------------------------------------------------------------------------*/

/*-------------------------------------------------------------------
 *  Module: conv1_buf
 *------------------------------------------------------------------*/
 
 module conv1_buf #(parameter WIDTH = 28, HEIGHT = 28, DATA_BITS = 8)(
   input clk,
   input rst_n,
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
     buf_idx <= -1;
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
   buf_idx <= buf_idx + 1;
   if(buf_idx == WIDTH * FILTER_SIZE - 1) begin // buffer size = 140 = 28(w) * 5(h)
     buf_idx <= 0;
   end
   
   buffer[buf_idx] <= data_in;  // data input
   
   // Wait until first 140 input data filled in buffer
   if(!state) begin
     if(buf_idx == WIDTH * FILTER_SIZE - 1) begin
       state <= 1'b1;
     end
   end else begin // valid state
     w_idx <= w_idx + 1'b1; // move right

     if(w_idx == WIDTH - FILTER_SIZE + 1) begin
       valid_out_buf <= 1'b0; // unvalid area
     end else if(w_idx == WIDTH - 1) begin
       buf_flag <= buf_flag + 1'b1;
       if(buf_flag == FILTER_SIZE - 1) begin
         buf_flag <= 0;
       end
       w_idx <= 0;

       if(h_idx == HEIGHT - FILTER_SIZE) begin  // done 1 input read -> 28 * 28
         h_idx <= 0;
         state <= 1'b0;
       end 
       
       h_idx <= h_idx + 1'b1;

     end else if(w_idx == 0) begin
       valid_out_buf <= 1'b1; // start valid area
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
endmodule

/*------------------------------------------------------------------------
 *
 *  Copyright (c) 2021 by Bo Young Kang, All rights reserved.
 *
 *  File name  : conv1_calc.v
 *  Written by : Kang, Bo Young
 *  Written on : Oct 1, 2021
 *  Version    : 21.2
 *  Design     : 1st Convolution Layer for CNN MNIST dataset
 *               Convolution Sum Calculation
 *
 *------------------------------------------------------------------------*/

/*-------------------------------------------------------------------
 *  Module: conv1_calc
 *------------------------------------------------------------------*/
 
 module conv1_calc #(parameter WIDTH = 28, HEIGHT = 28, DATA_BITS = 8)(
   input valid_out_buf,
   input [DATA_BITS - 1:0] data_out_0, data_out_1, data_out_2, data_out_3, data_out_4,
   data_out_5, data_out_6, data_out_7, data_out_8, data_out_9,
   data_out_10, data_out_11, data_out_12, data_out_13, data_out_14,
   data_out_15, data_out_16, data_out_17, data_out_18, data_out_19,
   data_out_20, data_out_21, data_out_22, data_out_23, data_out_24,
   output signed [11:0] conv_out_1, conv_out_2, conv_out_3,
   output valid_out_calc,
   input [0:199] w_11,
   input [0:199] w_12,
   input [0:199] w_13,
   input [0:23] b_1
 );

 localparam FILTER_SIZE = 5;
 localparam CHANNEL_LEN = 3;



 wire signed [19:0] calc_out_1, calc_out_2, calc_out_3;
 wire signed [DATA_BITS:0] exp_data [0:FILTER_SIZE * FILTER_SIZE - 1];
 wire signed [11:0] exp_bias [0:CHANNEL_LEN - 1];
 
 reg signed [DATA_BITS - 1:0] weight_1 [0:FILTER_SIZE * FILTER_SIZE - 1];
 reg signed [DATA_BITS - 1:0] weight_2 [0:FILTER_SIZE * FILTER_SIZE - 1];
 reg signed [DATA_BITS - 1:0] weight_3 [0:FILTER_SIZE * FILTER_SIZE - 1];
 reg signed [DATA_BITS - 1:0] bias [0:CHANNEL_LEN - 1];
 
integer i;
always @(*) begin
    for(i=0;i<=24;i=i+1) begin
        weight_1[i]=w_11[(8*i)+:8];
        weight_2[i]=w_12[(8*i)+:8];
        weight_3[i]=w_13[(8*i)+:8];
    end
    for(i=0;i<=2;i=i+1) begin
        bias[i]=b_1[(8*i)+:8];
    end
end
 
 // Unsigned -> Signed
 assign exp_data[0] = {1'd0, data_out_0};
 assign exp_data[1] = {1'd0, data_out_1};
 assign exp_data[2] = {1'd0, data_out_2};
 assign exp_data[3] = {1'd0, data_out_3};
 assign exp_data[4] = {1'd0, data_out_4};
 assign exp_data[5] = {1'd0, data_out_5};
 assign exp_data[6] = {1'd0, data_out_6};
 assign exp_data[7] = {1'd0, data_out_7};
 assign exp_data[8] = {1'd0, data_out_8};
 assign exp_data[9] = {1'd0, data_out_9};
 assign exp_data[10] = {1'd0, data_out_10};
 assign exp_data[11] = {1'd0, data_out_11};
 assign exp_data[12] = {1'd0, data_out_12};
 assign exp_data[13] = {1'd0, data_out_13};
 assign exp_data[14] = {1'd0, data_out_14};
 assign exp_data[15] = {1'd0, data_out_15};
 assign exp_data[16] = {1'd0, data_out_16};
 assign exp_data[17] = {1'd0, data_out_17};
 assign exp_data[18] = {1'd0, data_out_18};
 assign exp_data[19] = {1'd0, data_out_19};
 assign exp_data[20] = {1'd0, data_out_20};
 assign exp_data[21] = {1'd0, data_out_21};
 assign exp_data[22] = {1'd0, data_out_22};
 assign exp_data[23] = {1'd0, data_out_23};
 assign exp_data[24] = {1'd0, data_out_24};

 //  Re-calibration of extracted weight data according to MSB
 assign exp_bias[0] = (bias[0][7] == 1) ? {4'b1111, bias[0]} : {4'd0, bias[0]};
 assign exp_bias[1] = (bias[1][7] == 1) ? {4'b1111, bias[1]} : {4'd0, bias[1]};
 assign exp_bias[2] = (bias[2][7] == 1) ? {4'b1111, bias[2]} : {4'd0, bias[2]};
 
 assign calc_out_1 = exp_data[0]*weight_1[0] + exp_data[1]*weight_1[1] + exp_data[2]*weight_1[2] + exp_data[3]*weight_1[3] + exp_data[4]*weight_1[4] +
					exp_data[5]*weight_1[5] + exp_data[6]*weight_1[6] + exp_data[7]*weight_1[7] + exp_data[8]*weight_1[8] + exp_data[9]*weight_1[9] +
					exp_data[10]*weight_1[10] + exp_data[11]*weight_1[11] + exp_data[12]*weight_1[12] + exp_data[13]*weight_1[13] + exp_data[14]*weight_1[14] +
					exp_data[15]*weight_1[15] + exp_data[16]*weight_1[16] + exp_data[17]*weight_1[17] + exp_data[18]*weight_1[18] + exp_data[19]*weight_1[19] +
					exp_data[20]*weight_1[20] + exp_data[21]*weight_1[21] +exp_data[22]*weight_1[22] +exp_data[23]*weight_1[23] +exp_data[24]*weight_1[24];
					
 assign calc_out_2 = exp_data[0]*weight_2[0] + exp_data[1]*weight_2[1] + exp_data[2]*weight_2[2] + exp_data[3]*weight_2[3] + exp_data[4]*weight_2[4] +
					exp_data[5]*weight_2[5] + exp_data[6]*weight_2[6] + exp_data[7]*weight_2[7] + exp_data[8]*weight_2[8] + exp_data[9]*weight_2[9] +
					exp_data[10]*weight_2[10] + exp_data[11]*weight_2[11] + exp_data[12]*weight_2[12] + exp_data[13]*weight_2[13] + exp_data[14]*weight_2[14] +
					exp_data[15]*weight_2[15] + exp_data[16]*weight_2[16] + exp_data[17]*weight_2[17] + exp_data[18]*weight_2[18] + exp_data[19]*weight_2[19] +
					exp_data[20]*weight_2[20] + exp_data[21]*weight_2[21] + exp_data[22]*weight_2[22] +exp_data[23]*weight_2[23] +exp_data[24]*weight_2[24];
					
 assign calc_out_3 = exp_data[0]*weight_3[0] + exp_data[1]*weight_3[1] + exp_data[2]*weight_3[2] + exp_data[3]*weight_3[3] + exp_data[4]*weight_3[4] + 
					exp_data[5]*weight_3[5] + exp_data[6]*weight_3[6] + exp_data[7]*weight_3[7] + exp_data[8]*weight_3[8] + exp_data[9]*weight_3[9] + 
					exp_data[10]*weight_3[10] + exp_data[11]*weight_3[11] + exp_data[12]*weight_3[12] + exp_data[13]*weight_3[13] + exp_data[14]*weight_3[14] + 
					exp_data[15]*weight_3[15] + exp_data[16]*weight_3[16] + exp_data[17]*weight_3[17] + exp_data[18]*weight_3[18] + exp_data[19]*weight_3[19] + 
					exp_data[20]*weight_3[20] + exp_data[21]*weight_3[21] + exp_data[22]*weight_3[22] + exp_data[23]*weight_3[23] + exp_data[24]*weight_3[24];
					
 
 assign conv_out_1 = calc_out_1[19:8] + exp_bias[0];
 assign conv_out_2 = calc_out_2[19:8] + exp_bias[1];
 assign conv_out_3 = calc_out_3[19:8] + exp_bias[2];

 assign valid_out_calc = valid_out_buf;
 
endmodule


