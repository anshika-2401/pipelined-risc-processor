# Simulation with Icarus Verilog (free, works on Linux/Mac/Windows+WSL)
SRC = rtl/alu.v rtl/register_file.v rtl/control_unit.v \
      rtl/hazard_forward_unit.v rtl/instr_mem.v rtl/data_mem.v \
      rtl/riscproc_top.v
TB  = tb/tb_riscproc.v

all: sim

sim:
	iverilog -g2012 -o sim/riscproc_tb.vvp $(SRC) $(TB)
	cd sim && vvp riscproc_tb.vvp

wave: sim
	gtkwave sim/riscproc_tb.vcd &

clean:
	rm -f sim/*.vvp sim/*.vcd

.PHONY: all sim wave clean
