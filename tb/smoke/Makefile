# ==============================================================================
# The output-path scenarios behind doc/design.md 13.3 and 13.6.
#
#   make          build and run
#   make clean
#
# Needs Verilator only -- no UVM, no simulator licence, no UVCs.
# ==============================================================================

VERILATOR ?= verilator
SRC := ../../src
TOP := mixer_output_smoke

RTL := $(SRC)/axis_video_mixer_pkg.sv \
       $(SRC)/axis_mixer_fifo.sv \
       $(SRC)/axis_mixer_layer.sv \
       $(SRC)/axis_video_mixer_core.sv

# WIDTHTRUNC is off because the scenario table assigns int literals to the
# 16-bit geometry inputs, and BLKSEQ because the source driver deliberately
# uses blocking assignments -- see the header. Original note:
# WIDTHTRUNC is off because the scenario table assigns int literals to the
# 16-bit geometry inputs, which is the readable way to write it.
VFLAGS := --binary --timing -j 4 -DSIMULATION -Wall \
          -Wno-DECLFILENAME -Wno-WIDTHTRUNC -Wno-VARHIDDEN -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-BLKSEQ -Wno-PROCASSINIT

.PHONY: all run clean

all: run

obj_dir/$(TOP): $(RTL) $(TOP).sv
	$(VERILATOR) $(VFLAGS) --top-module $(TOP) $(RTL) $(TOP).sv -o $(TOP)

run: obj_dir/$(TOP)
	@./obj_dir/$(TOP)

clean:
	rm -rf obj_dir
