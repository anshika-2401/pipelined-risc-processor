`timescale 1ns / 1ps
//
// riscproc_top.v - Top level: 32-bit, 5-stage pipelined RISC processor.
// IF -> ID -> EX -> MEM -> WB, classic datapath.
//
// Hazards:
//   - Forwarding (EX/MEM and MEM/WB -> EX operands) handles back to
//     back dependent ALU instructions with zero stall cycles.
//   - Load-use hazard (load immediately followed by a dependent
//     instruction) is caught by hazard_forward_unit and costs one
//     stall cycle: IF/ID is frozen and a bubble (NOP) is inserted into
//     ID/EX for that cycle.
//   - Branches (BEQ/BNE) are resolved in EX. Because two younger
//     instructions have already been fetched (IF, ID) by the time EX
//     knows the outcome, a taken branch flushes those two stages
//     (converts them to NOPs) - a 2 cycle misprediction penalty, paid
//     on every taken branch since there is no prediction here.
//

module riscproc_top (
    input clk,
    input rst
);

    // ============================================================
    // IF stage
    // ============================================================
    reg  [31:0] pc;
    wire [31:0] pc_next;
    wire [31:0] if_instr;
    wire        stall;          // from hazard unit, freezes IF/ID
    wire        branch_taken;   // from EX, flushes IF/ID and ID/EX
    wire [31:0] branch_target;

    assign pc_next = branch_taken ? branch_target : (pc + 32'd4);

    always @(posedge clk) begin
        if (rst) pc <= 32'd0;
        else if (!stall) pc <= pc_next;
        // if stall is asserted, PC holds (re-fetch not needed; IF/ID also holds)
    end

    instr_mem imem (
        .addr  (pc),
        .instr (if_instr)
    );

    // ============================================================
    // IF/ID latch
    // ============================================================
    reg [31:0] if_id_instr;
    reg [31:0] if_id_pc;
    reg        if_id_valid;     // 0 => bubble/NOP in this slot

    always @(posedge clk) begin
        if (rst) begin
            if_id_instr <= 32'd0;
            if_id_pc    <= 32'd0;
            if_id_valid <= 1'b0;
        end else if (branch_taken) begin
            // flush: a wrong-path instruction was just fetched into IF;
            // kill it before it reaches ID next cycle
            if_id_instr <= 32'd0;
            if_id_pc    <= 32'd0;
            if_id_valid <= 1'b0;
        end else if (!stall) begin
            if_id_instr <= if_instr;
            if_id_pc    <= pc;
            if_id_valid <= 1'b1;
        end
        // else (stall): hold current IF/ID contents (re-decode next cycle
        // is avoided since EX/ID latch below inserts the bubble instead)
    end

    // ============================================================
    // ID stage
    // ============================================================
    wire [5:0]  id_opcode   = if_id_instr[31:26];
    wire [4:0]  id_rs       = if_id_instr[25:21];
    wire [4:0]  id_rt       = if_id_instr[20:16];
    wire [4:0]  id_rd_rtype = if_id_instr[15:11];
    wire [10:0] id_funct    = if_id_instr[10:0];
    wire [15:0] id_imm      = if_id_instr[15:0];
    wire [31:0] id_imm_ext  = {{16{id_imm[15]}}, id_imm}; // sign extend

    wire        id_reg_write, id_alu_src, id_mem_read, id_mem_write;
    wire        id_mem_to_reg, id_branch_eq, id_branch_ne, id_is_halt;
    wire [3:0]  id_alu_op;

    control_unit cu (
        .opcode     (id_opcode),
        .funct      (id_funct),
        .reg_write  (id_reg_write),
        .alu_src    (id_alu_src),
        .alu_op     (id_alu_op),
        .mem_read   (id_mem_read),
        .mem_write  (id_mem_write),
        .mem_to_reg (id_mem_to_reg),
        .branch_eq  (id_branch_eq),
        .branch_ne  (id_branch_ne),
        .is_halt    (id_is_halt)
    );

    // destination register: rd for R-type, rt for I-type writes (ADDI, LW)
    wire [4:0] id_rd = (id_opcode == 6'b000000) ? id_rd_rtype : id_rt;

    wire [31:0] id_read_data1, id_read_data2;

    register_file rf (
        .clk        (clk),
        .rst        (rst),
        .read_addr1 (id_rs),
        .read_addr2 (id_rt),
        .read_data1 (id_read_data1),
        .read_data2 (id_read_data2),
        .write_en   (mem_wb_reg_write),
        .write_addr (mem_wb_rd),
        .write_data (wb_write_data)
    );

    // gate control signals off if this slot is a bubble or the pipeline
    // is stalling this instruction out (converted to NOP downstream)
    wire id_squash = !if_id_valid;

    // ============================================================
    // ID/EX latch
    // ============================================================
    reg        id_ex_reg_write, id_ex_alu_src, id_ex_mem_read, id_ex_mem_write;
    reg        id_ex_mem_to_reg, id_ex_branch_eq, id_ex_branch_ne;
    reg [3:0]  id_ex_alu_op;
    reg [31:0] id_ex_read_data1, id_ex_read_data2, id_ex_imm_ext, id_ex_pc;
    reg [4:0]  id_ex_rs, id_ex_rt, id_ex_rd;

    wire insert_bubble = stall; // load-use hazard: bubble into ID/EX this cycle

    always @(posedge clk) begin
        if (rst || insert_bubble || id_squash || branch_taken) begin
            id_ex_reg_write  <= 1'b0;
            id_ex_alu_src    <= 1'b0;
            id_ex_mem_read   <= 1'b0;
            id_ex_mem_write  <= 1'b0;
            id_ex_mem_to_reg <= 1'b0;
            id_ex_branch_eq  <= 1'b0;
            id_ex_branch_ne  <= 1'b0;
            id_ex_alu_op     <= 4'b0;
            id_ex_read_data1 <= 32'd0;
            id_ex_read_data2 <= 32'd0;
            id_ex_imm_ext    <= 32'd0;
            id_ex_pc         <= 32'd0;
            id_ex_rs         <= 5'd0;
            id_ex_rt         <= 5'd0;
            id_ex_rd         <= 5'd0;
        end else begin
            id_ex_reg_write  <= id_reg_write;
            id_ex_alu_src    <= id_alu_src;
            id_ex_mem_read   <= id_mem_read;
            id_ex_mem_write  <= id_mem_write;
            id_ex_mem_to_reg <= id_mem_to_reg;
            id_ex_branch_eq  <= id_branch_eq;
            id_ex_branch_ne  <= id_branch_ne;
            id_ex_alu_op     <= id_alu_op;
            id_ex_read_data1 <= id_read_data1;
            id_ex_read_data2 <= id_read_data2;
            id_ex_imm_ext    <= id_imm_ext;
            id_ex_pc         <= if_id_pc;
            id_ex_rs         <= id_rs;
            id_ex_rt         <= id_rt;
            id_ex_rd         <= id_rd;
        end
    end

    // ============================================================
    // EX stage
    // ============================================================
    wire [1:0] forward_a, forward_b;

    // operand A is always rs; forwarding can override it
    reg [31:0] ex_operand_a_fwd, ex_operand_b_fwd;
    always @(*) begin
        case (forward_a)
            2'b01: ex_operand_a_fwd = wb_write_data;      // from MEM/WB result
            2'b10: ex_operand_a_fwd = ex_mem_alu_result;  // from EX/MEM latch
            default: ex_operand_a_fwd = id_ex_read_data1;
        endcase
        case (forward_b)
            2'b01: ex_operand_b_fwd = wb_write_data;
            2'b10: ex_operand_b_fwd = ex_mem_alu_result;
            default: ex_operand_b_fwd = id_ex_read_data2;
        endcase
    end

    wire [31:0] ex_alu_b = id_ex_alu_src ? id_ex_imm_ext : ex_operand_b_fwd;
    wire [31:0] ex_alu_result;
    wire        ex_zero;

    alu alu0 (
        .alu_op (id_ex_alu_op),
        .a      (ex_operand_a_fwd),
        .b      (ex_alu_b),
        .result (ex_alu_result),
        .zero   (ex_zero)
    );

    assign branch_taken  = (id_ex_branch_eq && ex_zero) ||
                            (id_ex_branch_ne && !ex_zero);
    assign branch_target = id_ex_pc + 32'd4 + (id_ex_imm_ext << 2);

    // store-data also needs forwarding (SW rt may itself be a recent result)
    wire [31:0] ex_store_data = ex_operand_b_fwd;

    // ============================================================
    // EX/MEM latch
    // ============================================================
    reg        ex_mem_reg_write, ex_mem_mem_read, ex_mem_mem_write, ex_mem_mem_to_reg;
    reg [31:0] ex_mem_alu_result_r, ex_mem_store_data;
    reg [4:0]  ex_mem_rd;

    always @(posedge clk) begin
        if (rst) begin
            ex_mem_reg_write     <= 1'b0;
            ex_mem_mem_read      <= 1'b0;
            ex_mem_mem_write     <= 1'b0;
            ex_mem_mem_to_reg    <= 1'b0;
            ex_mem_alu_result_r  <= 32'd0;
            ex_mem_store_data    <= 32'd0;
            ex_mem_rd            <= 5'd0;
        end else begin
            ex_mem_reg_write     <= id_ex_reg_write;
            ex_mem_mem_read      <= id_ex_mem_read;
            ex_mem_mem_write     <= id_ex_mem_write;
            ex_mem_mem_to_reg    <= id_ex_mem_to_reg;
            ex_mem_alu_result_r  <= ex_alu_result;
            ex_mem_store_data    <= ex_store_data;
            ex_mem_rd            <= id_ex_rd;
        end
    end

    wire [31:0] ex_mem_alu_result = ex_mem_alu_result_r;

    // ============================================================
    // MEM stage
    // ============================================================
    wire [31:0] mem_read_data;

    data_mem dmem (
        .clk        (clk),
        .addr       (ex_mem_alu_result),
        .write_data (ex_mem_store_data),
        .mem_read   (ex_mem_mem_read),
        .mem_write  (ex_mem_mem_write),
        .read_data  (mem_read_data)
    );

    // ============================================================
    // MEM/WB latch
    // ============================================================
    reg        mem_wb_reg_write, mem_wb_mem_to_reg;
    reg [31:0] mem_wb_alu_result, mem_wb_mem_data;
    reg [4:0]  mem_wb_rd;

    always @(posedge clk) begin
        if (rst) begin
            mem_wb_reg_write  <= 1'b0;
            mem_wb_mem_to_reg <= 1'b0;
            mem_wb_alu_result <= 32'd0;
            mem_wb_mem_data   <= 32'd0;
            mem_wb_rd         <= 5'd0;
        end else begin
            mem_wb_reg_write  <= ex_mem_reg_write;
            mem_wb_mem_to_reg <= ex_mem_mem_to_reg;
            mem_wb_alu_result <= ex_mem_alu_result;
            mem_wb_mem_data   <= mem_read_data;
            mem_wb_rd         <= ex_mem_rd;
        end
    end

    // ============================================================
    // WB stage
    // ============================================================
    wire [31:0] wb_write_data = mem_wb_mem_to_reg ? mem_wb_mem_data : mem_wb_alu_result;

    // ============================================================
    // Hazard / forwarding unit
    // ============================================================
    hazard_forward_unit hfu (
        .id_rs         (id_rs),
        .id_rt         (id_rt),
        .ex_rs         (id_ex_rs),
        .ex_rt         (id_ex_rt),
        .ex_rd         (id_ex_rd),
        .ex_reg_write  (id_ex_reg_write),
        .ex_mem_read   (id_ex_mem_read),
        .mem_rd        (ex_mem_rd),
        .mem_reg_write (ex_mem_reg_write),
        .wb_rd         (mem_wb_rd),
        .wb_reg_write  (mem_wb_reg_write),
        .forward_a     (forward_a),
        .forward_b     (forward_b),
        .stall         (stall)
    );

endmodule
