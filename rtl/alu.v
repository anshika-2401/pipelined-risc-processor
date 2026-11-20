`timescale 1ns / 1ps
//
// alu.v - Combinational ALU for the EX stage.
// Supports ADD, SUB, AND, OR, XOR, SLT and a pass-through for branch
// comparisons (the branch condition itself is resolved here too, via
// the zero flag, so the EX stage can tell MEM/hazard logic whether to
// take a branch).
//

module alu (
    input  [3:0]  alu_op,      // operation select, see localparams below
    input  [31:0] a,
    input  [31:0] b,
    output [31:0] result,
    output        zero         // result == 0  (used for BEQ/BNE)
);

    localparam ALU_ADD = 4'b0000;
    localparam ALU_SUB = 4'b0001;
    localparam ALU_AND = 4'b0010;
    localparam ALU_OR  = 4'b0011;
    localparam ALU_XOR = 4'b0100;
    localparam ALU_SLT = 4'b0101;

    reg [31:0] result_r;

    always @(*) begin
        case (alu_op)
            ALU_ADD: result_r = a + b;
            ALU_SUB: result_r = a - b;
            ALU_AND: result_r = a & b;
            ALU_OR:  result_r = a | b;
            ALU_XOR: result_r = a ^ b;
            ALU_SLT: result_r = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            default: result_r = 32'hXXXXXXXX;
        endcase
    end

    assign result = result_r;
    assign zero   = (result_r == 32'd0);

endmodule
