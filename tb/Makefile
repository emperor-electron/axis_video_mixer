# ==============================================================================
# Makefile for the axis_video_mixer testbench.
#
# Usage:
#   make                 compile, elaborate, and run TEST in batch mode
#   make TEST=<uvm_test> run a different UVM test
#   make regress         run every test in turn against one snapshot
#   make full            one real 1920x1080 frame (slow, proves the raster)
#   make waves           run and dump a waveform database
#   make gui             run interactively in the XSIM GUI
#   make clean           remove simulation artifacts
#   make help            show this list of targets
#
# Common overrides:
#   TEST, SEED, UVM_VERBOSITY, WAVES, PLUSARGS, VIVADO_PATH
#   CANVAS_W, CANVAS_H, NUM_LAYERS, FIFO_DEPTH
#   PPC                pixels per beat: 1, 2, 4 or 8
#
# PPC is a compile-time define, not a generic, because the link width the UVC
# is specialised on follows from it -- so changing it rebuilds rather than just
# re-elaborates. The snapshot name carries it for the same reason the canvas
# size is carried: so switching does not silently reuse the other one's build.
#
# PPC > 1 also needs the register map regenerated, because CAPS.PPC is a
# constant in it and the CSR refuses a build that disagrees. `make ppc-sweep`
# does that for each value and restores the committed PPC=1 map afterwards;
# `make regen-ppc` does it once, deliberately, since it rewrites checked-in
# generated files.
#
# The canvas defaults to 64x8 so a frame is 512 beats and the regression runs
# in moments. It is passed to xelab as a generic on mixer_tb_top, so nothing in
# the source changes to run a real frame:
#   make full
#
# The FIFO defaults to 128 entries in simulation rather than the synthesis
# default of 2048. A shallow buffer is the stricter test: it forces the flow
# control to actually work instead of hiding behind capacity.
# ==============================================================================

SHELL           := /bin/bash

VIVADO_PATH     ?= /tools/Xilinx/Vivado/2023.2
XVLOG           := $(VIVADO_PATH)/bin/xvlog
XELAB           := $(VIVADO_PATH)/bin/xelab
XSIM            := $(VIVADO_PATH)/bin/xsim

TOP             ?= mixer_tb_top
TEST            ?= mixer_base_test
SEED            ?= random
UVM_VERBOSITY   ?= UVM_LOW
SNAPSHOT        ?= $(TOP)_$(CANVAS_W)x$(CANVAS_H)_ppc$(PPC)_snap

PPC             ?= 1
PPC             ?= 1
CANVAS_W        ?= 64
CANVAS_H        ?= 8
NUM_LAYERS      ?= 4
FIFO_DEPTH      ?= 128

AXI_STREAM_UVC_ROOT   ?= $(abspath ../../axi_stream_uvc)
AXI_LITE_UVC_ROOT     ?= $(abspath ../../axi_lite)
AXIS_VIDEO_MIXER_ROOT ?= $(abspath ..)

export AXI_STREAM_UVC_ROOT
export AXI_LITE_UVC_ROOT
export AXIS_VIDEO_MIXER_ROOT

UVC_FILELIST    := $(AXI_STREAM_UVC_ROOT)/src/axi_stream_uvc.f
AXIL_FILELIST   := $(AXI_LITE_UVC_ROOT)/src/axi_lite_uvc.f
DUT_FILELIST    := $(AXIS_VIDEO_MIXER_ROOT)/src/axis_video_mixer.f
TB_FILELIST     := filelist.f

# SIMULATION turns on the in-RTL assertions. The generated register block has
# no `timescale of its own, so one is supplied to xelab for the whole design;
# without it elaboration fails outright rather than defaulting.
XVLOG_OPTS      := -sv -L uvm -d SIMULATION -d MIX_PPC=$(PPC)
XELAB_OPTS      := -L uvm -timescale 1ns/1ps --debug typical -d SIMULATION \
                   --generic_top "CANVAS_W=$(CANVAS_W)" \
                   --generic_top "CANVAS_H=$(CANVAS_H)" \
                   --generic_top "NUM_LAYERS=$(NUM_LAYERS)" \
                   --generic_top "FIFO_DEPTH=$(FIFO_DEPTH)"

PLUSARGS        ?=
XSIM_ARGS       := --runall --testplusarg "UVM_TESTNAME=$(TEST)" \
                   --testplusarg "UVM_VERBOSITY=$(UVM_VERBOSITY)" $(PLUSARGS)

REGRESS_TESTS   := mixer_base_test \
                   mixer_backpressure_test \
                   mixer_tiling_test \
                   mixer_stacked_alpha_test \
                   mixer_alpha_extremes_test \
                   mixer_move_layer_test \
                   mixer_starve_test \
                   mixer_geometry_error_test \
                   mixer_bad_config_test

.PHONY: regen-ppc ppc-sweep all compile elab run regress full waves gui clean help

all: run

compile:
	$(XVLOG) $(XVLOG_OPTS) -f $(UVC_FILELIST) -f $(AXIL_FILELIST) \
	    -f $(DUT_FILELIST) -f $(TB_FILELIST)

elab: compile
	$(XELAB) $(XELAB_OPTS) -s $(SNAPSHOT) $(TOP)

# XSIM exits 0 even after UVM_FATAL, so the gate is a grep against the banner
# mixer_base_test::report_phase prints, not the exit status.
#
# RTL assertions are checked separately. $error from inside the design does not
# touch UVM's error counters, so a run can print thousands of them and still
# report PASSED -- which is exactly what happened here until the logs were read
# directly. Anything tagged RTL-ASSERT fails the test.
run: elab
	@set -o pipefail; \
	$(XSIM) $(SNAPSHOT) $(XSIM_ARGS) 2>&1 | tee $(TEST).log; \
	if grep -q 'RTL-ASSERT' $(TEST).log; then \
	    echo "FAIL: $(TEST) (RTL assertion fired $$(grep -c RTL-ASSERT $(TEST).log) times)"; exit 1; \
	elif grep -q '^ result  : FAILED$$' $(TEST).log; then \
	    echo "FAIL: $(TEST)"; exit 1; \
	elif grep -q '^ result  : SKIPPED$$' $(TEST).log; then \
	    echo "SKIP: $(TEST)"; \
	elif ! grep -q '^ result  : PASSED$$' $(TEST).log; then \
	    echo "FAIL: $(TEST) produced no result banner"; exit 1; \
	else \
	    echo "PASS: $(TEST)"; \
	fi

regress: elab
	@fail=0; \
	for t in $(REGRESS_TESTS); do \
	    printf '%-34s ' "$$t"; \
	    $(XSIM) $(SNAPSHOT) --runall --testplusarg "UVM_TESTNAME=$$t" \
	        --testplusarg "UVM_VERBOSITY=$(UVM_VERBOSITY)" > $$t.log 2>&1; \
	    if grep -q 'RTL-ASSERT' $$t.log; then \
	        echo "FAIL  (RTL assertion x$$(grep -c RTL-ASSERT $$t.log), see $$t.log)"; fail=1; \
	    elif grep -q '^ result  : PASSED$$' $$t.log; then echo "PASS"; \
	    elif grep -q '^ result  : SKIPPED$$' $$t.log; then echo "SKIP  (needs more layers)"; \
	    else echo "FAIL  (see $$t.log)"; fail=1; fi; \
	done; \
	echo; \
	if [ $$fail -eq 0 ]; then echo "regression PASSED"; else echo "regression FAILED"; fi; \
	exit $$fail

# One real 1080p frame pair, at the synthesis FIFO depth. Two frames rather than
# the usual three because a 1920x1080 frame is 2,073,600 beats and two is enough
# to satisfy the "at least two frames checked" guard.
full:
	$(MAKE) run CANVAS_W=1920 CANVAS_H=1080 FIFO_DEPTH=2048 TEST=mixer_base_test \
	    PLUSARGS='--testplusarg NUM_FRAMES=2'

waves:
	$(MAKE) run PLUSARGS='--testplusarg WAVES'

gui: elab
	$(XSIM) $(SNAPSHOT) -gui --testplusarg "UVM_TESTNAME=$(TEST)"

clean:
	rm -rf xsim.dir *.log *.jou *.pb *.wdb *.vcd *.str xsim.covdb .Xil

help:
	@echo "targets: all compile elab run regress full waves gui clean"
	@echo "tests:"
	@for t in $(REGRESS_TESTS); do echo "    $$t"; done


# ------------------------------------------------------------------------------
# Multi-pixel-per-clock
# ------------------------------------------------------------------------------
# Regenerate the register map for PPC. Rewrites files under ../src/generated and
# ../doc, so it is its own target rather than a dependency of `all`.
regen-ppc:
	cd ../regs && ./gen_regs.py -p $(PPC) && corsair -r regs.json -c csrconfig

# Every supported PPC in turn, full regression at each, then put the committed
# PPC=1 map back so the tree is left as it was found.
#
# The canvas is 64 wide, which is a whole number of beats at all four values --
# the DUT rejects a canvas that is not, so a sweep that did not respect that
# would be testing the error path rather than the datapath.
ppc-sweep:
	@rc=0; \
	for p in 1 2 4 8; do \
	  echo "=================== PPC=$$p ==================="; \
	  $(MAKE) --no-print-directory regen-ppc PPC=$$p >/dev/null || { rc=1; continue; }; \
	  $(MAKE) --no-print-directory regress PPC=$$p || rc=1; \
	done; \
	echo "=== restoring the committed PPC=1 map ==="; \
	$(MAKE) --no-print-directory regen-ppc PPC=1 >/dev/null; \
	echo; echo "ppc sweep $$([ $$rc -eq 0 ] && echo PASSED || echo FAILED)"; \
	exit $$rc
