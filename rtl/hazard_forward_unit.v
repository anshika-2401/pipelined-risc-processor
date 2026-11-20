`timescale 1ns / 1ps
//
// hazard_forward_unit.v - Hazard detection (stalling) and forwarding
// control for the 5-stage pipeline.
//
// Forwarding: the instruction currently IN EX needs its own operands
// (ex_rs, ex_rt) checked against the destinations of the instruction
// one stage ahead (now in MEM, i.e. the EX/MEM latch) and two stages
// ahead (now in WB, i.e. the MEM/WB latch). EX/MEM wins if both match,
// since it holds the more recently produced value.
//
// Stalling: separately, the instruction currently in ID (id_rs, id_rt)
// is checked against the instruction one stage ahead of it, in EX. If
// that EX instruction is a load targeting the same register, forwarding
// cannot help yet (the loaded word isn't ready until MEM finishes), so
// the pipeline stalls for one cycle.
//

module hazard_forward_unit (
    // ID-stage instruction (for stall detection only)
    input  [4:0] id_rs,
    input  [4:0] id_rt,

    // EX-stage instruction
    input  [4:0] ex_rs,          // EX instruction's own rs (forwarding)
    input  [4:0] ex_rt,          // EX instruction's own rt (forwarding)
    input  [4:0] ex_rd,          // EX instruction's rd     (stall detection)
    input        ex_reg_write,
    input        ex_mem_read,    // 1 if EX-stage instruction is a load

    // MEM-stage instruction (one ahead of EX -> "EX/MEM" forward source)
    input  [4:0] mem_rd,
    input        mem_reg_write,

    // WB-stage instruction (two ahead of EX -> "MEM/WB" forward source)
    input  [4:0] wb_rd,
    input        wb_reg_write,

    // forwarding select for EX-stage ALU operand A / B:
    // 00 = from register file read in ID (no hazard)
    // 01 = forward from WB stage (MEM/WB latch)
    // 10 = forward from MEM stage (EX/MEM latch) - higher priority
    output [1:0] forward_a,
    output [1:0] forward_b,

    output       stall           // 1 => bubble this cycle (load-use hazard)
);

    reg [1:0] fwd_a, fwd_b;

    always @(*) begin
        fwd_a = 2'b00;
        if (mem_reg_write && (mem_rd != 5'd0) && (mem_rd == ex_rs))
            fwd_a = 2'b10;
        else if (wb_reg_write && (wb_rd != 5'd0) && (wb_rd == ex_rs))
            fwd_a = 2'b01;

        fwd_b = 2'b00;
        if (mem_reg_write && (mem_rd != 5'd0) && (mem_rd == ex_rt))
            fwd_b = 2'b10;
        else if (wb_reg_write && (wb_rd != 5'd0) && (wb_rd == ex_rt))
            fwd_b = 2'b01;
    end

    assign forward_a = fwd_a;
    assign forward_b = fwd_b;

    // Load-use stall: EX-stage instruction is a load, and the ID-stage
    // instruction right behind it needs that same destination register.
    assign stall = ex_mem_read && (ex_rd != 5'd0) &&
                   ((ex_rd == id_rs) || (ex_rd == id_rt));

endmodule
