/*------------------------------------------------------------------------
 *
 *  Copyright (c) 2021 by Bo Young Kang, All rights reserved.
 *
 *  File name  : top_tb.v
 *  Written by : Kang, Bo Young
 *  Written on : Oct 15, 2021
 *  Version    : 21.2
 *  Design     : Testbench for CNN MNIST dataset - single input image
 *
 *------------------------------------------------------------------------*/

/*-------------------------------------------------------------------
 *  Module: top_tb
 *------------------------------------------------------------------*/
`timescale 1ps/1ps
module top_tb();
parameter DATA_BITS = 8;
reg clk, rst_n;
reg [7:0] pixels [0:783];
reg [9:0] img_idx;
reg [7:0] data_in;

wire [3:0] decision;
wire valid_out_6;

//conv1
reg signed [7:0] weight_11 [0:24];
reg signed [7:0] weight_12 [0:24];
reg signed [7:0] weight_13 [0:24];
reg signed [7:0] bias_1 [0:2];
//conv2
reg signed [7:0] bias_2 [0:2];
reg signed [7:0] weight_211 [0:24];
reg signed [7:0] weight_212 [0:24];
reg signed [7:0] weight_213 [0:24];

reg signed [7:0] weight_221 [0:24];
reg signed [7:0] weight_222 [0:24];
reg signed [7:0] weight_223 [0:24];

reg signed [7:0] weight_231 [0:24];
reg signed [7:0] weight_232 [0:24];
reg signed [7:0] weight_233 [0:24];
//fullyconnected

reg signed [7:0] weight_fc [0:479];
reg signed [7:0] bias_fc [0:9];


wire signed [0:199] w_11;
wire signed [0:199] w_12;
wire signed [0:199] w_13;
wire signed [0:23] b_1;
wire signed [0:23] b_2;
wire signed [0:199] w_211;
wire signed [0:199] w_212;
wire signed [0:199] w_213;
wire signed [0:199] w_221;
wire signed [0:199] w_222;
wire signed [0:199] w_223;
wire signed [0:199] w_231;
wire signed [0:199] w_232;
wire signed [0:199] w_233;
wire signed [0:3839] w_fc;
wire signed [0:79] b_fc;
// Clock generation
always #5 clk = ~clk;

// Read image text file
initial begin
  $readmemh("C:/cnn_verilog/data/2_0.txt", pixels);
  clk <= 1'b0;
  rst_n <= 1'b1;
  #3
  rst_n <= 1'b0;
  #3
  rst_n <= 1'b1;
end
initial begin
   //conv1
   $readmemh("C:/cnn_verilog/data/conv1_weight_1.txt", weight_11);
   $readmemh("C:/cnn_verilog/data/conv1_weight_2.txt", weight_12);
   $readmemh("C:/cnn_verilog/data/conv1_weight_3.txt", weight_13);
   $readmemh("C:/cnn_verilog/data/conv1_bias.txt", bias_1);
   //conv2
   $readmemh("C:/cnn_verilog/data/conv2_bias.txt", bias_2);
   	$readmemh("C:/cnn_verilog/data/conv2_weight_11.txt", weight_211);
	$readmemh("C:/cnn_verilog/data/conv2_weight_12.txt", weight_212);
	$readmemh("C:/cnn_verilog/data/conv2_weight_13.txt", weight_213);
	$readmemh("C:/cnn_verilog/data/conv2_weight_21.txt", weight_221);
	$readmemh("C:/cnn_verilog/data/conv2_weight_22.txt", weight_222);
	$readmemh("C:/cnn_verilog/data/conv2_weight_23.txt", weight_223);
    $readmemh("C:/cnn_verilog/data/conv2_weight_31.txt", weight_231);
	$readmemh("C:/cnn_verilog/data/conv2_weight_32.txt", weight_232);
	$readmemh("C:/cnn_verilog/data/conv2_weight_33.txt", weight_233);
   //fullyconnected
   $readmemh("C:/cnn_verilog/data/fc_weight.txt", weight_fc);
   $readmemh("C:/cnn_verilog/data/fc_bias.txt", bias_fc);
 end
 
always @(posedge clk) begin
  if(~rst_n) begin
    img_idx <= 0;
  end else begin
    if(img_idx < 10'd784) begin
      img_idx <= img_idx + 1'b1;
    end
    data_in <= pixels[img_idx];
  end
end
always @(*) begin
    if(valid_out_6==1) #5 $finish;
end
chip chip1 (
clk,rst_n,data_in,decision,valid_out_6,
 w_11 , w_12 , w_13 , b_1 ,
//conv2
 b_2 , w_211 , w_212 , w_213 , w_221 , w_222 , w_223 , w_231 , w_232 , w_233 ,
//fullyconnected
 w_fc, b_fc);

genvar i;
generate
    for(i=0;i<=24;i=i+1) begin
        assign w_11[(8*i)+:8]=weight_11[i];
        assign w_12[(8*i)+:8]=weight_12[i];
        assign w_13[(8*i)+:8]=weight_13[i];
        assign w_211[(8*i)+:8]=weight_211[i];
        assign w_212[(8*i)+:8]=weight_212[i];
        assign w_213[(8*i)+:8]=weight_213[i];
        assign w_221[(8*i)+:8]=weight_221[i];
        assign w_222[(8*i)+:8]=weight_222[i];
        assign w_223[(8*i)+:8]=weight_223[i];
        assign w_231[(8*i)+:8]=weight_231[i];
        assign w_232[(8*i)+:8]=weight_232[i];
        assign w_233[(8*i)+:8]=weight_233[i];            
    end
    for(i=0;i<=2;i=i+1) begin
        assign b_1[(8*i)+:8]=bias_1[i];
        assign b_2[(8*i)+:8]=bias_2[i];          
    end
    for(i=0;i<=479;i=i+1) begin
        assign w_fc[(8*i)+:8]=weight_fc[i];    
    end
    for(i=0;i<=9;i=i+1) begin
        assign b_fc[(8*i)+:8]=bias_fc[i];          
    end
endgenerate





endmodule

/*------------------------------------------------------------------------
 *
 *  Copyright (c) 2021 by Bo Young Kang, All rights reserved.
 *
 *  File name  : top_tb_2.v
 *  Written by : Kang, Bo Young
 *  Written on : Oct 20, 2021
 *  Version    : 21.2
 *  Design     : Testbench for CNN MNIST dataset - multiple input image (1000)
 *
 *------------------------------------------------------------------------*/

/*-------------------------------------------------------------------
 *  Module: top_tb_2
 *------------------------------------------------------------------*/
/*------------------------------------------------------------------------
 *
 *  Copyright (c) 2021 by Bo Young Kang, All rights reserved.
 *
 *  File name  : top_tb.v
 *  Written by : Kang, Bo Young
 *  Written on : Oct 15, 2021
 *  Version    : 21.2
 *  Design     : Testbench for CNN MNIST dataset - single input image
 *
 *------------------------------------------------------------------------*/

/*-------------------------------------------------------------------
 *  Module: top_tb
 *------------------------------------------------------------------*/
`timescale 1ps/1ps


module top_tb_1000();

reg clk, rst_n;
reg [7:0] pixels [0:783999];
reg [9:0] img_idx;
reg [7:0] data_in;
reg [9:0] cnt;  // num of input image (1000)
reg [9:0] input_cnt;
reg [9:0] rand_num; // 1000
reg state;

integer i_cnt;  // loop variable
reg [9:0] accuracy; // hit/miss count (1000)


wire [3:0] decision;
wire valid_out_6;

//conv1
reg signed [7:0] weight_11 [0:24];
reg signed [7:0] weight_12 [0:24];
reg signed [7:0] weight_13 [0:24];
reg signed [7:0] bias_1 [0:2];
//conv2
reg signed [7:0] bias_2 [0:2];
reg signed [7:0] weight_211 [0:24];
reg signed [7:0] weight_212 [0:24];
reg signed [7:0] weight_213 [0:24];

reg signed [7:0] weight_221 [0:24];
reg signed [7:0] weight_222 [0:24];
reg signed [7:0] weight_223 [0:24];

reg signed [7:0] weight_231 [0:24];
reg signed [7:0] weight_232 [0:24];
reg signed [7:0] weight_233 [0:24];
//fullyconnected

reg signed [7:0] weight_fc [0:479];
reg signed [7:0] bias_fc [0:9];


wire signed [0:199] w_11;
wire signed [0:199] w_12;
wire signed [0:199] w_13;
wire signed [0:23] b_1;
wire signed [0:23] b_2;
wire signed [0:199] w_211;
wire signed [0:199] w_212;
wire signed [0:199] w_213;
wire signed [0:199] w_221;
wire signed [0:199] w_222;
wire signed [0:199] w_223;
wire signed [0:199] w_231;
wire signed [0:199] w_232;
wire signed [0:199] w_233;
wire signed [0:3839] w_fc;
wire signed [0:79] b_fc;
// Clock generation
always #5 clk = ~clk;

// Read image text file

initial begin
   //conv1
   $readmemh("C:/cnn_verilog/data/conv1_weight_1.txt", weight_11);
   $readmemh("C:/cnn_verilog/data/conv1_weight_2.txt", weight_12);
   $readmemh("C:/cnn_verilog/data/conv1_weight_3.txt", weight_13);
   $readmemh("C:/cnn_verilog/data/conv1_bias.txt", bias_1);
   //conv2
   $readmemh("C:/cnn_verilog/data/conv2_bias.txt", bias_2);
   	$readmemh("C:/cnn_verilog/data/conv2_weight_11.txt", weight_211);
	$readmemh("C:/cnn_verilog/data/conv2_weight_12.txt", weight_212);
	$readmemh("C:/cnn_verilog/data/conv2_weight_13.txt", weight_213);
	$readmemh("C:/cnn_verilog/data/conv2_weight_21.txt", weight_221);
	$readmemh("C:/cnn_verilog/data/conv2_weight_22.txt", weight_222);
	$readmemh("C:/cnn_verilog/data/conv2_weight_23.txt", weight_223);
    $readmemh("C:/cnn_verilog/data/conv2_weight_31.txt", weight_231);
	$readmemh("C:/cnn_verilog/data/conv2_weight_32.txt", weight_232);
	$readmemh("C:/cnn_verilog/data/conv2_weight_33.txt", weight_233);
   //fullyconnected
   $readmemh("C:/cnn_verilog/data/fc_weight.txt", weight_fc);
   $readmemh("C:/cnn_verilog/data/fc_bias.txt", bias_fc);
 end
 

chip chip1 (
clk,rst_n,data_in,decision,valid_out_6,
 w_11 , w_12 , w_13 , b_1 ,
//conv2
 b_2 , w_211 , w_212 , w_213 , w_221 , w_222 , w_223 , w_231 , w_232 , w_233 ,
//fullyconnected
 w_fc, b_fc);

genvar i;
generate
    for(i=0;i<=24;i=i+1) begin
        assign w_11[(8*i)+:8]=weight_11[i];
        assign w_12[(8*i)+:8]=weight_12[i];
        assign w_13[(8*i)+:8]=weight_13[i];
        assign w_211[(8*i)+:8]=weight_211[i];
        assign w_212[(8*i)+:8]=weight_212[i];
        assign w_213[(8*i)+:8]=weight_213[i];
        assign w_221[(8*i)+:8]=weight_221[i];
        assign w_222[(8*i)+:8]=weight_222[i];
        assign w_223[(8*i)+:8]=weight_223[i];
        assign w_231[(8*i)+:8]=weight_231[i];
        assign w_232[(8*i)+:8]=weight_232[i];
        assign w_233[(8*i)+:8]=weight_233[i];            
    end
    for(i=0;i<=2;i=i+1) begin
        assign b_1[(8*i)+:8]=bias_1[i];
        assign b_2[(8*i)+:8]=bias_2[i];          
    end
    for(i=0;i<=479;i=i+1) begin
        assign w_fc[(8*i)+:8]=weight_fc[i];    
    end
    for(i=0;i<=9;i=i+1) begin
        assign b_fc[(8*i)+:8]=bias_fc[i];          
    end
endgenerate



// Read image text file
initial begin
  $readmemh("C:/cnn_verilog/data/input_1000.txt", pixels);
  cnt <= 0;
  img_idx <= 0;
  clk <= 1'b0;
  input_cnt <= -1;
  rst_n <= 1'b1;
  rand_num <= 1'b0;
  accuracy <= 0;

  #3
  rst_n <= 1'b0;
  
  #3
  rst_n <= 1'b1;
end

always @(posedge clk) begin
  if(~rst_n) begin

    #3
    rst_n <= 1'b1;
  end else begin
    // decision done
    if(valid_out_6 == 1'b1) begin
      if(state !== 1'bx) begin
        if(cnt % 10 == 1) begin
          if(rand_num % 10 == decision) begin
            $display("%0dst input image : original value = %0d, decision = %0d at %0t ps ==> Success", cnt, rand_num % 10, decision, $time);
            accuracy <= accuracy + 1'b1;
          end else begin
            $display("%0dst input image : original value = %0d, decision = %0d at %0t ps ==> Fail", cnt, rand_num % 10, decision, $time);
          end
        end else if(cnt % 10 == 2) begin
          if(rand_num % 10 == decision) begin
            $display("%0dnd input image : original value = %0d, decision = %0d at %0t ps ==> Success", cnt, rand_num % 10, decision, $time);
            accuracy <= accuracy + 1'b1;
          end else begin
            $display("%0dnd input image : original value = %0d, decision = %0d at %0t ps ==> Fail", cnt, rand_num % 10, decision, $time);
          end
        end else if(cnt % 10 == 3)
          if(rand_num % 10 == decision) begin
            $display("%0drd input image : original value = %0d, decision = %0d at %0t ps ==> Success", cnt, rand_num % 10, decision, $time);
            accuracy <= accuracy + 1'b1;
          end else begin
            $display("%0drd input image : original value = %0d, decision = %0d at %0t ps ==> Fail", cnt, rand_num % 10, decision, $time);
          end
        else begin
          if(rand_num % 10 == decision) begin
            $display("%0dth input image : original value = %0d, decision = %0d at %0t ps ==> Success", cnt, rand_num % 10, decision, $time);
            accuracy <= accuracy + 1'b1;
          end else begin
            $display("%0dth input image : original value = %0d, decision = %0d at %0t ps ==> Fail", cnt, rand_num % 10, decision, $time);
          end
        end
      end

      state <= 1'b0;
      rst_n <= 1'b0;
      input_cnt <= input_cnt + 1'b1;
      rand_num <= $urandom_range(0, 1000);
      //rand_num <= rand_num + 1'b1;
    end

    if(state == 1'b0) begin
      //data_in <= pixels[cnt*784 + img_idx];
      data_in <= pixels[rand_num*784 + img_idx];
      //data_in <= pixel[img_idx];
      img_idx <= img_idx + 1'b1;

      if(img_idx == 10'd784) begin
        cnt <= cnt + 1'b1;

        if(cnt == 10'd1000) begin
          $display("\n\n------ Final Accuracy for 1000 Input Image ------");
          $display("Accuracy : %3d%%", accuracy/10);
          $stop;
        end
        img_idx <= 0;
        state <= 1'b1;  // done
      end
    end
  end
end

endmodule
