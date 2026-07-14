# Non-project mode synthesis for baseline chip
# Invoked by: vivado -mode batch -source synth.tcl -tclargs <build_dir>
#
# Produces (in $build_dir):
#   netlist.v          — post-synth Verilog netlist
#   synth.dcp          — Vivado checkpoint
#   utilization.rpt    — area breakdown
#   timing.rpt         — timing summary (Fmax → 1/period)
#   power.rpt          — power estimate

if {[llength $argv] < 1} {
    puts "ERROR: Usage: vivado -mode batch -source synth.tcl -tclargs <build_dir>"
    exit 1
}
set build_dir [lindex $argv 0]
file mkdir $build_dir

set proj_root [file normalize [file join [file dirname [info script]] ../..]]
set rtl_files [glob -directory $proj_root/verilog chip.v conv1.v conv2.v fc.v maxpool_relu.v comparator.v]

puts "===== Reading RTL ====="
foreach f $rtl_files {
    puts "  $f"
    read_verilog $f
}

puts "===== Reading constraints ====="
set xdc $proj_root/flow/constraints/timing.xdc
read_xdc $xdc
puts "  $xdc"

puts "===== Synthesizing chip (target: xck26-sfvc784-2LV-c) ====="
synth_design -top chip -part xck26-sfvc784-2LV-c

puts "===== Writing reports ====="
report_utilization -file $build_dir/utilization.rpt
report_timing_summary -file $build_dir/timing.rpt
report_power -file $build_dir/power.rpt

puts "===== Writing netlist + checkpoint ====="
write_verilog -force $build_dir/netlist.v
write_checkpoint -force $build_dir/synth.dcp

puts "===== DONE ====="
puts "Reports: $build_dir/{utilization,timing,power}.rpt"
