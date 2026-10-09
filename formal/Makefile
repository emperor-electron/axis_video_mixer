# ==============================================================================
# Formal verification for the AXI4-Stream video mixer.
#
#   make            every proof, every task
#   make blend      one unit: blend, fifo, layer, core, top
#   make quick      every bmc task plus the cheap blend groups -- about 30 s,
#                   for use while editing RTL
#   make report     re-print the summary without re-running anything
#   make clean      remove the sby work directories
#
#   make TASKS="bmc cover" fifo      run named tasks of one unit
#
# Needs SymbiYosys, Yosys with the slang plugin, and boolector -- all three are
# in the OSS CAD Suite. `make tools` checks.
#
# Everything here is driven by the .sby files, which are the real interface:
# `sby -f fv_core.sby prove` and `make core TASKS=prove` do the same thing. The
# Makefile exists to run them all and to summarise, because a suite that is
# awkward to run in one command stops being run.
# ==============================================================================

SBY ?= sby
UNITS := blend fifo layer core top

# Tasks default to "everything in the file", which is what sby does when given
# no task names.
TASKS ?=

.PHONY: all $(UNITS) quick report clean tools help

all: $(UNITS)
	@$(MAKE) --no-print-directory report

help:
	@sed -n '2,20p' Makefile | sed 's/^# \?//'

tools:
	@ok=1; \
	for t in $(SBY) yosys boolector; do \
	  if command -v $$t >/dev/null 2>&1; then printf '  %-12s %s\n' "$$t" "$$(command -v $$t)"; \
	  else printf '  %-12s MISSING\n' "$$t"; ok=0; fi; \
	done; \
	if yosys -m slang -p 'help read_slang' >/dev/null 2>&1; then \
	  printf '  %-12s ok\n' "slang plugin"; \
	else printf '  %-12s MISSING -- yosys-slang is required, the built-in Verilog frontend cannot read this RTL\n' "slang plugin"; ok=0; fi; \
	[ $$ok = 1 ] || { echo; echo "Install the OSS CAD Suite and put its bin/ on PATH."; exit 1; }

# One target per unit. `-f` makes sby overwrite a previous work directory
# rather than refusing; without it a re-run after a failure needs a clean.
$(UNITS): tools
	@echo "=== $@ ==="
	@$(SBY) -f fv_$@.sby $(TASKS)

# Every bmc task plus the three cheap blend groups. Around thirty seconds from
# clean, and enough to catch the great majority of RTL mistakes: what it leaves
# out is the k-induction runs, the deep BMC, and the cover tasks.
quick: tools
	@$(SBY) -f fv_blend.sby div8 scale8 blend8
	@$(SBY) -f fv_fifo.sby bmc
	@$(SBY) -f fv_layer.sby bmc
	@$(SBY) -f fv_core.sby bmc
	@$(SBY) -f fv_top.sby bmc
	@$(MAKE) --no-print-directory report

# Reads the status files sby leaves behind, so it works after the fact and
# without re-running anything. A missing directory is reported as such rather
# than skipped, because a task that was never run is not a task that passed.
report:
	@echo
	@printf '%-28s %s\n' "TASK" "RESULT"
	@printf '%-28s %s\n' "----" "------"
	@fail=0; \
	for f in fv_*.sby; do \
	  u=$${f%.sby}; \
	  for d in $${u}_*; do \
	    [ -d "$$d" ] || continue; \
	    if [ -f "$$d/PASS" ]; then r=PASS; \
	    elif [ -f "$$d/FAIL" ]; then r=FAIL; fail=1; \
	    elif [ -f "$$d/UNKNOWN" ]; then r="UNKNOWN (induction did not close)"; fail=1; \
	    elif [ -f "$$d/ERROR" ]; then r=ERROR; fail=1; \
	    else r="no status -- did not finish"; fail=1; fi; \
	    printf '%-28s %s\n' "$$d" "$$r"; \
	  done; \
	done; \
	echo; \
	[ $$fail = 0 ] && echo "all recorded tasks passed" || { echo "something did not pass"; exit 1; }

# Both the per-task work directories and the per-file status databases sby
# keeps alongside them (fv_core/status.sqlite and friends). Matched on
# directories only -- a glob of fv_* would take the .sby files with it.
clean:
	@find . -maxdepth 1 -type d -name 'fv_*' -exec rm -rf {} +
