`timescale 1ns / 1ps
//
// data_mem.v - Data memory for LW/SW, accessed in the MEM stage.
// Synchronous write, combinational read (read value is available
// within the same MEM cycle for a dependent WB).
//

module data_mem #(
    parameter DEPTH = 256
) (
    input         clk,
    input  [31:0] addr,
    input  [31:0] write_data,
    input         mem_read,
    input         mem_write,
    output [31:0] read_data
);

    reg [31:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (mem_write)
            mem[addr[31:2]] <= write_data;
    end

    assign read_data = mem_read ? mem[addr[31:2]] : 32'd0;

endmodule
