`timescale 1ps/1ps
module AND4x2_ASAP7_75t_R(output Y, input A, input B, input C, input D);
assign Y = (A & B & C & D);
endmodule
module AND5x2_ASAP7_75t_R(output Y, input A, input B, input C, input D, input E);
assign Y = (A & B & C & D & E);
endmodule
module AO21x2_ASAP7_75t_R(output Y, input A1, input A2, input B);
assign Y = (A1 & A2) | (B);
endmodule
module AO222x2_ASAP7_75t_R(output Y, input A1, input A2, input B1, input B2, input C1, input C2);
assign Y = (A1 & A2) | (B1 & B2) | (C1 & C2);
endmodule
module AO33x2_ASAP7_75t_R(output Y, input A1, input A2, input A3, input B1, input B2, input B3);
assign Y = (A1 & A2 & A3) | (B1 & B2 & B3);
endmodule
module OA222x2_ASAP7_75t_R(output Y, input A1, input A2, input B1, input B2, input C1, input C2);
assign Y = (A1 & B1 & C1) | (A1 & B1 & C2) | (A1 & B2 & C1) | (A1 & B2 & C2) | (A2 & B1 & C1) | (A2 & B1 & C2) | (A2 & B2 & C1) | (A2 & B2 & C2);
endmodule
module OA33x2_ASAP7_75t_R(output Y, input A1, input A2, input A3, input B1, input B2, input B3);
assign Y = (A1 & B1) | (A1 & B2) | (A1 & B3) | (A2 & B1) | (A2 & B2) | (A2 & B3) | (A3 & B1) | (A3 & B2) | (A3 & B3);
endmodule
module OR3x2_ASAP7_75t_R(output Y, input A, input B, input C);
assign Y = (A) | (B) | (C);
endmodule
module OR4x2_ASAP7_75t_R(output Y, input A, input B, input C, input D);
assign Y = (A) | (B) | (C) | (D);
endmodule
