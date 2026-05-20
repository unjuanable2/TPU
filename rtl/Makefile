
# Makefile for Full Adder simulation in demo/ directory

VCS      = vcs
VERDI    = verdi

TOP      = tb_fp32_muti
SRCS     = ../fp32_muti.v ./tb_fp32_muti.sv
FSDB     = wave.fsdb

VCS_OPTS = -full64 -sverilog -debug_access+all -timescale=1ns/1ps

all: clean simv view
	./simv

simv: $(SRCS)
	$(VCS) -R $(VCS_OPTS) $(SRCS) -o simv

#view:
	#$(VERDI) -ssf $(FSDB) -top $(TOP) $(SRCS) &
view:
	$(VERDI) -ssf $(FSDB) -2001 -sverilog $(SRCS) &

	

clean:
	rm -rf simv csrc ucli.key DVEfiles *.log *.fsdb novas* *.vpd *.vcd *.vcs* *.daidir

.PHONY: all simv view clean tree
