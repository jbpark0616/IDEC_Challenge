# Generic non-project mode synthesis.
# Invoked by:
#   vivado -mode batch -source synth.tcl \
#       -tclargs <build_dir> [top_module] [rtl_file ...]
#
# Produces (in $build_dir):
#   netlist.v          — post-synth Verilog netlist
#   synth.dcp          — Vivado checkpoint
#   utilization.rpt    — area breakdown
#   timing.rpt         — timing summary (Fmax → 1/period)
#   power.rpt          — power estimate

if {[llength $argv] < 1} {
    puts "ERROR: Usage: vivado -mode batch -source synth.tcl -tclargs <build_dir> ?top_module? ?rtl_file ...?"
    exit 1
}
set build_dir [lindex $argv 0]
file mkdir $build_dir

set proj_root [file normalize [file join [file dirname [info script]] ../..]]
set top_module [expr {[llength $argv] >= 2 ? [lindex $argv 1] : "chip"}]

if {[llength $argv] >= 3} {
    set rtl_files {}
    foreach rtl_arg [lrange $argv 2 end] {
        if {[file pathtype $rtl_arg] eq "relative"} {
            lappend rtl_files [file normalize [file join $proj_root $rtl_arg]]
        } else {
            lappend rtl_files [file normalize $rtl_arg]
        }
    }
} else {
    set rtl_files {}
    foreach f [glob -directory $proj_root/verilog *.v] {
        lappend rtl_files $f
    }
}

puts "===== Reading RTL (top: $top_module) ====="
foreach f $rtl_files {
    puts "  $f"
    read_verilog $f
}

puts "===== Reading constraints ====="
set xdc $proj_root/flow/constraints/timing.xdc
read_xdc $xdc
puts "  $xdc"

puts "===== Synthesizing $top_module (target: xck26-sfvc784-2LV-c) ====="
synth_design -top $top_module -part xck26-sfvc784-2LV-c

puts "===== Writing reports ====="
report_utilization -file $build_dir/utilization.rpt
report_timing_summary -file $build_dir/timing.rpt
report_power -file $build_dir/power.rpt

puts "===== Writing netlist + checkpoint ====="
write_verilog -force $build_dir/netlist.v
write_checkpoint -force $build_dir/synth.dcp

puts "===== DONE ====="
puts "Reports: $build_dir/{utilization,timing,power}.rpt"
