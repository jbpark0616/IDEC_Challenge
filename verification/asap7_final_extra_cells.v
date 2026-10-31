`timescale 1ps/1ps
// Additional mapped cells; Boolean functions checked against the supplied
// ASAP7 RVT standard-cell Verilog library. Zero-delay simulation only.
module AND2x4_ASAP7_75t_R(output Y,input A,B); assign Y=A&B; endmodule
module AND3x4_ASAP7_75t_R(output Y,input A,B,C); assign Y=A&B&C; endmodule
module AND3x2_ASAP7_75t_R(output Y,input A,B,C); assign Y=A&B&C; endmodule
module INVx3_ASAP7_75t_R(output Y,input A); assign Y=~A; endmodule
module INVx6_ASAP7_75t_R(output Y,input A); assign Y=~A; endmodule
module BUFx12f_ASAP7_75t_R(output Y,input A); assign Y=A; endmodule
module MAJx2_ASAP7_75t_R(output Y,input A,B,C); assign Y=(A&B)|(A&C)|(B&C); endmodule
module AO211x2_ASAP7_75t_R(output Y,input A1,A2,B,C); assign Y=(A1&A2)|B|C; endmodule

`timescale 1ps/1ps
module ICGx1_ASAP7_75t_R(input CLK, ENA, SE, output GCLK);
reg IQ; always @* if (!CLK) IQ = ENA | SE;
assign GCLK = CLK & IQ;
endmodule
module TIELOx1_ASAP7_75t_R(output L);
assign L = 0;
endmodule
