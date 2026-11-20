`timescale 1ns / 1ps
//
// instr_mem.v - Instruction memory. Separate from data memory so IF and
// MEM can both access memory in the same cycle (classic Harvard split
// for a pipelined datapath). Combinational read, word addressed by
// byte address[31:2].
//

module instr_mem #(
    parameter DEPTH = 256
) (
    input  [31:0] addr,
    output [31:0] instr
);

    reg [31:0] mem [0:DEPTH-1];

    assign instr = mem[addr[31:2]];

    // Testbench loads a program with $readmemh or by direct assignment
    // to `mem` via a hierarchical reference, e.g. uut.imem.mem[0] = ...

endmodule
