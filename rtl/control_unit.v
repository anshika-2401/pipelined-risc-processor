`timescale 1ns / 1ps
//
// control_unit.v - Decodes opcode (+funct for R-type) into the control
// signals used downstream in EX / MEM / WB.
//

module control_unit (
    input  [5:0]  opcode,
    input  [10:0] funct,

    output        reg_write,     // write result back to register file
    output        alu_src,       // 1 = ALU operand B comes from immediate
    output [3:0]  alu_op,
    output        mem_read,
    output        mem_write,
    output        mem_to_reg,    // 1 = WB data comes from data memory, not ALU
    output        branch_eq,     // BEQ
    output        branch_ne,     // BNE
    output        is_halt
);

    localparam OP_RTYPE = 6'b000000;
    localparam OP_ADDI  = 6'b001000;
    localparam OP_LW    = 6'b001001;
    localparam OP_SW    = 6'b001010;
    localparam OP_BEQ   = 6'b001011;
    localparam OP_BNE   = 6'b001100;
    localparam OP_HALT  = 6'b111111;

    localparam ALU_ADD = 4'b0000;
    localparam ALU_SUB = 4'b0001;
    localparam ALU_AND = 4'b0010;
    localparam ALU_OR  = 4'b0011;
    localparam ALU_XOR = 4'b0100;
    localparam ALU_SLT = 4'b0101;

    reg reg_write_r, alu_src_r, mem_read_r, mem_write_r, mem_to_reg_r;
    reg branch_eq_r, branch_ne_r, is_halt_r;
    reg [3:0] alu_op_r;

    always @(*) begin
        // defaults
        reg_write_r  = 1'b0;
        alu_src_r    = 1'b0;
        alu_op_r     = ALU_ADD;
        mem_read_r   = 1'b0;
        mem_write_r  = 1'b0;
        mem_to_reg_r = 1'b0;
        branch_eq_r  = 1'b0;
        branch_ne_r  = 1'b0;
        is_halt_r    = 1'b0;

        case (opcode)
            OP_RTYPE: begin
                reg_write_r = 1'b1;
                alu_src_r   = 1'b0;
                case (funct)
                    11'd0: alu_op_r = ALU_ADD;
                    11'd1: alu_op_r = ALU_SUB;
                    11'd2: alu_op_r = ALU_AND;
                    11'd3: alu_op_r = ALU_OR;
                    11'd4: alu_op_r = ALU_XOR;
                    11'd5: alu_op_r = ALU_SLT;
                    default: alu_op_r = ALU_ADD;
                endcase
            end
            OP_ADDI: begin
                reg_write_r = 1'b1;
                alu_src_r   = 1'b1;
                alu_op_r    = ALU_ADD;
            end
            OP_LW: begin
                reg_write_r  = 1'b1;
                alu_src_r    = 1'b1;
                alu_op_r     = ALU_ADD;
                mem_read_r   = 1'b1;
                mem_to_reg_r = 1'b1;
            end
            OP_SW: begin
                alu_src_r   = 1'b1;
                alu_op_r    = ALU_ADD;
                mem_write_r = 1'b1;
            end
            OP_BEQ: begin
                alu_op_r    = ALU_SUB;
                branch_eq_r = 1'b1;
            end
            OP_BNE: begin
                alu_op_r    = ALU_SUB;
                branch_ne_r = 1'b1;
            end
            OP_HALT: begin
                is_halt_r = 1'b1;
            end
            default: ; // NOP / unrecognized -> all defaults (no write, no mem)
        endcase
    end

    assign reg_write  = reg_write_r;
    assign alu_src    = alu_src_r;
    assign alu_op     = alu_op_r;
    assign mem_read   = mem_read_r;
    assign mem_write  = mem_write_r;
    assign mem_to_reg = mem_to_reg_r;
    assign branch_eq  = branch_eq_r;
    assign branch_ne  = branch_ne_r;
    assign is_halt    = is_halt_r;

endmodule
