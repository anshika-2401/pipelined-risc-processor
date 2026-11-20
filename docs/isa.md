# Custom ISA Reference

32-bit instructions, two formats.

## R-type (register-register ALU ops)

```
 31      26 25    21 20    16 15    11 10        0
|  opcode  |   rs   |   rt   |   rd   |  funct    |
|    6     |   5    |   5    |   5    |    11     |
```

opcode = 6'b000000 for all R-type. funct selects the operation.

| Mnemonic | funct       | Operation         |
|----------|-------------|-------------------|
| ADD      | 11'd0       | rd = rs + rt      |
| SUB      | 11'd1       | rd = rs - rt      |
| AND      | 11'd2       | rd = rs & rt      |
| OR       | 11'd3       | rd = rs \| rt     |
| XOR      | 11'd4       | rd = rs ^ rt      |
| SLT      | 11'd5       | rd = (rs < rt) ? 1 : 0 |

## I-type (immediate / memory / branch)

```
 31      26 25    21 20    16 15                 0
|  opcode  |   rs   |   rt   |      immediate     |
|    6     |   5    |   5    |         16         |
```

| Mnemonic | opcode     | Operation                              |
|----------|------------|-----------------------------------------|
| ADDI     | 6'b001000  | rt = rs + sign_extend(imm)              |
| LW       | 6'b001001  | rt = MEM[rs + sign_extend(imm)]         |
| SW       | 6'b001010  | MEM[rs + sign_extend(imm)] = rt         |
| BEQ      | 6'b001011  | if (rs == rt) PC = PC + 4 + (imm << 2)  |
| BNE      | 6'b001100  | if (rs != rt) PC = PC + 4 + (imm << 2)  |
| HALT     | 6'b111111  | stop fetching (testbench sentinel)      |

Register 0 ($r0) is NOT hardwired to zero in this design — it is a normal
general purpose register. (Note this explicitly if asked: it's a deliberate
simplification versus MIPS, not an oversight.)
