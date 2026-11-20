`timescale 1ns / 1ps
//
// tb_riscproc.v - Directed test bench for the 5-stage pipelined RISC
// processor. Loads a short program directly into instruction memory
// (hierarchical reference into uut.imem.mem), runs the clock, and
// checks final register file contents against expected values.
//
// Test program covers, in program order:
//   1. ADDI into several registers (basic I-type write)
//   2. Back to back dependent ADD instructions   (EX/MEM forwarding)
//   3. A SUB and AND/OR/XOR exercising all ALU ops
//   4. SLT (comparison)
//   5. SW then LW to the same address              (memory path)
//   6. LW immediately followed by a dependent ADD   (load-use hazard / stall)
//   7. BEQ not taken, then BEQ taken                (branch, flush)
//   8. BNE not taken, then BNE taken
//   9. A chain of 3 dependent instructions using MEM/WB forwarding
//  10. HALT
//

module tb_riscproc;

    reg clk;
    reg rst;

    riscproc_top uut (
        .clk (clk),
        .rst (rst)
    );

    // 100 MHz-equivalent test clock
    always #5 clk = ~clk;

    // ---- instruction encoding helpers ----------------------------------
    function [31:0] rtype(input [5:0] op, input [4:0] rs, input [4:0] rt,
                          input [4:0] rd, input [10:0] funct);
        rtype = {op, rs, rt, rd, funct};
    endfunction

    function [31:0] itype(input [5:0] op, input [4:0] rs, input [4:0] rt,
                          input [15:0] imm);
        itype = {op, rs, rt, imm};
    endfunction

    localparam OP_R    = 6'b000000;
    localparam OP_ADDI = 6'b001000;
    localparam OP_LW   = 6'b001001;
    localparam OP_SW   = 6'b001010;
    localparam OP_BEQ  = 6'b001011;
    localparam OP_BNE  = 6'b001100;
    localparam OP_HALT = 6'b111111;

    localparam F_ADD = 11'd0;
    localparam F_SUB = 11'd1;
    localparam F_AND = 11'd2;
    localparam F_OR  = 11'd3;
    localparam F_XOR = 11'd4;
    localparam F_SLT = 11'd5;

    integer errors;
    integer i;

    task check(input [255:0] name, input [31:0] actual, input [31:0] expected);
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s  got=%0d (0x%08h)  expected=%0d (0x%08h)",
                          name, actual, actual, expected, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s  = %0d", name, actual);
            end
        end
    endtask

    initial begin
        errors = 0;
        clk = 0;
        rst = 1;

        // ---------------------------------------------------------------
        // Program (word addresses 0,1,2... -> byte addr = word*4)
        // Registers used: r1..r10, r20 (loop/branch scratch), r31 (halt pad)
        // ---------------------------------------------------------------
        i = 0;
        // 1. basic ADDI writes
        uut.imem.mem[i] = itype(OP_ADDI, 5'd0,  5'd1, 16'd5);   i=i+1; // r1 = r0 + 5 = 5
        uut.imem.mem[i] = itype(OP_ADDI, 5'd0,  5'd2, 16'd10);  i=i+1; // r2 = 10
        uut.imem.mem[i] = itype(OP_ADDI, 5'd0,  5'd3, 16'd3);   i=i+1; // r3 = 3

        // 2. back to back dependent ADDs -> forwarding from EX/MEM
        uut.imem.mem[i] = rtype(OP_R, 5'd1, 5'd2, 5'd4, F_ADD); i=i+1; // r4 = r1+r2 = 15
        uut.imem.mem[i] = rtype(OP_R, 5'd4, 5'd3, 5'd5, F_ADD); i=i+1; // r5 = r4+r3 = 18 (r4 fresh from previous instr)

        // 3. SUB / AND / OR / XOR
        uut.imem.mem[i] = rtype(OP_R, 5'd2, 5'd1, 5'd6, F_SUB); i=i+1; // r6 = r2-r1 = 5
        uut.imem.mem[i] = rtype(OP_R, 5'd1, 5'd2, 5'd7, F_AND); i=i+1; // r7 = 5 & 10 = 0
        uut.imem.mem[i] = rtype(OP_R, 5'd1, 5'd2, 5'd8, F_OR);  i=i+1; // r8 = 5 | 10 = 15
        uut.imem.mem[i] = rtype(OP_R, 5'd1, 5'd2, 5'd9, F_XOR); i=i+1; // r9 = 5 ^ 10 = 15

        // 4. SLT
        uut.imem.mem[i] = rtype(OP_R, 5'd1, 5'd2, 5'd10, F_SLT); i=i+1; // r10 = (5<10) = 1

        // 5. SW then LW same address
        uut.imem.mem[i] = itype(OP_ADDI, 5'd0, 5'd11, 16'd100); i=i+1; // r11 = base addr 100
        uut.imem.mem[i] = itype(OP_SW, 5'd11, 5'd5, 16'd0);     i=i+1; // MEM[100] = r5 (18)
        uut.imem.mem[i] = itype(OP_LW, 5'd11, 5'd12, 16'd0);    i=i+1; // r12 = MEM[100] = 18

        // 6. load-use hazard: LW then immediately dependent ADD
        uut.imem.mem[i] = itype(OP_LW, 5'd11, 5'd13, 16'd0);    i=i+1; // r13 = MEM[100] = 18
        uut.imem.mem[i] = rtype(OP_R, 5'd13, 5'd3, 5'd14, F_ADD); i=i+1; // r14 = r13+r3 = 21 (needs stall)

        // 7. BEQ not taken, then BEQ taken
        uut.imem.mem[i] = itype(OP_BEQ, 5'd1, 5'd2, 16'd50);    i=i+1; // r1(5) != r2(10) -> not taken
        uut.imem.mem[i] = itype(OP_ADDI, 5'd0, 5'd15, 16'd1);   i=i+1; // r15 = 1  (proves not-taken fell through)
        uut.imem.mem[i] = itype(OP_ADDI, 5'd20, 5'd20, 16'd7);  i=i+1; // r20 = r20(0)+7 = 7
        uut.imem.mem[i] = itype(OP_BEQ, 5'd20, 5'd20, 16'd2);   i=i+1; // r20==r20 -> taken, skip next 2 instr
        uut.imem.mem[i] = itype(OP_ADDI, 5'd0, 5'd16, 16'd99);  i=i+1; // SKIPPED: r16 should stay 0
        uut.imem.mem[i] = itype(OP_ADDI, 5'd0, 5'd16, 16'd99);  i=i+1; // SKIPPED: r16 should stay 0
        uut.imem.mem[i] = itype(OP_ADDI, 5'd0, 5'd17, 16'd42);  i=i+1; // branch target: r17 = 42

        // 8. BNE not taken, then BNE taken
        uut.imem.mem[i] = itype(OP_BNE, 5'd1, 5'd1, 16'd50);    i=i+1; // equal -> not taken
        uut.imem.mem[i] = itype(OP_ADDI, 5'd0, 5'd18, 16'd1);   i=i+1; // r18 = 1 (proves fallthrough)
        uut.imem.mem[i] = itype(OP_BNE, 5'd1, 5'd2, 16'd2);     i=i+1; // 5 != 10 -> taken, skip next 2
        uut.imem.mem[i] = itype(OP_ADDI, 5'd0, 5'd19, 16'd99);  i=i+1; // SKIPPED
        uut.imem.mem[i] = itype(OP_ADDI, 5'd0, 5'd19, 16'd99);  i=i+1; // SKIPPED
        uut.imem.mem[i] = itype(OP_ADDI, 5'd0, 5'd19, 16'd7);   i=i+1; // branch target: r19 = 7

        // 9. chain of 3 dependent instructions (MEM/WB forwarding reach)
        uut.imem.mem[i] = itype(OP_ADDI, 5'd0, 5'd21, 16'd1);   i=i+1; // r21 = 1
        uut.imem.mem[i] = rtype(OP_R, 5'd21, 5'd21, 5'd21, F_ADD); i=i+1; // r21 = 2
        uut.imem.mem[i] = rtype(OP_R, 5'd21, 5'd21, 5'd21, F_ADD); i=i+1; // r21 = 4
        uut.imem.mem[i] = rtype(OP_R, 5'd21, 5'd21, 5'd21, F_ADD); i=i+1; // r21 = 8

        // 10. halt
        uut.imem.mem[i] = itype(OP_HALT, 5'd0, 5'd0, 16'd0);    i=i+1;

        // release reset after memory is loaded
        #12;
        rst = 0;

        // run long enough for the whole program (with stalls/flushes) to retire
        #600;

        // ---------------------------------------------------------------
        // Checks (read register file hierarchically)
        // ---------------------------------------------------------------
        check("r1  ADDI base",            uut.rf.regs[1],  32'd5);
        check("r2  ADDI base",            uut.rf.regs[2],  32'd10);
        check("r4  back-to-back fwd",     uut.rf.regs[4],  32'd15);
        check("r5  back-to-back fwd #2",  uut.rf.regs[5],  32'd18);
        check("r6  SUB",                  uut.rf.regs[6],  32'd5);
        check("r7  AND",                  uut.rf.regs[7],  32'd0);
        check("r8  OR",                   uut.rf.regs[8],  32'd15);
        check("r9  XOR",                  uut.rf.regs[9],  32'd15);
        check("r10 SLT",                  uut.rf.regs[10], 32'd1);
        check("r12 LW after SW",          uut.rf.regs[12], 32'd18);
        check("r14 load-use stall result",uut.rf.regs[14], 32'd21);
        check("r15 BEQ not-taken fallthru",uut.rf.regs[15],32'd1);
        check("r16 BEQ taken (must skip)", uut.rf.regs[16],32'd0);
        check("r17 BEQ taken target",     uut.rf.regs[17], 32'd42);
        check("r18 BNE not-taken fallthru",uut.rf.regs[18],32'd1);
        check("r19 BNE taken target",     uut.rf.regs[19], 32'd7);
        check("r21 dependent chain x3",   uut.rf.regs[21], 32'd8);

        if (errors == 0)
            $display("\nALL TESTS PASSED");
        else
            $display("\n%0d TEST(S) FAILED", errors);

        $finish;
    end

    // waveform dump for debugging
    initial begin
        $dumpfile("riscproc_tb.vcd");
        $dumpvars(0, tb_riscproc);
    end

endmodule
