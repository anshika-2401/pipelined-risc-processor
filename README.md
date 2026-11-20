# 32 Bit 5 Stage Pipelined RISC Processor

A 32 bit RISC processor with a classic five stage pipeline, written in Verilog, with full hazard handling and a directed test suite.

This is a from scratch design: the datapath, the control unit and the hazard handling are all mine. It runs a custom instruction set, not RISC V.

## What it does

The processor implements a custom instruction set covering arithmetic, logic, immediate, memory and branch operations, with the datapath split across five stages:

| Stage | What happens |
|---|---|
| **IF** instruction fetch | Fetch the instruction, update the program counter |
| **ID** decode | Decode, read the register file, sign extend the immediate, generate control signals |
| **EX** execute | ALU operations, address calculation, branch resolution |
| **MEM** memory access | Data memory read and write |
| **WB** write back | Write the result back to the register file |

Pipeline registers carry values and control signals between stages.

## Instruction set

Two formats, 32 bits each. Full encoding in [docs/isa.md](docs/isa.md).

- **R type**: ADD, SUB, AND, OR, XOR, SLT
- **I type**: ADDI, LW, SW, BEQ, BNE, HALT

## Design details

**Multi functional ALU** arithmetic, logic and signed comparison, with a zero flag used for branch resolution.

**Register file** 32 general purpose 32 bit registers, two combinational read ports (rs and rt are both read every cycle in ID) and one synchronous write port used by WB. The read ports forward the write data combinationally when WB is writing the same register ID is reading, so a write and a read in the same cycle return the new value rather than the stale one.

**Separate instruction and data memories** a Harvard split, so an instruction fetch and a data access can happen in the same cycle without contention.

**Control unit** decodes the opcode, and the funct field for R type, into the control signals consumed by EX, MEM and WB.

### Hazard handling

Dependent instructions are the hard part of a pipeline, and this design handles them two ways.

**Forwarding.** The instruction in EX has its own source registers compared against the destinations of the instruction one stage ahead of it, in MEM, and two stages ahead, in WB. A match routes that result straight into the ALU input instead of the value read from the register file. MEM wins over WB when both match, since it holds the more recent value. This makes back to back dependent ALU instructions cost zero stall cycles.

**Stalling.** The one case forwarding cannot fix is a load immediately followed by an instruction that uses the loaded value: the word is not available until the end of MEM, a cycle later than an ALU result would be. For that load use hazard the pipeline stalls one cycle. IF and the PC are frozen, a bubble is injected into ID/EX, and the dependent instruction re-decodes and enters EX a cycle later, by which point the load is in WB and the value forwards cleanly.

**Branches.** BEQ and BNE are resolved in EX, from the ALU zero flag, with the target computed as PC + 4 + (immediate << 2). By the time EX knows the outcome, two younger instructions have already been fetched, one in ID and one in IF, so a taken branch flushes both by converting them to bubbles. There is no branch prediction, so a taken branch costs a two cycle penalty.

## Verification

17 directed checks in [tb/tb_riscproc.v](tb/tb_riscproc.v), covering:

- every ALU operation (ADD, SUB, AND, OR, XOR, SLT)
- immediate writes
- back to back dependent ALU instructions, exercising MEM to EX forwarding
- a three deep dependent chain, exercising both forwarding paths
- SW followed by LW to the same address
- a load immediately followed by a dependent ADD, exercising the load use stall
- BEQ not taken and BEQ taken, checking that the two in flight instructions after a taken branch really are flushed
- BNE not taken and BNE taken

Results are checked against expected register contents after the program retires. Current state: all 17 pass, log in [docs/simulation_log.txt](docs/simulation_log.txt).

Two bugs worth recording, both found by these tests:

1. The forwarding unit originally compared the ID stage instruction's sources against the MEM and WB destinations, when it needed to compare the EX stage instruction's own sources. Off by one pipeline stage, and it silently produced stale operands.
2. The branch flush originally squashed only the instruction in IF, not the one already in ID, so on a taken branch one wrong path instruction still executed and wrote its result.

## Repository layout

```
rtl/     Verilog source, one module per file
tb/      directed test bench
docs/    ISA reference, simulation log
sim/     build output (gitignored)
```

## Running the simulation

With [Icarus Verilog](http://iverilog.icarus.com/) installed:

```
make sim
```

Or directly:

```
iverilog -g2012 -o sim/riscproc_tb.vvp rtl/*.v tb/tb_riscproc.v
cd sim && vvp riscproc_tb.vvp
```

To view waveforms, `make wave` opens the dump in GTKWave.

## Tools

Verilog · Icarus Verilog · GTKWave · Xilinx Vivado (synthesis)

---

Built as part of my Computer Architecture work at BITS Pilani Hyderabad, January to February 2026.
