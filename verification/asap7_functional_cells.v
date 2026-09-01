`timescale 1ps/1ps

// Zero-delay functional models for the ASAP7 cells instantiated by the
// post-synthesis Winograd chip netlist. Timing is checked separately by
// OpenSTA; these models are used only for gate-level logic equivalence.

module BUFx2_ASAP7_75t_R(output Y, input A); assign Y = A; endmodule
module BUFx3_ASAP7_75t_R(output Y, input A); assign Y = A; endmodule
module BUFx4_ASAP7_75t_R(output Y, input A); assign Y = A; endmodule
module BUFx4f_ASAP7_75t_R(output Y, input A); assign Y = A; endmodule
module BUFx5_ASAP7_75t_R(output Y, input A); assign Y = A; endmodule
module BUFx6f_ASAP7_75t_R(output Y, input A); assign Y = A; endmodule
module INVx1_ASAP7_75t_R(output Y, input A); assign Y = ~A; endmodule
module INVx2_ASAP7_75t_R(output Y, input A); assign Y = ~A; endmodule
module INVx4_ASAP7_75t_R(output Y, input A); assign Y = ~A; endmodule

module AND2x2_ASAP7_75t_R(output Y, input A, B); assign Y = A & B; endmodule
module AND3x1_ASAP7_75t_R(output Y, input A, B, C); assign Y = A & B & C; endmodule
module AND4x1_ASAP7_75t_R(output Y, input A, B, C, D); assign Y = A & B & C & D; endmodule
module AND5x1_ASAP7_75t_R(output Y, input A, B, C, D, E); assign Y = A & B & C & D & E; endmodule
module OR2x2_ASAP7_75t_R(output Y, input A, B); assign Y = A | B; endmodule
module OR3x1_ASAP7_75t_R(output Y, input A, B, C); assign Y = A | B | C; endmodule
module OR4x1_ASAP7_75t_R(output Y, input A, B, C, D); assign Y = A | B | C | D; endmodule
module OR5x1_ASAP7_75t_R(output Y, input A, B, C, D, E); assign Y = A | B | C | D | E; endmodule
module NAND2x1_ASAP7_75t_R(output Y, input A, B); assign Y = ~(A & B); endmodule
module NAND2x2_ASAP7_75t_R(output Y, input A, B); assign Y = ~(A & B); endmodule
module NAND3x1_ASAP7_75t_R(output Y, input A, B, C); assign Y = ~(A & B & C); endmodule
module NAND3x2_ASAP7_75t_R(output Y, input A, B, C); assign Y = ~(A & B & C); endmodule
module NOR2x1_ASAP7_75t_R(output Y, input A, B); assign Y = ~(A | B); endmodule
module NOR2x2_ASAP7_75t_R(output Y, input A, B); assign Y = ~(A | B); endmodule
module NOR3x1_ASAP7_75t_R(output Y, input A, B, C); assign Y = ~(A | B | C); endmodule
module NOR3x2_ASAP7_75t_R(output Y, input A, B, C); assign Y = ~(A | B | C); endmodule
module XOR2x2_ASAP7_75t_R(output Y, input A, B); assign Y = A ^ B; endmodule
module XNOR2x2_ASAP7_75t_R(output Y, input A, B); assign Y = ~(A ^ B); endmodule

module AO21x1_ASAP7_75t_R(output Y, input A1, A2, B); assign Y = (A1 & A2) | B; endmodule
module AO221x1_ASAP7_75t_R(output Y, input A1, A2, B1, B2, C); assign Y = (A1 & A2) | (B1 & B2) | C; endmodule
module AO22x1_ASAP7_75t_R(output Y, input A1, A2, B1, B2); assign Y = (A1 & A2) | (B1 & B2); endmodule
module AO31x2_ASAP7_75t_R(output Y, input A1, A2, A3, B); assign Y = (A1 & A2 & A3) | B; endmodule
module AO32x1_ASAP7_75t_R(output Y, input A1, A2, A3, B1, B2); assign Y = (A1 & A2 & A3) | (B1 & B2); endmodule
module AOI211x1_ASAP7_75t_R(output Y, input A1, A2, B, C); assign Y = ~((A1 & A2) | B | C); endmodule
module AOI21x1_ASAP7_75t_R(output Y, input A1, A2, B); assign Y = ~((A1 & A2) | B); endmodule
module AOI221x1_ASAP7_75t_R(output Y, input A1, A2, B1, B2, C); assign Y = ~((A1 & A2) | (B1 & B2) | C); endmodule
module AOI22x1_ASAP7_75t_R(output Y, input A1, A2, B1, B2); assign Y = ~((A1 & A2) | (B1 & B2)); endmodule

module OA211x2_ASAP7_75t_R(output Y, input A1, A2, B, C); assign Y = (A1 | A2) & B & C; endmodule
module OA21x2_ASAP7_75t_R(output Y, input A1, A2, B); assign Y = (A1 | A2) & B; endmodule
module OA221x2_ASAP7_75t_R(output Y, input A1, A2, B1, B2, C); assign Y = (A1 | A2) & (B1 | B2) & C; endmodule
module OA22x2_ASAP7_75t_R(output Y, input A1, A2, B1, B2); assign Y = (A1 | A2) & (B1 | B2); endmodule
module OA31x2_ASAP7_75t_R(output Y, input A1, A2, A3, B1); assign Y = (A1 | A2 | A3) & B1; endmodule
module OAI21x1_ASAP7_75t_R(output Y, input A1, A2, B); assign Y = ~((A1 | A2) & B); endmodule
module OAI22x1_ASAP7_75t_R(output Y, input A1, A2, B1, B2); assign Y = ~((A1 | A2) & (B1 | B2)); endmodule

module HAxp5_ASAP7_75t_R(output CON, SN, input A, B);
    // ASAP7's HA exposes inverted carry and inverted sum (CON/SN).
    assign SN = ~(A ^ B);
    assign CON = ~(A & B);
endmodule

module FAx1_ASAP7_75t_R(output CON, SN, input A, B, CI);
    // ASAP7's FA likewise exposes inverted carry and inverted sum.
    assign SN = ~(A ^ B ^ CI);
    assign CON = ~((A & B) | (A & CI) | (B & CI));
endmodule

module TIEHIx1_ASAP7_75t_R(output H); assign H = 1'b1; endmodule

module DFFHQNx1_ASAP7_75t_R(output reg QN, input D, CLK);
    always @(posedge CLK)
        QN <= ~D;
endmodule

module DFFASRHQNx1_ASAP7_75t_R(
    output reg QN,
    input D,
    input RESETN,
    input SETN,
    input CLK
);
    always @(posedge CLK or negedge RESETN or negedge SETN) begin
        if (!RESETN)
            QN <= 1'b1;
        else if (!SETN)
            QN <= 1'b0;
        else
            QN <= ~D;
    end
endmodule
