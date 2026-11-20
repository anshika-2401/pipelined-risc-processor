`timescale 1ns / 1ps
//
// register_file.v - 32 x 32-bit general purpose register file.
// Two combinational read ports (rs, rt read every cycle in ID) and one
// write port (write back happens in WB, on the clock edge).
//
// Write-during-read: if WB is writing to the same register ID is
// reading this cycle, the read port forwards the write data out
// combinationally (same-cycle write-then-read). This matters whenever
// a result is written and read in the same clock edge due to the
// pipeline's register-file timing; without it, back-to-back dependent
// instructions separated by exactly enough stalls could read stale data.
//

module register_file (
    input         clk,
    input         rst,

    input  [4:0]  read_addr1,
    input  [4:0]  read_addr2,
    output [31:0] read_data1,
    output [31:0] read_data2,

    input         write_en,
    input  [4:0]  write_addr,
    input  [31:0] write_data
);

    reg [31:0] regs [0:31];
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'd0;
        end else if (write_en) begin
            regs[write_addr] <= write_data;
        end
    end

    // Combinational read with write-forwarding.
    assign read_data1 = (write_en && write_addr == read_addr1) ? write_data : regs[read_addr1];
    assign read_data2 = (write_en && write_addr == read_addr2) ? write_data : regs[read_addr2];

endmodule
