# Out-of-context synthesis and implementation for the video mixer, to answer
# two questions the simulation cannot: does it close timing at the 1080p60
# pixel clock, and what does it cost.
set part xc7z045ffg900-2
set root [file normalize ../]

read_verilog -sv $root/src/axis_video_mixer_pkg.sv
read_verilog       $root/src/generated/axis_video_mixer_regs.v
read_verilog -sv $root/src/generated/axis_video_mixer_csr.sv
read_verilog -sv $root/src/axis_mixer_fifo.sv
read_verilog -sv $root/src/axis_mixer_layer.sv
read_verilog -sv $root/src/axis_video_mixer_core.sv
read_verilog -sv $root/src/axis_video_mixer.sv

synth_design -top axis_video_mixer -part $part -mode out_of_context \
    -generic P_NUM_LAYERS=4 -generic P_FIFO_DEPTH=2048

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
