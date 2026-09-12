# Out-of-context synthesis and implementation for the video mixer, to answer
# two questions the simulation cannot: does it close timing at the 1080p60
# pixel clock, and what does it cost.
set part xc7z045ffg900-2
set root [file normalize ../]

# Pixels per beat, and the layer buffer depth in BEATS.
#
# The buffer holds one layer line, so for a given pixel capacity the beat count
# falls as PPC rises -- 2048 pixels is 2048 beats at PPC 1 and 256 beats at
# PPC 8, the same number of bits and the same block RAMs either way.
#
# -tclargs consumes every remaining argument, so it must come LAST on the
# command line -- put -log or -journal after it and they arrive here as values.
#
#   vivado -mode batch -source syn.tcl -tclargs 4        # PPC 4, 512-beat buffer
#   vivado -mode batch -source syn.tcl -tclargs 8 256    # explicit depth
set ppc        1
set fifo_depth 0
if {[llength $argv] > 0} { set ppc        [lindex $argv 0] }
if {[llength $argv] > 1} { set fifo_depth [lindex $argv 1] }
if {![string is integer -strict $ppc] || $ppc ni {1 2 4 8}} {
    error "syn.tcl: first argument must be a PPC of 1, 2, 4 or 8, got '$ppc'"
}
if {![string is integer -strict $fifo_depth]} {
    error "syn.tcl: second argument must be a beat count, got '$fifo_depth' -- note that\
           -tclargs takes everything after it, so -log and -journal must come before it"
}
if {$fifo_depth == 0}    { set fifo_depth [expr {2048 / $ppc}] }
puts "SYN: P_PPC = $ppc, P_FIFO_DEPTH = $fifo_depth beats ([expr {$ppc*$fifo_depth}] pixels)"

read_verilog -sv $root/src/axis_video_mixer_pkg.sv
read_verilog       $root/src/generated/axis_video_mixer_regs.v
read_verilog -sv $root/src/generated/axis_video_mixer_csr.sv
read_verilog -sv $root/src/axis_mixer_fifo.sv
read_verilog -sv $root/src/axis_mixer_layer.sv
read_verilog -sv $root/src/axis_video_mixer_core.sv
read_verilog -sv $root/src/axis_video_mixer.sv

synth_design -top axis_video_mixer -part $part -mode out_of_context \
    -generic P_NUM_LAYERS=4 -generic P_PPC=$ppc -generic P_FIFO_DEPTH=$fifo_depth

# 148.5 MHz is the 1080p60 pixel clock, the fastest this has to run in the
# target system.
create_clock -period 6.734 -name clk [get_ports clk]
set_false_path -from [get_ports rst_n]

opt_design
place_design
route_design

set ws [get_property SLACK [get_timing_paths -delay_type max]]
set wh [get_property SLACK [get_timing_paths -delay_type min]]
puts "SYN: WNS = $ws ns"
puts "SYN: WHS = $wh ns"
report_utilization -hierarchical -file util.rpt
report_timing_summary -file timing.rpt
puts "SYN: DONE"
